# Installation Guide - Heren MCP

Heren MCP is a Model Context Protocol (MCP) server for Godot Engine 4.x. It enables AI assistants to interact with Godot projects through a centralized tool system.

## Requirements

- **Python**: 3.10 or higher
- **Godot Engine**: 4.0 or higher (4.2+ recommended)
- **Operating System**: Windows, Linux, or macOS

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/heren-mcp.git
cd heren-mcp
```

### 2. Run the Installer

```bash
python install.py
```

The installer will:
- Detect your operating system
- Find your Godot installation
- Install Python dependencies
- Configure the Godot Daemon
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
        "PYTHONPATH": "./src"
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

### Step 2: Configure Godot Daemon (Optional but Recommended)

The Godot Daemon provides fast (~20ms) operations. To set it up:

1. Copy `src/heren/daemon/heren_daemon.gd` to your Godot project's `addons/heren_daemon/` folder
2. Enable the addon in Project Settings

### Step 3: Set Environment Variables (Optional)

```bash
# Windows
set GODOT_PATH=D:\Mis Juegos\Godot\Godot.exe
set GODOT_PROJECT_PATH=D:\YourGame

# Linux/macOS
export GODOT_PATH=/usr/bin/godot
export GODOT_PROJECT_PATH=/home/user/YourGame
```

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

List available tools:

```python
index(action="list")
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues.

## Next Steps

- Read the [API Reference](API.md)
- Learn about the [Architecture](ARCHITECTURE.md)
- Explore the [Spanish documentation](INSTALL.es.md)
