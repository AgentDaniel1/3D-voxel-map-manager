# 🧊 Voxel World Manager - Godot 4.5 Addon

A complete, production-ready voxel world management system for Godot 4.5. Perfect for Minecraft-like games, voxel editors, and procedural worlds.

## ✨ Features

### Core Features
- **Chunk-based World Management** - Efficient streaming and memory management
- **Optimized Mesh Generation** - Greedy meshing algorithm with face culling
- **Automatic Save/Load** - Persistent world data with compression
- **Dynamic Chunk Loading** - Camera-based streaming with configurable render distance
- **Collision Generation** - Automatic per-chunk collision meshes
- **Clean API** - Simple, intuitive methods for block manipulation

### Performance Optimizations
- ✅ Greedy meshing reduces vertex count by up to 80%
- ✅ Face culling eliminates hidden geometry
- ✅ Chunk streaming based on render distance
- ✅ Configurable chunks per frame to prevent lag
- ✅ RLE compression for save data
- ✅ Bulk operations for placing multiple blocks
- ✅ Neighbor chunk update optimization

### Signals
- `chunk_loaded(chunk_position: Vector3i)`
- `chunk_unloaded(chunk_position: Vector3i)`
- `block_modified(world_position: Vector3i, block_id: int)`
- `chunk_saved(chunk_position: Vector3i)`
- `chunk_mesh_generated(chunk_position: Vector3i)`

## 📦 Installation

1. Download or clone this repository
2. Copy the `addons/voxel_world` folder to your project's `addons/` directory
3. Enable the plugin in Project Settings → Plugins → "Voxel World Manager"

## 🚀 Quick Start

### Basic Setup

1. Add a `VoxelWorld` node to your scene (it appears under Node3D in the Add Node dialog)
2. Configure settings in the Inspector
3. Use the API to place blocks!

```gdscript
extends Node3D

@onready var voxel_world: VoxelWorld = $VoxelWorld

func _ready():
    # Place a single block
    voxel_world.set_block(Vector3i(0, 0, 0), 1)
    
    # Place multiple blocks efficiently
    var blocks = [
        {"position": Vector3i(0, 0, 0), "block_id": 1},
        {"position": Vector3i(1, 0, 0), "block_id": 2},
        {"position": Vector3i(2, 0, 0), "block_id": 3}
    ]
    voxel_world.set_blocks_bulk(blocks)
```

## 🎮 API Reference

### Block Management

#### `set_block(world_pos: Vector3i, block_id: int) -> bool`
Place a block at world position. Returns `true` if successful.
```gdscript
voxel_world.set_block(Vector3i(10, 5, 10), 1)  # Place stone
```

#### `get_block(world_pos: Vector3i) -> int`
Get block ID at world position. Returns `0` for air or unloaded chunks.
```gdscript
var block_id = voxel_world.get_block(Vector3i(10, 5, 10))
```

#### `destroy_block(world_pos: Vector3i) -> bool`
Remove a block (sets to air/0).
```gdscript
voxel_world.destroy_block(Vector3i(10, 5, 10))
```

#### `has_block(world_pos: Vector3i) -> bool`
Check if a solid block exists at position.
```gdscript
if voxel_world.has_block(Vector3i(10, 5, 10)):
    print("Block exists!")
```

#### `set_blocks_bulk(blocks_data: Array) -> void`
Efficiently place multiple blocks at once. **Much faster** than multiple `set_block()` calls.
```gdscript
var blocks = []
for x in range(10):
    for z in range(10):
        blocks.append({
            "position": Vector3i(x, 0, z),
            "block_id": 2  # Grass
        })
voxel_world.set_blocks_bulk(blocks)
```

### Chunk Management

#### `load_chunk(chunk_pos: Vector3i) -> void`
Manually load a chunk at chunk coordinates.
```gdscript
voxel_world.load_chunk(Vector3i(0, 0, 0))
```

#### `unload_chunk(chunk_pos: Vector3i, save_before_unload: bool = true) -> void`
Unload a chunk and optionally save it.
```gdscript
voxel_world.unload_chunk(Vector3i(5, 0, 5), true)
```

#### `is_chunk_loaded(chunk_pos: Vector3i) -> bool`
Check if a chunk is currently loaded.
```gdscript
if voxel_world.is_chunk_loaded(Vector3i(0, 0, 0)):
    print("Chunk is loaded")
```

#### `get_loaded_chunks() -> Array[Vector3i]`
Get array of all loaded chunk positions.
```gdscript
var chunks = voxel_world.get_loaded_chunks()
print("Loaded %d chunks" % chunks.size())
```

#### `reload_chunk(chunk_pos: Vector3i) -> void`
Force regenerate mesh for a chunk.
```gdscript
voxel_world.reload_chunk(Vector3i(0, 0, 0))
```

### Save/Load

#### `save_chunk(chunk_pos: Vector3i) -> bool`
Save a specific chunk to disk.
```gdscript
voxel_world.save_chunk(Vector3i(0, 0, 0))
```

