"""
Benchmarks for Cache operations.

NO requiere Godot. Tests unitarios puros.
"""

import time
import sys
import json
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from heren.core.session_manager import LRUCache


def benchmark_cache_operations():
    """Benchmark cache operations."""
    print("\n" + "="*70)
    print("BENCHMARK: Cache Operations")
    print("="*70)
    
    cache = LRUCache(max_size=1000)
    
    # Benchmark: set
    print("\n  cache.set() x1000")
    start = time.perf_counter()
    for i in range(1000):
        cache.set(f"key_{i}", {"data": i, "nested": {"value": i * 2}})
    elapsed = time.perf_counter() - start
    print(f"    Total: {elapsed*1000:7.2f}ms | Avg: {elapsed/1000*1000*1000:7.2f}ns/op")
    
    # Benchmark: get (hit)
    print("\n  cache.get() (hit) x1000")
    start = time.perf_counter()
    for i in range(1000):
        cache.get(f"key_{i}")
    elapsed = time.perf_counter() - start
    print(f"    Total: {elapsed*1000:7.2f}ms | Avg: {elapsed/1000*1000*1000:7.2f}ns/op")
    
    # Benchmark: get (miss)
    print("\n  cache.get() (miss) x1000")
    start = time.perf_counter()
    for i in range(1000):
        cache.get(f"nonexistent_{i}")
    elapsed = time.perf_counter() - start
    print(f"    Total: {elapsed*1000:7.2f}ms | Avg: {elapsed/1000*1000*1000:7.2f}ns/op")
    
    # Benchmark: invalidate_pattern
    print("\n  cache.invalidate_pattern() x100")
    # Populate with patterned keys
    for i in range(1000):
        cache.set(f"scene:/node_{i}", {"id": i})
        cache.set(f"project:/data_{i}", {"id": i})
    
    start = time.perf_counter()
    for _ in range(100):
        # Manual pattern invalidation
        for key in list(cache._cache.keys()):
            if key.startswith("scene:"):
                cache.invalidate(key)
        # Repopulate for next iteration
        for i in range(1000):
            cache.set(f"scene:/node_{i}", {"id": i})
    elapsed = time.perf_counter() - start
    print(f"    Total: {elapsed*1000:7.2f}ms | Avg: {elapsed/100*1000:7.2f}ms/op")
    
    # Stats (manual calculation)
    hits = sum(1 for k in list(cache._cache.keys())[:500] if cache.get(k) is not None)
    misses = 500 - hits
    hit_rate = hits / 500 if hits > 0 else 0
    print(f"\n  Cache stats: hits={hits}, misses={misses}, hit_rate={hit_rate:.1%}")
    
    return {
        "cache_set_1000_avg_ns": elapsed / 1000 * 1000 * 1000,
        "cache_get_hit_avg_ns": elapsed / 1000 * 1000 * 1000,
        "cache_hit_rate": hit_rate,
    }


def benchmark_cache_memory():
    """Benchmark cache memory usage."""
    print("\n" + "="*70)
    print("BENCHMARK: Cache Memory Usage")
    print("="*70)
    
    import tracemalloc
    
    tracemalloc.start()
    
    cache = LRUCache(max_size=10000)
    
    # Measure memory for 1000 entries
    current, peak = tracemalloc.get_traced_memory()
    print(f"\n  Before: {current / 1024 / 1024:.2f} MB")
    
    for i in range(1000):
        cache.set(f"key_{i}", {"data": "x" * 1000})  # 1KB per entry
    
    current, peak = tracemalloc.get_traced_memory()
    print(f"  After 1000 entries: {current / 1024 / 1024:.2f} MB")
    print(f"  Peak: {peak / 1024 / 1024:.2f} MB")
    print(f"  Per entry: {current / 1000 / 1024:.2f} KB")
    
    tracemalloc.stop()
    
    return {
        "memory_1000_entries_mb": current / 1024 / 1024,
        "memory_per_entry_kb": current / 1000 / 1024,
    }


if __name__ == "__main__":
    print("="*70)
    print("HEREN MCP CACHE BENCHMARKS")
    print("="*70)
    
    results = {}
    results.update(benchmark_cache_operations())
    results.update(benchmark_cache_memory())
    
    # Save results
    with open("benchmark_cache_results.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print("\nResults saved to: benchmark_cache_results.json")
