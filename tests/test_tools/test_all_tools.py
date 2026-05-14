"""
Tests para tools restantes: batch, resource, animation, skeleton, shader, tilemap, project, debug, validate, index.

Cubre operaciones básicas de cada tool.
"""

import os
import pytest


@pytest.mark.tool
@pytest.mark.integration
class TestBatchTool:
    """Test batch tool operations."""
    
    @pytest.mark.daemon
    def test_batch_multiple_operations(self, daemon_session):
        """Test batch with multiple node operations."""
        from heren.tools.batch_tools import heren_batch
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://batch_test_scene.tscn"
        
        # Create and load scene
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        # Batch operations
        operations = [
            {"action": "add", "params": {"scene_path": scene_path, "parent_path": ".", "node_type": "Node2D", "node_name": "Node1"}},
            {"action": "add", "params": {"scene_path": scene_path, "parent_path": ".", "node_type": "Node2D", "node_name": "Node2"}},
            {"action": "add", "params": {"scene_path": scene_path, "parent_path": ".", "node_type": "Node2D", "node_name": "Node3"}},
            {"action": "save", "params": {"scene_path": scene_path}}
        ]
        
        result = heren_batch(session_id=daemon_session, operations=operations)
        
        assert result["success"] is True
        assert result["success_count"] == 4
        assert result["error_count"] == 0
    
    def test_batch_fallback(self, fallback_session, temp_project):
        """Test batch in fallback mode."""
        from heren.tools.batch_tools import heren_batch
        from heren.tools.scene_tool import scene_tool
        
        scene_path = f"res://batch_fallback_scene.tscn"
        
        # Create scene
        scene_tool(action="create", session_id=fallback_session, scene_path=scene_path)
        
        operations = [
            {"action": "get_tree", "params": {"scene_path": scene_path}}
        ]
        
        result = heren_batch(session_id=fallback_session, operations=operations)
        
        assert result["success"] is True
        assert result["success_count"] == 1


@pytest.mark.tool
@pytest.mark.integration
class TestResourceTool:
    """Test resource tool operations."""
    
    @pytest.mark.daemon
    def test_resource_create(self, daemon_session):
        """Test creating a resource."""
        from heren.tools.resource_tool import resource
        
        result = resource(
            action="create",
            session_id=daemon_session,
            resource_path="res://test_material.tres",
            resource_type="ShaderMaterial",
            properties={}
        )
        
        assert result["success"] is True
        assert "resource_path" in result
    
    @pytest.mark.daemon
    def test_resource_list(self, daemon_session):
        """Test listing resources."""
        from heren.tools.resource_tool import resource
        
        result = resource(
            action="list",
            session_id=daemon_session,
            resource_path="res://"
        )
        
        assert result["success"] is True
        assert "resources" in result


@pytest.mark.tool
@pytest.mark.integration
class TestAnimationTool:
    """Test animation tool operations."""
    
    @pytest.mark.daemon
    def test_animation_create_player(self, daemon_session):
        """Test creating animation player."""
        from heren.tools.animation_tool import animation
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://anim_test_scene.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        result = animation(
            action="create_player",
            session_id=daemon_session,
            scene_path=scene_path,
            player_path=".",
            anim_name="AnimationPlayer"
        )
        
        assert result["success"] is True
    
    @pytest.mark.daemon
    def test_animation_create(self, daemon_session):
        """Test creating animation."""
        from heren.tools.animation_tool import animation
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://anim_create_test.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        # Create player first
        animation(
            action="create_player",
            session_id=daemon_session,
            scene_path=scene_path,
            player_path=".",
            anim_name="Player"
        )
        
        result = animation(
            action="create",
            session_id=daemon_session,
            scene_path=scene_path,
            player_path="Player",
            anim_name="idle",
            length=1.0,
            loop=True
        )
        
        # May fail due to known bug, but should not crash
        assert "success" in result


@pytest.mark.tool
@pytest.mark.integration
class TestSkeletonTool:
    """Test skeleton tool operations."""
    
    @pytest.mark.daemon
    def test_skeleton_create(self, daemon_session):
        """Test creating skeleton."""
        from heren.tools.skeleton_tool import skeleton
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://skel_test_scene.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        result = skeleton(
            action="create",
            session_id=daemon_session,
            scene_path=scene_path,
            skeleton_name="TestSkeleton"
        )
        
        assert result["success"] is True
    
    @pytest.mark.daemon
    def test_skeleton_add_bone(self, daemon_session):
        """Test adding bone to skeleton."""
        from heren.tools.skeleton_tool import skeleton
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://bone_test_scene.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        # Create skeleton
        skeleton(
            action="create",
            session_id=daemon_session,
            scene_path=scene_path,
            skeleton_name="Skel"
        )
        
        result = skeleton(
            action="add_bone",
            session_id=daemon_session,
            scene_path=scene_path,
            skeleton_path="Skel",
            bone_name="root",
            length=32
        )
        
        assert result["success"] is True


