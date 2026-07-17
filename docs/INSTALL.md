# Installation Guide - Heren MCP

Heren MCP is a Model Context Protocol (MCP) server for Godot Engine 4.x. It enables AI assistants to interact with Godot projects through a centralized tool system.

## Requirements

- **Python**: 3.10 or higher
- **Godot Engine**: 4.2 or higher (4.6+ recommended)
- **Operating System**: Windows, Linux, or macOS

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/CerebroCanibalus/heren-mcp.git
cd heren-mcp
```

### 2. Run the Installer

```bash
python install.py
```

Or with a specific project:

```bash
python install.py --project-path D:/YourGame
```

The installer will:
- Detect your operating system
- Find your Godot installation
- Install Python dependencies
- Copy the Heren daemon files into your Godot project (`addons/heren/daemon/`)
- Show MCP configuration instructions

### 3. Configure Your MCP Client

Add the following to your MCP client configuration (e.g., `opencode.jsonc`):

```json
{
  "mcpServers": {
    "heren-godot": {
      "command": "python",
      "args": ["-m", "heren.server"],
      "env": {
        "PYTHONPATH": "./src",
        "GODOT_EXE": "D:/Mis Juegos/Godot/Godot_v4.6.1-stable_win64.exe",
        "HEREN_PROJECT_PATH": "D:/YourGame"
      }
    }
  }
}
```

### 4. Start Using Heren MCP

Open a Godot project and start a session:

```python
session(action="open", project_path="D:/YourGame")
```

## Manual Installation

If you prefer manual installation or the automatic installer fails:

### Step 1: Install Python Dependencies

```bash
pip install -r requirements.txt
```

Required packages:
- `fastmcp>=1.0.0` - MCP framework
- `pydantic>=2.0.0` - Data validation
- `websocket-client>=1.6.0` - WebSocket communication with Godot

### Step 2: Configure Godot Daemon in Your Project

The Godot Daemon provides fast (~20ms) operations. To set it up, run from the heren-mcp directory:

```bash
python -m heren.tools.project_tool setup_daemon --project-path D:/YourGame
```

Or programmatically:

```python
from heren.tools.project_tool import project_tool
project_tool("setup_daemon", project_path="D:/YourGame")
```

This copies all daemon files (`heren_daemon.gd` + modules) into `D:/YourGame/addons/heren/daemon/`.

### Step 3: Set Environment Variables (Optional)

```bash
# Windows
set GODOT_EXE=D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe
set HEREN_PROJECT_PATH=D:\YourGame

# Linux/macOS
export GODOT_EXE=/usr/bin/godot
export HEREN_PROJECT_PATH=/home/user/YourGame
```

Supported variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `GODOT_EXE` | Path to Godot executable | `D:/Godot/Godot.exe` |
| `GODOT_PATH` | Alias for `GODOT_EXE` | `D:/Godot/Godot.exe` |
| `HEREN_PROJECT_PATH` | Default Godot project path | `D:/YourGame` |
| `HEREN_PORT` | Daemon WebSocket port | `4567` |
| `HEREN_LOG_LEVEL` | Logging level | `INFO`, `DEBUG` |

## Platform-Specific Notes

### Windows

- Godot is commonly installed at `D:\Mis Juegos\Godot\` or `C:\Program Files\Godot\`
- The installer searches these paths automatically
- If Godot is not found, specify the path with `--godot-path`

### Linux

- Install Godot via package manager or download from godotengine.org
- Common paths: `/usr/bin/godot`, `/usr/local/bin/godot`
- The installer checks `PATH` for `godot` executable

### macOS

- Godot is typically in `/Applications/Godot.app`
- The installer checks common application directories
- You can also install via Homebrew: `brew install --cask godot`

## Verification

Test your installation:

```bash
python -c "from heren.server import mcp; print('Heren MCP loaded successfully')"
```

Open a session and list loaded scenes:

```python
from heren.tools.session_tool import session_tool
from heren.tools.scene_tool import scene_tool

session = session_tool("open", project_path="D:/YourGame")
print(session)
scene_tool("list_loaded", session_id=session["session_id"])
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues.

## Next Steps

- Read the [API Reference](API.md)
- Learn about the [Architecture](ARCHITECTURE.md)
- Explore the [Spanish documentation](INSTALL.es.md)
