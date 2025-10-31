@tool
extends EditorPlugin

## Voxel World Manager Plugin
##
## Registers the VoxelWorld custom node type and provides editor integration

func _enter_tree() -> void:
	# Register custom node type
	add_custom_type(
		"VoxelWorld",
		"Node3D",
		preload("res://addons/voxel_world/voxel_world.gd"),
		preload("res://addons/voxel_world/icons/voxel_world.svg")
	)
	
	print("Voxel World Manager addon loaded successfully!")

func _exit_tree() -> void:
	# Unregister custom node type
	remove_custom_type("VoxelWorld")
	
	print("Voxel World Manager addon unloaded.")

func _get_plugin_name() -> String:
	return "Voxel World Manager"