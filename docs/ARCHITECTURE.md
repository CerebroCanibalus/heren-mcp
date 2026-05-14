# Architecture - Heren MCP

This document describes the architecture and design philosophy of Heren MCP.

## Design Philosophy

**Centralized. Modular. Powerful.**

Heren MCP follows these core principles:

1. **Centralization**: 15 tools handle ALL Godot operations
2. **Modularity**: Each tool has multiple actions via the `action` parameter
3. **Power**: Godot does the heavy lifting; Heren orchestrates
4. **Speed**: GodotDaemon provides ~20ms operations via persistent WebSocket
5. **Resilience**: Automatic fallback to temporary scripts if daemon is unavailable

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MCP Client (OpenCode)                    │
└──────────────────────┬──────────────────────────────────────┘
                       │ MCP Protocol
┌──────────────────────▼──────────────────────────────────────┐
│                  Heren MCP Server                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Tools     │  │  Tools Index│  │  i18n (es/en)       │  │
│  │  (15 tools) │  │  (Discovery)│  │  (Auto-detect)      │  │
│  └──────┬──────┘  └─────────────┘  └─────────────────────┘  │
│         │                                                   │
│  ┌──────▼──────────────────────────────────────────────┐   │
│  │              Session Manager (Layer 0)               │   │
│  │  ┌────────────┐  ┌────────────┐  ┌──────────────┐   │   │
│  │  │  Sessions  │  │    Cache   │  │  Temp Files  │   │   │
│  │  │  (Active)  │  │  (LRU+TTL) │  │  (GDScripts) │   │   │
│  │  └─────┬──────┘  └────────────┘  └──────────────┘   │   │
│  │        │                                             │   │
│  │  ┌─────▼──────┐  ┌──────────────┐                   │   │
│  │  │GodotDaemon │  │ GodotServer  │  (Legacy HTTP)    │   │
│  │  │(WebSocket) │  │   (HTTP)     │                   │   │
│  │  └─────┬──────┘  └──────────────┘                   │   │
│  └────────┼─────────────────────────────────────────────┘   │
└───────────┼─────────────────────────────────────────────────┘
            │
┌───────────▼─────────────────────────────────────────────────┐
│                 Godot Engine (External)                     │
│  ┌────────────┐  ┌────────────┐  ┌──────────────────────┐  │
│  │   Editor   │  │  Projects  │  │  heren_daemon.gd     │  │
│  │   (CLI)    │  │  (.tscn)   │  │  (WebSocket server)  │  │
│  └────────────┘  └────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Layer Structure

### Layer 3: Tools (User Interface)

The public API exposed to MCP clients. Each tool is a Python function decorated with `@mcp.tool()`.

**Key Tools:**
- `session_tool` - Session lifecycle
- `scene_tool` - Scene CRUD operations
- `node_tool` - Node manipulation
- `signal_tool` - Signal connections
- `global_tool` - Project configuration

### Layer 2: Interface (Abstraction)

`GodotInterface` class in `godot_cli.py` provides high-level methods that:
- Generate GDScript templates
- Handle retries and timeouts
- Process responses
- Manage cache invalidation

### Layer 1: Session Manager (Coordination)

`SessionManager` singleton handles:
- Session creation/destruction
- Godot executable detection
- GDScript execution via subprocess
- Cache management (LRU + TTL)
- Cleanup of expired sessions

### Layer 0: Communication (Transport)

Two communication modes:

1. **GodotDaemon (Primary)**
   - Persistent WebSocket connection
   - ~20ms response time
   - Requires running Godot Editor
   - Implemented in `godot_daemon.py`

2. **Temporary Scripts (Fallback)**
   - Spawns Godot CLI with `--script`
   - ~370ms response time
   - Works without Editor
   - Uses `TemplateEngine` for GDScript generation

## Data Flow

### With Daemon (Fast Path)

```
Client → Tool Function → Session Manager → GodotDaemon → Godot Editor
                                          ↓
                                    WebSocket (~20ms)
                                          ↓
Client ← JSON Response ← Session Manager ← GodotDaemon
```

### Without Daemon (Fallback Path)

```
Client → Tool Function → Session Manager → TemplateEngine → GDScript File
                                          ↓
                                    Godot CLI --script (~370ms)
                                          ↓
Client ← JSON Response ← Session Manager ← Godot Output
```

## Cache Strategy

### Scene Cache
- **Type**: LRU with TTL
- **Max Size**: 50 entries
- **TTL**: 5 minutes
- **Invalidation**: On scene save/modification

### Resource Cache
- **Type**: LRU with TTL
- **Max Size**: 100 entries
- **TTL**: 5 minutes

## Session Lifecycle

```
1. CREATE
   └── SessionManager.start_session()
       ├── Auto-detect Godot executable
       ├── Start GodotDaemon (if requested)
       └── Create session with UUID

2. USE
   └── Operations via Tools
       ├── Cache lookup (fast path)
       ├── Daemon execution (fast path)
       └── Fallback to scripts (slow path)

3. DESTROY
   └── SessionManager.end_session()
       ├── Stop GodotDaemon
       ├── Clear caches
       └── Cleanup temp files
```

## Internationalization (i18n)

Heren MCP supports two languages:
- **Spanish (es)**: Default fallback
- **English (en)**: Auto-detected from OS locale

The system:
1. Detects OS locale on startup
2. Loads translations from JSON files
3. Falls back to Spanish if translation missing
4. Supports variable interpolation

## Error Handling

```
Error Hierarchy:
├── Session Errors (session_not_found, expired)
├── Daemon Errors (daemon_not_running, connection_failed)
├── Scene Errors (scene_not_found, invalid_format)
├── Node Errors (node_not_found, property_not_found)
├── Validation Errors (invalid_parameters, script_error)
└── System Errors (file_not_found, permission_denied)
```

All errors return a consistent format:
```json
{
  "success": false,
  "error": "error_key",
  "message": "Human-readable description"
}
```

## Plugin Architecture

Tools are organized as plugins following the FastMCP pattern:

```python
@mcp.tool()
def my_tool(action: str, **kwargs) -> dict:
    """Tool documentation."""
    return implementation(action, **kwargs)
```

New tools can be added by:
1. Creating a module in `src/heren/tools/`
2. Implementing the tool function
3. Registering in `server.py`
4. Adding to `tools_index.py`

## Performance Benchmarks

| Operation | With Daemon | Without Daemon | Improvement |
|-----------|-------------|----------------|-------------|
| Get Scene Tree | ~20ms | ~370ms | 18.5x |
| Add Node | ~20ms | ~400ms | 20x |
| Set Property | ~20ms | ~380ms | 19x |
| Save Scene | ~15ms | ~350ms | 23x |
| Batch (10 ops) | ~50ms | ~3500ms | 70x |

## Security Considerations

- Temporary GDScript files are cleaned up after execution
- Sessions expire after 1 hour of inactivity
- File operations are restricted to project directory
- No arbitrary code execution (only predefined templates)

## Future Improvements

1. **GodotDaemon in C++**: Native GDExtension for even faster communication
2. **Incremental Updates**: Only sync changed nodes instead of full scene
3. **Multi-project**: Support for multiple simultaneous projects
4. **Undo/Redo Stack**: Full operation history with rollback support
5. **Asset Pipeline**: Import and manage external assets

## Related Documents

- [Installation Guide](INSTALL.md)
- [API Reference](API.md)
- [Troubleshooting](TROUBLESHOOTING.md)
