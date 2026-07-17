import json
import os
import sys
import time

os.environ.setdefault(
    "GODOT_EXE", r"D:\Mis Juegos\Godot\Godot_v4.6.1-stable_win64.exe"
)

PROJECT_PATH = r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd"
TEST_SCENE = "res://test_level.tscn"
ABS_SCENE = os.path.join(PROJECT_PATH, "test_level.tscn")
BACKUP_SCENE = os.path.join(PROJECT_PATH, f"test_level_backup_{int(time.time())}.tscn")

sys.path.insert(0, r"D:\Mis Juegos\GodotMCP\heren-mcp\src")

from heren.tools.session_tool import session_tool
from heren.tools.scene_tool import scene_tool
from heren.tools.node_tool import node_tool
from heren.tools.validate_tool import validate


def log(title, data):
    print(f"\n=== {title} ===")
    print(json.dumps(data, indent=2, ensure_ascii=False, default=str))


def main():
    print(f"Proyecto: {PROJECT_PATH}")
    print(f"Escena: {TEST_SCENE}")

    if os.path.exists(ABS_SCENE):
        import shutil
        shutil.copy2(ABS_SCENE, BACKUP_SCENE)
        print(f"Backup creado: {BACKUP_SCENE}")

    session = session_tool("open", project_path=PROJECT_PATH)
    log("session.open", session)
    if not session.get("success"):
        print("FALLO: no se pudo abrir sesion")
        return
    sid = session["session_id"]

    try:
        tree_before = scene_tool("get_tree", session_id=sid, scene_path=TEST_SCENE)
        log("scene.get_tree (before)", tree_before)

        # Mover Player
        move = node_tool(
            "set_prop", session_id=sid, scene_path=TEST_SCENE,
            node_path="Root/Player", property_name="position",
            value={"x": 123, "y": 456}
        )
        log("node.set_prop Player.position", move)

        # Renombrar Coin1
        rename = node_tool(
            "rename", session_id=sid, scene_path=TEST_SCENE,
            node_path="Root/Coin1", new_name="CoinGold"
        )
        log("node.rename Coin1 -> CoinGold", rename)

        # Guardar
        save = scene_tool("save", session_id=sid, scene_path=TEST_SCENE)
        log("scene.save", save)

        # Validar
        valid = validate("scene", session_id=sid, scene_path=TEST_SCENE)
        log("validate.scene", valid)

        # Verificar contenido
        with open(ABS_SCENE, "r", encoding="utf-8") as f:
            content = f.read()
        print("\n=== Primeras 40 lineas de test_level.tscn ===")
        print("\n".join(content.splitlines()[:40]))

        checks = {
            "visible = false": "visible = false" in content,
            "HerenWrapper": "HerenWrapper" in content,
            "Viewport::": "Viewport::" in content,
            "@Node2D@": "@Node2D@" in content,
            "child_order_changed": "child_order_changed" in content,
            "CoinGold": "CoinGold" in content,
        }
        print("\n=== Checks ===")
        for k, v in checks.items():
            if k == "CoinGold":
                status = "OK" if v else "FAIL"
            else:
                status = "OK" if not v else "FAIL"
            print(f"  {k}: {v} -> {status}")

        tree_after = scene_tool("get_tree", session_id=sid, scene_path=TEST_SCENE)
        log("scene.get_tree (after)", tree_after)

    finally:
        session_tool("close", session_id=sid)
        print("\nSesion cerrada.")


if __name__ == "__main__":
    main()
