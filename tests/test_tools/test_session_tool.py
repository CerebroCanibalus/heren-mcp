"""
Tests para Session Tool.

Cubre:
- open/close
- health
- list/info
"""

import pytest


@pytest.mark.tool
@pytest.mark.integration
class TestSessionTool:
    """Test session tool operations."""

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
        assert result["memory_mb"] < 200

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
        assert "session" in result
        assert result["session"]["id"] == daemon_session

    @pytest.mark.daemon
    def test_session_close(self, daemon_session):
        """Test closing a session."""
        from heren.tools.session_tool import session_tool

        result = session_tool(action="close", session_id=daemon_session)
        assert result["success"] is True
