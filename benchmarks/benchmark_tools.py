"""
Benchmarks for Heren MCP Tools.

Mide rendimiento de cada tool para detectar regresiones.
Requiere Godot engine instalado.
"""

import os
import sys
import time
import tempfile
import shutil
import json

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from heren.core.session_manager import SessionManager, get_session_manager
from heren.tools.scene_tools import heren_start_session, heren_end_session, heren_get_scene_tree, heren_save_scene
from heren.tools.node_tools import heren_add_node, heren_remove_node, heren_set_property


# =============================================================================
# Helpers
# =============================================================================

def create_temp_project():
    """Create a temporary Godot project."""
    tmpdir = tempfile.mkdtemp(prefix="heren_benchmark_")
    project_file = os.path.join(tmpdir, "project.godot")
    with open(project_file, "w", encoding="utf-8") as f:
        f.write("""[application]
config/name="BenchmarkProject"
config/features=PackedStringArray("4.6")

[rendering]
renderer/rendering_method="forward_plus"
""")
    return tmpdir


def create_sample_scene(project_dir, name="test.tscn"):
    """Create a sample scene file."""
    scene_path = os.path.join(project_dir, name)
    with open(scene_path, "w", encoding="utf-8") as f:
        f.write("""[gd_scene load_steps=1 format=3]

[node name="Root" type="Node2D"]

[node name="Player" type="CharacterBody2D" parent="."]

[node name="Sprite" type="Sprite2D" parent="Player"]

[node name="Enemy" type="CharacterBody2D" parent="."]
""")
    return scene_path


def measure(func, *args, **kwargs):
    """Measure execution time of a function."""
    start = time.perf_counter()
    result = func(*args, **kwargs)
    elapsed = time.perf_counter() - start
    return result, elapsed


def run_benchmark(name, func, *args, warmup=1, iterations=10, **kwargs):
    """Run benchmark with warmup and multiple iterations."""
    print(f"\n  Benchmark: {name}")
    print(f"  {'='*60}")
    
    # Warmup
    for _ in range(warmup):
        func(*args, **kwargs)
    
    # Measure
    times = []
    for i in range(iterations):
        _, elapsed = measure(func, *args, **kwargs)
        times.append(elapsed)
        print(f"    Iteration {i+1}/{iterations}: {elapsed*1000:7.2f}ms")
    
    avg = sum(times) / len(times)
    min_t = min(times)
    max_t = max(times)
    
    print(f"  {'-'*60}")
    print(f"    Avg: {avg*1000:7.2f}ms | Min: {min_t*1000:7.2f}ms | Max: {max_t*1000:7.2f}ms")
    
    return {
        "name": name,
        "avg_ms": avg * 1000,
        "min_ms": min_t * 1000,
        "max_ms": max_t * 1000,
        "iterations": iterations,
    }


# =============================================================================
# Benchmark Suites
# =============================================================================

class BenchmarkSession:
    """Benchmark session operations."""
    
    @staticmethod
    def run():
        print("\n" + "="*70)
        print("BENCHMARK SUITE: Session Operations")
        print("="*70)
        
        project_dir = create_temp_project()
        try:
            # Reset session manager
            get_session_manager()
            
            results = []
            
            # Benchmark: start_session
            def start():
                return heren_start_session(project_path=project_dir)
            
            result = run_benchmark("start_session", start, warmup=0, iterations=5)
            results.append(result)
            
            # Start a session for subsequent tests
            session_result = heren_start_session(project_path=project_dir)
            session_id = session_result["session_id"]
            
            return results
            
        finally:
            shutil.rmtree(project_dir, ignore_errors=True)


