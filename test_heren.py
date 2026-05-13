import sys
sys.path.insert(0, r"D:\Mis Juegos\GodotMCP\heren-mcp\src")

from heren.core.session_manager import get_session_manager
from heren.tools.scene_tools import heren_start_session, heren_get_scene_tree

print("HEREN MCP TEST")
print("=" * 50)

# Iniciar sesion
try:
    result = heren_start_session(
        project_path=r"D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd",
    )
    print(f"Start session: {result}")
    
    if result.get("success"):
        session_id = result["session_id"]
        
        # Test get_scene_tree
        print("\nObteniendo arbol de escena...")
        scene_result = heren_get_scene_tree(
            session_id=session_id,
            scene_path="res://src/test/manual_test/test_scene/test_scene.tscn"
        )
        print(f"Scene tree success: {scene_result.get('success')}")
        if scene_result.get('success'):
            print(f"Scene name: {scene_result.get('tree', {}).get('name')}")
            print(f"Children count: {len(scene_result.get('tree', {}).get('children', []))}")
        else:
            print(f"Error: {scene_result.get('error')}")
    else:
        print(f"Error: {result.get('error')}")
        
except Exception as e:
    print(f"Excepcion: {e}")
    import traceback
    traceback.print_exc()
