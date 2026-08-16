# Contributing to Heren MCP

¡Gracias por tu interés en contribuir! / Thank you for your interest in contributing!

> ⚠️ **Stack actual (v4)**: server **Rust** (FlojoMCP) + plugin **GDScript** (Godot 4.6+).
> El bridge Python v3 fue archivado en la rama `archive/v3`. NO añadas código Python.

---

## 🚀 Cómo empezar / Getting Started

### 1. Clonar / Clone

```bash
git clone https://github.com/CerebroCanibalus/heren-mcp.git
cd heren-mcp
```

### 2. Compilar el server Rust / Build the Rust server

```bash
# Windows (recomendado: usa el toolset MSVC correcto)
scripts/heren-build.bat        # VsDevCmd + debug + test + release + clippy
# o directamente:
cargo build --release
```

> 💡 El `.cargo/config.toml` fija el toolset MSVC del VS 2022 BuildTools (el VS
> 18 Insiders tiene `link.exe` pero CRT incompleto — ver GOTCHA en `AGENTS.md`).

### 3. Correr tests / Run tests

```bash
cargo test --all          # tests Rust (unit + integration)
cargo clippy --all -- -D warnings   # lints (pedantic activo)
cargo fmt --all -- --check          # formato
```

### 4. Validar el plugin GDScript / Validate the GDScript plugin

Requiere Godot 4.6+ en `GODOT_EXE` o PATH:

```bash
# 1. Copiar el plugin al fixture (bajo demanda)
cp -r addons fixtures/empty_project/

# 2. Grafo headless (detecta parse errors que rompen TODO el plugin)
godot --headless --editor --path fixtures/empty_project --quit-after 40

# 3. Tests GDScript unitarios (helpers puros)
godot --headless --path fixtures/empty_project --script res://addons/heren/tests/run_tests.gd

# 4. Limpiar el fixture (no versionar la copia)
rm -rf fixtures/empty_project/addons fixtures/empty_project/.godot
```

> 🔴 **Regla de oro**: un parse error en un handler rompe TODO el plugin (el
> editor no conecta sin error visible). SIEMPRE valida el grafo headless tras
> editar handlers GDScript.

---

## 🛠️ Cómo añadir una tool / How to Add a Tool

Heren MCP usa el patrón **"1 tool, N acciones"** (`action` requerida). Para añadir
una tool sigues 4 capas:

### Paso 1 — Schema en Rust (`crates/heren-server/src/server.rs`)

Añade una función `async fn` con el atributo `#[tool(...)]`. Todos los args
excepto `action` son `Option<>` (el plugin aplica defaults):

```rust
#[tool(description = "MiTool (v4): op1|op2 - descripción. TODOS los args opcionales (defaults por action).")]
async fn mi_tool(
    action: String,
    scene_path: Option<String>,
    project_path: Option<String>,
    // ... más args Option<>
) -> Result<Value, ToolError> {
    let proj = resolve_project(project_path.as_deref())?;
    let registry = EditorRegistry::global();
    let scene_path = scene_path.as_deref().map(normalize_scene_path).unwrap_or_default();
    let a = apply_scene_context(&proj, args(&[
        ("scene_path", (!scene_path.is_empty()).then(|| Value::String(scene_path.clone()))),
        // ...
    ]));
    let mutating = matches!(action.as_str(), "op1" | "op2");
    if mutating {
        forward_mutating(registry, &proj, &format!("mi_tool/{action}"), a, &scene_path).await
    } else {
        forward(registry, &proj, &format!("mi_tool/{action}"), a).await
    }
}
```

### Paso 2 — Handler en GDScript (`addons/heren/handlers/`)

Crea o edita el handler. Todos extienden `heren_handler.gd` (contrato base):

```gdscript
extends "res://addons/heren/handlers/heren_handler.gd"
# @tool heredado de la base

func handle_mi_tool(args: Dictionary) -> Dictionary:
    var action: String = args.get("action", "")
    match action:
        "op1":
            return _op1(args)
        "op2":
            return _op2(args)
        _:
            return _err("action desconocida: " + action)
```

> Los errores SIEMPRE devuelven `_err("mensaje")` → shape `{"ok": false, "error": ...}`.
> Los éxitos devuelven `{"ok": true, ...}`.

### Paso 3 — Registrar en `editor_plugin.gd` y `dispatcher.gd`

