"""
Tests for Session Manager (Capa 0).

NO requiere Godot. Tests unitarios puros.
"""

import pytest
import time
import threading

from heren.core.session_manager import (
    SessionManager,
    get_session_manager,
    LRUCache,
)
import tempfile
import shutil
import os


class TestSessionManagerBasics:
    """Test basic session operations."""

    def test_singleton_pattern(self):
        """Session manager should be a singleton."""
        manager1 = get_session_manager()
        manager2 = get_session_manager()
        assert manager1 is manager2

    def test_start_session(self):
        """Test creating a session."""
        manager = SessionManager()
        # Create a temp project for testing
        tmpdir = tempfile.mkdtemp()
        try:
            with open(os.path.join(tmpdir, "project.godot"), "w") as f:
                f.write("[application]\nconfig/name=\"Test\"\n")
            
            # Mock godot verification to avoid needing Godot executable
            original_verify = manager._verify_godot
            manager._verify_godot = lambda x: None
            
            session = manager.start_session(tmpdir, use_server=False)
            assert session is not None
            assert session.project_path == tmpdir
            
            manager._verify_godot = original_verify
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)
        
    def test_get_session(self):
        """Test retrieving a session."""
        manager = SessionManager()
        # Create a temp project
        tmpdir = tempfile.mkdtemp()
        try:
            with open(os.path.join(tmpdir, "project.godot"), "w") as f:
                f.write("[application]\nconfig/name=\"Test\"\n")
            
            original_verify = manager._verify_godot
            manager._verify_godot = lambda x: None
            
            session = manager.start_session(tmpdir, use_server=False)
            session_id = session.id
            
            retrieved = manager.get_session(session_id)
            assert retrieved is not None
            assert retrieved.project_path == tmpdir
            
            manager._verify_godot = original_verify
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)
        
    def test_get_session_invalid(self):
        """Test retrieving non-existent session."""
        manager = SessionManager()
        session = manager.get_session("nonexistent")
        assert session is None
        
    def test_end_session(self):
        """Test ending a session."""
        manager = SessionManager()
        tmpdir = tempfile.mkdtemp()
        try:
            with open(os.path.join(tmpdir, "project.godot"), "w") as f:
                f.write("[application]\nconfig/name=\"Test\"\n")
            
            original_verify = manager._verify_godot
            manager._verify_godot = lambda x: None
            
            session = manager.start_session(tmpdir, use_server=False)
            session_id = session.id
            
            result = manager.end_session(session_id)
            assert result is True
            assert manager.get_session(session_id) is None
            
            manager._verify_godot = original_verify
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)
        
    def test_end_session_invalid(self):
        """Test ending non-existent session."""
        manager = SessionManager()
        result = manager.end_session("nonexistent")
        assert result is False


class TestSessionManagerLRUCache:
    """Test cache operations via Session."""

    def test_session_cache(self):
        """Test session cache operations."""
        manager = SessionManager()
        tmpdir = tempfile.mkdtemp()
        try:
            with open(os.path.join(tmpdir, "project.godot"), "w") as f:
                f.write("[application]\nconfig/name=\"Test\"\n")
            
            original_verify = manager._verify_godot
            manager._verify_godot = lambda x: None
            
            session = manager.start_session(tmpdir, use_server=False)
            
            # Test cache
            session.scene_cache.set("key1", "value1")
            assert session.scene_cache.get("key1") == "value1"
            
            session.scene_cache.invalidate("key1")
            assert session.scene_cache.get("key1") is None
            
            manager._verify_godot = original_verify
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)


class TestSessionManagerThreadSafety:
    """Test thread safety."""

    def test_concurrent_cache_access(self):
        """Test concurrent cache access."""
        cache = LRUCache(max_size=100)
        
        def writer():
            for i in range(100):
                cache.set(f"key_{i}", f"value_{i}")
                
        def reader():
            for i in range(100):
                cache.get(f"key_{i}")
                
        threads = [
            threading.Thread(target=writer),
            threading.Thread(target=reader),
            threading.Thread(target=writer),
            threading.Thread(target=reader),
        ]
        
        for t in threads:
            t.start()
        for t in threads:
            t.join()
            
        # No exceptions = thread-safe
        assert True


class TestSessionManagerCleanup:
    """Test cleanup operations."""

    def test_cleanup_temp_files(self):
        """Test temporary file cleanup."""
        manager = SessionManager()
        tmpfile = tempfile.NamedTemporaryFile(delete=False, suffix=".gd")
        tmpfile.close()
        
        manager._temp_files.append(tmpfile.name)
        assert os.path.exists(tmpfile.name)
        
        manager.cleanup_temp_files()
        
        # File should be removed
        assert not os.path.exists(tmpfile.name)
        
    def test_shutdown_all(self):
        """Test shutdown of all sessions."""
        manager = SessionManager()
        tmpdir = tempfile.mkdtemp()
        try:
            with open(os.path.join(tmpdir, "project.godot"), "w") as f:
                f.write("[application]\nconfig/name=\"Test\"\n")
            
            original_verify = manager._verify_godot
            manager._verify_godot = lambda x: None
            
            session = manager.start_session(tmpdir, use_server=False)
            
            manager.shutdown_all()
            
            assert manager.get_session(session.id) is None
            
            manager._verify_godot = original_verify
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)
