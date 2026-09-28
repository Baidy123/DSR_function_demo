extends SceneTree

func _initialize() -> void:
	_bake.call_deferred()

func _bake() -> void:
	var arena = load("res://scenes/arena.tscn").instantiate()
	root.add_child(arena)
	var region: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	region.bake_navigation_mesh(false)
	var count: int = region.navigation_mesh.get_polygon_count()
	var error: Error = ResourceSaver.save(region.navigation_mesh, "res://resources/navigation/arena_navigation.tres")
	print("Arena navigation polygons: ", count, "; save: ", error)
	quit(0 if count > 0 and error == OK else 1)
