extends SceneTree

var checks := 0
var failed := 0

class Recorder extends Node:
	var events: Array[Dictionary] = []
	func receive_noise(source: Node3D, _position: Vector3, radius: float, _multiplier: float) -> void:
		events.append({"source": source, "radius": radius})

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	var enemy = scene.get_node("Arena/Enemy")
	player.set_physics_process(false)
	enemy.get_node("AI").set_physics_process(false)
	check(player.get("sprint_noise_radius") != null and enemy.get("fast_movement_noise_radius") != null, "玩家敌人分别导出快速移动声音半径")
	if failed > 0:
		finish()
		return
	var recorder := Recorder.new()
	root.add_child(recorder)
	recorder.add_to_group("hearing_listener")
	player.movement_noise_radius = 3.0
	player.sprint_noise_radius = 6.0
	enemy.movement_noise_radius = 3.0
	enemy.fast_movement_noise_radius = 6.0
	for frame in range(5):
		await physics_frame
	player.rotation = Vector3.ZERO
	Input.action_press("move_up")
	player._movement_noise_timer = 0.0
	player._physics_process(0.1)
	await process_frame
	check(recorder.events.size() == 1 and recorder.events[0].radius == 3.0, "玩家真实走路发出3米声音")
	recorder.events.clear()
	Input.action_press("sprint")
	player._movement_noise_timer = 0.0
	player._physics_process(0.1)
	await process_frame
	check(player.is_sprinting and recorder.events.size() == 1 and recorder.events[0].radius == 6.0, "玩家当帧奔跑发出6米声音")
	recorder.events.clear()
	Input.action_release("sprint")
	player._movement_noise_timer = 0.0
	player._physics_process(0.1)
	await process_frame
	check(recorder.events.size() == 1 and recorder.events[0].radius == 3.0, "退出奔跑恢复普通声音")
	Input.action_release("move_up")
	recorder.events.clear()
	player.is_sprinting = true
	player._update_movement_noise(1.0, player.global_position)
	await process_frame
	check(recorder.events.is_empty(), "没有实际位移即使奔跑标志为真也不发声")
	for multiplier in [1.0, 2.0, 0.5]:
		recorder.events.clear()
		enemy._movement_noise_timer = 0.0
		enemy.move_character(Vector3.RIGHT, 1.0 / 60.0, multiplier)
		await process_frame
		var expected: float = 6.0 if multiplier > 1.0 else 3.0
		check(recorder.events.size() == 1 and recorder.events[0].source == enemy and recorder.events[0].radius == expected, "敌人移动倍率%s选择半径%s" % [multiplier, expected])
	recorder.events.clear()
	enemy.move_character(Vector3.ZERO, 0.5, 2.0)
	await process_frame
	check(recorder.events.is_empty(), "敌人快速指令但无位移时不发声")
	enemy.fast_movement_noise_radius = 9.0
	enemy._movement_noise_timer = 0.0
	enemy.move_character(Vector3.RIGHT, 1.0 / 60.0, 2.0)
	await process_frame
	check(recorder.events.size() == 1 and recorder.events[0].radius == 9.0, "敌人快速半径可独立调整")
	recorder.events.clear()
	enemy.move_character(Vector3.RIGHT, 1.0 / 60.0, 2.0)
	await process_frame
	check(recorder.events.is_empty(), "快慢声音仍遵守原发声间隔")
	check(player.movement_noise.occluded_range_multiplier == enemy.movement_noise.occluded_range_multiplier, "继续复用原隔墙衰减资源")
	finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("MOVEMENT NOISE MODES: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)
