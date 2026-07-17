"""
pytest fixtures for Heren MCP tests (v3 - GodotDaemon Only).

Organizacion:
- Fixtures compartidas: temp_project, daemon_session
- Helpers: create_minimal_project, create_sample_scene
- Marcadores: integration (requiere Godot), daemon (requiere daemon activo)

No hay fallback: GodotDaemon es el UNICO modo.
"""

import os
import sys
import tempfile
import shutil
from pathlib import Path

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from heren.core.session_manager import get_session_manager


GODOT_EXE = os.environ.get("GODOT_EXE", r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe")
LAIKA_PROJECT = r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd"


def create_minimal_project(project_dir: str) -> str:
    project_file = os.path.join(project_dir, "project.godot")
    with open(project_file, "w", encoding="utf-8") as f:
        f.write("""[application]
config/name="TestProject"
config/features=PackedStringArray("4.6")

[rendering]
renderer/rendering_method="forward_plus"
""")
    return project_file


def create_sample_scene(scene_path: str, root_type: str = "Node2D", root_name: str = "Root") -> str:
    with open(scene_path, "w", encoding="utf-8") as f:
        f.write(f"""[gd_scene load_steps=1 format=3]

[node name="{root_name}" type="{root_type}"]
""")
    return scene_path


def create_complex_scene(scene_path: str) -> str:
    with open(scene_path, "w", encoding="utf-8") as f:
        f.write("""[gd_scene load_steps=1 format=3]

[node name="Root" type="Node2D"]

[node name="Player" type="CharacterBody2D" parent="."]
position = Vector2(100, 200)

[node name="Sprite" type="Sprite2D" parent="Player"]

[node name="CollisionShape2D" type="CollisionShape2D" parent="Player"]

[node name="Enemy" type="CharacterBody2D" parent="."]
position = Vector2(300, 200)
""")
    return scene_path


@pytest.fixture(autouse=True)
def reset_session_manager():
    manager = get_session_manager()
    manager.shutdown_all()
    yield
    manager = get_session_manager()
    manager.shutdown_all()


@pytest.fixture
def temp_project():
    tmpdir = tempfile.mkdtemp(prefix="heren_test_")
    try:
        create_minimal_project(tmpdir)
        yield tmpdir
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


@pytest.fixture
def temp_scene(temp_project):
    scene_path = os.path.join(temp_project, "test_scene.tscn")
    create_sample_scene(scene_path)
    return scene_path


@pytest.fixture
def daemon_session():
    """Create a session with GodotDaemon active (uses LAIKA project)."""
    if not os.path.exists(GODOT_EXE):
        pytest.skip(f"Godot executable not found at {GODOT_EXE}")

    if not os.path.exists(LAIKA_PROJECT):
        pytest.skip(f"LAIKA project not found at {LAIKA_PROJECT}")

    from heren.tools.session_tool import session_tool

    result = session_tool(action="open", project_path=LAIKA_PROJECT)
    assert result.get("success") is True, f"Failed to start session: {result.get('error')}"

    session_id = result["session_id"]

    yield session_id

    session_tool(action="close", session_id=session_id)


def pytest_configure(config):
    config.addinivalue_line("markers", "integration: marks tests that require Godot engine")
    config.addinivalue_line("markers", "daemon: marks tests that require GodotDaemon")
    config.addinivalue_line("markers", "benchmark: marks slow benchmark tests")
    config.addinivalue_line("markers", "slow: marks tests as slow")
    config.addinivalue_line("markers", "tool: marks tool-specific tests")


@pytest.fixture
def skip_without_godot():
    if not os.path.exists(GODOT_EXE):
        pytest.skip(f"Godot executable not found at {GODOT_EXE}")


@pytest.fixture
def skip_without_laika():
    if not os.path.exists(LAIKA_PROJECT):
        pytest.skip(f"LAIKA project not found at {LAIKA_PROJECT}")
