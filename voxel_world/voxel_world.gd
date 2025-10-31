@tool
@icon("res://addons/voxel_world/icons/voxel_world.svg")
class_name VoxelWorld
extends Node3D

## Voxel World Manager - Manages 3D voxel chunks with optimized rendering and streaming
##
## This node manages a voxel-based world system with automatic chunk loading/unloading,
## mesh generation, collision, and save/load functionality.
## Use the API to set/get blocks and the system handles everything else automatically.

#region Signals
## Emitted when a chunk finishes loading and generating its mesh
signal chunk_loaded(chunk_position: Vector3i)

## Emitted when a chunk is unloaded from memory
signal chunk_unloaded(chunk_position: Vector3i)

## Emitted when a block is modified (placed or destroyed)
signal block_modified(world_position: Vector3i, block_id: int)

## Emitted when a chunk is saved to disk
signal chunk_saved(chunk_position: Vector3i)

## Emitted when mesh generation for a chunk is complete
signal chunk_mesh_generated(chunk_position: Vector3i)
#endregion

#region Exported Properties
@export_group("Chunk Settings")
## Size of chunk in X and Z dimensions (horizontal)
@export_range(8, 64, 8) var chunk_size_xz: int = 16:
	set(value):
		chunk_size_xz = value
		if Engine.is_editor_hint():
			notify_property_list_changed()

## Size of chunk in Y dimension (vertical)
@export_range(8, 256, 8) var chunk_size_y: int = 128:
	set(value):
		chunk_size_y = value
		if Engine.is_editor_hint():
			notify_property_list_changed()

@export_group("Render Distance")
## Render distance in chunks for horizontal (X/Z) directions
@export_range(2, 32) var render_distance_xz: int = 8:
	set(value):
		render_distance_xz = value
		if is_inside_tree() and not Engine.is_editor_hint():
			_update_loaded_chunks()

## Render distance in chunks for vertical (Y) direction
@export_range(1, 16) var render_distance_y: int = 4:
	set(value):
		render_distance_y = value
		if is_inside_tree() and not Engine.is_editor_hint():
			_update_loaded_chunks()

@export_group("Performance")
## Maximum chunks to generate per frame (0 = unlimited)
@export_range(0, 10) var max_chunks_per_frame: int = 2

## Enable collision generation for chunks
@export var generate_collision: bool = true

## Enable automatic chunk saving
@export var auto_save_chunks: bool = true

@export_group("Persistence")
## Directory where chunk data will be saved
@export_dir var save_directory: String = "user://voxel_world/chunks"

## Enable compression for saved chunks
@export var compress_chunks: bool = true

@export_group("Debug")
## Show debug information in editor and runtime
@export var show_debug_info: bool = false

## Show chunk boundaries (editor only)
@export var show_chunk_boundaries: bool = false
#endregion

#region Private Variables
var _chunks: Dictionary = {}  # Vector3i -> VoxelChunk
var _chunk_queue: Array[Vector3i] = []  # Chunks waiting to be generated
var _active_camera: Camera3D = null
var _last_camera_chunk: Vector3i = Vector3i.ZERO
var _is_ready: bool = false
#endregion

#region Lifecycle Methods
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	_is_ready = true
	_setup_save_directory()
	_find_active_camera()
	
	# Start chunk loading system
	set_physics_process(true)
	set_process(true)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if _active_camera == null:
		_find_active_camera()
		return
	
	var camera_chunk = world_to_chunk(_active_camera.global_position)
	
	if camera_chunk != _last_camera_chunk:
		_last_camera_chunk = camera_chunk
		_update_loaded_chunks()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	# Process chunk generation queue
	_process_chunk_queue()

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	
	if auto_save_chunks:
		save_all_chunks()
	
	_cleanup_chunks()
#endregion

#region Public API - Block Management
## Set a block at world position with given block ID
## Returns true if successful
func set_block(world_pos: Vector3i, block_id: int) -> bool:
	var chunk_pos = world_to_chunk(world_pos)
	var local_pos = world_to_local(world_pos)
	
	var chunk = _get_or_create_chunk(chunk_pos)
	if chunk == null:
		return false
	
	var old_id = chunk.get_block(local_pos)
	if old_id == block_id:
		return false
	
	chunk.set_block(local_pos, block_id)
	chunk.mark_dirty()
	
	# Update neighboring chunks if on boundary
	_check_neighbor_updates(world_pos)
	
	block_modified.emit(world_pos, block_id)
	return true