```gdscript
# editor_plugin.gd
const MiToolHandlersScript := preload("handlers/mi_tool_handlers.gd")
var _mi_tool_handlers: Node
# en _enter_tree:
_mi_tool_handlers = MiToolHandlersScript.new()
_mi_tool_handlers.set_editor_plugin(self)
add_child(_mi_tool_handlers)
_dispatcher.register_handler("mi_tool", _mi_tool_handlers)
# en _exit_tree: queue_free + null
```

### Paso 4 — Tests

```bash
# Rust: añade la tool a EXPECTED_TOOLS en tests/tools_parity.rs
# + valida schema/description (el test all_tools_have_non_empty_descriptions lo exige)
cargo test --all

# GDScript: añade helpers puros a addons/heren/tests/run_tests.gd si aplica
```

**Checklist de tool nueva:**

- [ ] Schema `#[tool]` con `description` y args `Option<>`
- [ ] Handler `handle_<tool>` que extiende `heren_handler.gd`
- [ ] Registrado en `editor_plugin.gd` (crear + dispatcher + cleanup)
- [ ] Añadido a `EXPECTED_TOOLS` en `tests/tools_parity.rs`
- [ ] `cargo test --all`, `cargo clippy -D warnings`, `cargo fmt --check` pasan
- [ ] Grafo headless Godot valida sin `SCRIPT ERROR|Parse Error`
- [ ] Documentado en `README.md` (tabla de tools) y `AGENTS.md` (§6)

---

## 🧩 Cómo añadir un template / How to Add a Template (v4.7)

El **sistema de templates es transversal** (`template_registry.gd`, patrón `coords.gd`):
cualquier tool puede instanciar templates (hoy `node/instantiate {template}` y `ui/create`;
mañana `resource`, `shader`, `tilemap`…). **Modelo híbrido**: templates `.tscn` + params
por **nombre de nodo canónico**. NUNCA generar el árbol con código GDScript.

### Los 3 archivos que tocar

```
addons/heren/templates/<categoria>/mi_template.tscn   # 1. el .tscn con nodos canónicos
addons/heren/templates/metadata.json                  # 2. la entrada en el índice
addons/heren/tests/run_tests.gd                       # 3. test de instanciación
```

### Paso 1 — El `.tscn` con nodos canónicos

El template es un Control (o árbol) 2D normal. Los nodos que el agente personalizará
tienen nombres canónicos (`Fill`, `Background`, `Label`, `Icon`, `Count`…) y las
propiedades setteables son directas del nodo (ColorRect `color`, Label `text`,
TextureRect `texture`…). Los StyleBoxFlat van fijos en sub_resources (el estilo fino
se hace con `ui/theme`).

### Paso 2 — Entrada en `metadata.json`

```json
{
  "name": "mi_template",
  "category": "hud",
  "description": "Qué hace y qué nodos canónicos expone",
  "file": "hud/mi_template.tscn",
  "params": [
    {"name": "color", "target": "Fill", "property": "color", "description": "Color del relleno"},
    {"name": "text", "target": ".", "property": "text", "description": "Target '.' = root"},
    {"name": "icon", "target": "Icon", "property": "texture", "resource": true, "description": "resource:true carga el path res://"}
  ]
}
```

Reglas de `params`:
- `target` → nodo hijo por path (`.` = root). `targets` (array) → mismo valor a varios nodos.
- `property` → propiedad directa del nodo. Las theme overrides funcionan (`theme_override_colors/font_color`).
- `resource: true` → el valor es un path `res://...` que se carga con `load()` (ej: texture).
- Los valores viajan por el **sistema de coordenadas**: `{x,y}` → Vector2, `{r,g,b,a}` → Color.

### Paso 3 — Test de instanciación en `run_tests.gd`

```gdscript
func _test_mi_template_instantiate() -> bool:
	var instance: Node = TemplateRegistryScript.instantiate("mi_template", {
		"color": {"r": 0.9, "g": 0.2, "b": 0.2, "a": 1.0},
	})
	if instance == null:
		push_error("instantiate(mi_template) = null")
		return false
	var fill: ColorRect = instance.get_node_or_null("Fill") as ColorRect
	if fill == null or not fill.color.is_equal_approx(Color(0.9, 0.2, 0.2, 1.0)):
		push_error("Fill no seteado")
		instance.free()
		return false
	instance.free()
	return true
```

Y registrarlo en `_init()` con `_run("mi_template instantiate", _test_mi_template_instantiate)`.

