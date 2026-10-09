extends SceneTree

const Geometry = preload("res://scripts/enemy/services/enemy_cover_inspection_geometry.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0
var scene
var arena
var player
var cover
var actors: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	if OS.get_cmdline_user_args().has("--mixed-only"):
		await _mixed_eligibility_case(false)
		await _mixed_eligibility_case(true)
		print("COVER INSPECTION MIXED: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	await _visual_loss_case(false)
	await _visual_loss_case(true)
	await _exact_clue_case()
	await _mixed_eligibility_case(false)
	await _mixed_eligibility_case(true)
	print("COVER INSPECTION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _visual_loss_case(full_training: bool) -> void:
	seed(20261010)
	await _setup(full_training)
	print("COVER INSPECTION FULL TRAINING ", full_training)
	for frame in 4: await _tick()
	check(actors.all(func(actor): return actor.get_node("AI").context.sees_player), "两名敌人通过真实感知看见站立玩家")
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 3: await _tick()
	var contexts: Array = [actors[0].get_node("AI").context, actors[1].get_node("AI").context]
	var evidence: Dictionary = contexts[0].cover_inspection_evidence()
	check(player.is_crouching() and contexts.all(func(context): return not context.sees_player), "真实蹲进低墙后失视，没有手工指定感知结果")
	check(not evidence.is_empty() and evidence.get("cover") is WeakRef and evidence.cover.get_ref() == cover, "真实失视保存合法掩体归属与冻结调查线索")
	if evidence.is_empty():
		scene.queue_free()
		await physics_frame
		return
	var known: Vector3 = evidence.position
	var frozen_id: int = evidence.id
	var frozen_geometry: Dictionary = Geometry.describe(contexts[0], evidence)
	# The player silently leaves under a separate opaque screen. Both inspectors
	# must still check the original empty cover, never follow the hidden body.
	player.global_position = arena.to_global(Vector3(6, 0, -4))
	var entries := [false, false]
	var inspected := [false, false]
	var assigned := [0, 0]
	var starts: Array[Vector3] = [actors[0].global_position, actors[1].global_position]
	var distance := [0.0, 0.0]
	var immutable := true
	var safe := true
	var shots: int = actors[0].shot_count + actors[1].shot_count
	var previous_shots := [actors[0].shot_count, actors[1].shot_count]
	var inspection_never_fires := true
	var fire_trace: Array = []
	var phases: Array = []
	for frame in 840:
		await _tick()
		for index in 2:
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var search = ai.actions[&"search"]
			distance[index] = maxf(distance[index], actor.global_position.distance_to(starts[index]))
			var token: Dictionary = search._inspection_claim
			var fire: Dictionary = ai.context.fire.request
			if search._inspection_phase != search.InspectionPhase.NONE:
				inspection_never_fires = inspection_never_fires and fire.is_empty() and actor.shot_count == previous_shots[index]
			if actor.shot_count > previous_shots[index]:
				var basis: Dictionary = ai.context.suppression_basis()
				var aim: Vector3 = fire.get("point", Vector3.INF)
				var legal: bool = fire.get("owner", &"") == &"suppression" and fire.get("mode", &"") == &"memory" and aim.is_finite() and basis.get("source", &"") == &"visual_loss" and float(basis.get("valid_until", -INF)) > ai.context.evidence_elapsed_seconds
				legal = legal and basis.get("position", Vector3.INF).is_equal_approx(known) and aim.distance_to(basis.get("aim_position", Vector3.INF)) <= ai.actions[&"suppression"].target_radius + 0.001
				if aim.is_finite():
					var origin: Vector3 = actor.get_shot_origin()
					legal = legal and ai.context.fire.has_clear_suppression_lane(origin, aim - origin, origin.distance_to(aim)) and ai.context.fire.has_clear_suppression_lane(origin, actor.aim_direction, origin.distance_to(aim)) and ai.context.cooperation_line_safe(origin, aim)
					for endpoint: Dictionary in frozen_geometry.get("ends", {}).values():
						legal = legal and ai.context._horizontal_distance_between(aim, endpoint.entry) > 0.1 and ai.context._horizontal_distance_between(aim, endpoint.peek) > 0.1
				fire_trace.append({"frame": frame, "actor": index, "request": fire, "evidence": basis, "legal": legal})
				inspection_never_fires = inspection_never_fires and legal
			previous_shots[index] = actor.shot_count
			if not token.is_empty():
				assigned[index] = int(token.end)
				entries[index] = entries[index] or actor.global_position.distance_to(token.entry) <= 0.3
				inspected[index] = inspected[index] or (actor.global_position.distance_to(token.peek) <= 0.3 and ai.context.perception.can_observe_position(known))
			var current: Dictionary = ai.context.cover_inspection_evidence()
			immutable = immutable and (current.is_empty() or (int(current.id) == frozen_id and current.position.is_equal_approx(known)))
			var state := [ai.utility_current.get("id", &""), search._inspection_phase]
			if frame % 60 == 0: phases.append({"frame": frame, "actor": index, "state": state, "position": actor.global_position, "end": assigned[index]})
		var offset: Vector3 = actors[0].global_position - actors[1].global_position
		safe = safe and Vector2(offset.x, offset.z).length() >= 0.69
		if inspected.all(func(value): return value): break
	check(assigned[0] in [-1, 1] and assigned[1] == -assigned[0], "普通Utility自主认领同掩体的两个不同端槽")
	check(entries.all(func(value): return value) and distance[0] > 0.5 and distance[1] > 0.5, "两名敌人实际沿各自端口入位，不仅声明不同终点")
	check(inspected.all(func(value): return value), "两端均实际绕到观察位置并以各自视线核实冻结地面")
	check(immutable, "玩家无新线索地离开后不读取隐藏坐标或刷新冻结调查轮")
	check(inspection_never_fires and (full_training or actors[0].shot_count + actors[1].shot_count == shots), "隐藏双端调查不发射击意图；完整装配的独立合法记忆压制仍可执行")
	check(safe, "双端全过程保留身体碰撞及队友间距")
	print("COVER INSPECTION TRACE ", JSON.stringify(phases))
	print("COVER INSPECTION OTHER FIRE ", JSON.stringify(fire_trace))
	await _protocol(contexts, evidence)
	scene.queue_free()
	await physics_frame

func _setup(full_training: bool = false) -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	arena = scene.get_node("Arena")
	for child in arena.get_children():
		if child != arena.get_node("Enemy") and child.has_method("move_character"): child.free()
	var navigation: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	for body in navigation.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor":
			body.collision_layer = 0
			body.remove_from_group("cover_region")
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var xs := [-8.0, -1.95, 1.95, 8.0]
	var zs := [-8.0, -0.75, 0.75, 8.0]
	for z in zs:
		for x in xs: vertices.append(Vector3(x, 0.3, z))
	mesh.vertices = vertices
	for z in 3:
		for x in 3:
			if x == 1 and z == 1: continue
			var index: int = z * 4 + x
			mesh.add_polygon(PackedInt32Array([index, index + 1, index + 5, index + 4]))
	navigation.navigation_mesh = mesh
	cover = _box(Vector3(0, 0.6, 0), Vector3(3, 1.2, 0.6), true)
	navigation.add_child(cover)
	var screen = _box(Vector3(5.2, 1.5, 0), Vector3(0.2, 3, 16), false)
	navigation.add_child(screen)
	var first = arena.get_node("Enemy")
	first.position = Vector3(-0.65, 0, 2.4)
	var second = load("res://scenes/enemy/enemy.tscn").instantiate()
	second.position = Vector3(0.65, 0, 2.4)
	arena.add_child(second)
	actors = [first, second]
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3(0, 0, -0.8))
	for actor in actors:
		var ai = actor.get_node("AI")
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
		actor.equip_weapon(WeaponData.new())
		ai.training.profile = ai.training.profile.duplicate(true)
		if not full_training: ai.training.profile.selected_tactics.assign([&"cooperate"])
		ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
		ai.refresh_configuration(true)
		ai.set_physics_process(false)
		actor.look_at(player.global_position)
	for frame in 12: await physics_frame

func _box(position: Vector3, size: Vector3, low: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	if low:
		body.set_script(preload("res://scripts/world/cover_region.gd"))
		body.low_cover = true
		body.vault_enabled = false
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	return body

func _tick() -> void:
	await physics_frame
	for actor in actors: actor.get_node("AI")._physics_process(STEP)

func _protocol(contexts: Array, evidence: Dictionary) -> void:
	var active_token: Dictionary = actors[0].get_node("AI").actions[&"search"]._inspection_claim
	if not active_token.is_empty():
		var collision: CollisionShape3D = cover.get_node("CollisionShape3D")
		var original_shape: Shape3D = collision.shape
		collision.shape = SphereShape3D.new()
		check(not arena.cooperation._claim_valid(active_token) and not Geometry.valid(contexts[0], active_token.geometry), "动态替换非Box形状使调查合同失效且不报错")
		collision.shape = null
		check(not arena.cooperation._claim_valid(active_token), "动态清空碰撞形状安全释放调查资格")
		collision.shape = original_shape
		var layer: int = cover.collision_layer
		cover.collision_layer = 0
		check(not arena.cooperation._claim_valid(active_token) and not Geometry.valid(contexts[0], active_token.geometry), "关闭掩体碰撞层不能保留旧端口合同")
		cover.collision_layer = layer
		collision.disabled = true
		check(not arena.cooperation._claim_valid(active_token), "禁用碰撞子节点不能保留旧端口合同")
		collision.disabled = false
		cover.remove_child(collision)
		var replacement := Node3D.new()
		replacement.name = "CollisionShape3D"
		cover.add_child(replacement)
		var search = actors[0].get_node("AI").actions[&"search"]
		search.reset()
		check(not arena.cooperation._claim_valid(active_token) and search._inspection_candidate().is_empty(), "替换同名碰撞子节点时预览和原合同均安全失效")
		replacement.free()
		cover.add_child(collision)
	for actor in actors: actor.get_node("AI").reset_actions()
	var context = contexts[0]
	var board = arena.cooperation
	var before: int = board.revision
	var report: Dictionary = context.cover_inspection_evidence()
	if report.is_empty(): report = evidence
	var geometry: Dictionary = Geometry.describe(context, report)
	for count in 5:
		context.actor.get_node("AI").actions[&"search"].collect_candidates(false)
	check(before == board.revision, "重复候选评估不认领、不刷新轮次或证据期限")
	var saved: StringName = actors[1].communication_group
	actors[1].communication_group = &"unrelated_inspection"
	check(board.inspection_evidence(contexts[1], contexts[1].cooperation_target_id()).is_empty(), "不同通信组不能拿到调查线索")
	actors[1].communication_group = saved
	if not geometry.is_empty():
		var blocker = _box(arena.to_local(geometry.ends[1].entry).lerp(arena.to_local(geometry.ends[1].peek), 0.5) + Vector3.UP, Vector3(1.0, 2.0, 2.0), false)
		arena.add_child(blocker)
		await physics_frame
		check(Geometry.describe(context, report).is_empty(), "真实封死其中一端时不伪造两端均可通行")
		blocker.queue_free()
		await physics_frame
	var deadline: float = float(report.get("valid_until", context.evidence_elapsed_seconds))
	board.advance(maxf(0.0, deadline - context.evidence_elapsed_seconds) + 0.1)
	check(board.inspection_evidence(context, context.cooperation_target_id()).is_empty(), "调查证据到期后不能续约原双端轮次")

func _exact_clue_case() -> void:
	await _setup(true)
	actors[0].global_position = arena.to_global(Vector3(-0.45, 0, 1.0))
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	for frame in 3: await _tick()
	var contexts: Array = [actors[0].get_node("AI").context, actors[1].get_node("AI").context]
	var evidence: Dictionary = contexts[0].cover_inspection_evidence()
	check(contexts.all(func(context): return not context.sees_player and not context.has_visual_memory), "近距掩体线索场景没有个人真实目击历史")
	check(not evidence.is_empty() and evidence.get("source", &"") == &"close_cover_exact", "真实近距确认掩体后产生合法独立调查线索")
	check(contexts[1].is_alerted and not contexts[1].cover_inspection_evidence().is_empty(), "没有视觉报告时同组队友也接收调查线索并响应")
	if not evidence.is_empty():
		var known: Vector3 = evidence.position
		player.global_position = arena.to_global(Vector3(6, 0, -4))
		var assigned := [0, 0]
		var observed := [false, false]
		var shots: int = actors[0].shot_count + actors[1].shot_count
		for frame in 840:
			await _tick()
			for index in 2:
				var ai = actors[index].get_node("AI")
				var token: Dictionary = ai.actions[&"search"]._inspection_claim
				if not token.is_empty():
					assigned[index] = int(token.end)
					observed[index] = observed[index] or (actors[index].global_position.distance_to(token.peek) <= 0.3 and ai.context.perception.can_observe_position(known))
			if observed.all(func(value): return value): break
		check(assigned[0] in [-1, 1] and assigned[1] == -assigned[0] and observed.all(func(value): return value), "完整战术装配在无目击历史的合法掩体线索下也从双端实际核实")
		check(actors[0].shot_count + actors[1].shot_count == shots, "共享精确调查线索不会授权隔墙射击")
	scene.queue_free()
	await physics_frame

func _mixed_eligibility_case(immobile: bool) -> void:
	seed(20261010)
	await _setup(false)
	var first_ai = actors[0].get_node("AI")
	var other_ai = actors[1].get_node("AI")
	var label := "不可移动队友" if immobile else "高级OFF队友"
	if not immobile:
		other_ai.training.profile.selected_tactics.clear()
		other_ai.refresh_configuration(true)
		other_ai.set_physics_process(false)
	for frame in 4: await _tick()
	player.request_crouch(true)
	for frame in 30:
		await physics_frame
		player._update_posture(STEP)
	if immobile:
		# Start the body restriction before visual loss can assign either end.
		# Hold a genuine windup, publishing measured facts while this AI rests.
		check(actors[1].begin_melee(0.5) and not actors[1].can_move(), label + "进入真实近战禁移状态")
	for frame in 3:
		await physics_frame
		if immobile:
			other_ai.context.update_evidence(STEP, other_ai.perception.can_see_player())
			other_ai.context.cooperation_publish_execution({})
		first_ai._physics_process(STEP)
		if not immobile: other_ai._physics_process(STEP)
	var context = first_ai.context
	var clue: Dictionary = context.cover_inspection_evidence()
	if not immobile:
		check(context.cooperation_enabled() and not other_ai.context.cooperation_enabled(), label + "保持同组但没有高级训练授权")
	check(not clue.is_empty() and not Geometry.describe(context, clue).is_empty(), label + "反例仍有合法失视线索及真实可通行双端")
	check(first_ai.actions[&"search"]._inspection_candidate().is_empty(), label + "不被误计为第二调查员或产生空等候选")
	player.global_position = arena.to_global(Vector3(6, 0, -4))
	var start: Vector3 = actors[0].global_position
	var maximum := 0.0
	var no_false_wait := true
	var trace: Array = []
	for frame in 240:
		await physics_frame
		if immobile:
			other_ai.context.update_evidence(STEP, other_ai.perception.can_see_player())
			other_ai.context.cooperation_publish_execution({})
		first_ai._physics_process(STEP)
		if not immobile: other_ai._physics_process(STEP)
		maximum = maxf(maximum, actors[0].global_position.distance_to(start))
		no_false_wait = no_false_wait and first_ai.utility_current.get("plan", &"") not in [&"inspect_wait", &"inspect_end"]
		if frame % 60 == 0: trace.append({"frame": frame, "position": actors[0].global_position, "action": first_ai.utility_current.get("id", &""), "plan": first_ai.utility_current.get("plan", &""), "partner_can_move": actors[1].can_move()})
	print("COVER INSPECTION MIXED TRACE ", label, " maximum=", maximum, " no_false_wait=", no_false_wait, " ", JSON.stringify(trace))
	check(no_false_wait and maximum > 0.5, label + "下唯一可执行者正常自主移动调查而非等待不存在的搭档")
	if immobile: actors[1].cancel_melee()
	scene.queue_free()
	await physics_frame
