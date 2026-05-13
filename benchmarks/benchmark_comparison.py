"""
Benchmark comparativo: Scripts Temporales vs GodotServer vs Batch.

Mide rendimiento real incluyendo overhead de inicio.
Requiere Godot engine instalado.
"""

import json
import os
import sys
import tempfile
import shutil
import time
import statistics

# Add paths
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from heren.core.session_manager import SessionManager, get_session_manager
from heren.tools.scene_tools import heren_start_session, heren_end_session, heren_get_scene_tree, heren_save_scene
from heren.tools.node_tools import heren_add_node, heren_remove_node, heren_set_property
from heren.tools.batch_tools import heren_batch


def create_temp_project():
    """Create a temporary Godot project."""
    tmpdir = tempfile.mkdtemp(prefix="heren_benchmark_")
    
    # Create project.godot
    with open(os.path.join(tmpdir, "project.godot"), "w") as f:
        f.write("""[application]
config/name="Benchmark"
config/features=PackedStringArray("4.2", "Mobile")

[rendering]
renderer/rendering_method="mobile"
""")
    
    # Create a test scene
    scene_path = os.path.join(tmpdir, "test_scene.tscn")
    with open(scene_path, "w") as f:
        f.write("""[gd_scene load_steps=1 format=3 uid="uid://benchmark"]

[node name="Root" type="Node2D"]

[node name="Child1" type="Sprite2D" parent="."]
position = Vector2(100, 200)

[node name="Child2" type="Node2D" parent="."]
""")
    
    return tmpdir


def measure_time(func, *args, **kwargs):
    """Measure execution time of a function."""
    start = time.perf_counter()
    result = func(*args, **kwargs)
    elapsed = (time.perf_counter() - start) * 1000  # ms
    return result, elapsed


def benchmark_scripts_temporal():
    """Benchmark using temporary scripts (current method)."""
    print("\n" + "="*70)
    print("BENCHMARK: Scripts Temporales (método actual)")
    print("="*70)
    
    project = create_temp_project()
    session_id = None
    
    try:
        # Start session (with server disabled)
        result, elapsed = measure_time(
            heren_start_session, project, use_server=False
        )
        session_id = result["session_id"]
        print(f"  start_session: {elapsed:.2f}ms")
        
        # Benchmark: get_scene_tree (cold)
        times = []
        for i in range(5):
            _, t = measure_time(heren_get_scene_tree, session_id, "res://test_scene.tscn")
            times.append(t)
        print(f"  get_scene_tree (5 ops): {statistics.mean(times):.2f}ms avg (min: {min(times):.2f}ms, max: {max(times):.2f}ms)")
        
        # Benchmark: add_node
        times = []
        for i in range(3):
            _, t = measure_time(
                heren_add_node, session_id, "res://test_scene.tscn", ".", "Node2D", f"NewNode{i}"
            )
            times.append(t)
        print(f"  add_node (3 ops): {statistics.mean(times):.2f}ms avg")
        
        # Benchmark: set_property
        times = []
        for i in range(3):
            _, t = measure_time(
                heren_set_property, session_id, "res://test_scene.tscn", "Root", 
                "position", {"x": i*10, "y": i*20}
            )
            times.append(t)
        print(f"  set_property (3 ops): {statistics.mean(times):.2f}ms avg")
        
        # Benchmark: save_scene
        _, t = measure_time(heren_save_scene, session_id, "res://test_scene.tscn")
        print(f"  save_scene: {t:.2f}ms")
        
        # Benchmark: 5 operations sequence (individual calls)
        start = time.perf_counter()
        heren_add_node(session_id, "res://test_scene.tscn", ".", "Sprite2D", "Batch1")
        heren_add_node(session_id, "res://test_scene.tscn", ".", "Sprite2D", "Batch2")
        heren_set_property(session_id, "res://test_scene.tscn", "Batch1", "position", {"x": 50, "y": 50})
        heren_set_property(session_id, "res://test_scene.tscn", "Batch2", "position", {"x": 100, "y": 100})
        heren_save_scene(session_id, "res://test_scene.tscn")
        seq_time = (time.perf_counter() - start) * 1000
        print(f"  5 ops sequence (individual): {seq_time:.2f}ms")
        
        heren_end_session(session_id)
        
        return {
            "method": "scripts_temporal",
            "get_scene_tree_avg_ms": statistics.mean(times),
            "add_node_avg_ms": statistics.mean(times),
            "set_property_avg_ms": statistics.mean(times),
            "save_scene_ms": t,
            "sequence_5_ops_ms": seq_time,
        }
        
    finally:
        shutil.rmtree(project, ignore_errors=True)


