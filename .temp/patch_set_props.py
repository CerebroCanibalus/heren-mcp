# coding: utf-8
path = r'D:\Mis Juegos\GodotMCP\heren-mcp\src\heren\daemon\heren_scene_ops.gd'
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# Add handle_set_properties after handle_set_property
old = '\t"new_value": str(deserialized)\n\t}\n\t\n\t\nfunc handle_get_node_properties'
new = '\t"new_value": str(deserialized)\n\t}\n\t\n\t\n# ============================================================\n# SET PROPS (multi-propiedad en 1 call)\n# ============================================================\n\nfunc handle_set_properties(params: Dictionary) -> Dictionary:\n\t"""Set multiple properties on a node in one call.\n\tparams: scene_path, node_path, properties: {prop_name: value, ...}\n\t"""\n\tvar scene_path = params.get("scene_path", "")\n\tvar node_path = params.get("node_path", "")\n\tvar properties = params.get("properties", {})\n\t\n\tif not scene_path or not node_path or properties.is_empty():\n\t\treturn {"success": false, "error": "missing_params", "message": "scene_path, node_path y properties (dict) son requeridos"}\n\t\n\tif not _scene_cache.has(scene_path):\n\t\treturn {"success": false, "error": "scene_not_loaded"}\n\t\n\tvar root = _scene_cache[scene_path]\n\tvar normalized_path = _normalize_node_path(node_path, root)\n\tvar node = root.get_node_or_null(normalized_path)\n\t\n\tif not node:\n\t\treturn {"success": false, "error": "node_not_found", "node_path": node_path}\n\t\n\tvar results = {}\n\tfor prop_name in properties.keys():\n\t\tvar val = properties[prop_name]\n\t\tvar deserialized = _deserialize_value_callback.call(val) if _deserialize_value_callback else val\n\t\tif prop_name in node:\n\t\t\tnode.set(prop_name, deserialized)\n\t\t\tresults[prop_name] = "ok"\n\t\telse:\n\t\t\tresults[prop_name] = "property_not_found"\n\t\n\t_mark_dirty(scene_path)\n\t\n\treturn {\n\t\t"success": true,\n\t\t"scene_path": scene_path,\n\t\t"node_path": node_path,\n\t\t"properties_count": properties.size(),\n\t\t"results": results\n\t}\n\n\nfunc handle_get_node_properties'
c = c.replace(old, new)

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)
print('OK - set_props handler added')
