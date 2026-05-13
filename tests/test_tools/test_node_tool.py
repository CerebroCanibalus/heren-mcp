"""
Tests for node tools.

Requiere Godot engine instalado.
Marcado como integration test.
"""

import pytest
import os

from heren.tools.node_tools import heren_add_node, heren_remove_node, heren_set_property
from heren.tools.scene_tools import heren_get_scene_tree


@pytest.mark.integration
class TestNodeToolAdd:
    """Tests for add_node."""

    def test_add_node_success(self, session_id, sample_scene_file):
        """Test adding a node."""
        result = heren_add_node(
            session_id=session_id,
            scene_path=sample_scene_file,
            parent_path=".",
            node_type="Sprite2D",
            node_name="MySprite"
        )
        
        assert result["success"] is True
        assert result.get("node_name") == "MySprite"
        
    def test_add_node_duplicate_fails(self, session_id, sample_scene_file):
        """Test adding duplicate node fails."""
        # First add
        result1 = heren_add_node(
            session_id=session_id,
            scene_path=sample_scene_file,
            parent_path=".",
            node_type="Sprite2D",
            node_name="Sprite"
        )
        assert result1["success"] is True
        
        # Second add with same name
        result2 = heren_add_node(
            session_id=session_id,
            scene_path=sample_scene_file,
            parent_path=".",
            node_type="Sprite2D",
            node_name="Sprite"
        )
        assert result2["success"] is False
        assert "ya existe" in result2.get("error", "")
        
    def test_add_node_with_properties(self, session_id, sample_scene_file):
        """Test adding node with properties."""
        result = heren_add_node(
            session_id=session_id,
            scene_path=sample_scene_file,
            parent_path=".",
            node_type="Sprite2D",
            node_name="PositionedSprite",
            properties={"position": {"x": 100, "y": 200}}
        )
        
        assert result["success"] is True
        
    def test_add_node_scene_not_found(self, session_id, temp_project):
        """Test adding node to non-existent scene creates it."""
        scene_path = os.path.join(temp_project, "auto_create.tscn")
        
        result = heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path=".",
            node_type="Node2D",
            node_name="Root"
        )
        
        assert result["success"] is True
        assert os.path.exists(scene_path)


@pytest.mark.integration
class TestNodeToolRemove:
    """Tests for remove_node."""

    def test_remove_node_success(self, session_id, complex_scene_file):
        """Test removing a node."""
        result = heren_remove_node(
            session_id=session_id,
            scene_path=complex_scene_file,
            node_path="Enemy"
        )
        
        assert result["success"] is True
        
    def test_remove_node_not_found(self, session_id, sample_scene_file):
        """Test removing non-existent node."""
        result = heren_remove_node(
            session_id=session_id,
            scene_path=sample_scene_file,
            node_path="NonExistent"
        )
        
        assert result["success"] is False
        assert "no encontrado" in result.get("error", "").lower()
        
    def test_remove_node_with_children(self, session_id, complex_scene_file):
        """Test removing node removes children too."""
        result = heren_remove_node(
            session_id=session_id,
            scene_path=complex_scene_file,
            node_path="Player"
        )
        
        assert result["success"] is True
        
        # Verify children are gone
        tree = heren_get_scene_tree(
            session_id=session_id,
            scene_path=complex_scene_file
        )
        
        node_names = [n["name"] for n in tree["nodes"]]
        assert "Player" not in node_names
        assert "Sprite" not in node_names
        assert "CollisionShape2D" not in node_names


@pytest.mark.integration
class TestNodeToolSetProperty:
    """Tests for set_property."""

    def test_set_property_success(self, session_id, sample_scene_file):
        """Test setting node property."""
        result = heren_set_property(
            session_id=session_id,
            scene_path=sample_scene_file,
            node_path="Root",
            property_name="position",
            value={"x": 50, "y": 100}
        )
        
        assert result["success"] is True
        
    def test_set_property_not_found(self, session_id, sample_scene_file):
        """Test setting property on non-existent node."""
        result = heren_set_property(
            session_id=session_id,
            scene_path=sample_scene_file,
            node_path="NonExistent",
            property_name="position",
            value={"x": 0, "y": 0}
        )
        
        assert result["success"] is False


@pytest.mark.integration
class TestNodeToolComplexOperations:
    """Tests for complex node operations."""

    def test_add_multiple_nodes(self, session_id, temp_project):
        """Test adding multiple nodes in sequence."""
        scene_path = os.path.join(temp_project, "multi.tscn")
        
        # Create root
        heren_add_node(
            session_id=session_id,
            scene_path=scene_path,
            parent_path=".",
            node_type="Node2D",
            node_name="Root"
        )
        
        # Add children
        for i in range(5):
            result = heren_add_node(
                session_id=session_id,
                scene_path=scene_path,
                parent_path="Root",
                node_type="Node2D",
                node_name=f"Child_{i}"
            )
            assert result["success"] is True
        
        # Verify
        tree = heren_get_scene_tree(
            session_id=session_id,
            scene_path=scene_path
        )
        
        node_names = [n["name"] for n in tree["nodes"]]
        for i in range(5):
            assert f"Child_{i}" in node_names
            
    def test_add_and_remove(self, session_id, sample_scene_file):
        """Test adding then removing a node."""
        # Add
        add_result = heren_add_node(
            session_id=session_id,
            scene_path=sample_scene_file,
            parent_path=".",
            node_type="Sprite2D",
            node_name="TempSprite"
        )
        assert add_result["success"] is True
        
        # Remove
        remove_result = heren_remove_node(
            session_id=session_id,
            scene_path=sample_scene_file,
            node_path="TempSprite"
        )
        assert remove_result["success"] is True
        
        # Verify gone
        tree = heren_get_scene_tree(
            session_id=session_id,
            scene_path=sample_scene_file
        )
        
        node_names = [n["name"] for n in tree["nodes"]]
        assert "TempSprite" not in node_names