class BenchmarkScene:
    """Benchmark scene operations."""
    
    @staticmethod
    def run():
        print("\n" + "="*70)
        print("BENCHMARK SUITE: Scene Operations")
        print("="*70)
        
        project_dir = create_temp_project()
        scene_path = create_sample_scene(project_dir)
        
        try:
            get_session_manager()
            
            # Start session
            session_result = heren_start_session(project_path=project_dir)
            session_id = session_result["session_id"]
            
            results = []
            
            # Benchmark: get_scene_tree (cold)
            def get_tree():
                return heren_get_scene_tree(session_id=session_id, scene_path=scene_path)
            
            result = run_benchmark("get_scene_tree (cold)", get_tree, warmup=0, iterations=5)
            results.append(result)
            
            # Benchmark: get_scene_tree (cache hit)
            # First call warms cache
            heren_get_scene_tree(session_id=session_id, scene_path=scene_path)
            
            def get_tree_cached():
                return heren_get_scene_tree(session_id=session_id, scene_path=scene_path)
            
            result = run_benchmark("get_scene_tree (cache)", get_tree_cached, warmup=1, iterations=20)
            results.append(result)
            
            # Benchmark: save_scene
            def save():
                return heren_save_scene(session_id=session_id, scene_path=scene_path)
            
            result = run_benchmark("save_scene", save, warmup=1, iterations=5)
            results.append(result)
            
            return results
            
        finally:
            shutil.rmtree(project_dir, ignore_errors=True)


class BenchmarkNode:
    """Benchmark node operations."""
    
    @staticmethod
    def run():
        print("\n" + "="*70)
        print("BENCHMARK SUITE: Node Operations")
        print("="*70)
        
        project_dir = create_temp_project()
        scene_path = create_sample_scene(project_dir)
        
        try:
            get_session_manager()
            
            session_result = heren_start_session(project_path=project_dir)
            session_id = session_result["session_id"]
            
            results = []
            
            # Benchmark: add_node
            counter = [0]
            def add():
                counter[0] += 1
                return heren_add_node(
                    session_id=session_id,
                    scene_path=scene_path,
                    parent_path=".",
                    node_type="Node2D",
                    node_name=f"Node_{counter[0]}"
                )
            
            result = run_benchmark("add_node", add, warmup=0, iterations=5)
            results.append(result)
            
            # Benchmark: set_property
            def update():
                return heren_set_property(
                    session_id=session_id,
                    scene_path=scene_path,
                    node_path="Root",
                    property_name="position",
                    value={"x": 10, "y": 20}
                )
            
            result = run_benchmark("set_property", update, warmup=1, iterations=5)
            results.append(result)
            
            # Benchmark: remove_node
            # First add a node to remove
            heren_add_node(
                session_id=session_id,
                scene_path=scene_path,
                parent_path=".",
                node_type="Node2D",
                node_name="ToRemove"
            )
            
            def remove():
                return heren_remove_node(
                    session_id=session_id,
                    scene_path=scene_path,
                    node_path="ToRemove"
                )
            
            result = run_benchmark("remove_node", remove, warmup=0, iterations=3)
            results.append(result)
            
            return results
            
        finally:
            shutil.rmtree(project_dir, ignore_errors=True)


# =============================================================================
# Main
# =============================================================================

if __name__ == "__main__":
    print("="*70)
    print("HEREN MCP TOOL BENCHMARKS")
    print("="*70)
    print(f"Python: {sys.version}")
    print(f"Godot: {os.environ.get('GODOT_EXE', 'D:/Mis Juegos/Godot/Godot_v4.6.1-stable_win64.exe')}")
    
    all_results = []
    
    all_results.extend(BenchmarkSession.run())
    all_results.extend(BenchmarkScene.run())
    all_results.extend(BenchmarkNode.run())
    
    # Summary
    print("\n" + "="*70)
    print("SUMMARY")
    print("="*70)
    print(f"{'Benchmark':<35} {'Avg (ms)':>10} {'Min (ms)':>10} {'Max (ms)':>10}")
    print("-"*70)
    for r in all_results:
        print(f"{r['name']:<35} {r['avg_ms']:>10.2f} {r['min_ms']:>10.2f} {r['max_ms']:>10.2f}")
    
    # Save results
    output_file = "benchmark_results.json"
    with open(output_file, "w") as f:
        json.dump({
            "timestamp": time.time(),
            "python_version": sys.version,
            "results": all_results,
        }, f, indent=2)
    
    print(f"\nResults saved to: {output_file}")
