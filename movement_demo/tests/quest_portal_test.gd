extends SceneTree

## 酒馆任务传送门：替换旧门禁，并在 task_a 接取后进入第一关。
const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")
const LEVEL_ONE := "res://scenes/world/levels/lvl_1.tscn"

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn", "工程默认启动酒馆")
	var scene: Node3D = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	for _frame in range(4):
		await physics_frame

	var player: CharacterBody3D = scene.get_node("Player")
	var quests = scene.get_node("QuestController")
	var state = root.get_node("GameState")
	var portal = scene.get_node_or_null("Interactables/LevelPortal")
	var old_keycard = scene.get_node_or_null("Interactables/Keycard")
	var old_gate = scene.get_node_or_null("Interactables/AccessGate")
	player.set_physics_process(false)
	state.help_choice = ""
	state.clear_interaction_state()
	quests.reset_progress()
	await process_frame
	await process_frame

	_check(old_keycard == null, "酒馆不再包含门禁卡")
	_check(old_gate == null, "酒馆不再包含旧门禁屏障")
	_check(portal != null, "酒馆门口存在任务传送门")
	if portal == null:
		await _finish(scene)
		return

	player.global_position = portal.global_position + Vector3(0.0, 0.0, -0.9)
	for _frame in range(4):
		await physics_frame
	_check(not portal.can_interact(player), "未接任务时传送门拒绝进入")
	_check(portal.prompt.text == "需要先接取 A 的任务", "未接任务时显示任务阻断提示")

	state.help_choice = "accepted"
	await _wait_for_status(quests, QuestControllerScript.Status.IN_PROGRESS)
	await process_frame
	_check(portal.prompt.text == "E 进入 关卡1", "接取任务后传送门显示进入提示")
	_check(portal.interact(player), "接取任务后可以进入传送门")
	var loaded: Node = await _wait_for_scene(LEVEL_ONE)
	_check(loaded != null and loaded.scene_file_path == LEVEL_ONE, "传送门加载第一关场景")
	var world: World3D = loaded.get_world_3d() if loaded != null else null
	var fallback: Environment = world.fallback_environment if world != null else null
	_check(
		fallback != null
		and fallback.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED
		and fallback.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED,
		"传送后恢复中性默认渲染环境"
	)
	await _finish(loaded)


func _wait_for_status(quests: Node, status: int) -> void:
	for _frame in range(30):
		if quests.status_of(&"task_a") == status:
			return
		await process_frame


func _wait_for_scene(path: String) -> Node:
	for _frame in range(60):
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			return current_scene
		await process_frame
	return null


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)


func _finish(scene: Node) -> void:
	paused = false
	if is_instance_valid(scene):
		scene.queue_free()
	current_scene = null
	for _frame in range(4):
		await process_frame
	print("QUEST PORTAL: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
