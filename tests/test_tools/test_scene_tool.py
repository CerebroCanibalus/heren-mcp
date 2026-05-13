"""
Tests for scene tools.

Requiere Godot engine instalado.
Marcado como integration test.
"""

import pytest
import os

from heren.tools.scene_tools import heren_get_scene_tree, heren_save_scene, heren_start_session
from tests.conftest import create_sample_scene


@pytest.mark.integration
class TestSceneToolGetTree:
    """Tests for get_scene_tree."""

    def test_get_scene_tree_success(self, session_id, sample_scene_file):
        """Test getting scene tree."""
        result = heren_get_scene_tree(
            session_id=session_id,
            scene_path=sample_scene_file
        )
        
        assert result["success"] is True
        assert "nodes" in result
        assert len(result["nodes"]) >= 1
        
    def test_get_scene_tree_not_found(self, session_id, temp_project):
        """Test getting non-existent scene."""
        result = heren_get_scene_tree(
            session_id=session_id,
            scene_path=os.path.join(temp_project, "nonexistent.tscn")
        )
        
        assert result["success"] is False
        assert "error" in result
        
    def test_get_scene_tree_cache(self, session_id, sample_scene_file):
        """Test that cache works for scene tree."""
        # First call
        result1 = heren_get_scene_tree(
            session_id=session_id,
            scene_path=sample_scene_file
        )
        
        # Second call should use cache
        result2 = heren_get_scene_tree(
            session_id=session_id,
            scene_path=sample_scene_file
        )
        
        assert result1["success"] is True
        assert result2["success"] is True
        # Data should be identical
        assert result1["nodes"] == result2["nodes"]


@pytest.mark.integration
class TestSceneToolSave:
    """Tests for save_scene."""

    def test_save_scene_success(self, session_id, sample_scene_file):
        """Test saving a scene."""
        result = heren_save_scene(
            session_id=session_id,
            scene_path=sample_scene_file
        )
        
        assert result["success"] is True
        
    def test_save_scene_not_found(self, session_id, temp_project):
        """Test saving non-existent scene."""
        result = heren_save_scene(
            session_id=session_id,
            scene_path=os.path.join(temp_project, "nonexistent.tscn")
        )
        
        assert result["success"] is False


@pytest.mark.integration
class TestSceneToolInfo:
    """Tests for get_project_info (via scene_tools)."""

    def test_get_project_info(self, session_id, temp_project):
        """Test getting project info."""
        from heren.interfaces.godot_cli import create_interface
        
        interface = create_interface(session_id)
        result = interface.get_project_info()
        
        assert result["success"] is True
        assert "project_name" in result
        assert result["project_name"] == "TestProject"


