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


def _godot_processes_for(project_path: str) -> list[int]:
    """PIDs of Godot editor processes running for the given project.

    Uses WMI to match CommandLine containing '--editor' and the project path
    (normalized loosely: any segment that equals the project path). This is
    how the bridge avoids launching a duplicate editor when one is already
    open for the project (Q3: reuse an already-open editor).
    """
    import subprocess as _sp
    pids: list[int] = []
    proj = str(Path(project_path).resolve())
    try:
        if sys.platform == "win32":
            out = _sp.run(
                ["wmic", "process", "where", "Name like '%Godot%'",
                 "get", "ProcessId,CommandLine", "/format:csv"],
                capture_output=True, text=True, timeout=10,
            )
            for line in out.stdout.splitlines()[1:]:
                parts = line.split(",", 2)
                if len(parts) < 3:
                    continue
                cmd = parts[2].lower()
                if "--editor" not in cmd and "--path" not in cmd:
                    continue
                # Match project path with either slash style, no trailing.
                if proj.lower().rstrip("/").replace("\\", "/") in cmd:
                    try:
                        pids.append(int(parts[1]))
                    except ValueError:
                        pass
        else:
            # POSIX: pgrep -f
            out = _sp.run(["pgrep", "-f", f"--editor.*{proj}"],
                          capture_output=True, text=True, timeout=10)
            for pid_str in out.stdout.split():
                try:
                    pids.append(int(pid_str))
                except ValueError:
                    pass
    except Exception as e:  # noqa: BLE001
        logger.warning("godot process detection failed: %s", e)
    return pids


def is_editor_running(project_path: str) -> bool:
    return bool(_godot_processes_for(project_path))


def close_editor(project_path: str) -> bool:
    """Kill Godot editor processes running for the project."""
    pids = _godot_processes_for(project_path)
    if not pids:
        return False
    for pid in pids:
        try:
            os.kill(pid, 9) if sys.platform != "win32" else _terminate_windows(pid)
        except Exception as e:  # noqa: BLE001
            logger.warning("failed to kill editor pid %s: %s", pid, e)
    return True


def _terminate_windows(pid: int) -> None:
    import subprocess as _sp
    _sp.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True, text=True)


def launch_editor(project_path: str, port: int, godot_path: str = "") -> tuple[bool, str]:
    """Launch the Godot editor with the plugin for the given project.

    If an editor for this project is already running, does NOT launch a
    duplicate — returns (False, 'already running') so the caller can wait
    for it to connect instead.
    """
    godot = godot_path or find_godot_executable()
    if not godot:
        return False, "no Godot executable found (set GODOT_EXE)"
    if not Path(project_path).exists():
        return False, f"project not found: {project_path}"

    if is_editor_running(project_path):
        logger.info("editor already running for %s; reusing", project_path)
        return False, "already running"

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
