extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const Coverage = preload("res://scripts/enemy/services/squad_map_coverage.gd")
const Search = preload("res://scripts/enemy/services/squad_search.gd")
const Visual = preload("res://scripts/enemy/services/enemy_visual_observation.gd")
const Map = preload("res://scripts/enemy/services/enemy_tactical_map.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func box(parent: Node, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.global_position = position
	return body

func _run() -> void:
	var scene := Fixture.single_member_scene()
	root.add_child(scene)
	current_scene = scene
	var actor = Fixture.primary_enemy(scene)
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	actor.set_physics_process(false)
	ai.set_physics_process(false)
	player.set_physics_process(false)
	for frame in 5: await physics_frame
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-6, 0, -6), Vector3(-6, 0, 6), Vector3(6, 0, 6), Vector3(6, 0, -6)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	scene.add_child(region)
	region.global_position = Vector3(100, 0, 100)
	box(region, Vector3(100, -0.2, 100), Vector3(14, 0.4, 14))
	actor.global_position = Vector3(100, 0, 100)
	actor.look_at(Vector3(103, 0, 100))
	player.global_position = Vector3(105, 0, 105)
	for frame in 5: await physics_frame
	var ctx = ai.context
	var old_region = ctx.navigation_region
	var old_map = ctx.tactical_map
	ctx.navigation_region = region
	ctx.tactical_map = Map.new()
	ctx.tactical_map.bind_region(region)
	check(not Visual.visible(ctx, Vector3(99, 0, 100)), "Nearby space behind the body is not visual coverage")
	check(Visual.visible(ctx, Vector3(103, 0, 100)), "Facing unobstructed hiding space is observable")
	var wall := box(region, Vector3(101.5, 1.0, 100), Vector3(0.2, 2.0, 4.0))
	for frame in 3: await physics_frame
	check(not Visual.visible(ctx, Vector3(103, 0, 100)), "Solid wall backs stay unknown")
	wall.get_node("CollisionShape3D").shape.size.y = 1.0
	wall.position.y = 0.5
	for frame in 3: await physics_frame
	check(not Visual.visible(ctx, Vector3(103, 0, 100)), "Seeing above a low wall does not clear crouched hiding space")
	wall.queue_free()
	for frame in 3: await physics_frame
	player.global_position = Vector3(101.5, 0, 100)
	for frame in 3: await physics_frame
	check(Visual.visible(ctx, Vector3(103, 0, 100)), "Hidden player's body is not an environmental observation probe")
	var ledger := Coverage.new()
	for frame in 90:
		ctx.tactical_map.advance_preparation(24, Time.get_ticks_usec() + 500, frame)
		ledger.advance(ctx, frame / 60.0, Time.get_ticks_usec() + 1000)
		await physics_frame
	check(ledger.ready() and ledger.snapshot(2.0).area > 100.0, "Area preparation covers the full region beyond a local clue radius")
	var before := ledger.snapshot(2.0)
	ledger.reserve({actor.get_instance_id(): {"coverage_key": ledger.cells.keys()[0]}})
	check(ledger.snapshot(2.0).observed_area == before.observed_area, "A responsibility reservation does not mark observed area")
	var total_area: float = before.area
	# Allow a fair bounded scan to revisit every nearby sample enough times;
	# elapsed time itself must never be credited as unchecked observation.
	for frame in 360:
		ledger.observe(ctx, {"task_id": 1}, 2.0 + frame / 60.0, 1.0 / 60.0, Time.get_ticks_usec() + 10000)
		await physics_frame
	var after := ledger.snapshot(8.0, true)
	check(after.observed_area > 0.0 and after.observed_area < total_area, "Actual orientation creates partial map coverage, not a full-map flag")
	check(after.display.any(func(cell): return cell.state == &"partial"), "A partly visible area cell cannot be counted as wholly inspected")
	var copy := after.duplicate(true)
	copy.display.clear()
	check(not ledger.snapshot(8.0, true).display.is_empty(), "Debug copies cannot mutate live area records")
	var frozen := ledger.cells.duplicate(true)
	ledger.observe(ctx, {"task_id": 1}, 4.0, 10.0, Time.get_ticks_usec() + 10000)
	check(frozen == ledger.cells, "Duplicate and old observation timestamps cannot accumulate time")
	var key: String = ledger.cells.keys()[0]
	ledger.reject(key, &"temporary_congestion", 8.0)
	check(ledger.snapshot(8.0).area == total_area and ledger.cells[key].failure == &"temporary_congestion", "Blocked travel preserves the coverage denominator and failure reason")
	var search := Search.new()
	search.coverage = ledger
	search.begin({"position": Vector3(102, 0, 100)}, {}, 8.0)
	check(search.snapshot(8.0).observed_area == after.observed_area, "New evidence does not erase accumulated map observations")
	search.center = Vector3(104, 0, 100)
	search._rebuild()
	check(search.snapshot(8.0).observed_area == after.observed_area, "A new uncertain hint changes priorities without clearing history")
	check(ledger.snapshot(45.0).recent_area < ledger.snapshot(8.0).recent_area and ledger.snapshot(45.0).observed_area == after.observed_area, "Aging requests reinspection while preserving historical evidence")
	ledger.release(actor.get_instance_id())
	check(ledger.cells.values().all(func(cell): return cell.samples.all(func(sample): return sample.watched_until <= 8.0)), "Released observers cannot remain current watchers")
	var before_geometry: float = ledger.snapshot(8.0).observed_area
	box(region, Vector3(102.2, 1.0, 100), Vector3(0.2, 2.0, 3.0))
	for frame in 180:
		await physics_frame
		ctx.tactical_map.advance_preparation(24, Time.get_ticks_usec() + 1000, Engine.get_physics_frames())
		ledger.advance(ctx, 8.0 + frame / 60.0, Time.get_ticks_usec() + 1000)
	var changed := ledger.snapshot(11.0)
	print("GEOMETRY OBSERVATION before=", before_geometry, " after=", changed.observed_area)
	check(changed.observed_area < before_geometry and changed.observed_area > 0.0, "A changed wall invalidates related visibility while preserving unaffected history")
	check(changed.area == total_area, "A new blocking wall does not quietly remove unverified area")
	ctx.tactical_map.release()
	ctx.tactical_map = old_map
	ctx.navigation_region = old_region
	scene.queue_free()
	await physics_frame
	print("SQUAD MAP OBSERVATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
