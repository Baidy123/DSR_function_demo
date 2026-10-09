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
	check(options.any(func(option): return option.get("mode") == &"covering_retreat"), "实际地图存在可评估的撤退候选")
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
	# 中心弹道明确被墙挡住，避免把仅外围散布擦墙的路线误当作完全不能开火。
	actor.global_position = Vector3(24, 0, -3)
	var blocked: Dictionary = ai.context.spatial.assess_route(ai.context, PackedVector3Array([Vector3(24, 0.3, -3.1)]), Vector3(22, 0, -3), 0.8, 0.0, true)
	check(is_zero_approx(blocked.fire_seconds), "真实墙体阻断中心弹道时整段路线不预支火力")
	actor.global_position = Vector3(24, 0, -2)
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
	await _retreat_execution_contract(ai)
	print("RETREAT FIRE CREDIT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

## Execution contract for a real legal candidate, not a claim that Utility must
## prefer retreat over every equally legal cover or engagement alternative.
func _retreat_execution_contract(ai) -> void:
	var actor = ai.actor
	var player = ai.player
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(actor)
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	ai.context.reset_memory()
	actor.global_position = Vector3(24, 0, -2)
	actor.velocity = Vector3.ZERO
	player.global_position = Vector3(22, 0, -2)
	actor.look_at(player.global_position)
	actor.cancel_reload()
	actor.ammo.magazine_rounds = actor.weapon.magazine_capacity
	for frame in 5: await physics_frame
	var real_visible: bool = ai.perception.can_see_player()
	check(real_visible, "合法候选执行契约：先取得真实目击")
	for frame in 90:
		await physics_frame
		ai.context.update_evidence(1.0 / 60.0, ai.perception.can_see_player())
		ai.context.spatial.advance_evaluation()
	var candidates: Array = ai.action_selector.assess_options(ai, ai.context.sees_player).filter(func(option): return option.get("mode") == &"covering_retreat" and option.get("route", {}).is_empty() and option.outcome.unavailable_seconds < ai.utility_horizon_seconds)
	candidates.sort_custom(func(a, b): return a.outcome.unavailable_seconds < b.outcome.unavailable_seconds)
	check(not candidates.is_empty(), "合法候选执行契约：原空间评估提供有射界的真实退让路线")
	if candidates.is_empty(): return
	var candidate: Dictionary = candidates[0]
	ai._start_utility_option(candidate, true)
	var action = ai.actions[&"covering_retreat"]
	check(ai.current_action == action and action.valid(true), "合法候选执行契约：通过原validate和begin提交退让")
	var start: Vector3 = actor.global_position
	var shots: int = actor.shot_count
	var saw_intent := false
	var saw_moving_shot := false
	var reaction_respected := true
	var moving_respected := true
	var saw_moving_gate := false
	var saw_pressure := false
	# The request must obey both gates. Restore the original movement permission
	# after reaction completes; no route, speed, score or aim is replaced.
	ai.training.profile.set_setting(&"tactics", &"fire_while_moving", false)
	for frame in 240:
		await physics_frame
		var visible: bool = ai.perception.can_see_player()
		ai.context.update_evidence(1.0 / 60.0, visible)
		if frame == 35: ai.training.profile.set_setting(&"tactics", &"fire_while_moving", true)
		var output: Dictionary = action.execute_tick(1.0 / 60.0, visible)
		actor.request_crouch(output.get("crouch", false))
		actor.face_direction(output.get("facing", Vector3.ZERO), 1.0 / 60.0)
		actor.move_character(output.get("direction", Vector3.ZERO), 1.0 / 60.0, output.get("multiplier", 1.0))
		var moving: bool = not actor.get_local_movement_velocity().is_zero_approx() or Vector2(actor.velocity.x, actor.velocity.z).length_squared() > 0.0025
		var intent: Dictionary = output.get("fire", {})
		var before: int = actor.shot_count
		var reacting: bool = ai.context.fire.fire_reaction_elapsed + 1.0 / 60.0 < ai.context.fire.fire_reaction_seconds
		if not intent.is_empty():
			saw_intent = saw_intent or (intent.get("pressure_reason") == &"retreat" and intent.get("support_intent", false) and not intent.get("bypass_steady", false))
			saw_pressure = saw_pressure or (visible and moving and ai.context.fire.suppression_pressure(intent, moving) > 0.0)
		ai.context.fire.update(1.0 / 60.0, visible, moving, intent)
		if reacting: reaction_respected = reaction_respected and actor.shot_count == before
		if moving and not ai.context.fire.fire_while_moving and not intent.is_empty():
			saw_moving_gate = true
			moving_respected = moving_respected and actor.shot_count == before
		if moving and actor.shot_count > before: saw_moving_shot = true
		if not output.get("running", true) or (saw_moving_shot and actor.global_position.distance_to(start) > 0.5): break
	ai.training.profile.set_setting(&"tactics", &"fire_while_moving", true)
	check(saw_intent and saw_pressure, "合法候选执行契约：移动退让输出真实压力意图且不绕过稳枪")
	check(reaction_respected and saw_moving_gate and moving_respected, "合法候选执行契约：退让压力仍遵守反应和禁止移动开火门控")
	check(saw_moving_shot and actor.shot_count > shots and actor.global_position.distance_to(start) > 0.5, "合法候选执行契约：经原body和fire管线实际边移动边开火")
	ai._cancel_utility_execution()
