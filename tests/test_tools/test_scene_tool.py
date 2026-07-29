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
        import tempfile
        import os
        from heren.tools.scene_tool import scene_tool

        scene_name = f"daemon_test_scene_{tempfile.gettempprefix()}{os.urandom(4).hex()}.tscn"
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd", scene_name)

        # Limpiar si existe de una corrida anterior
        if os.path.exists(full_path):
            os.remove(full_path)

        result = scene_tool(
            action="create",
            session_id=daemon_session,
            scene_path=scene_path,
            root_type="Node2D",
            root_name="Root"
        )
        assert result["success"] is True

        result = scene_tool(
            action="load",
            session_id=daemon_session,
            scene_path=scene_path
        )
        assert result["success"] is True
        assert result["cached"] in [True, False]

        result = scene_tool(
            action="get_tree",
            session_id=daemon_session,
            scene_path=scene_path
        )
        assert result["success"] is True
        assert result["node_count"] >= 1

        result = scene_tool(
            action="save",
            session_id=daemon_session,
            scene_path=scene_path
        )
        assert result["success"] is True

        if os.path.exists(full_path):
            os.remove(full_path)

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
    def test_scene_instantiate(self, daemon_session):
        """Test instantiating a scene as a node."""
        import os
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        # Crear una escena reusable para instanciar
        source_name = f"sub_scene_{os.urandom(4).hex()}.tscn"
        source_path = f"res://{source_name}"
        source_full = os.path.join(r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd", source_name)
        if os.path.exists(source_full):
            os.remove(source_full)

        scene_tool(action="create", session_id=daemon_session, scene_path=source_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=source_path)
        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=source_path,
            node_path=".",
            node_type="Node2D",
            node_name="SubRoot"
        )
        scene_tool(action="save", session_id=daemon_session, scene_path=source_path)

        # Crear escena principal e instanciar
        main_name = f"main_scene_{os.urandom(4).hex()}.tscn"
        main_path = f"res://{main_name}"
        main_full = os.path.join(r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd", main_name)
        if os.path.exists(main_full):
            os.remove(main_full)

        scene_tool(action="create", session_id=daemon_session, scene_path=main_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=main_path)

        result = scene_tool(
            action="instantiate",
            session_id=daemon_session,
            scene_path=main_path,
            instance_path=source_path,
            parent_path=".",
            node_name="Instance"
        )

        assert result["success"] is True
        assert "node_path" in result

        if os.path.exists(source_full):
            os.remove(source_full)
        if os.path.exists(main_full):
            os.remove(main_full)

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
