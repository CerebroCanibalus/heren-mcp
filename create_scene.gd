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
        print("TEST_OUTPUT: SUCCESS")
    else:
        print("TEST_OUTPUT: FAILED ", err)
    
    quit()
