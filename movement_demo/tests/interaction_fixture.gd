extends RefCounted

## Optional interaction examples belong to component tests, not the main map.
static func attach(scene: Node) -> void:
	var examples := Node3D.new()
	examples.name = "Interactables"
	scene.add_child(examples)
	var resources := ["keycard", "wine_glass", "terminal", "record_player", "access_gate"]
	var positions := [Vector3(-6, 0, 1.6), Vector3(3, 0, 4.6), Vector3(7.2, 0, 3.2), Vector3(5.4, 0, 4.1), Vector3(9.125, 0, 0)]
	for index in resources.size():
		var path: String = "res://scenes/world/objects/%s.tscn" % resources[index] if index < 4 else "res://scenes/world/access_gate.tscn"
		var item: Node3D = load(path).instantiate()
		item.position = positions[index]
		if index == 4: item.rotation.y = PI * 0.5
		examples.add_child(item)