> ⚠️ `godot --headless --path fixtures/empty_project` — los .tscn de templates se cargan
> sin importar (PackedScene directa). Un `.tscn` con Parse Error rompe el grafo → valida siempre.
> ⚠️ **Lección 2026-08-14**: `String.split()` devuelve `PackedStringArray` (sin `pop_back`) →
> tipar `var segments: Array`; `NodePath` no tiene `begins_with`/`trim_prefix` → `str(path)` primero.

---

## 🧪 Tests / Tests

| Suite | Comando | Qué cubre |
|-------|---------|-----------|
| Rust unit | `cargo test --lib` | helpers puros, registry, launcher |
| Rust integration | `cargo test --all` | paridad tools, latencia, mutabilidad, WS |
| GDScript unit | `godot --headless --script .../run_tests.gd` | coords, constants, heren_error |
| Benchmarks | `cargo bench --bench tools` | latencia list_tools, serialización schemas |

---

## 🐛 Cómo reportar bugs / Reporting Bugs

Busca en [Issues](https://github.com/CerebroCanibalus/heren-mcp/issues) antes.

```markdown
**Descripción:** breve descripción

**Pasos para reproducir:** 1. ... 2. ...

**Esperado:** ... **Actual:** ...

**Entorno:**
- OS: Windows 11 / Ubuntu 22.04
- Rust: stable (rustc --version)
- Godot: 4.6.1-stable
- Versión Heren MCP: 4.6.0

**Logs:** (usar HEREN_LOG_FILE) y **Configuración MCP:**
```

---

## 📝 Estilo / Code Style

### Rust

- `cargo clippy --all -- -D warnings` (pedantic activo, `#![warn(clippy::pedantic)]`).
- `cargo fmt --all` antes de commitear.
- Errores con `thiserror`/`ToolError`, nunca `unwrap()` en producción.
- SAFE por defecto; `unsafe` solo con comentario `SAFETY`.

### GDScript

- Tabs (Godot default), nombres `snake_case`, `_` para métodos privados.
- Toda clase handler extiende `heren_handler.gd` y usa `_err()` para errores.
- Comentarios en español para lógica compleja.

### Commits

Conventional Commits:

```
feat(tool): añadir mi_tool con ops op1/op2
fix(plugin): corregir parse error en node_handlers
test(core): añadir benchmarks para list_tools
refactor(cleanup): Fase X — descripción
docs: actualizar CONTRIBUTING con guía de tools
```

---

## 🔧 Estructura / Project Structure

```
heren-mcp/
├── crates/heren-server/        # server Rust (src/: editor, launcher, pure, registry, server, ws_plugin_server)
│   ├── src/pure.rs             # helpers puros + tests
│   ├── src/constants.rs        # constantes (puerto, timeouts)
│   └── tests/                  # tools_parity, tool_latency, registry_mutability, ws_plugin
├── addons/heren/               # plugin Godot (FUENTE DE VERDAD)
│   ├── handlers/               # heren_handler.gd (base) + handlers por dominio
│   ├── templates/              # .tscn prefabricados + metadata.json (sistema transversal)
│   ├── template_registry.gd    # list/instantiate/exists de templates (patrón coords.gd)
│   ├── constants.gd            # constantes del plugin
│   └── tests/                  # run_tests.gd (unit headless)
├── scripts/                    # heren-build.bat, install_mcp.py, run.bat...
├── fixtures/empty_project/     # proyecto Godot mínimo para tests
├── docs/                       # API, INSTALL, ARCHITECTURE, TROUBLESHOOTING
└── .github/workflows/ci.yml    # CI (Rust + Godot headless + ruff)
```

---

## 🏆 Flujo de contribución / Contribution Flow

1. **Fork** y **rama**: `git checkout -b feat/mi-tool`
2. **Commits** Conventional Commits
3. **Tests**: todos verdes (Rust + GDScript + grafo headless)
4. **CI** pasa (`.github/workflows/ci.yml`)
5. **Actualiza** `README.md`, `AGENTS.md`, `CHANGELOG.md`
6. **PR** con descripción clara

### Checklist del PR

- [ ] `cargo test --all`, `cargo clippy -D warnings`, `cargo fmt --check` verdes
- [ ] Grafo headless Godot sin `SCRIPT ERROR|Parse Error`
- [ ] Tests añadidos
- [ ] Documentación actualizada (README + AGENTS + CHANGELOG)
- [ ] No hay breaking changes sin justificación

---

## 📜 Código de conducta / Code of Conduct

Este proyecto sigue el [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

¡Gracias por contribuir! / Thank you for contributing! 🎉