## Get block ID at world position
## Returns 0 if position is not loaded or invalid
func get_block(world_pos: Vector3i) -> int:
	var chunk_pos = world_to_chunk(world_pos)
	var local_pos = world_to_local(world_pos)
	
	if not _chunks.has(chunk_pos):
		return 0
	
	return _chunks[chunk_pos].get_block(local_pos)

## Set multiple blocks at once (more efficient than multiple set_block calls)
## blocks_data: Array of {position: Vector3i, block_id: int}
func set_blocks_bulk(blocks_data: Array) -> void:
	var affected_chunks: Dictionary = {}
	
	for data in blocks_data:
		if not data.has("position") or not data.has("block_id"):
			continue
		
		var world_pos: Vector3i = data.position
		var block_id: int = data.block_id
		var chunk_pos = world_to_chunk(world_pos)
		var local_pos = world_to_local(world_pos)
		
		var chunk = _get_or_create_chunk(chunk_pos)
		if chunk != null:
			chunk.set_block(local_pos, block_id)
			affected_chunks[chunk_pos] = chunk
			block_modified.emit(world_pos, block_id)
	
	# Mark all affected chunks as dirty
	for chunk in affected_chunks.values():
		chunk.mark_dirty()
		_check_neighbor_updates_for_chunk(chunk.chunk_position)

## Remove/destroy a block (sets it to air/0)
func destroy_block(world_pos: Vector3i) -> bool:
	return set_block(world_pos, 0)

## Check if a block exists at position (non-air block)
func has_block(world_pos: Vector3i) -> bool:
	return get_block(world_pos) != 0
#endregion

#region Public API - Chunk Management
## Force load a chunk at chunk coordinates
func load_chunk(chunk_pos: Vector3i) -> void:
	if _chunks.has(chunk_pos):
		return
	
	var chunk = _create_chunk(chunk_pos)
	_chunks[chunk_pos] = chunk
	
	# Try to load from disk
	if _load_chunk_data(chunk):
		chunk.generate_mesh()
		chunk_loaded.emit(chunk_pos)
	else:
		# Queue for generation if not loaded from disk
		if not chunk_pos in _chunk_queue:
			_chunk_queue.append(chunk_pos)

## Unload a chunk and optionally save it
func unload_chunk(chunk_pos: Vector3i, save_before_unload: bool = true) -> void:
	if not _chunks.has(chunk_pos):
		return
	
	var chunk: VoxelChunk = _chunks[chunk_pos]
	
	if save_before_unload and chunk.is_modified:
		_save_chunk_data(chunk)
	
	chunk.cleanup()
	chunk.queue_free()
	_chunks.erase(chunk_pos)
	
	chunk_unloaded.emit(chunk_pos)

## Check if a chunk is loaded
func is_chunk_loaded(chunk_pos: Vector3i) -> bool:
	return _chunks.has(chunk_pos)

## Get chunk at chunk coordinates
func get_chunk(chunk_pos: Vector3i) -> VoxelChunk:
	return _chunks.get(chunk_pos, null)

## Get all loaded chunk positions
func get_loaded_chunks() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	result.assign(_chunks.keys())
	return result

## Reload/regenerate mesh for a specific chunk
func reload_chunk(chunk_pos: Vector3i) -> void:
	if _chunks.has(chunk_pos):
		_chunks[chunk_pos].mark_dirty()
		_chunks[chunk_pos].generate_mesh()
#endregion

#region Public API - Save/Load
## Save a specific chunk to disk
func save_chunk(chunk_pos: Vector3i) -> bool:
	if not _chunks.has(chunk_pos):
		return false
	
	return _save_chunk_data(_chunks[chunk_pos])

## Save all loaded chunks
func save_all_chunks() -> void:
	for chunk in _chunks.values():
		if chunk.is_modified:
			_save_chunk_data(chunk)

