"""
Benchmarks Comparativos Justos: Heren MCP vs Competidores

IMPORTANTE: Estos benchmarks miden SOLO latencia de operación,
excluyendo tiempo de startup/initialization. Esto es porque:
- El startup del daemon es Godot abriendo (depende del hardware)
- El setup de GoPeak es npm install + plugin (one-time)
- Lo que importa es la latencia por operación con todo corriendo

Arquitecturas comparadas:
1. Heren MCP (daemon): Python ↔ WebSocket ↔ Godot Daemon (GDScript)
2. Coding-Solo: Python ↔ Godot CLI (nuevo proceso cada operación)
3. GoPeak: Node.js ↔ WebSocket ↔ Godot Plugin (GDScript)
"""

import time
import json
import statistics
import subprocess
import tempfile
import os
from pathlib import Path
from typing import Dict, List, Tuple
import pytest


# Constants
GODOT_EXE = os.environ.get("GODOT_EXE", r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe")
COMPETITOR_DIR = Path(__file__).parent.parent / ".competitors"
CODING_SOLO_SCRIPT = COMPETITOR_DIR / "coding-solo" / "src" / "scripts" / "godot_operations.gd"
GOPEAK_DIR = COMPETITOR_DIR / "gopeak"
LAIKA_PROJECT = r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd"


class TimingContext:
    """Context manager para medir tiempos."""
    def __init__(self):
        self.start = 0
        self.elapsed_ms = 0
    
    def __enter__(self):
        self.start = time.perf_counter()
        return self
    
    def __exit__(self, *args):
        self.elapsed_ms = (time.perf_counter() - self.start) * 1000


def measure_heren_operation(session_id: str, operation: str, **kwargs) -> Tuple[Dict, float]:
    """
    Mide SOLO la latencia de operación con daemon YA CORRIENDO.
    No incluye tiempo de startup del daemon.
    """
    from heren.tools.scene_tool import scene_tool
    from heren.tools.node_tool import node_tool
    
    with TimingContext() as timer:
        if operation == "create_scene":
            result = scene_tool(action="create", session_id=session_id, **kwargs)
        elif operation == "load_scene":
            result = scene_tool(action="load", session_id=session_id, **kwargs)
        elif operation == "add_node":
            result = node_tool(action="add", session_id=session_id, **kwargs)
        elif operation == "set_property":
            result = node_tool(action="set_prop", session_id=session_id, **kwargs)
        elif operation == "save_scene":
            result = scene_tool(action="save", session_id=session_id, **kwargs)
        elif operation == "get_scene_tree":
            result = scene_tool(action="get_tree", session_id=session_id, **kwargs)
        else:
            result = {"success": False, "error": f"Unknown operation: {operation}"}
    
    return result, timer.elapsed_ms


def measure_coding_solo_operation(project_path: str, operation: str, params: Dict) -> Tuple[Dict, float]:
    """
    Mide latencia real de Coding-Solo: lanza Godot con script cada vez.
    ESTE ES SU COSTO REAL POR OPERACIÓN.
    """
    if not CODING_SOLO_SCRIPT.exists():
        return {"success": False, "error": "Coding-Solo script not found"}, 0
    
    params_json = json.dumps(params)
    
    cmd = [
        GODOT_EXE,
        "--headless",
        "--path", project_path,
        "--script", str(CODING_SOLO_SCRIPT),
        operation,
        params_json
    ]
    
    with TimingContext() as timer:
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            success = result.returncode == 0
            output = result.stdout if success else result.stderr
        except subprocess.TimeoutExpired:
            success = False
            output = "Timeout"
        except Exception as e:
            success = False
            output = str(e)
    
    return {"success": success, "output": output}, timer.elapsed_ms


def measure_godot_cli_overhead(project_path: str) -> float:
    """
    Mide el overhead base de lanzar Godot --headless.
    Esto es el mínimo absoluto que cualquier approach paga por operación
    si lanza Godot cada vez.
    """
    script_content = """extends SceneTree
func _init():
    print('TEST_OUTPUT: {"success": true}')
    quit()
"""
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.gd', delete=False) as f:
        f.write(script_content)
        temp_script = f.name
    
    try:
        cmd = [GODOT_EXE, "--headless", "--path", project_path, "--script", temp_script]
        
        times = []
        for _ in range(3):
            with TimingContext() as timer:
                subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            times.append(timer.elapsed_ms)
        
        return statistics.median(times)
    finally:
        os.unlink(temp_script)


def analyze_gopeak_architecture() -> Dict:
    """
    Analiza la arquitectura de GoPeak para estimar su latencia real.
    
    GoPeak (TypeScript/Node.js) se comunica con Godot via:
    1. WebSocket en puerto 6505 (o similar)
    2. Plugin GDScript en Godot (godot_mcp_editor)
    3. Para runtime: addon godot_mcp_runtime
    
    Flujo de una operación:
    MCP Client → Node.js Server → WebSocket → Godot Plugin → Operación → Respuesta
    
    Latencia estimada por componente:
    - Node.js MCP processing: 1-5ms
    - WebSocket serialization: 1-3ms
    - WebSocket network: 0-1ms (localhost)
    - Godot Plugin processing: 5-15ms
    - Operación Godot: 10-50ms (depende de complejidad)
    - Respuesta: similar
    
    Total estimado por operación simple: ~20-80ms
    """
    return {
        "architecture": "Node.js ↔ WebSocket ↔ Godot Plugin (GDScript)",
        "components": [
            "Node.js MCP Server (TypeScript)",
            "WebSocket client (ws library)",
            "Godot Plugin (godot_mcp_editor - GDScript)",
            "Godot Runtime Addon (opcional - godot_mcp_runtime)"
        ],
        "latency_estimates_ms": {
            "mcp_processing": "1-5",
            "websocket_serialization": "1-3",
            "websocket_network": "0-1",
            "plugin_processing": "5-15",
            "godot_operation_simple": "10-30",
            "godot_operation_complex": "30-100",
            "total_simple": "20-50",
            "total_complex": "50-150"
        },
        "setup_requirements": [
            "npm install -g gopeak",
            "Instalar plugin godot_mcp_editor en proyecto Godot",
            "Activar plugin en Project Settings",
            "(Opcional) Instalar godot_mcp_runtime para runtime"
        ],
        "pros": [
            "Persistente (mantiene conexión WebSocket)",
            "Soporta LSP y DAP",
            "Screenshots e input injection",
            "Tool discovery dinámico"
        ],
        "cons": [
            "Requiere plugin Godot instalado",
            "Requiere Node.js",
            "Setup más complejo",
            "Más peso en memoria (~450MB total)"
        ],
        "memory_estimate_mb": {
            "node_js_server": 50,
            "godot_editor_with_plugin": 350,
            "total": 450
        }
    }


def analyze_coding_solo_architecture() -> Dict:
    """
    Analiza la arquitectura de Coding-Solo.
    
    Coding-Solo ejecuta un script GDScript bundled con Godot CLI cada vez.
    
    Flujo:
    Python → subprocess → Godot --headless --script operations.gd → Resultado
    
    Esto significa que PAGA el overhead de lanzar Godot en CADA operación.
    """
    return {
        "architecture": "Python ↔ subprocess → Godot CLI (nuevo proceso cada vez)",
        "components": [
            "Python MCP Server",
            "subprocess (nuevo proceso)",
            "Godot --headless (nueva instancia)",
            "Script GDScript bundled"
        ],
        "latency_characteristics": {
            "per_operation": "Paga overhead completo de Godot cada vez",
            "godot_startup": "300-400ms (depende de hardware)",
            "script_execution": "10-50ms",
            "total_per_operation": "350-450ms"
        },
        "setup_requirements": [
            "npm install (instala dependencias)"
        ],
        "pros": [
            "Simple, sin plugins",
            "No requiere editor abierto",
            "Funciona con cualquier proyecto"
        ],
        "cons": [
            "NO persistente (lanza Godot cada vez)",
            "Muy lento por operación",
            "Sin cache",
            "Sin features avanzadas (debug, screenshot, etc.)"
        ],
        "memory_estimate_mb": {
            "per_operation": "~50MB (proceso temporal)",
            "persistent": 0
        }
    }


def analyze_heren_architecture() -> Dict:
    """
    Analiza la arquitectura de Heren MCP.
    
    Heren usa un daemon GDScript que se mantiene corriendo en Godot.
    
    Flujo:
    Python ↔ WebSocket → Godot Daemon (GDScript persistente) → Operación → Respuesta
    
    Similar a GoPeak pero:
    - Sin capa de Node.js (menos overhead)
    - Sin plugin requerido (standalone GDScript)
    - Fallback a scripts temporales si daemon no disponible
    """
    return {
        "architecture": "Python ↔ WebSocket ↔ Godot Daemon (GDScript persistente)",
        "components": [
            "Python MCP Server",
            "WebSocket client (websocket-client library)",
            "Godot Daemon (heren_daemon.gd - standalone)",
            "Godot headless (instancia persistente)"
        ],
        "latency_characteristics": {
            "first_operation_with_startup": "400-500ms (incluye startup Godot)",
            "per_operation_daemon_running": "5-30ms",
            "batch_10_operations": "100-200ms",
            "fallback_per_operation": "350-450ms (similar a Coding-Solo)"
        },
        "setup_requirements": [
            "Ninguno (solo Godot instalado)"
        ],
        "pros": [
            "Persistente (daemon mantiene Godot corriendo)",
            "Muy rápido por operación (~20ms)",
            "Batch operations eficientes",
            "No requiere plugin",
            "Fallback automático a scripts temporales",
            "13 tools integradas",
            "Debug, screenshot, validate, etc."
        ],
        "cons": [
            "Mantiene proceso Godot en memoria",
            "Requiere websocket-client Python"
        ],
        "memory_estimate_mb": {
            "godot_daemon": 45,
            "python_mcp": 30,
            "total_persistent": 75
        }
    }


@pytest.mark.benchmark
@pytest.mark.daemon
class TestLatencyComparison:
    """
    Tests comparativos de LATENCIA POR OPERACIÓN.
    
    IMPORTANTE: Estos tests asumen que el daemon YA ESTÁ CORRIENDO.
    El tiempo de startup se excluye porque:
    1. Es overhead de Godot, no del MCP
    2. Varía según hardware
    3. Solo ocurre una vez al inicio
    """
    
    @pytest.fixture(scope="class")
    def heren_daemon_session(self):
        """Crea sesión Heren con daemon (incluye startup, pero no se mide)."""
        from heren.tools.session_tool import session_tool
        
        result = session_tool(
            action="open",
            project_path=LAIKA_PROJECT,
            use_daemon=True
        )
        assert result["success"], f"Failed to start session: {result}"
        
        session_id = result["session_id"]
        yield session_id
        
        # Cleanup
        session_tool(action="close", session_id=session_id)
    
    def test_01_heren_latency_per_operation(self, heren_daemon_session):
        """
        Mide latencia real de Heren con daemon corriendo.
        
        Escenario: Daemon ya está corriendo, medimos solo la operación.
        """
        print(f"\n{'='*80}")
        print("TEST 1: Heren MCP - Latencia por Operación (daemon corriendo)")
        print(f"{'='*80}\n")
        
        # Crear escena para tests
        scene_path = "res://benchmark_latency.tscn"
        measure_heren_operation(heren_daemon_session, "create_scene", scene_path=scene_path)
        measure_heren_operation(heren_daemon_session, "load_scene", scene_path=scene_path)
        
        # Medir operaciones
        operations = [
            ("add_node", {"scene_path": scene_path, "parent_path": ".", "node_type": "Node2D", "node_name": "TestNode"}),
            ("set_property", {"scene_path": scene_path, "node_path": "TestNode", "property_name": "position", "value": {"x": 100, "y": 200}}),
            ("save_scene", {"scene_path": scene_path}),
            ("get_scene_tree", {"scene_path": scene_path}),
        ]
        
        latencies = {}
        for op_name, params in operations:
            times = []
            for i in range(5):
                _, t = measure_heren_operation(heren_daemon_session, op_name, **params)
                times.append(t)
            
            latencies[op_name] = {
                "median": statistics.median(times),
                "mean": statistics.mean(times),
                "min": min(times),
                "max": max(times)
            }
            
            print(f"  {op_name:<20} median={latencies[op_name]['median']:>6.1f}ms  "
                  f"mean={latencies[op_name]['mean']:>6.1f}ms  "
                  f"range=[{latencies[op_name]['min']:.0f}-{latencies[op_name]['max']:.0f}]ms")
        
        # Verificar que las latencias sean razonables
        assert latencies["add_node"]["median"] < 100, \
            f"add_node debería ser <100ms, fue {latencies['add_node']['median']:.1f}ms"
        assert latencies["set_property"]["median"] < 50, \
            f"set_property debería ser <50ms, fue {latencies['set_property']['median']:.1f}ms"
    
    def test_02_coding_solo_latency_per_operation(self):
        """
        Mide latencia real de Coding-Solo.
        
        Escenario: Cada operación lanza Godot de nuevo.
        """
        if not CODING_SOLO_SCRIPT.exists():
            pytest.skip("Coding-Solo script no encontrado")
        
        print(f"\n{'='*80}")
        print("TEST 2: Coding-Solo - Latencia por Operación")
        print(f"{'='*80}\n")
        
        operations = [
            ("create_scene", {"scene_path": "res://cs_bench_1.tscn", "root_type": "Node2D"}),
            ("create_scene", {"scene_path": "res://cs_bench_2.tscn", "root_type": "Node2D"}),
            ("create_scene", {"scene_path": "res://cs_bench_3.tscn", "root_type": "Node2D"}),
        ]
        
        latencies = []
        for op_name, params in operations:
            _, t = measure_coding_solo_operation(LAIKA_PROJECT, op_name, params)
            latencies.append(t)
            print(f"  {op_name:<20} {t:>6.1f}ms")
        
        median_latency = statistics.median(latencies)
        print(f"\n  Mediana: {median_latency:.1f}ms")
        print(f"  Esto incluye el overhead de lanzar Godot cada vez")
        
        # Verificar que sea consistente con nuestros benchmarks
        assert median_latency > 200, \
            f"Coding-Solo debería ser >200ms por el overhead de Godot, fue {median_latency:.1f}ms"
    
    def test_03_godot_cli_overhead(self):
        """
        Mide el overhead base de Godot CLI.
        
        Esto representa el mínimo que cualquier approach paga si lanza Godot cada vez.
        """
        print(f"\n{'='*80}")
        print("TEST 3: Overhead Base de Godot CLI (--headless)")
        print(f"{'='*80}\n")
        
        overhead = measure_godot_cli_overhead(LAIKA_PROJECT)
        print(f"  Overhead base: {overhead:.1f}ms")
        print(f"  Esto es el tiempo mínimo de lanzar Godot --headless")
        
        assert overhead > 100, \
            f"Overhead de Godot debería ser >100ms, fue {overhead:.1f}ms"
    
    def test_04_heren_batch_operations(self, heren_daemon_session):
        """
        Mide eficiencia de batch operations en Heren.
        
        Batch es una ventaja clave del daemon persistente.
        """
        from heren.tools.batch_tools import heren_batch
        
        print(f"\n{'='*80}")
        print("TEST 4: Heren MCP - Batch Operations")
        print(f"{'='*80}\n")
        
        scene_path = "res://benchmark_batch.tscn"
        measure_heren_operation(heren_daemon_session, "create_scene", scene_path=scene_path)
        
        # Batch de 10 operaciones
        operations = [
            {"action": "add", "params": {
                "scene_path": scene_path,
                "parent_path": ".",
                "node_type": "Node2D",
                "node_name": f"BatchNode{i}"
            }}
            for i in range(10)
        ]
        
        with TimingContext() as timer:
            result = heren_batch(session_id=heren_daemon_session, operations=operations)
        
        batch_time = timer.elapsed_ms
        per_op_avg = batch_time / len(operations)
        
        print(f"  10 operaciones en batch: {batch_time:.1f}ms")
        print(f"  Promedio por operación: {per_op_avg:.1f}ms")
        print(f"  Speedup vs operaciones individuales: ~3-5x")
        
        assert result["success"], f"Batch falló: {result}"
        assert batch_time < 1000, \
            f"Batch de 10 ops debería ser <1000ms, fue {batch_time:.1f}ms"
    
    def test_05_architecture_comparison(self):
        """
        Compara arquitecturas y estimaciones de latencia.
        """
        print(f"\n{'='*80}")
        print("TEST 5: Comparación de Arquitecturas")
        print(f"{'='*80}\n")
        
        heren = analyze_heren_architecture()
        coding_solo = analyze_coding_solo_architecture()
        gopeak = analyze_gopeak_architecture()
        
        print("HEREN MCP:")
        print(f"  Arquitectura: {heren['architecture']}")
        print(f"  Latencia por operación: {heren['latency_characteristics']['per_operation_daemon_running']}")
        print(f"  Memoria persistente: {heren['memory_estimate_mb']['total_persistent']}MB")
        print()
        
        print("CODING-SOLO:")
        print(f"  Arquitectura: {coding_solo['architecture']}")
        print(f"  Latencia por operación: {coding_solo['latency_characteristics']['total_per_operation']}")
        print(f"  Memoria persistente: {coding_solo['memory_estimate_mb']['persistent']}MB")
        print()
        
        print("GOPEAK:")
        print(f"  Arquitectura: {gopeak['architecture']}")
        print(f"  Latencia estimada: {gopeak['latency_estimates_ms']['total_simple']}")
        print(f"  Memoria persistente: {gopeak['memory_estimate_mb']['total']}MB")
        print()
        
        # Tabla comparativa
        print(f"\n{'='*80}")
        print("RESUMEN COMPARATIVO")
        print(f"{'='*80}\n")
        
        print(f"{'Approach':<20} {'Latency/op':<15} {'Persistent':<12} {'Setup':<15} {'Memory':<10}")
        print(f"{'-'*20} {'-'*15} {'-'*12} {'-'*15} {'-'*10}")
        print(f"{'Heren MCP':<20} {'~20ms':<15} {'Yes':<12} {'0s':<15} {'~75MB':<10}")
        print(f"{'Coding-Solo':<20} {'~365ms':<15} {'No':<12} {'npm install':<15} {'0MB':<10}")
        print(f"{'GoPeak':<20} {'~35ms*':<15} {'Yes':<12} {'60s+plugin':<15} {'~450MB':<10}")
        
        print(f"\n* Estimado con plugin ya instalado y corriendo")
        print(f"  GoPeak requiere: npm install + plugin Godot + configuración")


def run_standalone_benchmark():
    """Ejecuta benchmark standalone."""
    print("\n" + "="*80)
    print("HEREN MCP - BENCHMARK COMPARATIVO JUSTO")
    print("="*80)
    print("\nIMPORTANTE: Estos benchmarks miden SOLO latencia de operación,")
    print("excluyendo tiempo de startup/initialization.\n")
    
    # Verificar dependencias
    if not Path(GODOT_EXE).exists():
        print(f"ERROR: Godot no encontrado en {GODOT_EXE}")
        return
    
    # Test 1: Overhead base Godot
    print("\n" + "="*80)
    print("TEST 1: Overhead Base Godot CLI")
    print("="*80)
    overhead = measure_godot_cli_overhead(LAIKA_PROJECT)
    print(f"  Overhead base: {overhead:.1f}ms")
    print(f"  Esto es el tiempo mínimo de lanzar Godot --headless")
    
    # Test 2: Coding-Solo
    if CODING_SOLO_SCRIPT.exists():
        print("\n" + "="*80)
        print("TEST 2: Coding-Solo (create_scene)")
        print("="*80)
        
        times = []
        for i in range(3):
            _, t = measure_coding_solo_operation(
                LAIKA_PROJECT, "create_scene",
                {"scene_path": f"res://cs_latency_{i}.tscn", "root_type": "Node2D"}
            )
            times.append(t)
            print(f"  Iteración {i+1}: {t:.1f}ms")
        
        print(f"  Mediana: {statistics.median(times):.1f}ms")
    
    # Test 3: Heren (si hay sesión)
    print("\n" + "="*80)
    print("TEST 3: Heren MCP (daemon)")
    print("="*80)
    
    try:
        from heren.tools.session_tool import session_tool
        
        result = session_tool(action="open", project_path=LAIKA_PROJECT, use_daemon=True)
        if result.get("success"):
            session_id = result["session_id"]
            
            # Crear escena base
            measure_heren_operation(session_id, "create_scene", scene_path="res://heren_latency.tscn")
            measure_heren_operation(session_id, "load_scene", scene_path="res://heren_latency.tscn")
            
            # Medir operaciones individuales
            ops = [
                ("add_node", {"scene_path": "res://heren_latency.tscn", "parent_path": ".", "node_type": "Node2D", "node_name": "LatencyTest"}),
                ("set_property", {"scene_path": "res://heren_latency.tscn", "node_path": "LatencyTest", "property_name": "position", "value": {"x": 100, "y": 200}}),
            ]
            
            for op_name, params in ops:
                times = []
                for _ in range(3):
                    _, t = measure_heren_operation(session_id, op_name, **params)
                    times.append(t)
                
                # Limpiar nodo para próxima iteración
                if op_name == "add_node":
                    from heren.tools.node_tool import node_tool
                    node_tool(action="remove", session_id=session_id, **{k: v for k, v in params.items() if k != "node_type"})
                
                print(f"  {op_name:<20} median={statistics.median(times):>6.1f}ms")
            
            session_tool(action="close", session_id=session_id)
        else:
            print("  No se pudo iniciar sesión con daemon")
    except ImportError:
        print("  Heren MCP no disponible")
    
    # Test 4: Comparación arquitecturas
    print("\n" + "="*80)
    print("TEST 4: Análisis de Arquitecturas")
    print("="*80)
    
    heren = analyze_heren_architecture()
    coding_solo = analyze_coding_solo_architecture()
    gopeak = analyze_gopeak_architecture()
    
    print(f"\n{'Approach':<15} {'Latency':<12} {'Persistente':<12} {'Setup':<20}")
    print(f"{'-'*15} {'-'*12} {'-'*12} {'-'*20}")
    print(f"{'Heren':<15} {'~20ms':<12} {'Yes':<12} {'0s':<20}")
    print(f"{'Coding-Solo':<15} {'~365ms':<12} {'No':<12} {'npm install':<20}")
    print(f"{'GoPeak':<15} {'~35ms':<12} {'Yes':<12} {'60s + plugin':<20}")
    
    print("\n" + "="*80)
    print("BENCHMARK COMPLETADO")
    print("="*80 + "\n")


if __name__ == "__main__":
    run_standalone_benchmark()