def benchmark_godot_server():
    """Benchmark using GodotServer (new method)."""
    print("\n" + "="*70)
    print("BENCHMARK: GodotServer (nuevo método HTTP persistente)")
    print("="*70)
    
    project = create_temp_project()
    session_id = None
    server_start_time = 0
    
    try:
        # Start session (with server enabled)
        start = time.perf_counter()
        result = heren_start_session(project, use_server=True)
        server_start_time = (time.perf_counter() - start) * 1000
        session_id = result["session_id"]
        
        print(f"  start_session + GodotServer init: {server_start_time:.2f}ms")
        
        # Benchmark: get_scene_tree (cold - first time server is used)
        _, t_cold = measure_time(heren_get_scene_tree, session_id, "res://test_scene.tscn")
        print(f"  get_scene_tree (cold): {t_cold:.2f}ms")
        
        # Benchmark: get_scene_tree (warm - server already loaded)
        times = []
        for i in range(10):
            _, t = measure_time(heren_get_scene_tree, session_id, "res://test_scene.tscn")
            times.append(t)
        print(f"  get_scene_tree (10 warm ops): {statistics.mean(times):.2f}ms avg (min: {min(times):.2f}ms, max: {max(times):.2f}ms)")
        
        # Benchmark: add_node (warm)
        times_add = []
        for i in range(5):
            _, t = measure_time(
                heren_add_node, session_id, "res://test_scene.tscn", ".", "Node2D", f"ServerNode{i}"
            )
            times_add.append(t)
        print(f"  add_node (5 warm ops): {statistics.mean(times_add):.2f}ms avg")
        
        # Benchmark: set_property (warm)
        times_set = []
        for i in range(5):
            _, t = measure_time(
                heren_set_property, session_id, "res://test_scene.tscn", "Root", 
                "position", {"x": i*10, "y": i*20}
            )
            times_set.append(t)
        print(f"  set_property (5 warm ops): {statistics.mean(times_set):.2f}ms avg")
        
        # Benchmark: save_scene (warm)
        _, t_save = measure_time(heren_save_scene, session_id, "res://test_scene.tscn")
        print(f"  save_scene (warm): {t_save:.2f}ms")
        
        # Benchmark: 5 operations sequence (individual calls, warm)
        start = time.perf_counter()
        heren_add_node(session_id, "res://test_scene.tscn", ".", "Sprite2D", "Seq1")
        heren_add_node(session_id, "res://test_scene.tscn", ".", "Sprite2D", "Seq2")
        heren_set_property(session_id, "res://test_scene.tscn", "Seq1", "position", {"x": 50, "y": 50})
        heren_set_property(session_id, "res://test_scene.tscn", "Seq2", "position", {"x": 100, "y": 100})
        heren_save_scene(session_id, "res://test_scene.tscn")
        seq_time = (time.perf_counter() - start) * 1000
        print(f"  5 ops sequence (individual, warm): {seq_time:.2f}ms")
        
        heren_end_session(session_id)
        
        return {
            "method": "godot_server",
            "server_init_ms": server_start_time,
            "get_scene_tree_cold_ms": t_cold,
            "get_scene_tree_warm_avg_ms": statistics.mean(times),
            "add_node_warm_avg_ms": statistics.mean(times_add),
            "set_property_warm_avg_ms": statistics.mean(times_set),
            "save_scene_warm_ms": t_save,
            "sequence_5_ops_ms": seq_time,
        }
        
    finally:
        shutil.rmtree(project, ignore_errors=True)


