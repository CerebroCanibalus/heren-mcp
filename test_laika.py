import json
import os
import sys
import time

os.environ.setdefault(
    "GODOT_EXE", r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe"
)

PROJECT_PATH = r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd"

sys.path.insert(0, r"D:\Mis Juegos\GodotMCP\heren-mcp\src")

from heren.tools.session_tool import session_tool
from heren.tools.scene_tool import scene_tool
from heren.tools.node_tool import node_tool


def log(title, data):
    print(f"\n=== {title} ===")
    print(json.dumps(data, indent=2, ensure_ascii=False, default=str))


def main():
    ts = str(int(time.time()))
    test_scene = f"res://heren_test_{ts}.tscn"
    abs_scene = os.path.join(PROJECT_PATH, f"heren_test_{ts}.tscn")

    print(f"Proyecto: {PROJECT_PATH}")
    print(f"Escena de prueba: {test_scene}")

    # Abrir sesion
    session = session_tool("open", project_path=PROJECT_PATH)
    log("session.open", session)
    if not session.get("success"):
        print("FALLO: no se pudo abrir sesion")
        return
    sid = session["session_id"]

    try:
        # Crear escena
        create = scene_tool(
            "create", session_id=sid, scene_path=test_scene,
            root_type="Node2D", root_name="Root"
        )
        log("scene.create", create)

        # Anadir Sprite2D
        add_sprite = node_tool(
            "add", session_id=sid, scene_path=test_scene,
            node_path=".", node_type="Sprite2D", node_name="TestSprite",
            properties={"position": {"x": 100, "y": 100}}
        )
        log("node.add Sprite2D", add_sprite)

        # Modificar propiedad
        set_rot = node_tool(
            "set_prop", session_id=sid, scene_path=test_scene,
            node_path="TestSprite", property_name="rotation", value=1.57
        )
        log("node.set_prop rotation", set_rot)

        # Modificar color (modulate)
        set_col = node_tool(
            "set_prop", session_id=sid, scene_path=test_scene,
            node_path="TestSprite", property_name="modulate",
            value={"r": 1.0, "g": 0.5, "b": 0.2, "a": 0.8}
        )
        log("node.set_prop modulate", set_col)

        # Duplicar nodo
        dup = node_tool(
            "duplicate", session_id=sid, scene_path=test_scene,
            node_path="TestSprite", new_name="TestSpriteCopy"
        )
        log("node.duplicate", dup)

        # Guardar
        save = scene_tool("save", session_id=sid, scene_path=test_scene)
        log("scene.save", save)

        # Verificar archivo
        if os.path.exists(abs_scene):
            with open(abs_scene, "r", encoding="utf-8") as f:
                content = f.read()
            print("\n=== Contenido .tscn ===")
            print(content)
            checks = {
                "visible = false": "visible = false" in content,
                "HerenWrapper": "HerenWrapper" in content,
                "Viewport::": "Viewport::" in content,
                "@Node2D@": "@Node2D@" in content,
                "rotation = 1.57": "rotation = 1.57" in content,
                "modulate = Color": "modulate = Color" in content,
            }
            print("\n=== Checks ===")
            for k, v in checks.items():
                status = "OK" if ((k in ["rotation = 1.57", "modulate = Color"] and v) or (k not in ["rotation = 1.57", "modulate = Color"] and not v)) else "FAIL"
                print(f"  {k}: {v} -> {status}")
        else:
            print(f"No se encontro archivo: {abs_scene}")

        # Recargar y ver arbol
        tree = scene_tool("get_tree", session_id=sid, scene_path=test_scene)
        log("scene.get_tree final", tree)

    finally:
        session_tool("close", session_id=sid)
        print("\nSesion cerrada.")


if __name__ == "__main__":
    main()
