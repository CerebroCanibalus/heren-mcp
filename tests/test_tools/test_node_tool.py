"""
Tests para Node Tool.

Cubre:
- add, remove
- set_prop, get_prop
- get_info, get_children, find, set_owner, reorder
- duplicate, rename, move
"""

import os
import pytest
import tempfile


LAIKA_PROJECT = r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd"


def _unique_scene_name(prefix: str) -> str:
    return f"{prefix}_{tempfile.gettempprefix()}{os.urandom(4).hex()}.tscn"


@pytest.mark.tool
@pytest.mark.integration
class TestNodeTool:
    """Test node tool operations (daemon only)."""

    @pytest.mark.daemon
    def test_node_add_with_properties_daemon(self, daemon_session):
        """Test adding node with properties via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        scene_name = _unique_scene_name("node_add")
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(LAIKA_PROJECT, scene_name)
        if os.path.exists(full_path):
            os.remove(full_path)

        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)

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

        if os.path.exists(full_path):
            os.remove(full_path)

    @pytest.mark.daemon
    def test_node_duplicate_daemon(self, daemon_session):
        """Test duplicating a node via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        scene_name = _unique_scene_name("dup")
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(LAIKA_PROJECT, scene_name)
        if os.path.exists(full_path):
            os.remove(full_path)

        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)

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

        result = node_tool(
            action="duplicate",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="Original"
        )

        assert result["success"] is True
        assert "duplicate" in result

        if os.path.exists(full_path):
            os.remove(full_path)

    @pytest.mark.daemon
    def test_node_rename_daemon(self, daemon_session):
        """Test renaming a node via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        scene_name = _unique_scene_name("rename")
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(LAIKA_PROJECT, scene_name)
        if os.path.exists(full_path):
            os.remove(full_path)

        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)

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

        if os.path.exists(full_path):
            os.remove(full_path)

    @pytest.mark.daemon
    def test_node_get_info_daemon(self, daemon_session):
        """Test getting full node info via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        scene_name = _unique_scene_name("info")
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(LAIKA_PROJECT, scene_name)
        if os.path.exists(full_path):
            os.remove(full_path)

        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)

        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="CharacterBody2D",
            node_name="Player",
            properties={"position": {"x": 100, "y": 200}}
        )

        result = node_tool(
            action="get_info",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="Player"
        )

        assert result["success"] is True
        assert result["node_type"] == "CharacterBody2D"
        assert "properties" in result
        assert "children" in result
        assert "signals" in result

        if os.path.exists(full_path):
            os.remove(full_path)

    @pytest.mark.daemon
    def test_node_get_children_daemon(self, daemon_session):
        """Test listing node children via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        scene_name = _unique_scene_name("children")
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(LAIKA_PROJECT, scene_name)
        if os.path.exists(full_path):
            os.remove(full_path)

        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)

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
            node_path="Parent",
            node_type="Sprite2D",
            node_name="ChildSprite"
        )

        result = node_tool(
            action="get_children",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="Parent"
        )

        assert result["success"] is True
        assert result["count"] >= 1
        assert any(child["name"] == "ChildSprite" for child in result["children"])

        if os.path.exists(full_path):
            os.remove(full_path)

    @pytest.mark.daemon
    def test_node_find_daemon(self, daemon_session):
        """Test finding nodes via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        scene_name = _unique_scene_name("find")
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(LAIKA_PROJECT, scene_name)
        if os.path.exists(full_path):
            os.remove(full_path)

        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)

        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="CharacterBody2D",
            node_name="Enemy"
        )

        result = node_tool(
            action="find",
            session_id=daemon_session,
            scene_path=scene_path,
            query="Enemy",
            by="name"
        )

        assert result["success"] is True
        assert result["count"] >= 1
        assert any(r["name"] == "Enemy" for r in result["results"])

        if os.path.exists(full_path):
            os.remove(full_path)

    @pytest.mark.daemon
    def test_node_set_owner_daemon(self, daemon_session):
        """Test setting node owner via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        scene_name = _unique_scene_name("owner")
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(LAIKA_PROJECT, scene_name)
        if os.path.exists(full_path):
            os.remove(full_path)

        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)

        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Node2D",
            node_name="Owner"
        )
        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Node2D",
            node_name="Owned"
        )

        result = node_tool(
            action="set_owner",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="Owned",
            new_owner="Owner"
        )

        assert result["success"] is True

        if os.path.exists(full_path):
            os.remove(full_path)

    @pytest.mark.daemon
    def test_node_reorder_daemon(self, daemon_session):
        """Test reordering a child node via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        scene_name = _unique_scene_name("reorder")
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(LAIKA_PROJECT, scene_name)
        if os.path.exists(full_path):
            os.remove(full_path)

        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)

        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Node2D",
            node_name="First"
        )
        node_tool(
            action="add",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path=".",
            node_type="Node2D",
            node_name="Second"
        )

        result = node_tool(
            action="reorder",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="Second",
            index=0
        )

        assert result["success"] is True

        if os.path.exists(full_path):
            os.remove(full_path)

    @pytest.mark.daemon
    def test_node_move_daemon(self, daemon_session):
        """Test moving a node via daemon."""
        from heren.tools.node_tool import node_tool
        from heren.tools.scene_tool import scene_tool

        scene_name = _unique_scene_name("move")
        scene_path = f"res://{scene_name}"
        full_path = os.path.join(LAIKA_PROJECT, scene_name)
        if os.path.exists(full_path):
            os.remove(full_path)

        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)

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

        result = node_tool(
            action="move",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="Child",
            new_parent="Parent"
        )

        assert result["success"] is True
        assert "new_parent" in result

        if os.path.exists(full_path):
            os.remove(full_path)