def benchmark_batch():
    """Benchmark using batch operations."""
    print("\n" + "="*70)
    print("BENCHMARK: Batch Operations (5 ops en 1 llamada)")
    print("="*70)
    
    project = create_temp_project()
    session_id = None
    
    try:
        # Start session with server for best results
        result = heren_start_session(project, use_server=True)
        session_id = result["session_id"]
        
        # Benchmark: Batch of 5 operations
        operations = [
            {"operation": "add_node", "params": {"scene_path": "res://test_scene.tscn", "parent_path": ".", "node_type": "Sprite2D", "node_name": "Batch1"}},
            {"operation": "add_node", "params": {"scene_path": "res://test_scene.tscn", "parent_path": ".", "node_type": "Sprite2D", "node_name": "Batch2"}},
            {"operation": "set_property", "params": {"scene_path": "res://test_scene.tscn", "node_path": "Batch1", "property_name": "position", "value": {"x": 50, "y": 50}}},
            {"operation": "set_property", "params": {"scene_path": "res://test_scene.tscn", "node_path": "Batch2", "property_name": "position", "value": {"x": 100, "y": 100}}},
            {"operation": "save_scene", "params": {"scene_path": "res://test_scene.tscn"}},
        ]
        
        _, t = measure_time(heren_batch, session_id, operations)
        print(f"  batch (5 ops, server): {t:.2f}ms")
        
        # Benchmark: Batch with scripts temporal (no server)
        heren_end_session(session_id)
        result = heren_start_session(project, use_server=False)
        session_id = result["session_id"]
        
        _, t2 = measure_time(heren_batch, session_id, operations)
        print(f"  batch (5 ops, scripts): {t2:.2f}ms")
        
        heren_end_session(session_id)
        
        return {
            "method": "batch",
            "batch_5_ops_server_ms": t,
            "batch_5_ops_scripts_ms": t2,
        }
        
    finally:
        shutil.rmtree(project, ignore_errors=True)


def print_comparison(results_scripts, results_server, results_batch):
    """Print comparison table."""
    print("\n" + "="*70)
    print("COMPARATIVA DE RENDIMIENTO")
    print("="*70)
    print(f"{'Métrica':<40} {'Scripts':<12} {'GodotServer':<12} {'Mejora':<12}")
    print("-"*70)
    
    # get_scene_tree (comparable: cold vs cold, though server has init overhead)
    script_time = results_scripts.get("get_scene_tree_avg_ms", 0)
    server_cold = results_server.get("get_scene_tree_cold_ms", 0)
    server_warm = results_server.get("get_scene_tree_warm_avg_ms", 0)
    
    print(f"{'get_scene_tree (cold)':<40} {script_time:<12.2f} {server_cold:<12.2f} {script_time/server_cold if server_cold > 0 else 0:<12.1f}x")
    print(f"{'get_scene_tree (warm)':<40} {'N/A':<12} {server_warm:<12.2f} {'N/A':<12}")
    
    # Sequence of 5 ops
    script_seq = results_scripts.get("sequence_5_ops_ms", 0)
    server_seq = results_server.get("sequence_5_ops_ms", 0)
    batch_server = results_batch.get("batch_5_ops_server_ms", 0)
    batch_scripts = results_batch.get("batch_5_ops_scripts_ms", 0)
    
    print(f"{'5 ops secuencia (scripts)':<40} {script_seq:<12.2f} {'N/A':<12} {'N/A':<12}")
    print(f"{'5 ops secuencia (server)':<40} {'N/A':<12} {server_seq:<12.2f} {script_seq/server_seq if server_seq > 0 else 0:<12.1f}x")
    print(f"{'5 ops batch (scripts)':<40} {batch_scripts:<12.2f} {'N/A':<12} {script_seq/batch_scripts if batch_scripts > 0 else 0:<12.1f}x")
    print(f"{'5 ops batch (server)':<40} {'N/A':<12} {batch_server:<12.2f} {script_seq/batch_server if batch_server > 0 else 0:<12.1f}x")
    
    # Server init overhead
    server_init = results_server.get("server_init_ms", 0)
    print(f"\n{'Overhead inicio GodotServer':<40} {server_init:<12.2f}ms")
    print(f"{'Punto de equilibrio (ops)':<40} {server_init/script_time if script_time > 0 else 0:<12.0f} ops")
    
    print("="*70)


def main():
    print("="*70)
    print("HEREN MCP - BENCHMARK COMPARATIVO")
    print("Scripts Temporales vs GodotServer vs Batch")
    print("="*70)
    print("\n[!] Este benchmark requiere Godot instalado y toma ~1 minuto")
    print("Incluye tiempo de inicio del servidor en las mediciones\n")
    
    # Auto-start sin input interactivo
    print("Iniciando en 3 segundos...")
    import time
    time.sleep(3)
    
    # Run benchmarks
    results_scripts = benchmark_scripts_temporal()
    results_server = benchmark_godot_server()
    results_batch = benchmark_batch()
    
    # Print comparison
    print_comparison(results_scripts, results_server, results_batch)
    
    # Save results
    all_results = {
        "scripts_temporal": results_scripts,
        "godot_server": results_server,
        "batch": results_batch,
    }
    
    output_path = "benchmark_comparison.json"
    with open(output_path, "w") as f:
        json.dump(all_results, f, indent=2)
    
    print(f"\n[*] Resultados guardados en: {output_path}")


if __name__ == "__main__":
    main()
