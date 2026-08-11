# Benchmarks

Los benchmarks Python antiguos fueron archivados en la rama `archive/v3`.

Para Heren MCP v4 los benchmarks deben ejecutarse contra el binario server Rust:

```bash
# Ejecutar tests de latencia (sin editor Godot vivo)
cargo test --release --test tool_latency -- --nocapture

# TODO: añadir benchmarks con Criterion en crates/heren-server/benches/
```

Ver `crates/heren-server/tests/tool_latency.rs`.
