extends SceneTree

var checks := 0
var failures := 0
var hits := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.health.debug_invincible = true
	# 保留场景实际武器、训练、掩体和正常评分；不强制选择方案或堵住敌人退路。
	actor.global_position = Vector3(24, 0, -2)
	actor.rotation = Vector3.ZERO
	player.global_position = Vector3(24, 0, -5)
	player.rotation.y = PI
	actor.melee_struck.connect(func(target, _settings, _direction):
		if target == player: hits += 1)
	for frame in 4: await physics_frame
	# 先进入正常交战并让空间候选准备就绪，避免初帧无退路候选导致偶然挥击。
	for frame in 60:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	var eligible_frames := 0
	var saw_push := false
	var saw_retreat_plan := false
	var windup_moved := false
	var shot_during_melee := false
	var recovery_distance := 0.0
	for frame in 360:
		await physics_frame
		var direction: Vector3 = (actor.global_position - player.global_position).normalized()
		Input.action_press("move_right", maxf(0.0, direction.x))
		Input.action_press("move_left", maxf(0.0, -direction.x))
		Input.action_press("move_down", maxf(0.0, direction.z))
		Input.action_press("move_up", maxf(0.0, -direction.z))
		player._physics_process(1.0 / 60.0)
		var phase: int = ai.context.melee.phase
		var before: Vector3 = actor.global_position
		var shots: int = actor.shot_count
		ai._physics_process(1.0 / 60.0)
		var moved: float = Vector2(actor.global_position.x - before.x, actor.global_position.z - before.z).length()
		if phase == ai.context.melee.Phase.WINDUP: windup_moved = windup_moved or moved > 0.001
		if phase == ai.context.melee.Phase.RECOVERY: recovery_distance += moved
		if phase != ai.context.melee.Phase.READY: shot_during_melee = shot_during_melee or actor.shot_count > shots
		if actor.melee_active and not ai.utility_current.get("destination", {}).is_empty(): saw_retreat_plan = true
		if ai.context.melee.can_request(ai.context.sees_player): eligible_frames += 1
		saw_push = saw_push or player._melee_push_remaining > 0.0
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	check(eligible_frames > 0 or actor.melee_count > 0, "实际玩家追近能进入合法近战范围")
	check(actor.melee_count > 0, "原场景配置下玩家持续贴近，Utility 自主选择并开始近战")
	check(hits > 0 and saw_push, "自主近战实际命中并推开玩家")
	check(saw_retreat_plan and recovery_distance > 0.05, "Utility 选中带退路的近战方案，实际出手后在收招期间退让")
	check(not windup_moved and not shot_during_melee, "前摇不主动移动，整个挥击期间不同时开枪")
	print("APPROACH eligible_frames=", eligible_frames, " strikes=", actor.melee_count, " hits=", hits, " recovery_distance=", recovery_distance)
	scene.queue_free()
	await process_frame
	await process_frame
	print("Enemy melee approach: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
