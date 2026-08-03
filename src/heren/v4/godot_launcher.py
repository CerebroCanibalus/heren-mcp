"""Heren MCP v4 - Godot editor launcher.

Auto-lanza el editor Godot con el plugin v4 cuando no hay editor conectado.
Usa last_project de .heren/session.json (ADR-004) para reanudar trabajo.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import sys
from pathlib import Path

logger = logging.getLogger(__name__)

# Known Godot executables (checked in order; env vars take priority).
_GODOT_CANDIDATES = [
    "Godot_v4.7.1-stable_win64_console.exe",
    "Godot_v4.7.1-stable_win64.exe",
    "Godot_v4.6.1-stable_win64_console.exe",
    "Godot_v4.6.1-stable_win64.exe",
    "Godot_v4.6-stable_win64_console.exe",
    "Godot_v4.6-stable_win64.exe",
]

_GODOT_DIRS = [
    Path(r"D:\Mis Juegos\Godot"),
    Path(r"C:\Program Files\Godot"),
    Path(r"C:\Program Files (x86)\Godot"),
]


def find_godot_executable() -> str:
    """Resolve the Godot editor executable."""
    # 1. Explicit env vars (GODOT_EXE / GODOT_PATH) - highest priority.
    for env in ("GODOT_EXE", "GODOT_PATH"):
        val = os.environ.get(env)
        if val and Path(val).exists():
            return val
    # 2. Executable on PATH.
    which = shutil.which("godot")
    if which:
        return which
    # 3. Known locations.
    for d in _GODOT_DIRS:
        for name in _GODOT_CANDIDATES:
            p = d / name
            if p.exists():
                return str(p)
    return ""


def session_file(project_path: str) -> Path:
    """Path to .heren/session.json inside the project."""
    return Path(project_path) / ".heren" / "session.json"


def read_last_project(project_path: str) -> str | None:
    """Read last_project from .heren/session.json (ADR-004: 1 key only)."""
    f = session_file(project_path)
    try:
        if f.exists():
            data = json.loads(f.read_text(encoding="utf-8"))
            last = data.get("last_project")
            if last and Path(last).exists():
                return last
    except Exception as e:  # noqa: BLE001
        logger.warning("read_last_project failed: %s", e)
    return None


def write_last_project(project_path: str, last: str) -> None:
    """Write last_project (single key, ADR-004)."""
    f = session_file(project_path)
    try:
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(json.dumps({"last_project": last}, indent=2), encoding="utf-8")
    except Exception as e:  # noqa: BLE001
        logger.warning("write_last_project failed: %s", e)


def ensure_plugin_installed(project_path: str, plugin_source: Path | None = None) -> tuple[bool, str]:
    """Copy addons/heren/ into the project if missing.

    Returns (installed, message). The source defaults to the addon bundled
    with this package (addons/heren next to src/).
    """
    if plugin_source is None:
        # Heuristic: <repo_root>/addons/heren (source of truth).
        here = Path(__file__).resolve()
        # src/heren/v4/godot_launcher.py -> repo root is ../../../..
        candidate = here.parents[3] / "addons" / "heren"
        if candidate.exists():
            plugin_source = candidate
        else:
            return False, "plugin source not found"

    dst = Path(project_path) / "addons" / "heren"
    if (dst / "plugin.cfg").exists():
        return False, "already installed"
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(plugin_source, dst, dirs_exist_ok=True)
    return True, f"installed from {plugin_source}"


def enable_plugin_in_project(project_path: str) -> bool:
    """Add [editor_plugins] enabled=PackedStringArray(...) to project.godot.

    Returns True if the plugin was (re)enabled.
    """
    pg = Path(project_path) / "project.godot"
    if not pg.exists():
        return False
    text = pg.read_text(encoding="utf-8")
    plugin_line = 'enabled=PackedStringArray("res://addons/heren/plugin.cfg")'
    if "addons/heren/plugin.cfg" in text:
        return False
    if "[editor_plugins]" in text:
        # Append to existing section.
        text = text.replace("[editor_plugins]", "[editor_plugins]\n" + plugin_line)
    else:
        text = text.rstrip() + "\n\n[editor_plugins]\n" + plugin_line + "\n"
    pg.write_text(text, encoding="utf-8")
    return True


def launch_editor(project_path: str, port: int, godot_path: str = "") -> tuple[bool, str]:
    """Launch the Godot editor with the plugin for the given project."""
    godot = godot_path or find_godot_executable()
    if not godot:
        return False, "no Godot executable found (set GODOT_EXE)"
    if not Path(project_path).exists():
        return False, f"project not found: {project_path}"

    installed, msg = ensure_plugin_installed(project_path)
    enable_plugin_in_project(project_path)
    write_last_project(project_path, str(Path(project_path).resolve()))

    env = os.environ.copy()
    env["HEREN_MCP_PORT"] = str(port)
    logger.info("launching Godot editor: %s --editor --path %s", godot, project_path)
    try:
        subprocess.Popen(
            [godot, "--editor", "--path", str(project_path)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
        )
    except Exception as e:  # noqa: BLE001
        return False, f"launch failed: {e}"
    return True, msg
