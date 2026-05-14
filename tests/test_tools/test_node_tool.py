"""
Tests para Node Tool.

Cubre:
- add, remove
- set_prop, get_prop
- duplicate, rename, move
"""

import os
import pytest


@pytest.mark.tool
@pytest.mark.integration
class TestNodeTool:
    """Test node tool operations."""
    
    def test_node_add_fallback(self, fallback_session, temp_project):
        """Test adding a node via fallback."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool
        
        scene_path = f"res://node_test_scene.tscn"
        
        # Create scene
        scene_tool(action="create", session_id=fallback_session, scene_path=scene_path)
        
        # Add node
        result = node_tool(
            action="add",
            session_id=fallback_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Sprite2D",
            node_name="TestSprite"
        )
        
        assert result["success"] is True
        assert "node_path" in result
    
    def test_node_set_get_property_fallback(self, fallback_session, temp_project):
        """Test setting and getting properties via fallback."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool
        
        scene_path = f"res://prop_test_scene.tscn"
        
        # Create scene with a node
        scene_tool(action="create", session_id=fallback_session, scene_path=scene_path)
        node_tool(
            action="add",
            session_id=fallback_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Node2D",
            node_name="TestNode"
        )
        
        # Set property
        result = node_tool(
            action="set_prop",
            session_id=fallback_session,
            scene_path=scene_path,
            node_path="TestNode",
            property_name="position",
            value={"x": 100, "y": 200}
        )
        
        assert result["success"] is True
    
    @pytest.mark.daemon
    def test_node_add_with_properties_daemon(self, daemon_session):
        """Test adding node with properties via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://node_daemon_test.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        # Add node with position
        result = node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="CharacterBody2D",
            node_name="Player",
            properties={"position": {"x": 150, "y": 250}}
        )
        
        assert result["success"] is True
        assert "node_path" in result
    
    @pytest.mark.daemon
    def test_node_duplicate_daemon(self, daemon_session):
        """Test duplicating a node via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://dup_test_scene.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        # Add original
        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Node2D",
            node_name="Original"
        )
        scene_tool(action="save", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        # Duplicate
        result = node_tool(
            action="duplicate",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="Original"
        )
        
        assert result["success"] is True
        assert "duplicate" in result
    
    @pytest.mark.daemon
    def test_node_rename_daemon(self, daemon_session):
        """Test renaming a node via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://rename_test_scene.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        # Add and rename
        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Node2D",
            node_name="OldName"
        )
        scene_tool(action="save", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        result = node_tool(
            action="rename",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="OldName",
            new_name="NewName"
        )
        
        assert result["success"] is True
    
    @pytest.mark.daemon
    def test_node_move_daemon(self, daemon_session):
        """Test moving a node via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://move_test_scene.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        # Add parent and child
        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Node2D",
            node_name="Parent"
        )
        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Node2D",
            node_name="Child"
        )
        scene_tool(action="save", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        # Move
        result = node_tool(
            action="move",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="Child",
            new_parent="Parent"
        )
        
        assert result["success"] is True
        assert "new_parent" in result
