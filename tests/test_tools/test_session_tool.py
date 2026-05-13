"""
Tests for session tools.

Requiere Godot engine instalado.
Marcado como integration test.
"""

import pytest
import os

from heren.tools.scene_tools import heren_start_session, heren_end_session


@pytest.mark.integration
class TestSessionTool:
    """Tests for session tools."""

    def test_start_session(self, temp_project):
        """Test starting a session."""
        result = heren_start_session(project_path=temp_project, use_server=False)
        
        assert result["success"] is True
        assert "session_id" in result
        assert result["project_path"] == temp_project
        
    def test_start_session_invalid_project(self):
        """Test starting session with invalid project."""
        result = heren_start_session(project_path="/nonexistent")
        
        assert result["success"] is False
        assert "error" in result
        
    def test_end_session(self, temp_project):
        """Test ending a session."""
        # Start session
        start_result = heren_start_session(project_path=temp_project, use_server=False)
        session_id = start_result["session_id"]
        
        # End session
        end_result = heren_end_session(session_id=session_id)
        assert end_result["success"] is True
        
    def test_end_invalid_session(self):
        """Test ending non-existent session."""
        result = heren_end_session(session_id="nonexistent")
        assert result["success"] is False
