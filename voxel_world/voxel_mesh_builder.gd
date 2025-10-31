class_name VoxelMeshBuilder
extends RefCounted

## Voxel Mesh Builder - Generates optimized meshes with greedy meshing and culling
##
## This class handles the complex task of converting voxel data into optimized 3D meshes.
## It uses greedy meshing algorithm to reduce vertex count and performs face culling
## to skip hidden faces. UV coordinates are automatically generated for texture atlases.

#region Constants
const FACE_DIRECTIONS = [
	Vector3i(0, 1, 0),   # Top
	Vector3i(0, -1, 0),  # Bottom
	Vector3i(1, 0, 0),   # Right
	Vector3i(-1, 0, 0),  # Left
	Vector3i(0, 0, 1),   # Front
	Vector3i(0, 0, -1)   # Back
]

const FACE_VERTICES = [
	# Top (Y+)
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	# Bottom (Y-)
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
	# Right (X+)
	[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	# Left (X-)
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	# Front (Z+)
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	# Back (Z-)
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]
]

const FACE_NORMALS = [
	Vector3(0, 1, 0),   # Top
	Vector3(0, -1, 0),  # Bottom
	Vector3(1, 0, 0),   # Right
	Vector3(-1, 0, 0),  # Left
	Vector3(0, 0, 1),   # Front
	Vector3(0, 0, -1)   # Back
]

const FACE_INDICES = [0, 1, 2, 0, 2, 3]  # Two triangles per quad
#endregion

#region Private Variables
var _vertices: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _uvs: PackedVector2Array = PackedVector2Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _colors: PackedColorArray = PackedColorArray()
#endregion

#region Public API
## Build optimized mesh for a chunk with greedy meshing and culling
func build_chunk_mesh(chunk: VoxelChunk, world_manager: VoxelWorld) -> Array:
	_clear_mesh_data()
	
	var chunk_size = chunk.chunk_size
	var has_any_blocks = false
	
	# Greedy meshing for each face direction
	for face_index in range(6):
		var direction = FACE_DIRECTIONS[face_index]
		_build_greedy_faces(chunk, world_manager, face_index, direction)
	
	# Check if we generated any geometry
	if _vertices.is_empty():
		return []
	
	# Build final mesh arrays
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	arrays[Mesh.ARRAY_COLOR] = _colors
	
	return arrays
#endregion

#region Private Methods - Greedy Meshing
func _build_greedy_faces(chunk: VoxelChunk, world_manager: VoxelWorld, face_index: int, direction: Vector3i) -> void:
	var chunk_size = chunk.chunk_size
	var axis = _get_primary_axis(direction)
	
	# Determine dimensions for slicing
	var dims = _get_slice_dimensions(axis, chunk_size)
	var width = dims[0]
	var height = dims[1]
	var depth = dims[2]
	
	# Process each slice along the primary axis
	for d in range(depth):
		var mask: Array = []
		mask.resize(width * height)
		mask.fill(-1)  # -1 means no block, >= 0 is block_id
		
		# Build mask for this slice
		_build_face_mask(chunk, world_manager, face_index, direction, d, mask, width, height, axis)
		
		# Greedy mesh the mask
		_greedy_mesh_slice(mask, width, height, d, face_index, direction, axis, chunk_size)

func _build_face_mask(chunk: VoxelChunk, world_manager: VoxelWorld, face_index: int, 
					   direction: Vector3i, slice_depth: int, mask: Array, 
					   width: int, height: int, axis: int) -> void:
	var chunk_size = chunk.chunk_size
	
	for h in range(height):
		for w in range(width):
			var pos = _slice_to_position(w, h, slice_depth, axis, chunk_size)
			var neighbor_pos = pos + direction
			
			# Check if current position has a block
			var current_block = chunk.get_block(pos)
			if current_block == 0:
				continue
			
			# Check if neighbor should be culled
			var should_draw = false
			
			# Check if neighbor is outside chunk
			if not _is_position_in_chunk(neighbor_pos, chunk_size):
				# Check neighbor chunk if world manager exists
				if world_manager != null:
					var world_pos = chunk.chunk_position * chunk_size + neighbor_pos
					var neighbor_block = world_manager.get_block(world_pos)
					should_draw = (neighbor_block == 0)
				else:
					should_draw = true
			else:
				# Neighbor is inside chunk
				var neighbor_block = chunk.get_block(neighbor_pos)
				should_draw = (neighbor_block == 0)
			
			if should_draw:
				mask[h * width + w] = current_block

