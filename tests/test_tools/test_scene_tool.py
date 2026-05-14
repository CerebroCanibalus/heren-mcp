"""
Tests para Scene Tool.

Cubre:
- create, load, save
- get_tree
- screenshot (daemon only)
"""

import os
import pytest


@pytest.mark.tool
@pytest.mark.integration
class TestSceneTool:
    """Test scene tool operations."""
    
    def test_scene_create_fallback(self, fallback_session, temp_project):
        """Test creating a scene via fallback."""
        from heren.tools.scene_tool import scene_tool
        
        scene_path = os.path.join(temp_project, "new_scene.tscn")
        scene_path_res = f"res://new_scene.tscn"
        
        result = scene_tool(
            action="create",
            session_id=fallback_session,
            scene_path=scene_path_res,
            root_type="Node2D",
            root_name="Root"
        )
        
        assert result["success"] is True
        assert os.path.exists(scene_path)
    
    def test_scene_load_and_get_tree_fallback(self, fallback_session, temp_scene):
        """Test loading and getting tree via fallback."""
        from heren.tools.scene_tool import scene_tool
        
        # Create scene first
        scene_path_res = f"res://test_scene.tscn"
        
        # Get tree directly via fallback script
        result = scene_tool(
            action="get_tree",
            session_id=fallback_session,
            scene_path=scene_path_res
        )
        
        assert result["success"] is True
        assert "nodes" in result
        assert len(result["nodes"]) >= 1
        assert result["nodes"][0]["name"] == "Root"
    
    @pytest.mark.daemon
    def test_scene_create_load_save_daemon(self, daemon_session):
        """Test full scene lifecycle with daemon."""
        from heren.tools.scene_tool import scene_tool
        
        # Create
        result = scene_tool(
            action="create",
            session_id=daemon_session,
            scene_path="res://daemon_test_scene.tscn",
            root_type="Node2D",
            root_name="Root"
        )
        assert result["success"] is True
        
        # Load
        result = scene_tool(
            action="load",
            session_id=daemon_session,
            scene_path="res://daemon_test_scene.tscn"
        )
        assert result["success"] is True
        assert result["cached"] in [True, False]
        
        # Get tree
        result = scene_tool(
            action="get_tree",
            session_id=daemon_session,
            scene_path="res://daemon_test_scene.tscn"
        )
        assert result["success"] is True
        assert result["node_count"] >= 1
        
        # Save
        result = scene_tool(
            action="save",
            session_id=daemon_session,
            scene_path="res://daemon_test_scene.tscn"
        )
        assert result["success"] is True
    
    @pytest.mark.daemon
    def test_scene_list_loaded(self, daemon_session):
        """Test listing loaded scenes."""
        from heren.tools.scene_tool import scene_tool
        
        # Load a scene first
        scene_tool(
            action="create",
            session_id=daemon_session,
            scene_path="res://loaded_test.tscn"
        )
        scene_tool(
            action="load",
            session_id=daemon_session,
            scene_path="res://loaded_test.tscn"
        )
        
        result = scene_tool(
            action="list_loaded",
            session_id=daemon_session
        )
        
        assert result["success"] is True
        assert "scenes" in result
        assert len(result["scenes"]) > 0
    
    @pytest.mark.daemon
    @pytest.mark.slow
    def test_scene_screenshot(self, daemon_session):
        """Test taking a screenshot."""
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://test_level.tscn"
        output_path = r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd\test_screenshot_tool.png"
        
        # Ensure scene exists
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        result = scene_tool(
            action="screenshot",
            session_id=daemon_session,
            scene_path=scene_path,
            output_path=output_path,
            resolution=(800, 600)
        )
        
        assert result["success"] is True
        assert os.path.exists(output_path)
