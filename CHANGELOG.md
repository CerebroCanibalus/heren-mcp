# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-14

### Added

#### Core Infrastructure
- **13 Centralized Tools** - Single-tool architecture replacing fragmented multi-tool approaches
  - `session` - Session management (open/close/list/info/health)
  - `scene` - Scene operations (load/save/get_tree/screenshot)
  - `node` - Node manipulation (add/remove/set_prop/get_prop/duplicate/rename/move)
  - `animation` - Animation system (create_player/create/add_track/add_key/state_machine)
  - `shader` - Shader and material tools (create/edit/validate/material/uniform)
  - `skeleton` - 2D/3D rigging (create/add_bone/set_rest/skin/attachment)
  - `tilemap` - TileMap/TileSet operations (inspect/set_cell/terrain/pattern)
  - `resource` - Resource management (create/read/update/delete/list)
  - `project` - Project configuration (settings/autoloads/shader_globals)
  - `batch` - Batch operations for complex multi-step workflows
  - `debug` - Debugging tools (breakpoint/stack_trace/watch/console)
  - `validate` - Validation (scene/script/node/resource)
  - `index` - Tool discovery (list/info/example)

#### WebSocket Daemon
- **Persistent Godot Daemon** via WebSocket (~20ms per operation)
- **Automatic Fallback** to script-based execution when daemon unavailable (~370ms)
- **Zero Setup** - No plugins, no npm, no external dependencies beyond Godot
- **Session Management** with automatic cleanup
- **Headless Godot** execution support

#### Batch Operations
- High-performance batch execution for complex workflows
- Single WebSocket call for multiple operations
- Automatic rollback on errors (optional)
- Perfect for: scene creation, refactoring, imports

#### Testing & Benchmarking
- Real benchmarks vs competitors (Coding-Solo, GoPeak)
- 18x faster than Coding-Solo (20ms vs 367ms)
- 1.75x faster than GoPeak (20ms vs 35ms)
- 6x less memory than GoPeak (~75MB vs ~450MB)
- Zero setup time vs 60s+ for GoPeak

#### Language & Community
- Full Spanish and Portuguese documentation
- Iberophone-first design (Spain, Mexico, Argentina, Colombia, Brazil, Portugal)
- No language barrier for game development

#### Tools Features
- Scene tree inspection with full node hierarchy
- Screenshot capture with GPU rendering
- Animation state machine support
- ShaderMaterial uniform management
- Skeleton2D and Skeleton3D support
- Terrain painting for TileMaps
- Translation extraction and import
- Format painter for spreadsheets
- Cache management (LRU + TTL)

### Technical Details

#### Dependencies
- Python 3.10+
- `websocket-client` >= 1.6.0
- `fastmcp` >= 1.0.0
- `jinja2` >= 3.1.0 (for templates)
- `watchdog` >= 3.0.0 (for file monitoring)

#### Supported Godot Versions
- Godot 4.2+
- Godot 4.6+ (recommended)

#### Platforms
- Windows 10/11
- Linux (Ubuntu 22.04+)
- macOS (Intel & Apple Silicon)

### Documentation
- [README.md](README.md) - Overview and quick start
- [AGENTS.md](AGENTS.md) - Guide for AI agents
- [CONTRIBUTING.md](CONTRIBUTING.md) - How to contribute
- [docs/INSTALL.md](docs/INSTALL.md) - Detailed installation
- [docs/API.md](docs/API.md) - Complete API reference
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - Technical architecture
- [benchmarks/BENCHMARKS.md](benchmarks/BENCHMARKS.md) - Performance comparisons

[1.0.0]: https://github.com/tu-usuario/heren-mcp/releases/tag/v1.0.0
