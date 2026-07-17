"""
Tests para Scene Tool.

Cubre:
- create, load, save (daemon)
- get_tree (daemon)
- screenshot (daemon)
- list_loaded (daemon)
"""

import os
import pytest


@pytest.mark.tool
@pytest.mark.integration
class TestSceneTool:
    """Test scene tool operations (daemon only)."""

    @pytest.mark.daemon
    def test_scene_create_load_save_daemon(self, daemon_session):
        """Test full scene lifecycle with daemon."""
        from heren.tools.scene_tool import scene_tool

        result = scene_tool(
            action="create",
            session_id=daemon_session,
            scene_path="res://daemon_test_scene.tscn",
            root_type="Node2D",
            root_name="Root"
        )
        assert result["success"] is True

        result = scene_tool(
            action="load",
            session_id=daemon_session,
            scene_path="res://daemon_test_scene.tscn"
        )
        assert result["success"] is True
        assert result["cached"] in [True, False]

        result = scene_tool(
            action="get_tree",
            session_id=daemon_session,
            scene_path="res://daemon_test_scene.tscn"
        )
        assert result["success"] is True
        assert result["node_count"] >= 1

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

        scene_tool(action="create", session_id=daemon_session, scene_path="res://loaded_test.tscn")
        scene_tool(action="load", session_id=daemon_session, scene_path="res://loaded_test.tscn")

        result = scene_tool(action="list_loaded", session_id=daemon_session)

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
