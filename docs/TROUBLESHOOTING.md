# Troubleshooting - Heren MCP

Common issues and their solutions.

## Quick Diagnostic

Run this command to check your setup:

```bash
python -c "from heren.server import mcp; from heren.i18n import get_text; print('✅ Heren MCP OK')"
```

---

## Connection Issues

### "GodotDaemon is not running"

**Problem**: The daemon is not active for the session.

**Solutions:**

1. Start a session with `use_daemon=True`:
   ```python
   session(action="open", project_path="D:/YourGame", use_daemon=True)
   ```

2. Ensure Godot Editor is running with the project open

3. Check if the daemon port (9742) is available:
   ```bash
   # Windows
   netstat -an | findstr 9742
   
   # Linux/macOS
   lsof -i :9742
   ```

4. If port is in use, kill the process or wait for it to release

### "Session not found"

**Problem**: The session ID is invalid or expired.

**Solutions:**

1. List active sessions:
   ```python
   session(action="list")
   ```

2. Sessions expire after 1 hour of inactivity. Create a new one:
   ```python
   session(action="open", project_path="D:/YourGame")
   ```

3. Check the session health:
   ```python
   session(action="health", session_id="abc123")
   ```

### "Connection failed with GodotDaemon"

**Problem**: Cannot establish WebSocket connection.

**Solutions:**

1. Verify Godot Editor is running
2. Check firewall settings (allow port 9742)
3. Restart Godot Editor
4. Try without daemon (fallback mode):
   ```python
   session(action="open", project_path="D:/YourGame", use_daemon=False)
   ```

---

## Godot Detection Issues

### "Godot not found"

**Problem**: Heren MCP cannot find the Godot executable.

**Solutions:**

1. Specify the path explicitly:
   ```python
   session(
       action="open",
       project_path="D:/YourGame",
       godot_path="D:/Mis Juegos/Godot/Godot.exe"
   )
   ```

2. Add Godot to your system PATH

3. Common locations:
   - **Windows**: `D:\Mis Juegos\Godot\Godot.exe`, `C:\Program Files\Godot\Godot.exe`
   - **Linux**: `/usr/bin/godot`, `/usr/local/bin/godot`
   - **macOS**: `/Applications/Godot.app/Contents/MacOS/Godot`

### "Godot no responde"

**Problem**: Godot executable found but not responding.

**Solutions:**

1. Verify Godot version (4.0+ required):
   ```bash
   godot --version
   ```

2. Run Godot directly to check for errors:
   ```bash
   godot --headless --version
   ```

3. Reinstall Godot if corrupted

---

## Scene and Node Issues

### "Scene not found"

**Problem**: The scene file doesn't exist at the specified path.

**Solutions:**

1. Use `res://` paths (relative to project root):
   ```python
   scene(action="get_tree", session_id="abc", scene_path="res://Player.tscn")
   ```

2. Verify the file exists in your project

3. Check for typos in the path

### "Node not found"

**Problem**: The specified node doesn't exist in the scene.

**Solutions:**

1. Get the scene tree to see available nodes:
   ```python
   scene(action="get_tree", session_id="abc", scene_path="res://Player.tscn")
   ```

2. Use correct node paths (e.g., `Player/Sprite2D`, not just `Sprite2D`)

3. Remember that the root node name is part of the path

### "Node already exists"

**Problem**: Trying to add a node with a duplicate name.

**Solutions:**

1. Use a different name
2. Remove the existing node first:
   ```python
   node(action="remove", session_id="abc", scene_path="res://Player.tscn", node_path="Player/OldNode")
   ```

---

## Script and Signal Issues

### "Error en script GDScript"

**Problem**: Generated GDScript has syntax errors.

**Solutions:**

1. Check that property values are valid Godot types
2. Ensure scene paths use forward slashes (`/`)
3. Verify node paths are correct

### "Signal not found"

**Problem**: The signal doesn't exist on the source node.

**Solutions:**

1. List available signals:
   ```python
   signal(action="list", session_id="abc", scene_path="res://Player.tscn", from_node="Player/Area2D")
   ```

2. Check Godot documentation for correct signal names
3. Ensure the node type supports the signal (e.g., `body_entered` requires `Area2D`)

---

## Performance Issues

### Operations are very slow (>500ms)

**Problem**: Using fallback mode (temporary scripts) instead of daemon.

**Solutions:**

1. Use GodotDaemon for faster operations:
   ```python
   session(action="open", project_path="D:/YourGame", use_daemon=True)
   ```

2. Ensure Godot Editor is running with the project
3. Check daemon health:
   ```python
   session(action="health", session_id="abc")
   ```

### High memory usage

**Problem**: Cache growing too large.

**Solutions:**

1. Cache auto-clears after 5 minutes of inactivity
2. Restart the session to clear all caches:
   ```python
   session(action="close", session_id="abc")
   session(action="open", project_path="D:/YourGame")
   ```

---

## Installation Issues

### "pip not found"

**Problem**: Python package manager not available.

**Solutions:**

1. Install pip:
   ```bash
   python -m ensurepip --upgrade
   ```

2. Or use your system package manager:
   ```bash
   # Ubuntu/Debian
   sudo apt install python3-pip
   
   # macOS
   brew install python
   ```

### "Module not found" errors

**Problem**: Python dependencies not installed.

**Solutions:**

1. Install requirements:
   ```bash
   pip install -r requirements.txt
   ```

2. Or install individually:
   ```bash
   pip install fastmcp pydantic websocket-client
   ```

3. Ensure you're using the correct Python environment

---

## Platform-Specific Issues

### Windows: Permission Denied

**Problem**: Windows blocks script execution.

**Solutions:**

1. Run as Administrator
2. Check Windows Defender or antivirus settings
3. Ensure the project directory has write permissions

### Linux: Godot not in PATH

**Problem**: Godot installed but not accessible.

**Solutions:**

1. Create a symlink:
   ```bash
   sudo ln -s /opt/godot/Godot_v4.x /usr/local/bin/godot
   ```

2. Or add to `.bashrc`:
   ```bash
   export PATH="$PATH:/opt/godot"
   ```

### macOS: "App can't be opened"

**Problem**: macOS Gatekeeper blocks unsigned applications.

**Solutions:**

1. Right-click Godot.app and select "Open"
2. Or in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Godot.app
   ```

---

## Getting Help

If your issue isn't listed here:

1. Check the logs for detailed error messages
2. Run with debug logging:
   ```bash
   python -m heren.server --log-level DEBUG
   ```

3. Check if it's a known issue in the project repository

4. Include this information when reporting:
   - OS and version
   - Godot version
   - Python version
   - Full error message
   - Steps to reproduce

---

## Error Code Reference

| Error Code | Meaning | Solution |
|------------|---------|----------|
| `daemon_not_running` | GodotDaemon not active | Start session with `use_daemon=True` |
| `session_not_found` | Invalid/expired session ID | Create new session |
| `scene_not_found` | Scene file missing | Check path and file existence |
| `node_not_found` | Node doesn't exist in scene | Check node path |
| `godot_not_found` | Godot executable not found | Specify `godot_path` |
| `timeout_error` | Operation timed out | Check Godot is responsive |
| `invalid_parameters` | Wrong parameters for action | Check API docs |
| `file_not_found` | Required file missing | Check file path |
| `permission_denied` | Insufficient permissions | Run with appropriate permissions |

## Related Documents

- [Installation Guide](INSTALL.md)
- [API Reference](API.md)
- [Architecture](ARCHITECTURE.md)
