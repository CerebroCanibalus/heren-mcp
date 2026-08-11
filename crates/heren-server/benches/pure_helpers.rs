//! Benchmarks Criterion (Fase D5) — helpers puros del server Heren MCP.
//!
//! Ejecutar:
//!     cargo bench
//!
//! Mide operaciones sin efectos secundarios (pure.rs) para detectar
//! regresiones de rendimiento estables entre cambios.

use criterion::{BenchmarkId, Criterion, black_box, criterion_group, criterion_main};
use heren_server::pure;
use serde_json::json;

fn bench_normalize_scene_path(c: &mut Criterion) {
    let inputs = [
        "res://scenes/level1.tscn",
        "scenes/level1.tscn",
        r"res:\scenes\level1.tscn",
        "res://scenes/level1.tscn/",
        "",
    ];
    let mut group = c.benchmark_group("normalize_scene_path");
    for (i, input) in inputs.iter().enumerate() {
        group.bench_with_input(BenchmarkId::new("case", i), input, |b, s| {
            b.iter(|| pure::normalize_scene_path(black_box(s)));
        });
    }
    group.finish();
}

fn bench_args_builder(c: &mut Criterion) {
    c.bench_function("args_10_entries", |b| {
        b.iter(|| {
            pure::args(&[
                ("action", Some(json!("add"))),
                ("scene_path", Some(json!("res://test.tscn"))),
                ("parent_path", Some(json!("."))),
                ("node_type", Some(json!("Node2D"))),
                ("node_name", Some(json!("Foo"))),
                ("recursive", None),
                ("index", Some(json!(3))),
                ("visible", Some(json!(true))),
                ("position", Some(json!({"x": 10.0, "y": 20.0}))),
                ("op", None),
            ])
        })
    });
}

fn bench_unwrap_result(c: &mut Criterion) {
    let raw = json!({
        "content": [{"type": "text", "text": "{\"ok\":true,\"node_path\":\"res://x.tscn/Foo\"}"}]
    });
    c.bench_function("unwrap_result_text", |b| {
        b.iter(|| pure::unwrap_result(black_box(&raw)));
    });
}

criterion_group!(
    benches,
    bench_normalize_scene_path,
    bench_args_builder,
    bench_unwrap_result
);
criterion_main!(benches);
