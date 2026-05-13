"""
pytest fixtures for Heren MCP tests.

Organización:
- Fixtures compartidas: temp_project, session_id, sample_scene
- Helpers: create_minimal_project, create_sample_scene
- Marcadores: integration (requiere Godot), benchmark (lento)
"""

import os
import sys
import tempfile
import shutil
from pathlib import Path

import pytest

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from heren.core.session_manager import SessionManager, get_session_manager


# =============================================================================
# Constants
# =============================================================================

GODOT_EXE = os.environ.get("GODOT_EXE", r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe")


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
def session_id(temp_project):
    """Create a real session for testing."""
    from heren.tools.scene_tools import heren_start_session
    # Use use_server=False to avoid starting GodotServer in tests
    # Tests will use temporary scripts instead
    result = heren_start_session(project_path=temp_project, use_server=False)
    assert result.get("success") is True, f"Failed to start session: {result.get('error')}"
    return result["session_id"]


@pytest.fixture
def sample_scene_file(temp_project):
    """Create a simple scene file for testing."""
    scene_path = os.path.join(temp_project, "test_scene.tscn")
    create_sample_scene(scene_path)
    return scene_path


@pytest.fixture
def complex_scene_file(temp_project):
    """Create a complex scene with hierarchy."""
    scene_path = os.path.join(temp_project, "complex.tscn")
    create_complex_scene(scene_path)
    return scene_path


# =============================================================================
# Markers
# =============================================================================


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "integration: marks tests that require Godot engine")
    config.addinivalue_line("markers", "benchmark: marks slow benchmark tests")
    config.addinivalue_line("markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')")


@pytest.fixture
def skip_without_godot():
    """Skip test if Godot executable is not found."""
    if not os.path.exists(GODOT_EXE):
        pytest.skip(f"Godot executable not found at {GODOT_EXE}")