## Clear all chunks and optionally save them
func clear_world(save_before_clear: bool = true) -> void:
	if save_before_clear:
		save_all_chunks()
	
	_cleanup_chunks()
	_chunks.clear()
	_chunk_queue.clear()
#endregion

#region Public API - Coordinate Conversion
## Convert world position to chunk position
func world_to_chunk(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_pos.x / chunk_size_xz),
		floori(world_pos.y / chunk_size_y),
		floori(world_pos.z / chunk_size_xz)
	)

## Convert world position to local chunk position
func world_to_local(world_pos: Vector3i) -> Vector3i:
	var cx = posmod(world_pos.x, chunk_size_xz)
	var cy = posmod(world_pos.y, chunk_size_y)
	var cz = posmod(world_pos.z, chunk_size_xz)
	return Vector3i(cx, cy, cz)

## Convert chunk position to world position (corner)
func chunk_to_world(chunk_pos: Vector3i) -> Vector3:
	return Vector3(
		chunk_pos.x * chunk_size_xz,
		chunk_pos.y * chunk_size_y,
		chunk_pos.z * chunk_size_xz
	)
#endregion

#region Private Methods - Chunk Management
func _get_or_create_chunk(chunk_pos: Vector3i) -> VoxelChunk:
	if _chunks.has(chunk_pos):
		return _chunks[chunk_pos]
	
	# Auto-load chunk if within render distance
	if _is_within_render_distance(chunk_pos):
		load_chunk(chunk_pos)
		return _chunks.get(chunk_pos, null)
	
	return null

func _create_chunk(chunk_pos: Vector3i) -> VoxelChunk:
	var chunk = VoxelChunk.new()
	chunk.chunk_position = chunk_pos
	chunk.chunk_size = Vector3i(chunk_size_xz, chunk_size_y, chunk_size_xz)
	chunk.world_manager = self
	chunk.generate_collision = generate_collision
	chunk.name = "Chunk_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, chunk_pos.z]
	chunk.position = chunk_to_world(chunk_pos)
	add_child(chunk)
	return chunk

func _update_loaded_chunks() -> void:
	if _active_camera == null:
		return
	
	var camera_chunk = _last_camera_chunk
	var chunks_to_load: Array[Vector3i] = []
	var chunks_to_unload: Array[Vector3i] = []
	
	# Find chunks that should be loaded
	for x in range(-render_distance_xz, render_distance_xz + 1):
		for z in range(-render_distance_xz, render_distance_xz + 1):
			for y in range(-render_distance_y, render_distance_y + 1):
				var chunk_pos = camera_chunk + Vector3i(x, y, z)
				
				# Check if within circular render distance
				var dist_xz = Vector2(x, z).length()
				if dist_xz <= render_distance_xz and not _chunks.has(chunk_pos):
					chunks_to_load.append(chunk_pos)
	
	# Find chunks that should be unloaded
	for chunk_pos in _chunks.keys():
		if not _is_within_render_distance(chunk_pos):
			chunks_to_unload.append(chunk_pos)
	
	# Load new chunks
	for chunk_pos in chunks_to_load:
		load_chunk(chunk_pos)
	
	# Unload far chunks
	for chunk_pos in chunks_to_unload:
		unload_chunk(chunk_pos, auto_save_chunks)

func _is_within_render_distance(chunk_pos: Vector3i) -> bool:
	if _active_camera == null:
		return false
	
	var camera_chunk = _last_camera_chunk
	var diff = chunk_pos - camera_chunk
	
	var dist_xz = Vector2(diff.x, diff.z).length()
	var dist_y = abs(diff.y)
	
	return dist_xz <= render_distance_xz and dist_y <= render_distance_y

func _process_chunk_queue() -> void:
	if _chunk_queue.is_empty():
		return
	
	var chunks_processed = 0
	
	while not _chunk_queue.is_empty() and (max_chunks_per_frame == 0 or chunks_processed < max_chunks_per_frame):
		var chunk_pos = _chunk_queue.pop_front()
		
		if _chunks.has(chunk_pos):
			var chunk = _chunks[chunk_pos]
			chunk.generate_mesh()
			chunk_loaded.emit(chunk_pos)
			chunk_mesh_generated.emit(chunk_pos)
			chunks_processed += 1

