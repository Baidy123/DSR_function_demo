extends SceneTree

## Maintenance command, not a regression or a runtime dependency.
## Solid boxes exclude both their interiors and their tops from these flat maps.
func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var failed := false
	for number in range(1, 6):
		var scene: Node3D = load("res://scenes/world/levels/lvl_%d.tscn" % number).instantiate()
		root.add_child(scene)
		var region: NavigationRegion3D = scene.get_node("NavigationRegion3D")
		var mesh := region.navigation_mesh
		mesh.filter_baking_aabb = AABB()
		mesh.cell_height = 0.25
		mesh.agent_height = 1.75
		mesh.agent_max_climb = 0.25
		var source := NavigationMeshSourceGeometryData3D.new()
		for obstacle in region.find_children("*", "NavigationObstacle3D", true, false):
			if obstacle.has_method("sync_geometry"): obstacle.sync_geometry()
		NavigationServer3D.parse_source_geometry_data(mesh, source, region)
		for body in region.get_node("Environment").find_children("*", "StaticBody3D", true, false):
			if body.get_parent().name == "Ground": continue
			var native := false
			for obstacle in body.find_children("*", "NavigationObstacle3D", true, false):
				if obstacle.affect_navigation_mesh:
					native = true
					break
			if native: continue
			var collision: CollisionShape3D = body.get_node("CollisionShape3D")
			var half: Vector3 = collision.shape.size * 0.5
			var footprint := PackedVector3Array()
			for corner in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z)]:
				footprint.append(region.to_local(collision.to_global(corner)))
			var bottom := region.to_local(collision.to_global(Vector3(0, -half.y, 0))).y
			source.add_projected_obstruction(footprint, bottom - 0.5, half.y * 2.0 + 1.0, false)
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		var path := "res://resources/navigation/lvl_%d_navigation.tres" % number
		var uid := ResourceLoader.get_resource_uid(path)
		var error := ResourceSaver.save(mesh, path)
		if error == OK and uid != ResourceUID.INVALID_ID:
			error = ResourceSaver.set_uid(path, uid)
		failed = failed or mesh.get_polygon_count() == 0 or error != OK
		print("Lvl_%d: %d navigation polygons; save %d" % [number, mesh.get_polygon_count(), error])
		scene.queue_free()
		await process_frame
	quit(1 if failed else 0)
