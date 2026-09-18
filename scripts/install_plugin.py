"""Heren MCP v4 - Plugin installer.

Copies addons/heren/ (source of truth in this repo) into a Godot project
and enables it in project.godot. This is the setup replacement for the old
v3 daemon setup: the v4 plugin travels WITH the project as an EditorPlugin.

Usage:
    python tools/install_plugin.py --project D:/path/to/godot/project
    python tools/install_plugin.py --project ... --source D:/repo/addons/heren
    python tools/install_plugin.py --project ... --force   # content-aware sync
    python tools/install_plugin.py --project ... --force --dry-run
    python tools/install_plugin.py --project ... --remove   # uninstall

Por defecto solo chequea EXISTENCIA de archivos. Con --force hace content-aware
sync: detecta archivos modificados/nuevos/borrados y sincroniza solo el diff.
Útil para iterar: edita addons/heren/ en este repo, --force actualiza el
proyecto destino sin necesidad de re-instalar desde cero.
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
OLD_PLUGIN_RE = re.compile(
    r"^\s*enabled_plugins\s*=\s*\[[^\]]*plugin\.cfg[^\]]*\]", re.MULTILINE
)


def ensure_no_bom(path: Path) -> None:
    """Rewrite a text file without UTF-8 BOM (Godot rejects BOM)."""
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        path.write_bytes(data[3:])


def _source_files_match(source: Path, dst: Path, *, content_aware: bool = False) -> bool:
    """¿TODOS los archivos del source existen en dst? (instalación completa)

    Por defecto solo chequea existencia. Si content_aware=True, también
    compara bytes — útil para sincronizar después de editar el source
    (instalación incremental real).
    """
    for f in source.rglob("*"):
        if not f.is_file():
            continue
        rel = f.relative_to(source)
        target = dst / rel
        if not target.exists():
            return False
        if content_aware:
            try:
                if f.read_bytes() != target.read_bytes():
                    return False
            except OSError:
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
            text = text.replace(
                "[editor_plugins]", "[editor_plugins]\n" + PLUGIN_LINE, 1
            )
        else:
            text = text.rstrip() + "\n\n[editor_plugins]\n" + PLUGIN_LINE + "\n"
    pg.write_text(text, encoding="utf-8")
    ensure_no_bom(pg)


def install(
    project: Path, source: Path, *, force: bool = False, dry_run: bool = False
) -> tuple[bool, str]:
    if not source.exists():
        return False, f"plugin source not found: {source}"
    if not (project / "project.godot").exists():
        return False, f"not a Godot project (no project.godot): {project}"

    dst = project / "addons" / "heren"
    # Verifica TODOS los archivos. --force (o --content-aware) hace content-aware
    # sync: detecta archivos modificados y los copia aunque ya existan.
    content_aware = force  # --force implica content-aware (alias futuro)
    if (dst / "plugin.cfg").exists() and _source_files_match(
        source, dst, content_aware=content_aware
    ):
        msg = "already installed (addons/heren synced)" if force else \
            "already installed (addons/heren/plugin.cfg exists)"
        if not dry_run:
            _normalize_enabled(project / "project.godot")
        return False, msg

    # Diff: qué archivos cambiaron/son nuevos/faltan en dst.
    changes: dict[str, list[str]] = {"new": [], "modified": [], "deleted": []}
    src_files = {f.relative_to(source) for f in source.rglob("*") if f.is_file()}
    if dst.exists():
        dst_files = {f.relative_to(dst) for f in dst.rglob("*") if f.is_file()}
        for rel in src_files:
            src_bytes = (source / rel).read_bytes()
            dst_bytes = (dst / rel).read_bytes() if (dst / rel).exists() else b""
            if rel not in dst_files:
                changes["new"].append(str(rel))
            elif src_bytes != dst_bytes:
                changes["modified"].append(str(rel))
        for rel in dst_files - src_files:
            changes["deleted"].append(str(rel))

    n_changed = sum(len(v) for v in changes.values())
    summary = (
        f"{len(changes['new'])} new, {len(changes['modified'])} modified, "
        f"{len(changes['deleted'])} deleted"
    )

    if dry_run:
        return True, f"[dry-run] would sync: {summary}"

    # Copia incremental: archivos nuevos/modificados se sobreescriben; los
    # borrados se eliminan (preserva archivos del usuario SOLO si no están
    # en el source — el plugin viaja completo).
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not dst.exists():
        shutil.copytree(source, dst)
    else:
        for rel in changes["new"] + changes["modified"]:
            target = dst / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / rel, target)
        for rel in changes["deleted"]:
            target = dst / rel
            if target.is_file():
                target.unlink()
            elif target.is_dir():
                shutil.rmtree(target)

    # Strip .uid sidecar files (Godot regenera por proyecto).
    for uid in dst.rglob("*.uid"):
        uid.unlink()

    # Enable plugin in project.godot (normaliza formato viejo).
    pg = project / "project.godot"
    had_old = OLD_PLUGIN_RE.search(pg.read_text(encoding="utf-8")) is not None
    _normalize_enabled(pg)
    force_tag = " (force)" if force else ""
    if had_old:
        msg = f"synced{force_tag} to {dst} ({summary}) + normalized [editor_plugins]"
    else:
        msg = f"synced{force_tag} to {dst} ({summary}) + enabled in project.godot"
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
    parser = argparse.ArgumentParser(
        description="Install Heren MCP v4 plugin into a Godot project"
    )
    parser.add_argument(
        "--project", required=True, help="path to the Godot project (has project.godot)"
    )
    parser.add_argument(
        "--source",
        default=str(DEFAULT_SOURCE),
        help="plugin source dir (default: repo addons/heren)",
    )
    parser.add_argument(
        "--remove", action="store_true", help="uninstall instead of install"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="content-aware sync: detecta archivos modificados y los actualiza "
             "(sin --force, asume que ya está sincronizado si plugin.cfg existe)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="muestra qué se copiaría sin tocar disco",
    )
    args = parser.parse_args()

    project = Path(args.project).resolve()
    source = Path(args.source).resolve()
    if args.remove:
        ok, msg = uninstall(project)
    else:
        ok, msg = install(project, source, force=args.force, dry_run=args.dry_run)
    print(("OK: " if ok else "SKIP: ") + msg)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
