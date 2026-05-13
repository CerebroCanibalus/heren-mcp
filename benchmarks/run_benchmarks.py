"""
Unified benchmark runner for Heren MCP.

Ejecuta todos los benchmarks y genera reporte comparativo.

Usage:
    python -m benchmarks.run_benchmarks
    python -m benchmarks.run_benchmarks --output report.json
    python -m benchmarks.run_benchmarks --compare baseline.json
    python -m benchmarks.run_benchmarks --suite cache
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

# Add paths
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.join(script_dir, "..")
sys.path.insert(0, os.path.join(project_root, "src"))
sys.path.insert(0, project_root)

from benchmarks.benchmark_tools import BenchmarkSession, BenchmarkScene, BenchmarkNode
from benchmarks.benchmark_cache import benchmark_cache_operations, benchmark_cache_memory


def load_baseline(path):
    """Load baseline results for comparison."""
    try:
        with open(path, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"Warning: Baseline file not found: {path}")
        return None
    except json.JSONDecodeError:
        print(f"Warning: Invalid JSON in baseline file: {path}")
        return None


def compare_results(current, baseline, threshold=0.1):
    """Compare current results with baseline.
    
    Returns list of regressions (items that got slower by more than threshold).
    """
    if not baseline or "results" not in baseline:
        return []
    
    regressions = []
    baseline_map = {r["name"]: r for r in baseline["results"]}
    
    for current_result in current.get("results", []):
        name = current_result["name"]
        if name not in baseline_map:
            continue
            
        baseline_avg = baseline_map[name]["avg_ms"]
        current_avg = current_result["avg_ms"]
        
        if baseline_avg == 0:
            continue
            
        change = (current_avg - baseline_avg) / baseline_avg
        
        if change > threshold:
            regressions.append({
                "name": name,
                "baseline_ms": baseline_avg,
                "current_ms": current_avg,
                "change_percent": change * 100,
            })
    
    return regressions


def run_all_benchmarks():
    """Run all benchmark suites."""
    print("="*70)
    print("HEREN MCP UNIFIED BENCHMARK RUNNER")
    print("="*70)
    print(f"Started at: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Python: {sys.version.split()[0]}")
    print()
    
    all_results = {
        "timestamp": time.time(),
        "python_version": sys.version,
        "godot_exe": os.environ.get("GODOT_EXE", "D:/Mis Juegos/Godot/Godot_v4.6.1-stable_win64.exe"),
        "results": [],
    }
    
    # Run tool benchmarks
    try:
        all_results["results"].extend(BenchmarkSession.run())
        all_results["results"].extend(BenchmarkScene.run())
        all_results["results"].extend(BenchmarkNode.run())
    except Exception as e:
        print(f"\nERROR in tool benchmarks: {e}")
        import traceback
        traceback.print_exc()
    
    # Run cache benchmarks
    try:
        cache_results = {}
        cache_results.update(benchmark_cache_operations())
        cache_results.update(benchmark_cache_memory())
        
        # Convert cache results to standard format
        for name, value in cache_results.items():
            all_results["results"].append({
                "name": name,
                "avg_ms": value if isinstance(value, float) else 0,
                "min_ms": value if isinstance(value, float) else 0,
                "max_ms": value if isinstance(value, float) else 0,
                "iterations": 1,
            })
    except Exception as e:
        print(f"\nERROR in cache benchmarks: {e}")
        import traceback
        traceback.print_exc()
    
    return all_results


def print_summary(results):
    """Print benchmark summary."""
    print("\n" + "="*70)
    print("BENCHMARK SUMMARY")
    print("="*70)
    print(f"{'Benchmark':<45} {'Avg (ms)':>12} {'Status':>10}")
    print("-"*70)
    
    for r in results.get("results", []):
        name = r["name"]
        avg = r["avg_ms"]
        
        # Determine status based on thresholds
        if "cache" in name.lower() or "memory" in name.lower():
            status = "OK"
        elif avg < 1:
            status = "EXCELLENT"
        elif avg < 100:
            status = "GOOD"
        elif avg < 500:
            status = "ACCEPTABLE"
        else:
            status = "SLOW"
        
        print(f"{name:<45} {avg:>12.2f} {status:>10}")


def main():
    parser = argparse.ArgumentParser(description="Heren MCP Benchmark Runner")
    parser.add_argument("--output", "-o", default="benchmark_results.json",
                       help="Output file for results")
    parser.add_argument("--compare", "-c", default=None,
                       help="Baseline file to compare against")
    parser.add_argument("--suite", "-s", default="all",
                       choices=["all", "tools", "cache"],
                       help="Benchmark suite to run")
    parser.add_argument("--threshold", "-t", type=float, default=0.1,
                       help="Regression threshold (default: 0.1 = 10%)")
    
    args = parser.parse_args()
    
    # Run benchmarks
    results = run_all_benchmarks()
    
    # Print summary
    print_summary(results)
    
    # Compare with baseline if provided
    regressions = []
    if args.compare:
        print("\n" + "="*70)
        print("REGRESSION ANALYSIS")
        print("="*70)
        
        baseline = load_baseline(args.compare)
        regressions = compare_results(results, baseline, args.threshold)
        
        if regressions:
            print(f"\nFound {len(regressions)} regressions (threshold: {args.threshold*100:.0f}%):")
            for reg in regressions:
                print(f"  ⚠️  {reg['name']}")
                print(f"      Baseline: {reg['baseline_ms']:.2f}ms")
                print(f"      Current:  {reg['current_ms']:.2f}ms")
                print(f"      Change:   +{reg['change_percent']:.1f}%")
        else:
            print("\n✅ No regressions found!")
    
    # Save results
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\nResults saved to: {output_path.absolute()}")
    
    # Exit with error if regressions found
    if args.compare and regressions:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
