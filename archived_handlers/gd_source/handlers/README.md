# Heren MCP v4 — Handlers archivados (2026-09-09).

> **Ubicación actual**: `archived_handlers/gd_source/handlers/`. **FUERA de `addons/heren/`** a propósito: Godot escanea recursivamente cualquier archivo `.gd` dentro del addon y compila sus scripts — como estos handlers están rotos a propósito (dependen de APIs v3 que ya no existen), dejarlos dentro del addon rompía la compilación de TODO el plugin al arrancar el editor (BUG-NEW-2026-09-22, reportado por General Beria).

Este directorio contiene handlers que fueron **removidos del toolset** porque
`scene_script` (§0.12 W4) los reemplazó completamente. Se mantienen aquí
como referencia y por si se necesita restaurar alguno en el futuro.

## ¿Por qué se archivaron?

El worker GDScript del agente habla directo con la API de Godot sin pasar por
un traductor (coder.rs + schemas.rs). Para mutaciones complejas (búsqueda en
árbol, ownership transaccional, AnimationTree params, esqueletos 2D/3D, etc.)
un worker es ~10 líneas vs cientos en el handler + schema + dispatcher.

## Estructura

- `animation_tree_handlers.gd` — tree_activate/travel/set_param/get_param/add_blend_node/connect_blend_nodes/set_anim_player + capture_pose + blend_pose + retarget (de animation_handlers.gd original).
- `skeleton_handlers.gd` — TODAS las actions skeleton/* (esqueleto 3D/2D completo).
- `tilemap_handlers.gd` — TODAS las actions tilemap/*.
- `ui_layout_theme_handlers.gd` — ui/layout + ui/theme (de ui_handlers.gd original).
- `shader_ops_handlers.gd` — shader/material + shader/uniform + shader/apply (de shader_handlers.gd original).
- `node_movement_handlers.gd` — node/reorder + node/move + node/set_owner (de node_handlers.gd original).
- `signal_set_script_handlers.gd` — signal/set_script (de signal_handlers.gd original) — pendiente de archivar (todavía en `signal_handlers.gd` activo).

## ⚠️ Por qué siguen siendo `.gd`

Mantener la extensión `.gd` es la ÚNICA forma de preservar highlighting del
editor y la lógica del archivo legible para restauraciones. **Estos archivos
NO se compilan** porque están en `archived_handlers/`, fuera de `addons/`.
Godot no los escanea. Si por algún motivo futuro un archivo de aquí se
compilara, fallaría (parse errors garantizados por diseño).

## Cómo restaurar una tool

1. Copiar el archivo de vuelta a `addons/heren/handlers/` (o integrarlo en el handler activo si tiene sentido).
2. Restaurar el `preload` + `_X_handlers = X.new() + add_child + register_handler` en `editor_plugin.gd`.
3. Restaurar la(s) entrada(s) en `_routes.gd`.
4. **Implementar el `#[tool]` fn en `server.rs`** — los handlers archivados NO tienen `fn` equivalente en el server actual (la herramienta ya no está en el schema). Si restauras el handler pero no el `fn`, el plugin recibe mensajes que el server no sabe enviar.
5. Añadir la(s) entrada(s) en `tests/tools_parity.rs::DISPATCH_ROUTES` (si la tool tiene flujo dispatcher-rust).
6. Tests: `cargo test` (tools_parity) + `run_tests.gd` (gdscript).

**Lección operativa**: al añadir herramientas en el repo del usuario, recordar
que la red de seguridad es `scripts/validate_plugin.bat` (compila todo el
grafo del plugin headless y emite errores antes de que el agente pierda
tiempo).