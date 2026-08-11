# Tests

Los tests Python de v3 fueron archivados en la rama `archive/v3`.

Heren MCP v4 usa dos suites de tests activas:

1. **Tests Rust** (`crates/heren-server/tests/`):
   - `tools_parity.rs` — paridad de tools y schemas.
   - `ws_plugin.rs` — integración WS server/plugin.
   - `tool_latency.rs` — benchmarks de latencia.
   - `registry_mutability.rs` — tests de mutabilidad del registro.

2. **Tests GDScript** (`addons/heren/tests/`):
   - `test_node_mutability.gd` — mutaciones de nodos y undo/redo.
   - Requiere editor de Godot + GUT (opcional).

Ejecutar:

```bash
cargo test --all
```

Para tests GDScript headless:

```bash
godot --headless --path fixtures/empty_project --script ../addons/heren/tests/test_node_mutability.gd
```