#### `save_all_chunks() -> void`
Save all loaded chunks.
```gdscript
voxel_world.save_all_chunks()
```

#### `clear_world(save_before_clear: bool = true) -> void`
Clear all chunks from memory.
```gdscript
voxel_world.clear_world(true)  # Save before clearing
```

### Coordinate Conversion

#### `world_to_chunk(world_pos: Vector3) -> Vector3i`
Convert world position to chunk position.
```gdscript
var chunk_pos = voxel_world.world_to_chunk(Vector3(25, 10, 30))
```

#### `world_to_local(world_pos: Vector3i) -> Vector3i`
Convert world position to local chunk position.
```gdscript
var local_pos = voxel_world.world_to_local(Vector3i(25, 10, 30))
```

#### `chunk_to_world(chunk_pos: Vector3i) -> Vector3`
Convert chunk position to world position (corner).
```gdscript
var world_pos = voxel_world.chunk_to_world(Vector3i(1, 0, 1))
```

## ⚙️ Inspector Settings

### Chunk Settings
- **Chunk Size XZ** (8-64, step 8) - Horizontal chunk dimensions
- **Chunk Size Y** (8-256, step 8) - Vertical chunk dimension

### Render Distance
- **Render Distance XZ** (2-32) - Horizontal render distance in chunks
- **Render Distance Y** (1-16) - Vertical render distance in chunks

### Performance
- **Max Chunks Per Frame** (0-10) - Limit mesh generation per frame (0 = unlimited)
- **Generate Collision** - Enable/disable collision mesh generation
- **Auto Save Chunks** - Automatically save modified chunks on unload

### Persistence
- **Save Directory** - Where chunk data is saved (default: `user://voxel_world/chunks`)
- **Compress Chunks** - Enable compression for smaller save files

### Debug
- **Show Debug Info** - Display debug information
- **Show Chunk Boundaries** - Visualize chunk edges (editor only)

## 📊 Block IDs

The system uses integer IDs for blocks. You can define your own mapping:

```gdscript
enum BlockType {
    AIR = 0,
    STONE = 1,
    GRASS = 2,
    DIRT = 3,
    SAND = 4,
    WATER = 5,
    WOOD = 6,
    LEAVES = 7
}
```

## 🎨 Customization

### Custom Block Colors

Edit `VoxelMeshBuilder.gd` → `_get_block_color()`:

```gdscript
func _get_block_color(block_id: int) -> Color:
    match block_id:
        1: return Color(0.5, 0.5, 0.5)  # Stone
        2: return Color(0.3, 0.6, 0.2)  # Grass
        3: return Color(0.4, 0.25, 0.1) # Dirt
        _: return Color(1.0, 1.0, 1.0)
```

### Texture Atlas Support

The system generates UVs ready for texture atlases. Extend `_get_block_color()` or add UV mapping logic in `VoxelMeshBuilder._add_quad()`.

## 🏗️ Project Structure

```
addons/voxel_world/
├── plugin.cfg              # Plugin configuration
├── plugin.gd               # Plugin entry point
├── voxel_world.gd          # Main world manager
├── voxel_chunk.gd          # Individual chunk class
├── voxel_mesh_builder.gd   # Mesh generation
└── icons/
    └── voxel_world.svg     # Node icon
```

## 📝 Example: Terrain Generation

```gdscript
func generate_terrain(size: int, height: int):
    var blocks = []
    
    for x in range(-size, size):
        for z in range(-size, size):
            # Simple height map
            var h = int(sin(x * 0.1) * cos(z * 0.1) * height)
            
            # Place blocks
            for y in range(h):
                var block_id = 1  # Stone
                if y == h - 1:
                    block_id = 2  # Grass on top
                elif y > h - 4:
                    block_id = 3  # Dirt below grass
                
                blocks.append({
                    "position": Vector3i(x, y, z),
                    "block_id": block_id
                })
    
    voxel_world.set_blocks_bulk(blocks)
```

## 🔧 Performance Tips

1. **Use `set_blocks_bulk()`** for placing multiple blocks
2. **Adjust render distance** based on target platform
3. **Limit `max_chunks_per_frame`** to prevent frame drops
4. **Enable compression** for smaller save files
5. **Use signals wisely** - avoid heavy processing in `block_modified`

## 🐛 Troubleshooting

**Chunks not loading?**
- Check that a Camera3D is in the scene
- Verify render distance settings
- Check console for errors

**Performance issues?**
- Reduce render distance
- Lower `max_chunks_per_frame`
- Disable collision if not needed

**Blocks not appearing?**
- Ensure block_id > 0 (0 is air)
- Check chunk is within render distance
- Verify world coordinates are correct

## 📄 License

MIT License - Feel free to use in commercial projects!

## 🤝 Contributing

Contributions welcome! Feel free to submit issues and pull requests.

## 🔗 Links

- [Godot Engine](https://godotengine.org/)
- [Documentation](https://docs.godotengine.org/)
- [VoxelWorldGenerator](https://github.com/AgentDaniel1/3D-voxel-map-generator.git)

---

Made with ❤️ for the Godot community
