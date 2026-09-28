@tool
extends "res://addons/godot_ai/testing/test_suite.gd"

func test_cover_instance_save() -> void:
	var root: Node = load("res://scenes/arena.tscn").instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	for name in ["CoverA", "CoverC"]:
		var cover := root.get_node("NavigationRegion3D/Environment/" + name)
		var collision := cover.get_node("CollisionShape3D") as CollisionShape3D
		var expected := Vector3(1.2, 2.2, 6.890625) if name == "CoverA" else Vector3(2, 2.2, 1)
		assert_true(collision.shape.size.is_equal_approx(expected), name + "编辑器保留原尺寸")
		assert_true(cover.get_node("Mesh").mesh.size.is_equal_approx(expected), name + "外观与碰撞一致")
	var packed := PackedScene.new()
	packed.pack(root)
	var copy := packed.instantiate()
	for name in ["CoverA", "CoverC"]:
		var expected := Vector3(1.2, 2.2, 6.890625) if name == "CoverA" else Vector3(2, 2.2, 1)
		assert_true(copy.get_node("NavigationRegion3D/Environment/" + name + "/CollisionShape3D").shape.size.is_equal_approx(expected), name + "保存并实例化保留原尺寸")
	assert_true(copy.get_node("NavigationRegion3D/Environment/CoverA/CollisionShape3D").position.is_equal_approx(Vector3(0, 0, 1.4453125)), "保存后保留CoverA局部偏移")
	copy.free()
	root.free()
