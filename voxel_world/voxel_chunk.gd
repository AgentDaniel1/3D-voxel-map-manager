class_name VoxelChunk
extends Node3D

## Individual Voxel Chunk - Manages block data, mesh generation, and collision
##
## This class represents a single chunk in the voxel world. It stores block data,
## generates optimized meshes with greedy meshing and face culling, and handles
## collision generation.

#region Properties
var chunk_position: Vector3i = Vector3i.ZERO
var chunk_size: Vector3i = Vector3i(16, 128, 16)
var world_manager: VoxelWorld = null
var generate_collision: bool = true
var is_modified: bool = false
var is_mesh_dirty: bool = true
#endregion

#region Private Variables
var _block_data: PackedByteArray = PackedByteArray()
var _mesh_instance: MeshInstance3D = null
var _collision_shape: CollisionShape3D = null
var _static_body: StaticBody3D = null
var _mesh_builder: VoxelMeshBuilder = null
#endregion

#region Lifecycle
func _init() -> void:
	_mesh_builder = VoxelMeshBuilder.new()

func _ready() -> void:
	_setup_mesh_instance()
	if generate_collision:
		_setup_collision()
	
	# Initialize block data array
	var total_blocks = chunk_size.x * chunk_size.y * chunk_size.z
	_block_data.resize(total_blocks)
	_block_data.fill(0)

func _setup_mesh_instance() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "ChunkMesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_instance)

func _setup_collision() -> void:
	_static_body = StaticBody3D.new()
	_static_body.name = "ChunkCollision"
	add_child(_static_body)
	
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "CollisionShape"
	_static_body.add_child(_collision_shape)
#endregion

#region Public API - Block Management
## Get block ID at local chunk position
func get_block(local_pos: Vector3i) -> int:
	if not _is_valid_position(local_pos):
		return 0
	
	var index = _pos_to_index(local_pos)
	return _block_data[index]

## Set block ID at local chunk position
func set_block(local_pos: Vector3i, block_id: int) -> void:
	if not _is_valid_position(local_pos):
		return
	
	var index = _pos_to_index(local_pos)
	if _block_data[index] == block_id:
		return
	
	_block_data[index] = block_id
	is_modified = true

## Mark chunk as needing mesh regeneration
func mark_dirty() -> void:
	is_mesh_dirty = true

## Check if position has a solid block (non-air)
func is_solid_at(local_pos: Vector3i) -> bool:
	return get_block(local_pos) != 0

## Get all block data as raw array
func get_block_data() -> PackedByteArray:
	return _block_data

## Set all block data from raw array
func set_block_data(data: PackedByteArray) -> void:
	if data.size() != _block_data.size():
		push_error("Invalid block data size for chunk %s" % chunk_position)
		return
	
	_block_data = data
	is_modified = true
	mark_dirty()
#endregion

#region Public API - Mesh Generation
## Generate mesh for this chunk with optimization
func generate_mesh() -> void:
	if not is_mesh_dirty:
		return
	
	var mesh_data = _mesh_builder.build_chunk_mesh(self, world_manager)
	
	if mesh_data.is_empty():
		# Chunk is empty, clear mesh
		_mesh_instance.mesh = null
		if _collision_shape:
			_collision_shape.shape = null
		is_mesh_dirty = false
		return
	
	# Create and assign mesh
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data)
	_mesh_instance.mesh = array_mesh
	
	# Generate collision if enabled
	if generate_collision and _collision_shape:
		_generate_collision_from_mesh(mesh_data)
	
	is_mesh_dirty = false

## Force immediate mesh regeneration
func rebuild_mesh() -> void:
	is_mesh_dirty = true
	generate_mesh()
#endregion

#region Public API - Serialization
## Serialize chunk data to binary format
func serialize() -> PackedByteArray:
	var buffer = PackedByteArray()
	
	# Header: chunk position and size
	buffer.append_array(_encode_vector3i(chunk_position))
	buffer.append_array(_encode_vector3i(chunk_size))
	
	# Block data with RLE compression
	var compressed_blocks = _compress_block_data()
	buffer.append_array(compressed_blocks)
	
	return buffer

