import sys
sys.path.insert(0, 'D:\\Mis Juegos\\GodotMCP\\heren-mcp\\src')
from heren.core.session_manager import get_session_manager

manager = get_session_manager()

script = '''
extends SceneTree

func _initialize():
    var root = CharacterBody2D.new()
    root.name = "Hero"
    root.position = Vector2(100, 200)
    
    var packed = PackedScene.new()
    packed.pack(root)
    
    var path = "res://src/test/manual_test/test_scene/ComplexHero.tscn"
    var err = ResourceSaver.save(packed, path)
    
    if err == OK:
        print("TEST_OUTPUT: {\\"success\\": true, \\"path\\": \\"" + path + "\\"}")
    else:
        print("TEST_OUTPUT: {\\"success\\": false, \\"error\\": \\"save_failed\\"}")
    
    quit()
'''

result = manager.execute_gdscript('acd58ae9', script)
print('Result:', result)