func _check_neighbor_updates(world_pos: Vector3i) -> void:
	var local_pos = world_to_local(world_pos)
	
	# Check if on chunk boundary
	var neighbors_to_update: Array[Vector3i] = []
	
	if local_pos.x == 0:
		neighbors_to_update.append(world_to_chunk(world_pos + Vector3i(-1, 0, 0)))
	elif local_pos.x == chunk_size_xz - 1:
		neighbors_to_update.append(world_to_chunk(world_pos + Vector3i(1, 0, 0)))
	
	if local_pos.y == 0:
		neighbors_to_update.append(world_to_chunk(world_pos + Vector3i(0, -1, 0)))
	elif local_pos.y == chunk_size_y - 1:
		neighbors_to_update.append(world_to_chunk(world_pos + Vector3i(0, 1, 0)))
	
	if local_pos.z == 0:
		neighbors_to_update.append(world_to_chunk(world_pos + Vector3i(0, 0, -1)))
	elif local_pos.z == chunk_size_xz - 1:
		neighbors_to_update.append(world_to_chunk(world_pos + Vector3i(0, 0, 1)))
	
	for neighbor_pos in neighbors_to_update:
		if _chunks.has(neighbor_pos):
			_chunks[neighbor_pos].mark_dirty()
			_chunks[neighbor_pos].generate_mesh()

func _check_neighbor_updates_for_chunk(chunk_pos: Vector3i) -> void:
	var neighbors = [
		chunk_pos + Vector3i(1, 0, 0),
		chunk_pos + Vector3i(-1, 0, 0),
		chunk_pos + Vector3i(0, 1, 0),
		chunk_pos + Vector3i(0, -1, 0),
		chunk_pos + Vector3i(0, 0, 1),
		chunk_pos + Vector3i(0, 0, -1)
	]
	
	for neighbor_pos in neighbors:
		if _chunks.has(neighbor_pos):
			_chunks[neighbor_pos].mark_dirty()

func _cleanup_chunks() -> void:
	for chunk in _chunks.values():
		chunk.cleanup()
		chunk.queue_free()
#endregion

#region Private Methods - Save/Load
func _setup_save_directory() -> void:
	if save_directory.is_empty():
		save_directory = "user://voxel_world/chunks"
	
	DirAccess.make_dir_recursive_absolute(save_directory)

func _save_chunk_data(chunk: VoxelChunk) -> bool:
	var file_path = _get_chunk_file_path(chunk.chunk_position)
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if file == null:
		push_error("Failed to save chunk at %s: %s" % [chunk.chunk_position, FileAccess.get_open_error()])
		return false
	
	var data = chunk.serialize()
	
	if compress_chunks:
		var compressed = data.compress(FileAccess.COMPRESSION_ZSTD)
		file.store_32(compressed.size())
		file.store_buffer(compressed)
	else:
		file.store_buffer(data)
	
	file.close()
	chunk.is_modified = false
	chunk_saved.emit(chunk.chunk_position)
	return true

func _load_chunk_data(chunk: VoxelChunk) -> bool:
	var file_path = _get_chunk_file_path(chunk.chunk_position)
	
	if not FileAccess.file_exists(file_path):
		return false
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return false
	
	var data: PackedByteArray
	
	if compress_chunks:
		var compressed_size = file.get_32()
		var compressed = file.get_buffer(compressed_size)
		data = compressed.decompress_dynamic(-1, FileAccess.COMPRESSION_ZSTD)
	else:
		data = file.get_buffer(file.get_length())
	
	file.close()
	
	chunk.deserialize(data)
	return true

func _get_chunk_file_path(chunk_pos: Vector3i) -> String:
	return "%s/chunk_%d_%d_%d.dat" % [save_directory, chunk_pos.x, chunk_pos.y, chunk_pos.z]
#endregion

#region Private Methods - Utility
func _find_active_camera() -> void:
	var viewport = get_viewport()
	if viewport != null:
		_active_camera = viewport.get_camera_3d()
#endregion