## Deserialize chunk data from binary format
func deserialize(data: PackedByteArray) -> bool:
	if data.size() < 24:  # Minimum size for header
		return false
	
	var offset = 0
	
	# Read header
	var stored_position = _decode_vector3i(data, offset)
	offset += 12
	var stored_size = _decode_vector3i(data, offset)
	offset += 12
	
	# Validate
	if stored_position != chunk_position or stored_size != chunk_size:
		push_warning("Chunk data mismatch for position %s" % chunk_position)
		return false
	
	# Decompress block data
	var block_data_slice = data.slice(offset)
	_decompress_block_data(block_data_slice)
	
	is_modified = false
	mark_dirty()
	return true
#endregion

#region Public API - Utility
## Cleanup resources
func cleanup() -> void:
	if _mesh_instance:
		_mesh_instance.mesh = null
	if _collision_shape:
		_collision_shape.shape = null
	_block_data.clear()
#endregion

#region Private Methods - Validation
func _is_valid_position(pos: Vector3i) -> bool:
	return (pos.x >= 0 and pos.x < chunk_size.x and
			pos.y >= 0 and pos.y < chunk_size.y and
			pos.z >= 0 and pos.z < chunk_size.z)

func _pos_to_index(pos: Vector3i) -> int:
	return pos.x + pos.z * chunk_size.x + pos.y * chunk_size.x * chunk_size.z

func _index_to_pos(index: int) -> Vector3i:
	var x = index % chunk_size.x
	var z = (index / chunk_size.x) % chunk_size.z
	var y = index / (chunk_size.x * chunk_size.z)
	return Vector3i(x, y, z)
#endregion

#region Private Methods - Collision
func _generate_collision_from_mesh(mesh_data: Array) -> void:
	var vertices = mesh_data[Mesh.ARRAY_VERTEX]
	var indices = mesh_data[Mesh.ARRAY_INDEX]
	
	if vertices == null or indices == null:
		return
	
	# Create trimesh collision shape
	var faces = PackedVector3Array()
	for i in range(0, indices.size(), 3):
		if i + 2 < indices.size():
			faces.append(vertices[indices[i]])
			faces.append(vertices[indices[i + 1]])
			faces.append(vertices[indices[i + 2]])
	
	if faces.size() > 0:
		var shape = ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		_collision_shape.shape = shape
#endregion

#region Private Methods - Compression (RLE)
func _compress_block_data() -> PackedByteArray:
	var compressed = PackedByteArray()
	
	if _block_data.is_empty():
		return compressed
	
	var current_value = _block_data[0]
	var count = 1
	
	for i in range(1, _block_data.size()):
		if _block_data[i] == current_value and count < 255:
			count += 1
		else:
			# Write run
			compressed.append(current_value)
			compressed.append(count)
			current_value = _block_data[i]
			count = 1
	
	# Write final run
	compressed.append(current_value)
	compressed.append(count)
	
	return compressed

func _decompress_block_data(compressed: PackedByteArray) -> void:
	_block_data.clear()
	
	var i = 0
	while i < compressed.size() - 1:
		var value = compressed[i]
		var count = compressed[i + 1]
		
		for j in range(count):
			_block_data.append(value)
		
		i += 2
	
	# Ensure correct size
	var expected_size = chunk_size.x * chunk_size.y * chunk_size.z
	if _block_data.size() != expected_size:
		push_error("Decompressed block data size mismatch: got %d, expected %d" % [_block_data.size(), expected_size])
		_block_data.resize(expected_size)
		_block_data.fill(0)
#endregion

#region Private Methods - Binary Encoding
func _encode_vector3i(vec: Vector3i) -> PackedByteArray:
	var buffer = PackedByteArray()
	buffer.resize(12)
	buffer.encode_s32(0, vec.x)
	buffer.encode_s32(4, vec.y)
	buffer.encode_s32(8, vec.z)
	return buffer

func _decode_vector3i(data: PackedByteArray, offset: int) -> Vector3i:
	return Vector3i(
		data.decode_s32(offset),
		data.decode_s32(offset + 4),
		data.decode_s32(offset + 8)
	)
#endregion