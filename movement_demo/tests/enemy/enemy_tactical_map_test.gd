extends SceneTree

const TacticalMap = preload("res://scripts/enemy/services/enemy_tactical_map.gd")
var checks := 0
var failures := 0
var frame := 1000000


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + label)


func _run() -> void:
	var arena := _arena()
	root.add_child(arena)
	await physics_frame
	await physics_frame
	var region: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	var index := TacticalMap.new()
	index.bind_region(region)
	check(index.query_sectors(Vector3.ZERO, 30.0).is_empty(), "Cold query does not secretly prepare the map")
	var cold := index.statistics()
	index.advance_preparation(0, Time.get_ticks_usec() + 2000, frame)
	check(index.statistics().points == cold.points, "Zero shared allowance performs no geometry or source work")
	var first: Dictionary = index.advance_preparation(3, Time.get_ticks_usec() + 2000, frame)
	check(first.points <= 3 and first.points > 0, "Cold preparation consumes the passed point allowance")
	check(index.advance_preparation(24, Time.get_ticks_usec() + 2000, frame).points == 0, "Other members cannot advance the shared queue twice in one frame")
	check(not index.ready(), "Cold map preparation is genuinely incremental")
	_pump(index, 80)
	var sectors: Array[Dictionary] = index.query_sectors(Vector3.ZERO, 30.0, 1, 24)
	check(index.ready() and sectors.size() >= 4, "Unlabelled actual navigation creates several prepared sectors")
	check(index.query_sectors(Vector3.ZERO, 30.0, 2, 24).is_empty(), "Navigation layers remain part of map eligibility")
	var before_queries: Dictionary = index.statistics()
	for _member in 6:
		index.query_sectors(Vector3.ZERO, 30.0, 1, 6)
	check(index.statistics().points == before_queries.points and index.statistics().world_queries == before_queries.world_queries,
		"Six readers reuse values without six map scans or world queries")
	check(index.query_sectors(Vector3.ZERO, 10000.0, 1, 10000).size() <= 24, "Large caller radius and count cannot expand query work/result caps")
	if not sectors.is_empty():
		var copy: Dictionary = sectors[0]
		var key: String = copy.sector_key
		copy.candidates.clear()
		var fresh: Array[Dictionary] = index.query_sectors(Vector3.ZERO, 30.0, 1, 24)
		check(fresh.any(func(value: Dictionary): return value.sector_key == key and not value.candidates.is_empty()), "Returned candidate arrays cannot mutate the shared cache")
		check(not copy.has("actor_id") and not copy.has("checked") and not copy.has("visible") and not copy.has("path"), "Static map does not own personal eligibility, observations or paths")
	var built_before: int = index.statistics().built
	var nav_before: int = index.navigation_revision()
	index.reset()
	check(index.statistics().built == built_before and index.navigation_revision() == nav_before and index.ready(), "Same-map combat reset retains valid static preparation")
	var near := _near_sector(index, Vector3(-8, 0, -8))
	var distant := _near_sector(index, Vector3(10, 0, 10))
	var shape: CollisionShape3D = region.get_node("Wall/CollisionShape3D")
	shape.shape.size = Vector3(3, 2, 2)
	check(not index.template_valid(near.sector_key, near.source_revision, near.navigation_revision), "Actual shape resource edit immediately rejects affected known templates")
	_pump(index, 24)
	check(not index.template_valid(near.sector_key, near.source_revision, near.navigation_revision), "Shape size change rebuilds local source version")
	check(index.template_valid(distant.sector_key, distant.source_revision, distant.navigation_revision), "Distant unaffected sector survives local shape update")
	var source_count: int = index.statistics().sources
	var extra := _wall("AddedWithoutTag", Vector3(8, 0, 8))
	region.add_child(extra)
	_pump(index, 20)
	check(index.statistics().sources == source_count + 1, "Runtime collision node addition is detected without manual refresh")
	extra.position += Vector3(3, 0, 0)
	_pump(index, 20)
	var actual_geometry: Array[Dictionary] = index.query_geometry(extra.global_position, 1.0)
	check(actual_geometry.any(func(value: Dictionary): return value.transform.origin.is_equal_approx(extra.global_position)), "Ancestor transform change is found by bounded signature audit")
	var extra_shape: CollisionShape3D = extra.get_node("CollisionShape3D")
	extra_shape.disabled = true
	_pump(index, 20)
	check(index.query_geometry(extra.global_position, 1.0).is_empty(), "Disabled collision is removed from static geometry summaries")
	extra_shape.disabled = false
	extra_shape.shape = SphereShape3D.new()
	_pump(index, 20)
	check(index.query_geometry(extra.global_position, 1.0).any(func(value: Dictionary): return value.shape_type == "SphereShape3D"), "Actual shape replacement changes cached geometry")
	extra.free()
	_pump(index, 20)
	check(index.statistics().sources == source_count, "Freed nodes are removed without retaining old Node handles")
	var nav_old: int = index.navigation_revision()
	region.navigation_mesh.add_polygon(PackedInt32Array([0, 2, 1]))
	region.navigation_mesh.emit_changed()
	check(index.query_sectors(Vector3.ZERO, 30.0).is_empty(), "Changed navigation refuses old topology before rebuilding")
	_pump(index, 80)
	check(index.navigation_revision() > nav_old and index.ready(), "Navigation topology rebuild uses bounded preparation")
	# Geometry candidates on separate floors keep distinct y/layer sample IDs.
	var floor_ids: Dictionary = {}
	var floor_found := false
	for sector: Dictionary in index.query_sectors(Vector3.ZERO, 30.0, 1, 24):
		for sample_id: String in sector.sample_ids: floor_ids[sample_id] = true
		if sector.position.y > 2.5: floor_found = true
	check(floor_found and floor_ids.size() > 6, "Coincident horizontal islands at different heights retain distinct sample identities")
	# Release/rebind retains pure templates only; every source is re-read before use.
	index.release()
	arena.free()
	var reopened := _arena()
	root.add_child(reopened)
	await physics_frame
	await physics_frame
	var second := TacticalMap.new()
	second.bind_region(reopened.get_node("NavigationRegion3D"))
	check(second.query_sectors(Vector3.ZERO, 30.0).is_empty(), "Reopen never trusts cached geometry before current source validation")
	_pump(second, 80)
	check(second.statistics().reused > 0, "Same-map reopen reuses content-validated pure templates")
	var other := _arena()
	other.name = "OtherArena"
	other.position = Vector3(80, 0, 0)
	root.add_child(other)
	await physics_frame
	await physics_frame
	var third := TacticalMap.new()
	third.bind_region(other.get_node("NavigationRegion3D"))
	_pump(third, 80)
	check(third.statistics().reused == 0 and third.query_sectors(Vector3.ZERO, 20.0).is_empty(), "Different map transform cannot reuse another region's cached world geometry")
	print("TACTICAL MAP METRICS cold/steady=", before_queries, " final=", index.statistics(), " reopen=", second.statistics())
	second.release()
	third.release()
	reopened.free()
	other.free()
	print("TACTICAL MAP: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func _pump(index, count: int) -> void:
	for _step in count:
		frame += 1
		var result: Dictionary = index.advance_preparation(8, Time.get_ticks_usec() + 2000, frame)
		if result.points > 8:
			check(false, "Preparation exceeded original caller point allowance")
			return


func _near_sector(index, point: Vector3) -> Dictionary:
	var values: Array[Dictionary] = index.query_sectors(point, 8.0, 1, 1)
	return values[0] if not values.is_empty() else {}


func _arena() -> Node3D:
	var arena := Node3D.new()
	arena.name = "AnonymousArena"
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([
		Vector3(-12, 0, -12), Vector3(-4, 0, -12), Vector3(-4, 0, -4), Vector3(-12, 0, -4),
		Vector3(4, 0, 4), Vector3(12, 0, 4), Vector3(12, 0, 12), Vector3(4, 0, 12),
		Vector3(-12, 3, -12), Vector3(-4, 3, -12), Vector3(-4, 3, -4), Vector3(-12, 3, -4)])
	for polygon in [PackedInt32Array([0, 3, 2, 1]), PackedInt32Array([4, 7, 6, 5]), PackedInt32Array([8, 11, 10, 9])]: mesh.add_polygon(polygon)
	region.navigation_mesh = mesh
	arena.add_child(region)
	region.add_child(_wall("Wall", Vector3(-8, 0, -8)))
	return arena


func _wall(node_name: String, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	collision.shape = box
	body.add_child(collision)
	return body