func _greedy_mesh_slice(mask: Array, width: int, height: int, slice_depth: int,
						face_index: int, direction: Vector3i, axis: int, chunk_size: Vector3i) -> void:
	var n = 0
	
	for h in range(height):
		var w = 0
		while w < width:
			var block_id = mask[n]
			
			if block_id >= 0:
				# Compute width of quad
				var quad_width = 1
				while w + quad_width < width and mask[n + quad_width] == block_id:
					quad_width += 1
				
				# Compute height of quad
				var quad_height = 1
				var done = false
				while h + quad_height < height and not done:
					for k in range(quad_width):
						if mask[n + quad_height * width + k] != block_id:
							done = true
							break
					if not done:
						quad_height += 1
				
				# Create quad
				_add_quad(w, h, slice_depth, quad_width, quad_height, 
						 face_index, direction, axis, block_id, chunk_size)
				
				# Clear mask for merged area
				for l in range(quad_height):
					for k in range(quad_width):
						mask[n + l * width + k] = -1
				
				w += quad_width
			else:
				w += 1
			n += 1

func _add_quad(x: int, y: int, z: int, width: int, height: int,
			   face_index: int, direction: Vector3i, axis: int,
			   block_id: int, chunk_size: Vector3i) -> void:
	var base_index = _vertices.size()
	
	# Get base vertices for this face
	var face_verts = FACE_VERTICES[face_index]
	var normal = FACE_NORMALS[face_index]
	
	# Calculate actual positions based on axis and dimensions
	var positions = _calculate_quad_positions(x, y, z, width, height, axis, face_verts)
	
	# Add vertices
	for pos in positions:
		_vertices.append(pos)
		_normals.append(normal)
		_colors.append(_get_block_color(block_id))
	
	# Add UVs (simple mapping for now)
	_uvs.append(Vector2(0, 0))
	_uvs.append(Vector2(width, 0))
	_uvs.append(Vector2(width, height))
	_uvs.append(Vector2(0, height))
	
	# Add indices
	for i in FACE_INDICES:
		_indices.append(base_index + i)

func _calculate_quad_positions(x: int, y: int, z: int, width: int, height: int,
								axis: int, face_verts: Array) -> Array:
	var positions = []
	
	for vert in face_verts:
		var pos = Vector3.ZERO
		
		if axis == 0:  # X-axis (YZ plane)
			pos = Vector3(z, y, x) + Vector3(vert.x, vert.y * height, vert.z * width)
		elif axis == 1:  # Y-axis (XZ plane)
			pos = Vector3(x, z, y) + Vector3(vert.x * width, vert.y, vert.z * height)
		else:  # Z-axis (XY plane)
			pos = Vector3(x, y, z) + Vector3(vert.x * width, vert.y * height, vert.z)
		
		positions.append(pos)
	
	return positions
#endregion

#region Private Methods - Utility
func _clear_mesh_data() -> void:
	_vertices.clear()
	_normals.clear()
	_uvs.clear()
	_indices.clear()
	_colors.clear()

func _get_primary_axis(direction: Vector3i) -> int:
	if direction.y != 0:
		return 1  # Y-axis
	elif direction.x != 0:
		return 0  # X-axis
	else:
		return 2  # Z-axis

func _get_slice_dimensions(axis: int, chunk_size: Vector3i) -> Array:
	if axis == 0:  # X-axis
		return [chunk_size.z, chunk_size.y, chunk_size.x]
	elif axis == 1:  # Y-axis
		return [chunk_size.x, chunk_size.z, chunk_size.y]
	else:  # Z-axis
		return [chunk_size.x, chunk_size.y, chunk_size.z]

func _slice_to_position(w: int, h: int, d: int, axis: int, chunk_size: Vector3i) -> Vector3i:
	if axis == 0:  # X-axis
		return Vector3i(d, h, w)
	elif axis == 1:  # Y-axis
		return Vector3i(w, d, h)
	else:  # Z-axis
		return Vector3i(w, h, d)

func _is_position_in_chunk(pos: Vector3i, chunk_size: Vector3i) -> bool:
	return (pos.x >= 0 and pos.x < chunk_size.x and
			pos.y >= 0 and pos.y < chunk_size.y and
			pos.z >= 0 and pos.z < chunk_size.z)

func _get_block_color(block_id: int) -> Color:
	# Simple color mapping based on block ID
	# This can be extended to use a texture atlas or material system
	match block_id:
		1: return Color(0.5, 0.5, 0.5)  # Stone - gray
		2: return Color(0.3, 0.6, 0.2)  # Grass - green
		3: return Color(0.4, 0.25, 0.1) # Dirt - brown
		4: return Color(0.8, 0.8, 0.8)  # Sand - light gray
		5: return Color(0.2, 0.2, 0.8)  # Water - blue
		_: return Color(1.0, 1.0, 1.0)  # Default - white
#endregion