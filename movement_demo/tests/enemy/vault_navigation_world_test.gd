extends SceneTree

const VaultNavigation = preload("res://scripts/world/vault_navigation.gd")
var checks := 0
var failures := 0
var navigation_map: RID

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _box(parent: Node3D, size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.name = "CollisionShape3D"
	body.add_child(collision)
	parent.add_child(body)
	body.position = position
	return body

func _region() -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.cell_size = 0.1
	mesh.cell_height = 0.1
	mesh.agent_radius = 0.35
	mesh.agent_height = 1.75
	mesh.agent_max_climb = 0.2
	mesh.region_min_size = 0.0
	mesh.region_merge_size = 0.0
	region.navigation_mesh = mesh
	root.add_child(region)
	navigation_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(navigation_map, 0.1)
	NavigationServer3D.map_set_cell_height(navigation_map, 0.1)
	NavigationServer3D.map_set_use_async_iterations(navigation_map, false)
	NavigationServer3D.map_set_active(navigation_map, true)
	region.set_navigation_map(navigation_map)
	return region

func _cover(region: NavigationRegion3D) -> StaticBody3D:
	var cover: StaticBody3D = load("res://scenes/world/low_cover.tscn").instantiate()
	region.add_child(cover)
	return cover

func _settle(region: NavigationRegion3D) -> void:
	await process_frame
	await create_timer(0.1).timeout
	NavigationServer3D.map_force_update(region.get_navigation_map())
	for unused in 4: await physics_frame

func _path(region: NavigationRegion3D, from: Vector3, to: Vector3, layers: int) -> NavigationPathQueryResult3D:
	var parameters := NavigationPathQueryParameters3D.new()
	parameters.map = region.get_navigation_map()
	parameters.start_position = from
	parameters.target_position = to
	parameters.navigation_layers = layers
	parameters.included_regions = [region.get_rid()]
	if layers == 3:
		# Godot 4.7.2 discards link polygons when either native region
		# filter is nonempty. Query metadata must therefore enforce ownership.
		parameters.included_regions = []
	parameters.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_ALL
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(parameters, result)
	for index in result.path_owner_ids.size():
		if result.path_types[index] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_REGION:
			if result.path_owner_ids[index] != region.get_instance_id(): return NavigationPathQueryResult3D.new()
		else:
			var owner := instance_from_id(result.path_owner_ids[index]) as NavigationLink3D
			if owner == null or not region.is_ancestor_of(owner): return NavigationPathQueryResult3D.new()
	return result

func _arrived(result: NavigationPathQueryResult3D, goal: Vector3) -> bool:
	return not result.path.is_empty() and Vector2(result.path[-1].x - goal.x, result.path[-1].z - goal.z).length() <= 0.05

func _run() -> void:
	var region := _region()
	_box(region, Vector3(14, 0.5, 12), Vector3(0, -0.25, 0))
	var cover := _cover(region)
	var collision := cover.get_node("CollisionShape3D") as CollisionShape3D
	collision.shape.size = Vector3(4.5, 1.1, 0.8)
	collision.position.x = 0.3
	var obstacle := cover.get_node("NavigationBakeObstacle") as NavigationObstacle3D
	obstacle.sync_geometry()
	_check(not obstacle.avoidance_enabled and obstacle.affect_navigation_mesh and not obstacle.carve_navigation_mesh, "native helper retains baking erosion without runtime avoidance")
	var min_x := INF
	var max_x := -INF
	for vertex in obstacle.vertices:
		var point: Vector3 = obstacle.to_global(vertex)
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
	_check(is_equal_approx(max_x - min_x, 4.5) and is_equal_approx((max_x + min_x) * 0.5, 0.3), "native outline follows instance collision override rather than visible mesh")
	var replacement := BoxShape3D.new()
	replacement.size = Vector3(4.5, 1.1, 0.8)
	collision.shape = replacement
	collision.position.x = 0.4
	region.bake_navigation_mesh(false)
	var outline_center := Vector3.ZERO
	for vertex in obstacle.vertices: outline_center += obstacle.to_global(vertex) * 0.25
	_check(is_equal_approx(outline_center.x, 0.4), "native parser refreshes same-frame runtime sibling transform and replacement shape before baking")
	await _settle(region)
	var native := region.navigation_mesh.duplicate() as NavigationMesh
	var inside := NavigationServer3D.region_get_closest_point(region.get_rid(), Vector3(0.3, 0, 0))
	var top := NavigationServer3D.region_get_closest_point(region.get_rid(), Vector3(0.3, 1.1, 0))
	_check(absf(inside.z) > 0.7 and absf(top.z) > 0.7, "native bake excludes physical interior and cover top")
	var detour := _path(region, Vector3(0, 0, 3), Vector3(0, 0, -3), 1)
	_check(_arrived(detour, Vector3(0, 0, -3)) and detour.path.size() > 2, "native bake retains a valid floor detour around cover")
	# Maintenance uses the same parser source for covers; compare actual query
	# behavior after baking parsed geometry rather than comparing polygon counts.
	var maintenance := native.duplicate() as NavigationMesh
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(maintenance, source, region)
	NavigationServer3D.bake_from_source_geometry_data(maintenance, source)
	region.navigation_mesh = maintenance
	await _settle(region)
	var maintenance_inside := NavigationServer3D.region_get_closest_point(region.get_rid(), Vector3(0.3, 0, 0))
	var maintenance_detour := _path(region, Vector3(0, 0, 3), Vector3(0, 0, -3), 1)
	_check(absf(maintenance_inside.z) > 0.7 and _arrived(maintenance_detour, Vector3(0, 0, -3)), "native and maintenance parsing preserve identical obstruction and floor reachability")
	var fixture_path := "res://logs/vault_navigation_work/native_fixture.tres"
	var saved := ResourceSaver.save(native, fixture_path)
	var reloaded := ResourceLoader.load(fixture_path, "NavigationMesh", ResourceLoader.CACHE_MODE_IGNORE) as NavigationMesh
	region.navigation_mesh = reloaded
	await _settle(region)
	var reloaded_top := NavigationServer3D.region_get_closest_point(region.get_rid(), Vector3(0.3, 1.1, 0))
	_check(saved == OK and reloaded != null and absf(reloaded_top.z) > 0.7 and _arrived(_path(region, Vector3(0, 0, 3), Vector3(0, 0, -3), 1), Vector3(0, 0, -3)), "saved and reloaded fixture retains no cover top and valid floor detour")
	# Hand-authored two-island mesh gives a known disconnected graph, independent
	# of bake simplification, existing saved levels, or global edge connections.
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.35
	mesh.cell_size = 0.1
	mesh.vertices = PackedVector3Array([Vector3(-6, 0.1, 0.9), Vector3(-6, 0.1, 5), Vector3(6, 0.1, 5), Vector3(6, 0.1, 0.9),
		Vector3(-6, 0.1, -5), Vector3(-6, 0.1, -0.9), Vector3(6, 0.1, -0.9), Vector3(6, 0.1, -5)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	mesh.add_polygon(PackedInt32Array([4, 5, 6, 7]))
	region.navigation_mesh = mesh
	await _settle(region)
	var service := VaultNavigation.new()
	service.bind_region(region)
	for unused in 100:
		service.advance(4)
		if service.ready: break
	await _settle(region)
	var links := service.connections()
	_check(service.ready and links.size() >= 2, "bounded region service creates several static channels along one eligible wall")
	var walk := _path(region, Vector3(0, 0.1, 3), Vector3(0, 0.1, -3), 1)
	var vault := _path(region, Vector3(0, 0.1, 3), Vector3(0, 0.1, -3), 3)
	_check(not _arrived(walk, Vector3(0, 0.1, -3)) and _arrived(vault, Vector3(0, 0.1, -3)), "native links connect known floor islands only with walk|vault mask")
	var resolved := false
	for index in vault.path_types.size():
		if vault.path_types[index] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK:
			resolved = resolved or not service.resolve_link(vault.path_owner_ids[index]).is_empty()
	_check(resolved, "query metadata native owner ID resolves to this region's pure connection identity")
	var foreign := NavigationRegion3D.new()
	var foreign_mesh := NavigationMesh.new()
	foreign_mesh.vertices = PackedVector3Array([Vector3(-5, 0.2, -4), Vector3(-5, 0.2, 4), Vector3(5, 0.2, 4), Vector3(5, 0.2, -4)])
	foreign_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	foreign.navigation_mesh = foreign_mesh
	root.add_child(foreign)
	foreign.position.x = 100.0
	foreign.set_navigation_map(navigation_map)
	await _settle(region)
	var isolated := _path(region, Vector3(0, 0.1, 3), Vector3(0, 0.1, -3), 3)
	var foreign_used := false
	for owner_id in isolated.path_owner_ids:
		if owner_id == foreign.get_instance_id(): foreign_used = true
	_check(_arrived(isolated, Vector3(0, 0.1, -3)) and not foreign_used and not _arrived(_path(region, Vector3(0, 0.1, 3), Vector3(0, 0.1, -3), 1), Vector3(0, 0.1, -3)), "owned native graph remains valid with a second region on the same map")
	foreign.free()
	var before := service.revision
	service.bind_region(region)
	for unused in 20: service.advance(4)
	_check(service.revision == before, "same-region bind and native map synchronization preserve geometry revision")
	var dynamic := CharacterBody3D.new()
	var dynamic_collision := CollisionShape3D.new()
	var dynamic_shape := CapsuleShape3D.new()
	dynamic_shape.radius = 0.4
	dynamic_shape.height = 1.75
	dynamic_collision.shape = dynamic_shape
	dynamic_collision.position.y = 0.875
	dynamic.add_child(dynamic_collision)
	region.add_child(dynamic)
	dynamic.position = Vector3(-0.32, 0, 0.95)
	await _settle(region)
	for unused in 20: service.advance(4)
	_check(service.revision == before, "ungrouped dynamic characters do not invalidate the shared static geometry")
	collision.shape.size.x += 0.01
	for unused in 100: service.advance(4)
	_check(service.connections().size() == links.size(), "static seed rebuild ignores actual dynamic capsule occupancy")
	dynamic.position = Vector3(-0.32, 1.15, 0)
	await _settle(region)
	collision.shape.size.x += 0.01
	for unused in 100: service.advance(4)
	_check(service.connections().size() == links.size(), "ungrouped characters across the lifted sweep do not disable static links")
	dynamic.free()
	var ceiling := _box(region, Vector3(8, 0.2, 4), Vector3(0, 1.9, 0))
	await _settle(region)
	for unused in 100: service.advance(4)
	_check(service.ready and service.connections().is_empty(), "static low ceiling rejects the actual lifted capsule corridor")
	ceiling.free()
	await _settle(region)
	for unused in 100: service.advance(4)
	links = service.connections()
	_check(not links.is_empty(), "removing static ceiling regenerates legal channels within bounded advances")
	if not links.is_empty():
		var owner: int = links[0].owner_id
		collision.shape.size.x += 0.1
		_check(service.resolve_link(owner).is_empty(), "shape edits reject stale owner immediately before budgeted rebuild")
		for unused in 100: service.advance(4)
		var rebuilt := service.connections()
		if not rebuilt.is_empty():
			var link := instance_from_id(rebuilt[0].owner_id) as NavigationLink3D
			link.reparent(region)
			_check(service.resolve_link(rebuilt[0].owner_id).is_empty(), "metadata ownership rejects native link moved outside the owned container")
	cover.vault_enabled = false
	for unused in 100: service.advance(4)
	_check(service.ready and service.connections().is_empty(), "disabled low wall creates no connections after bounded invalidation")
	cover.vault_enabled = true
	cover.scale.y = 2.0
	for unused in 100: service.advance(4)
	_check(service.ready and service.connections().is_empty(), "high wall cannot retain low-wall links")
	service.release()
	_check(not region.has_node("_VaultNavigation") and service.connections().is_empty() and not service.ready, "release removes runtime native nodes and all identities")
	service.bind_region(region)
	region.free()
	_check(not service.ready and service.connections().is_empty(), "region unload releases the registry and native graph through scene lifecycle")
	NavigationServer3D.free_rid(navigation_map)
	print("VAULT NAVIGATION WORLD: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
