"""Heren MCP v4 - Plugin installer.

Copies addons/heren/ (source of truth in this repo) into a Godot project
and enables it in project.godot. This is the setup replacement for the old
v3 daemon setup: the v4 plugin travels WITH the project as an EditorPlugin.

Usage:
    python tools/install_plugin.py --project D:/path/to/godot/project
    python tools/install_plugin.py --project ... --source D:/repo/addons/heren
    python tools/install_plugin.py --project ... --remove   # uninstall
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

# Repo root: tools/install_plugin.py -> parents[1]
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = REPO_ROOT / "addons" / "heren"
PLUGIN_LINE = 'enabled=PackedStringArray("res://addons/heren/plugin.cfg")'
# Línea vieja (formato Godot 3/manual) que debe NORMALIZARSE al formato 4.
OLD_PLUGIN_RE = re.compile(r'^\s*enabled_plugins\s*=\s*\[[^\]]*plugin\.cfg[^\]]*\]', re.MULTILINE)


def ensure_no_bom(path: Path) -> None:
    """Rewrite a text file without UTF-8 BOM (Godot rejects BOM)."""
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        path.write_bytes(data[3:])


def _source_files_match(source: Path, dst: Path) -> bool:
    """¿TODOS los archivos del source existen en dst? (instalación completa)"""
    for f in source.rglob("*"):
        if f.is_file():
            rel = f.relative_to(source)
            if not (dst / rel).exists():
                return False
    return True


def _normalize_enabled(pg: Path) -> None:
    """Asegura [editor_plugins] enabled=PackedStringArray(...) en project.godot.
    Normaliza el formato viejo enabled_plugins=[...] al formato Godot 4."""
    text = pg.read_text(encoding="utf-8")
    if PLUGIN_LINE in text:
        return
    if OLD_PLUGIN_RE.search(text):
        text = OLD_PLUGIN_RE.sub(PLUGIN_LINE, text)
    else:
        if "[editor_plugins]" in text:
            text = text.replace("[editor_plugins]", "[editor_plugins]\n" + PLUGIN_LINE, 1)
        else:
            text = text.rstrip() + "\n\n[editor_plugins]\n" + PLUGIN_LINE + "\n"
    pg.write_text(text, encoding="utf-8")
    ensure_no_bom(pg)


def install(project: Path, source: Path) -> tuple[bool, str]:
    if not source.exists():
        return False, f"plugin source not found: {source}"
    if not (project / "project.godot").exists():
        return False, f"not a Godot project (no project.godot): {project}"

    dst = project / "addons" / "heren"
    # Verifica TODOS los archivos, no solo plugin.cfg (instalación parcial).
    if (dst / "plugin.cfg").exists() and _source_files_match(source, dst):
        msg = "already installed (addons/heren/plugin.cfg exists)"
        _normalize_enabled(project / "project.godot")
        return False, msg

    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(source, dst)
    # Strip .uid sidecar files (Godot regenerates per-project).
    for uid in dst.rglob("*.uid"):
        uid.unlink()

    # Enable plugin in project.godot (normaliza formato viejo).
    pg = project / "project.godot"
    had_old = OLD_PLUGIN_RE.search(pg.read_text(encoding="utf-8")) is not None
    _normalize_enabled(pg)
    if had_old:
        msg = f"installed to {dst} + normalized [editor_plugins] format"
    else:
        msg = f"installed to {dst} + enabled in project.godot"
    return True, msg


def uninstall(project: Path) -> tuple[bool, str]:
    dst = project / "addons" / "heren"
    if dst.exists():
        shutil.rmtree(dst)

    pg = project / "project.godot"
    if pg.exists():
        text = pg.read_text(encoding="utf-8")
        text = text.replace(PLUGIN_LINE + "\n", "")
        text = text.replace("\n" + PLUGIN_LINE, "")
        pg.write_text(text, encoding="utf-8")
        ensure_no_bom(pg)

    return True, f"removed {dst}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Install Heren MCP v4 plugin into a Godot project")
    parser.add_argument("--project", required=True, help="path to the Godot project (has project.godot)")
    parser.add_argument("--source", default=str(DEFAULT_SOURCE), help="plugin source dir (default: repo addons/heren)")
    parser.add_argument("--remove", action="store_true", help="uninstall instead of install")
    args = parser.parse_args()

    project = Path(args.project).resolve()
    source = Path(args.source).resolve()
    ok, msg = uninstall(project) if args.remove else install(project, source)
    print(("OK: " if ok else "SKIP: ") + msg)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
