//! Tests de velocidad / latencia del server Heren MCP.
//!
//! Estos tests no requieren un editor Godot vivo: miden la superficie MCP
//! (listado de tools, validación de schemas, serialización) para detectar
//! regresiones de rendimiento en el binario server.
//!
//! Para ejecutar:
//!     cargo test --test tool_latency -- --nocapture
//!
//! Recomendación: ejecutar en release para números estables:
//!     cargo test --release --test tool_latency -- --nocapture

use flojo_mcp::prelude::{Context, FlojoTester};
use heren_server::Heren;
use std::time::Instant;

const LIST_TOOLS_MIN_OPS: u32 = 100;
const SCHEMA_VALIDATION_MIN_OPS: u32 = 50;

/// Resultado de una micro-benchmark.
#[derive(Debug, Clone)]
struct BenchResult {
    name: String,
    iterations: u32,
    total_ms: u128,
    avg_ms: f64,
    min_ms: f64,
    max_ms: f64,
}

/// Mide `iterations` llamadas a `f` dentro del runtime proporcionado.
/// Crea el runtime una sola vez fuera del bucle para no contaminar la medida.
fn benchmark_rt<F, Fut>(
    name: &str,
    iterations: u32,
    rt: &tokio::runtime::Runtime,
    mut f: F,
) -> BenchResult
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = ()>,
{
    let mut min = u128::MAX;
    let mut max = 0u128;
    let start = Instant::now();

    for _ in 0..iterations {
        let t0 = Instant::now();
        rt.block_on(f());
        let elapsed = t0.elapsed().as_nanos();
        if elapsed < min {
            min = elapsed;
        }
        if elapsed > max {
            max = elapsed;
        }
    }

    let total = start.elapsed().as_millis();
    let avg = total as f64 / iterations.max(1) as f64;

    BenchResult {
        name: name.to_string(),
        iterations,
        total_ms: total,
        avg_ms: avg,
        min_ms: min as f64 / 1_000_000.0,
        max_ms: max as f64 / 1_000_000.0,
    }
}

fn print_result(r: &BenchResult) {
    println!(
        "[benchmark] {:40} iters={:4} total={:6}ms avg={:7.3}ms min={:7.3}ms max={:7.3}ms",
        r.name, r.iterations, r.total_ms, r.avg_ms, r.min_ms, r.max_ms
    );
}

#[test]
fn list_tools_latency_is_acceptable() {
    let rt = tokio::runtime::Runtime::new().expect("tokio runtime");
    let tester = FlojoTester::with_context(Heren::new(), Context::default());

    let result = benchmark_rt("list_tools", LIST_TOOLS_MIN_OPS, &rt, || async {
        let tools = tester.list_tools().await.expect("list_tools");
        assert!(!tools.is_empty(), "debe haber al menos una tool");
    });

    print_result(&result);

    // Umbral conservador para CI/debug. Ajustar tras medir baseline.
    assert!(
        result.avg_ms < 10.0,
        "list_tools promedio ({:.3}ms) excede umbral de 10ms",
        result.avg_ms
    );
}

#[test]
fn schema_validation_latency_is_acceptable() {
    let rt = tokio::runtime::Runtime::new().expect("tokio runtime");
    let tester = FlojoTester::with_context(Heren::new(), Context::default());

    let result = benchmark_rt(
        "validate_all_schemas",
        SCHEMA_VALIDATION_MIN_OPS,
        &rt,
        || async {
            let tools = tester.list_tools().await.expect("list_tools");
            for tool in &tools {
                let schema = serde_json::to_value(&tool.input_schema).expect("serialize schema");
                assert!(
                    schema.is_object(),
                    "schema de {} debe ser objeto",
                    tool.name
                );
            }
        },
    );

    print_result(&result);
    assert!(
        result.avg_ms < 20.0,
        "validación de schemas promedio ({:.3}ms) excede umbral de 20ms",
        result.avg_ms
    );
}

#[test]
fn tool_call_argument_marshalling_latency_is_acceptable() {
    // Mide el coste de construir y serializar un payload típico de tool call.
    // No requiere editor conectado: solo valida que el JSON se geniere rápido.
    let mut min = u128::MAX;
    let mut max = 0u128;
    let iterations = 1000;
    let start = Instant::now();

    for _ in 0..iterations {
        let t0 = Instant::now();
        let args = serde_json::json!({
            "action": "add",
            "scene_path": "res://test.tscn",
            "parent_path": ".",
            "node_type": "Node2D",
            "node_name": "Foo",
            "properties": {
                "position": {"x": 10.0, "y": 20.0},
                "visible": true,
            }
        });
        let s = serde_json::to_string(&args).expect("serialize");
        assert!(!s.is_empty());
        let elapsed = t0.elapsed().as_nanos();
        if elapsed < min {
            min = elapsed;
        }
        if elapsed > max {
            max = elapsed;
        }
    }

    let total = start.elapsed().as_millis();
    let avg = total as f64 / iterations as f64;
    println!(
        "[benchmark] {:40} iters={:4} total={:6}ms avg={:7.3}ms min={:7.3}ms max={:7.3}ms",
        "marshal_node_add_args",
        iterations,
        total,
        avg,
        min as f64 / 1_000_000.0,
        max as f64 / 1_000_000.0
    );
    assert!(
        avg < 1.0,
        "serialización de args ({:.3}ms) excede umbral de 1ms",
        avg
    );
}

#[test]
fn schema_enforces_action_parameter() {
    // Sanity: las tools centralizadas deben exponer `action`. Excepciones
    // legítimas (no son "1 tool N acciones"): `health` (solo project_path).
    const TOOLS_WITHOUT_ACTION: &[&str] = &["health"];

    let rt = tokio::runtime::Runtime::new().expect("tokio runtime");
    rt.block_on(async {
        let tester = FlojoTester::with_context(Heren::new(), Context::default());
        let tools = tester.list_tools().await.expect("list_tools");
        for tool in &tools {
            if TOOLS_WITHOUT_ACTION.contains(&tool.name.as_ref()) {
                continue;
            }
            let schema = serde_json::to_value(&tool.input_schema).expect("serialize");
            let props = schema.get("properties").and_then(|p| p.as_object());
            assert!(
                props.map(|p| p.contains_key("action")).unwrap_or(false),
                "tool '{}' debe tener parametro 'action'",
                tool.name
            );
        }
    });
}
