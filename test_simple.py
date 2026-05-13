from heren.tools.scene_tools import heren_start_session, heren_get_scene_tree

print('=== START SESSION ===')
result = heren_start_session(r'D:\Mis Juegos\LAIKA\LAIKA-Solarpunk-GJ\laika-gd')
print(f'Success: {result.get("success")}')
print(f'Session: {result.get("session_id")}')

if result.get('success'):
    session_id = result['session_id']
    print('\n=== GET SCENE TREE ===')
    tree = heren_get_scene_tree(session_id, 'res://src/scenes/main_menu.tscn')
    print(f'Nodes: {len(tree.get("nodes", []))}')
    for node in tree.get('nodes', [])[:5]:
        print(f'  - {node["name"]} ({node["type"]})')
else:
    print(f'Error: {result.get("error")}')
    print(f'Message: {result.get("message")}')
