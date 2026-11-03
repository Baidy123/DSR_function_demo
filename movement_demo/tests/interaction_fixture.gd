extends RefCounted

## Optional interaction examples belong to component tests, not the main map.
static func attach(scene: Node) -> void:
	var examples: Node3D = scene.get_node_or_null("Interactables")
	if examples == null:
		examples = Node3D.new()
		examples.name = "Interactables"
		scene.add_child(examples)
	var entries := [
		{"name": "WineGlass", "path": "res://scenes/world/objects/wine_glass.tscn", "position": Vector3(3, 0, 4.6)},
		{"name": "Terminal", "path": "res://scenes/world/objects/terminal.tscn", "position": Vector3(7.2, 0, 3.2)},
		{"name": "RecordPlayer", "path": "res://scenes/world/objects/record_player.tscn", "position": Vector3(5.4, 0, 4.1)},
		{"name": "LevelPortal", "path": "res://scenes/world/objects/quest_portal.tscn", "position": Vector3(8.2, 0, 0)},
	]
	for entry in entries:
		if examples.has_node(entry.name): continue
		var item: Node3D = load(entry.path).instantiate()
		item.name = entry.name
		item.position = entry.position
		if entry.name == "LevelPortal": item.rotation.y = PI * 0.5
		examples.add_child(item)
