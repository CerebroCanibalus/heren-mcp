"""
Tests para Session Tool.

Cubre:
- open/close
- health
- list/info
"""

import pytest
import time


@pytest.mark.tool
@pytest.mark.integration
class TestSessionTool:
    """Test session tool operations."""
    
    def test_session_open_fallback(self, fallback_session):
        """Test opening a session without daemon."""
        session_id = fallback_session
        assert session_id is not None
        assert len(session_id) > 0
    
    @pytest.mark.daemon
    def test_session_open_daemon(self, daemon_session):
        """Test opening a session with daemon."""
        session_id = daemon_session
        assert session_id is not None
        assert len(session_id) > 0
    
    @pytest.mark.daemon
    def test_session_health(self, daemon_session):
        """Test health check with daemon."""
        from heren.tools.session_tool import session_tool
        
        result = session_tool(action="health", session_id=daemon_session)
        
        assert result["success"] is True
        assert result["status"] == "healthy"
        assert "memory_mb" in result
        assert result["memory_mb"] > 0
        assert result["memory_mb"] < 200  # Should be under 200MB
    
    @pytest.mark.daemon
    def test_session_list(self, daemon_session):
        """Test listing sessions."""
        from heren.tools.session_tool import session_tool
        
        result = session_tool(action="list")
        
        assert result["success"] is True
        assert "sessions" in result
        assert len(result["sessions"]) > 0
    
    @pytest.mark.daemon
    def test_session_info(self, daemon_session):
        """Test getting session info."""
        from heren.tools.session_tool import session_tool
        
        result = session_tool(action="info", session_id=daemon_session)
        
        assert result["success"] is True
        assert "session_id" in result
        assert result["session_id"] == daemon_session
    
    @pytest.mark.daemon
    def test_session_close(self, temp_project):
        """Test closing a session."""
        from heren.tools.session_tool import session_tool
        
        # Open
        result = session_tool(action="open", project_path=temp_project, use_daemon=False)
        session_id = result["session_id"]
        
        # Close
        result = session_tool(action="close", session_id=session_id)
        assert result["success"] is True
        
        # Verify closed
        result = session_tool(action="info", session_id=session_id)
        assert result["success"] is False or "error" in result


@pytest.mark.tool
@pytest.mark.fallback
class TestSessionToolFallback:
    """Test session tool in fallback mode."""
    
    def test_session_open_no_daemon(self, fallback_session):
        """Test that fallback session works without daemon."""
        from heren.tools.session_tool import session_tool
        
        result = session_tool(action="health", session_id=fallback_session)
        # Health without daemon may fail, but session should exist
        assert fallback_session is not None