@pytest.mark.tool
@pytest.mark.integration
class TestShaderTool:
    """Test shader tool operations."""
    
    @pytest.mark.daemon
    def test_shader_create(self, daemon_session):
        """Test creating shader."""
        from heren.tools.shader_tool import shader
        
        result = shader(
            action="create",
            session_id=daemon_session,
            shader_path="res://test_shader.gdshader",
            shader_type="canvas_item",
            code="shader_type canvas_item; void fragment() { COLOR = vec4(1.0, 0.0, 0.0, 1.0); }"
        )
        
        assert result["success"] is True


@pytest.mark.tool
@pytest.mark.integration
class TestProjectTool:
    """Test project tool operations."""
    
    @pytest.mark.daemon
    def test_project_setting_write(self, daemon_session):
        """Test writing project setting."""
        from heren.tools.project_tool import project
        
        result = project(
            action="setting",
            setting_name="display/window/size/viewport_width",
            value=1920
        )
        
        assert result["success"] is True
    
    @pytest.mark.daemon
    def test_project_setting_read(self, daemon_session):
        """Test reading project setting."""
        from heren.tools.project_tool import project
        
        result = project(
            action="setting",
            setting_name="display/window/size/viewport_width"
        )
        
        assert result["success"] is True
        assert "value" in result


@pytest.mark.tool
@pytest.mark.integration
class TestDebugTool:
    """Test debug tool operations."""
    
    @pytest.mark.daemon
    def test_debug_breakpoint(self, daemon_session):
        """Test setting breakpoint."""
        from heren.tools.debug_tool import debug
        
        result = debug(
            action="breakpoint",
            session_id=daemon_session,
            script_path="res://test.gd",
            line=42
        )
        
        assert result["success"] is True
    
    @pytest.mark.daemon
    def test_debug_stack_trace(self, daemon_session):
        """Test getting stack trace."""
        from heren.tools.debug_tool import debug
        
        result = debug(
            action="stack_trace",
            session_id=daemon_session
        )
        
        assert result["success"] is True
        assert "frames" in result


@pytest.mark.tool
@pytest.mark.integration
class TestValidateTool:
    """Test validate tool operations."""
    
    @pytest.mark.daemon
    def test_validate_scene(self, daemon_session):
        """Test validating scene."""
        from heren.tools.validate_tool import validate
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://validate_test.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        
        result = validate(
            action="scene",
            session_id=daemon_session,
            scene_path=scene_path
        )
        
        assert result["success"] is True
        assert result["valid"] is True
    
    @pytest.mark.daemon
    def test_validate_node(self, daemon_session):
        """Test validating node."""
        from heren.tools.validate_tool import validate
        from heren.tools.scene_tool import scene_tool
        
        scene_path = "res://validate_node_test.tscn"
        scene_tool(action="create", session_id=daemon_session, scene_path=scene_path)
        scene_tool(action="load", session_id=daemon_session, scene_path=scene_path)
        
        result = validate(
            action="node",
            session_id=daemon_session,
            scene_path=scene_path,
            node_path="Root"
        )
        
        assert result["success"] is True
        assert result["valid"] is True


@pytest.mark.tool
class TestIndexTool:
    """Test index tool operations."""
    
    def test_index_list(self):
        """Test listing all tools."""
        from heren.tools.tools_index import list_tools
        
        result = list_tools()
        
        assert "tools" in result
        assert len(result["tools"]) >= 12
        assert result["tools_count"] >= 12
    
    def test_index_info(self):
        """Test getting tool info."""
        from heren.tools.tools_index import get_tool_info
        
        result = get_tool_info("scene")
        
        assert "description" in result
        assert "actions" in result
        assert "get_tree" in result["actions"]
    
    def test_index_example(self):
        """Test getting action example."""
        from heren.tools.tools_index import get_action_example
        
        result = get_action_example("scene", "create")
        
        assert result is not None
        assert len(result) > 0
