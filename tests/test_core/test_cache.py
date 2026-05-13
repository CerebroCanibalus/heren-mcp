"""
Tests for Cache operations.

NO requiere Godot. Tests unitarios puros.
"""

import pytest
import time

from heren.core.session_manager import LRUCache


class TestLRUCacheBasics:
    """Test basic cache operations."""

    def test_set_get(self):
        """Test basic set and get."""
        cache = LRUCache(max_size=10)
        cache.set("key1", "value1")
        
        assert cache.get("key1") == "value1"
        
    def test_get_missing(self):
        """Test getting missing key."""
        cache = LRUCache(max_size=10)
        assert cache.get("missing") is None
        
    def test_invalidate(self):
        """Test invalidating a key."""
        cache = LRUCache(max_size=10)
        cache.set("key1", "value1")
        cache.invalidate("key1")
        
        assert cache.get("key1") is None
        
    def test_clear(self):
        """Test clearing all entries."""
        cache = LRUCache(max_size=10)
        cache.set("key1", "value1")
        cache.set("key2", "value2")
        cache.clear()
        
        assert cache.get("key1") is None
        assert cache.get("key2") is None


class TestLRUCacheLRUBehavior:
    """Test LRU eviction behavior."""

    def test_lru_eviction(self):
        """Test that least recently used item is evicted."""
        cache = LRUCache(max_size=3)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.set("c", 3)
        
        # Access 'a' to make it recently used
        cache.get("a")
        
        # Add new item, should evict 'b' (least recently used)
        cache.set("d", 4)
        
        assert cache.get("a") == 1  # Still there
        assert cache.get("b") is None  # Evicted
        assert cache.get("c") == 3  # Still there
        assert cache.get("d") == 4  # New item
        
    def test_update_existing(self):
        """Test updating existing key doesn't evict."""
        cache = LRUCache(max_size=2)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.set("a", 10)  # Update 'a'
        
        assert cache.get("a") == 10
        assert cache.get("b") == 2
        
    def test_size_limit(self):
        """Test cache respects size limit."""
        cache = LRUCache(max_size=5)
        for i in range(10):
            cache.set(f"key_{i}", i)
            
        # Only last 5 should remain
        assert cache.get("key_0") is None
        assert cache.get("key_5") is not None
        assert cache.get("key_9") is not None


class TestLRUCacheTTL:
    """Test TTL (time-to-live) behavior."""

    def test_ttl_expiration(self):
        """Test that entries expire after TTL."""
        cache = LRUCache(max_size=10, ttl_seconds=0.1)
        cache.set("key", "value")
        
        assert cache.get("key") == "value"
        
        time.sleep(0.15)
        assert cache.get("key") is None
        
    def test_ttl_long(self):
        """Test TTL of large value means no immediate expiration."""
        cache = LRUCache(max_size=10, ttl_seconds=3600)
        cache.set("key", "value")
        
        time.sleep(0.1)
        assert cache.get("key") == "value"


class TestLRUCachePatternInvalidation:
    """Test pattern-based invalidation (manual)."""

    def test_invalidate_with_prefix(self):
        """Test invalidating keys matching prefix."""
        cache = LRUCache(max_size=10)
        cache.set("scene:/Player", "player")
        cache.set("scene:/Enemy", "enemy")
        cache.set("project:/info", "info")
        
        # Manual pattern invalidation
        for key in list(cache._cache.keys()):
            if key.startswith("scene:"):
                cache.invalidate(key)
        
        assert cache.get("scene:/Player") is None
        assert cache.get("scene:/Enemy") is None
        assert cache.get("project:/info") == "info"
        
    def test_invalidate_all(self):
        """Test invalidating all keys."""
        cache = LRUCache(max_size=10)
        cache.set("key1", "value1")
        cache.set("key2", "value2")
        
        cache.clear()
        
        assert cache.get("key1") is None
        assert cache.get("key2") is None
