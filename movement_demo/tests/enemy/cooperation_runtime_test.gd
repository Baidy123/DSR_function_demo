extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for count in [1, 2, 3, 6]:
		await _measure(count)
	quit(1 if failures else 0)

func _measure(count: int) -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var arena = scene.get_node("Arena")
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	var actors: Array = [arena.get_node("Enemy")]
	for index in range(1, count):
		var actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres")
		actor.weapon = load("res://resources/weapons/test_pistol.tres")
		arena.add_child(actor)
		actors.append(actor)
	player.global_position = Vector3(20, 0, 0)
	for index in actors.size():
		var actor = actors[index]
		var ai = actor.get_node("AI")
		ai.set_physics_process(false)
		Fixture.configure_timing(actor)
		ai.training.profile.selected_tactics.assign([&"cover", &"attack_position", &"suppression", &"cooperate"])
		ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.refresh_configuration(true)
		ai.cover_selection.debug_cover_selection = false
		ai.cover_selection.debug_attack_points = false
		actor.debug_shooting = false
		actor.global_position = Vector3(25, 0, (index - (actors.size() - 1) * 0.5) * 0.9)
		actor.look_at(player.global_position)
	var barrier := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 3, 12)
	collision.shape = shape
	barrier.add_child(collision)
	scene.add_child(barrier)
	barrier.global_position = Vector3(22.5, 40, 0)
	for frame in 8: await physics_frame
	var samples: Array[int] = []
	var individual: Array[int] = []
	var boards: Array[int] = []
	var actions := {}
	var moves := 0.0
	var loss_moves := 0.0
	var accumulated_move := 0.0
	var shots := 0
	var saw_loss := false
	var saw_investigation := false
	var first_positions: Array[Vector3] = []
	var previous_positions: Array[Vector3] = []
	var loss_positions: Array[Vector3] = []
	var seen: Array[bool] = []
	var hidden_actions := {}
	for actor in actors:
		first_positions.append(actor.global_position)
		previous_positions.append(actor.global_position)
		loss_positions.append(Vector3.INF)
		seen.append(false)
	# 七秒开放交战允许真实火控建立掩护；其后十一秒涵盖原证据和有限压制寿命。
	# 不能在失视仅两秒时把合法压制误判为没有调查。
	for frame in 1080:
		await physics_frame
		if frame == 240: player.global_position = Vector3(20, 0, 1)
		if frame == 420: barrier.global_position.y = 1.5
		var start := Time.get_ticks_usec()
		var board_start := Time.get_ticks_usec()
		arena.cooperation.advance(0.0)
		for actor in actors:
			var context = actor.get_node("AI").context
			arena.cooperation.evidence(context, context.cooperation_target_id())
			arena.cooperation.snapshot(context, context.cooperation_target_id())
		boards.append(Time.get_ticks_usec() - board_start)
		for index in actors.size():
			var actor = actors[index]
			var before := Time.get_ticks_usec()
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			individual.append(Time.get_ticks_usec() - before)
			actions[ai.utility_current.get("id", &"idle")] = true
			seen[index] = seen[index] or ai.context.sees_player
			if frame >= 420 and seen[index] and not ai.context.sees_player:
				saw_loss = true
				if not loss_positions[index].is_finite(): loss_positions[index] = actor.global_position
				hidden_actions[ai.utility_current.get("id", &"idle")] = true
				saw_investigation = saw_investigation or ai.utility_current.get("id") == &"search"
			if loss_positions[index].is_finite(): loss_moves = maxf(loss_moves, actor.global_position.distance_to(loss_positions[index]))
			moves = maxf(moves, actor.global_position.distance_to(first_positions[index]))
			accumulated_move += actor.global_position.distance_to(previous_positions[index])
			previous_positions[index] = actor.global_position
		samples.append(Time.get_ticks_usec() - start)
	for index in actors.size():
		shots += actors[index].shot_count
	samples.sort()
	individual.sort()
	boards.sort()
	var p99: int = samples[floori(samples.size() * 0.99)]
	var single_p99: int = individual[floori(individual.size() * 0.99)]
	check(shots > 0, "%d enemies actually fire through normal perception and weapon execution" % count)
	check(saw_loss and saw_investigation and loss_moves > 0.2, "%d enemies investigate and actually move after genuine loss and finite suppression" % count)
	check(single_p99 < 16000 and individual[-1] < 50000, "%d enemies preserve the existing per-enemy 16ms P99 / 50ms maximum budget" % count)
	if count == 3: check(actions.has(&"cooperate"), "three-enemy scenario selects cooperation through normal Utility")
	print("COOP_RUNTIME count=%d total_P99=%.3fms total_max=%.3fms individual_P99=%.3fms individual_max=%.3fms board_P99=%.3fms shots=%d max_move=%.3f loss_move=%.3f total_move=%.3f actions=%s hidden_actions=%s" % [count, p99 / 1000.0, samples[-1] / 1000.0, single_p99 / 1000.0, individual[-1] / 1000.0, boards[floori(boards.size() * 0.99)] / 1000.0, shots, moves, loss_moves, accumulated_move, actions.keys(), hidden_actions.keys()])
	scene.queue_free()
	await process_frame
	await physics_frame

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
