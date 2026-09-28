extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var ai = scene.get_node("Arena/Enemy/AI")
	var actor = ai.actor
	ai.set_physics_process(false)
	ai.player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(actor)
	ai.cover_selection.debug_cover_selection = false
	ai.player.global_position = Vector3(20, 0, 2.5)
	actor.global_position = Vector3(16.56584, 0, 4.678616)
	actor.look_at(ai.player.global_position)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.was_seeing_player = true
	# 在有真实避险需求的上下文评估撤退，避免缓存只留下健康时的远端候选。
	ai.recent_damage_pressure = 1.0
	ai.last_known_position = ai.player.global_position
	for frame in range(60):
		await physics_frame
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, true)
	var options: Array = ai.action_selector.assess_options(ai, true)
	var blocked_routes := 0
	for option: Dictionary in options:
		if option.get("mode") != &"covering_retreat": continue
		var route: PackedVector3Array = option.destination.path
		var no_fire := true
		var travelled := 0.0
		var previous: Vector3 = actor.global_position
		# 更密的独立路线探针：寻找整个评分窗口都没有射界的真实候选。
		for point: Vector3 in route:
			var length: float = ai.context._horizontal_distance_between(previous, point)
			var count: int = maxi(1, ceili(length / 0.1))
			for index in range(count):
				travelled += length / count
				if travelled > actor.move_speed * ai.actions[&"cover"].transfer.covering_retreat_speed_multiplier * ai.utility_horizon_seconds: break
				var sample: Vector3 = previous.lerp(point, float(index + 1) / count)
				sample.y = actor.global_position.y
				var origin := sample + Vector3.UP * 0.8
				var target: Vector3 = ai.last_known_position + Vector3.UP * 0.8
				if ai.context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)):
					no_fire = false
			previous = point
		if no_fire:
			blocked_routes += 1
			check(is_equal_approx(option.breakdown.unavailable_seconds, ai.utility_horizon_seconds), "整段无射界的撤退不能领取火力收益")
	check(blocked_routes > 0, "实际地图存在整段无射界的撤退候选")
	# 超长反应等待覆盖整个评分窗口，即使路线暴露也不能记为能开火。
	ai.training.profile.set_setting(&"tactics", &"fire_reaction_seconds", ai.utility_horizon_seconds + 1.0)
	ai.context.fire.fire_reaction_elapsed = 0.0
	options = ai.action_selector.assess_options(ai, true)
	var retreats: Array = options.filter(func(o): return o.get("mode") == &"covering_retreat")
	check(not retreats.is_empty(), "反应等待时仍可评估撤退路线")
	check(retreats.all(func(o): return is_equal_approx(o.breakdown.unavailable_seconds, ai.utility_horizon_seconds)), "射击准备未完成不预支火力")
	options = ai.action_selector.assess_options(ai, false)
	check(not options.any(func(o): return o.get("mode") == &"covering_retreat"), "本帧失视不使用上一帧可见状态生成跑打")
	# 正例防止简单地把全部撤退射击收益清零。
	actor.global_position = Vector3(24, 0, -2)
	ai.training.profile.set_setting(&"tactics", &"fire_reaction_seconds", 0.0)
	ai.context.fire.fire_pause_remaining = 0.0
	actor.shot_cooldown = 0.0
	var threat := Vector3(22, 0, -2)
	var route: Dictionary = ai.context.spatial.assess_route(ai.context, PackedVector3Array([Vector3(24.5, 0.3, -2)]), threat, 0.8, 0.0, true)
	check(route.fire_seconds > 0.0 and route.fire_seconds <= minf(route.seconds, ai.utility_horizon_seconds), "开阔路线保留真实火力收益且不超过实际时间")
	# 绕进遮挡后不提前假定还能找到玩家；同一条往返路线只计首次失视前火力。
	var wall = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(wall)
	wall.global_position = Vector3(23, 1.1, -3)
	var collision = wall.get_node("CollisionShape3D")
	collision.shape = collision.shape.duplicate()
	collision.shape.size = Vector3(0.2, 2.2, 0.6)
	for frame in range(3): await physics_frame
	var prefix := PackedVector3Array([Vector3(24, 0.3, -4)])
	var first: Dictionary = ai.context.spatial.assess_route(ai.context, prefix, threat, 0.8, 0.0, true)
	prefix.append(Vector3(24, 0.3, -2))
	var returning: Dictionary = ai.context.spatial.assess_route(ai.context, prefix, threat, 0.8, 0.0, true)
	check(first.fire_seconds > 0.0 and is_equal_approx(first.fire_seconds, returning.fire_seconds), "撤退失视后不预支绕回来的透视火力")
	wall.queue_free()
	for frame in range(3): await physics_frame
	ai.perception.sight_distance = 3.1
	ai.perception.close_awareness_radius = 0.0
	prefix = PackedVector3Array([Vector3(26, 0.3, -2)])
	first = ai.context.spatial.assess_route(ai.context, prefix, threat, 0.8, 0.0, true)
	prefix.append(Vector3(24, 0.3, -2))
	returning = ai.context.spatial.assess_route(ai.context, prefix, threat, 0.8, 0.0, true)
	check(first.fire_seconds > 0.0 and first.fire_seconds < first.seconds and is_equal_approx(first.fire_seconds, returning.fire_seconds), "超出视距后不按较长枪程继续计算火力")
	ai.perception.sight_distance = 10.0
	ai.last_known_position = ai.player.global_position
	for frame in range(30):
		await physics_frame
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, true)
	var job: Dictionary = ai.context.spatial.jobs.filter(func(item): return item.owner.get_ref().action_id == &"engage")[0]
	job.cursor = 25
	ai.last_known_position += Vector3.RIGHT * 0.3
	await physics_frame
	preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, true)
	check(job.cursor >= 25, "目标移动刷新候选后保留常规远点扫描进度")
	print("RETREAT FIRE CREDIT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
