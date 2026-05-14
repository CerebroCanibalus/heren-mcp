"""
pytest fixtures for Heren MCP tests (v2 - GodotDaemon).

Organización:
- Fixtures compartidas: temp_project, session_id, daemon_session
- Helpers: create_minimal_project, create_sample_scene
- Marcadores: integration (requiere Godot), daemon (requiere daemon activo)
"""

import os
import sys
import tempfile
import shutil
from pathlib import Path

import pytest

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from heren.core.session_manager import get_session_manager


# =============================================================================
# Constants
# =============================================================================

GODOT_EXE = os.environ.get("GODOT_EXE", r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe")
LAIKA_PROJECT = r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd"


# =============================================================================
# Helpers
# =============================================================================

def create_minimal_project(project_dir: str) -> str:
    """Create a minimal Godot project with project.godot."""
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
    """Create a simple .tscn file."""
    with open(scene_path, "w", encoding="utf-8") as f:
        f.write(f"""[gd_scene load_steps=1 format=3]

[node name="{root_name}" type="{root_type}"]
""")
    return scene_path


def create_complex_scene(scene_path: str) -> str:
    """Create a complex scene with hierarchy."""
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


# =============================================================================
# Fixtures
# =============================================================================


@pytest.fixture(autouse=True)
def reset_session_manager():
    """Reset session manager before each test."""
    manager = get_session_manager()
    manager.shutdown_all()
    yield
    # Cleanup after test
    manager = get_session_manager()
    manager.shutdown_all()


@pytest.fixture
def temp_project():
    """Create a temporary Godot project directory."""
    tmpdir = tempfile.mkdtemp(prefix="heren_test_")
    try:
        create_minimal_project(tmpdir)
        yield tmpdir
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


@pytest.fixture
def temp_scene(temp_project):
    """Create a temporary scene file."""
    scene_path = os.path.join(temp_project, "test_scene.tscn")
    create_sample_scene(scene_path)
    return scene_path


@pytest.fixture
def temp_complex_scene(temp_project):
    """Create a complex scene file."""
    scene_path = os.path.join(temp_project, "complex_scene.tscn")
    create_complex_scene(scene_path)
    return scene_path


@pytest.fixture
def daemon_session():
    """Create a session with GodotDaemon active (uses LAIKA project)."""
    if not os.path.exists(GODOT_EXE):
        pytest.skip(f"Godot executable not found at {GODOT_EXE}")
    
    if not os.path.exists(LAIKA_PROJECT):
        pytest.skip(f"LAIKA project not found at {LAIKA_PROJECT}")
    
    from heren.tools.session_tool import session_tool
    
    # Start session with daemon
    result = session_tool(action="open", project_path=LAIKA_PROJECT, use_daemon=True)
    assert result.get("success") is True, f"Failed to start session: {result.get('error')}"
    
    session_id = result["session_id"]
    
    yield session_id
    
    # Cleanup
    session_tool(action="close", session_id=session_id)


@pytest.fixture
def fallback_session(temp_project):
    """Create a session WITHOUT daemon (uses fallback/scripts)."""
    from heren.tools.session_tool import session_tool
    
    # Start session without daemon (use_daemon=False)
    result = session_tool(action="open", project_path=temp_project, use_daemon=False)
    assert result.get("success") is True, f"Failed to start session: {result.get('error')}"
    
    session_id = result["session_id"]
    
    yield session_id
    
    # Cleanup
    try:
        session_tool(action="close", session_id=session_id)
    except:
        pass


# =============================================================================
# Markers
# =============================================================================


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "integration: marks tests that require Godot engine")
    config.addinivalue_line("markers", "daemon: marks tests that require GodotDaemon")
    config.addinivalue_line("markers", "fallback: marks tests that use fallback mode")
    config.addinivalue_line("markers", "benchmark: marks slow benchmark tests")
    config.addinivalue_line("markers", "slow: marks tests as slow")
    config.addinivalue_line("markers", "tool: marks tool-specific tests")


@pytest.fixture
def skip_without_godot():
    """Skip test if Godot executable is not found."""
    if not os.path.exists(GODOT_EXE):
        pytest.skip(f"Godot executable not found at {GODOT_EXE}")


@pytest.fixture
def skip_without_laika():
    """Skip test if LAIKA project is not found."""
    if not os.path.exists(LAIKA_PROJECT):
        pytest.skip(f"LAIKA project not found at {LAIKA_PROJECT}")
