extends "res://tests/enemy/enemy_search_formation_test.gd"

var snapshot_checked := false
var render_captured := false

func _run() -> void:
	await _formation_case(3)
	check(snapshot_checked, "Read-only debug checked during a real complete squad plan")
	var view = root.get_node("DebugSettings/CoordinatorPaths")
	view._process(0.1)
	check(view.snapshots.is_empty(), "Scene removal clears old route markers and member labels")
	root.get_node("DebugSettings").set_enabled(false)
	print("COORDINATION DEBUG: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _tick() -> void:
	await super._tick()
	if snapshot_checked: return
	var context = actors[0].get_node("AI").context
	var order: Dictionary = context.inspection_order()
	if not order.has("approach") or context.coordination_assignment().is_empty(): return
	var coordinator = context._coordinator()
	var before: Dictionary = coordinator._inspection_orders.duplicate(true)
	var plan_before: Dictionary = coordinator._coordination_plans.duplicate(true)
	var revision: int = arena.cooperation.revision
	var queries: int = context.cover_selection.environment_ray_queries
	var free_queries: int = context.position_free_queries
	var target: Vector3 = context.agent.target_position
	var value: Dictionary = context.coordination_debug_snapshot()
	check(value.get("source") == &"inspection" and value.get("route", PackedVector3Array()).size() > 1, "Debug receives the actual coordinator route, not a fabricated target line")
	check(value.staging_position == order.entry and value.target_position == order.peek, "Debug identifies the assigned staging and inspection positions")
	value.route[0] += Vector3.ONE * 100.0
	value.waiting_for.append(-123)
	for query in 10: context.coordination_debug_snapshot()
	var view = root.get_node("DebugSettings/CoordinatorPaths")
	view._process(1.0)
	check(view.snapshots.size() == 3 and view.snapshots.all(func(item): return item.source == &"inspection"), "All three members have separate real plan snapshots")
	var refreshes: int = view.refresh_count
	view._process(0.001)
	check(view.refresh_count == refreshes, "Path refresh is bounded instead of rescanning every render frame")
	check(before == coordinator._inspection_orders and plan_before == coordinator._coordination_plans and revision == arena.cooperation.revision, "Reading or mutating debug copies cannot change orders, plans or deadlines")
	check(queries == context.cover_selection.environment_ray_queries and free_queries == context.position_free_queries and target == context.agent.target_position, "Debug performs no cover/body queries and cannot move the navigation target")
	snapshot_checked = true
	if OS.get_cmdline_user_args().has("--capture-debug"):
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("res://logs/coordinator_paths_preview.png")
		render_captured = true
