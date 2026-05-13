"""
End-to-end integration tests.

Test workflows completos que usan múltiples tools.
Requiere Godot engine instalado.
"""

import pytest
import os

from heren.tools.scene_tools import heren_start_session, heren_end_session
from heren.tools.scene_tools import heren_get_scene_tree, heren_save_scene
from heren.tools.node_tools import heren_add_node, heren_remove_node, heren_set_property


@pytest.mark.integration
@pytest.mark.slow
class TestFullWorkflow:
    """Test complete workflows."""

    def test_create_scene_and_add_nodes(self, temp_project):
        """Test creating a scene and adding multiple nodes."""
        # Start session
        session_result = heren_start_session(project_path=temp_project, use_server=False)
        assert session_result["success"] is True
        session_id = session_result["session_id"]
        
        # Create scene by adding root node
        scene_path = os.path.join(temp_project, "Player.tscn")
        root_result = heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path=".",
            node_type="CharacterBody2D",
            node_name="Player"
        )
        assert root_result["success"] is True
        
        # Add sprite
        sprite_result = heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path="Player",
            node_type="Sprite2D",
            node_name="Sprite"
        )
        assert sprite_result["success"] is True
        
        # Add collision
        collision_result = heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path="Player",
            node_type="CollisionShape2D",
            node_name="Collision"
        )
        assert collision_result["success"] is True
        
        # Get tree and verify
        tree = heren_get_scene_tree(
            session_id=session_id,
            scene_path=scene_path
        )
        
        assert tree["success"] is True
        node_names = [n["name"] for n in tree["nodes"]]
        assert "Player" in node_names
        assert "Sprite" in node_names
        assert "Collision" in node_names
        
    def test_modify_and_save_scene(self, temp_project):
        """Test modifying a scene and saving it."""
        # Start session
        session_result = heren_start_session(project_path=temp_project, use_server=False)
        session_id = session_result["session_id"]
        
        # Create scene
        scene_path = os.path.join(temp_project, "Test.tscn")
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path=".",
            node_type="Node2D",
            node_name="Root"
        )
        
        # Add node with properties
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path=".",
            node_type="Node2D",
            node_name="Movable",
            properties={"position": {"x": 100, "y": 200}}
        )
        
        # Update properties
        heren_set_property(
            session_id=session_id,
            scene_path=scene_path,
            node_path="Movable",
            property_name="position",
            value={"x": 300, "y": 400}
        )
        
        # Save
        save_result = heren_save_scene(
            session_id=session_id,
            scene_path=scene_path
        )
        assert save_result["success"] is True
        
        # Get tree to verify
        tree = heren_get_scene_tree(
            session_id=session_id,
            scene_path=scene_path
        )
        
        movable = [n for n in tree["nodes"] if n["name"] == "Movable"][0]
        # Node2D nodes have position directly in get_scene_tree output
        assert "position" in movable
        
    def test_complex_hierarchy(self, temp_project):
        """Test creating complex node hierarchy."""
        session_result = heren_start_session(project_path=temp_project, use_server=False)
        session_id = session_result["session_id"]
        
        scene_path = os.path.join(temp_project, "Level.tscn")
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path=".",
            node_type="Node2D",
            node_name="Level"
        )
        
        # Create hierarchy
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path="Level",
            node_type="Node2D",
            node_name="Entities"
        )
        
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path="Entities",
            node_type="CharacterBody2D",
            node_name="Player"
        )
        
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path="Entities",
            node_type="CharacterBody2D",
            node_name="Enemy1"
        )
        
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path="Level",
            node_type="Node2D",
            node_name="UI"
        )
        
        # Verify hierarchy
        tree = heren_get_scene_tree(
            session_id=session_id,
            scene_path=scene_path
        )
        
        # Check parent relationships
        nodes = {n["name"]: n for n in tree["nodes"]}
        assert nodes["Entities"]["parent"] == "Level"
        assert nodes["Player"]["parent"] == "Entities"
        assert nodes["Enemy1"]["parent"] == "Entities"
        assert nodes["UI"]["parent"] == "Level"
        
    def test_session_isolation(self, temp_project):
        """Test that sessions are isolated."""
        # Create two sessions for same project
        session1 = heren_start_session(project_path=temp_project, use_server=False)
        session2 = heren_start_session(project_path=temp_project, use_server=False)
        
        # Should get same session ID
        assert session1["session_id"] == session2["session_id"]
        
    def test_end_to_end_with_save(self, temp_project):
        """Test complete workflow with save."""
        session_result = heren_start_session(project_path=temp_project, use_server=False)
        session_id = session_result["session_id"]
        
        scene_path = os.path.join(temp_project, "Game.tscn")
        
        # Create
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path=".",
            node_type="Node2D",
            node_name="Game"
        )
        
        # Add nodes
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path="Game",
            node_type="Camera2D",
            node_name="Camera"
        )
        
        # Save scene
        save_result = heren_save_scene(
            session_id=session_id,
            scene_path=scene_path
        )
        
        assert save_result["success"] is True
        
        # Verify file exists and has content
        assert os.path.exists(scene_path)
        with open(scene_path, "r") as f:
            content = f.read()
            assert "Camera" in content
            assert "Camera2D" in content
