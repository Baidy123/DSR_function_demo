extends SceneTree

## Task 3 fixed money: QuestDefinition defaults to 100, five main tasks pay once,
## paid side quests synchronize the active checkpoint, and Quest_task_music stays 0.
## Run: godot --headless --path movement_demo --script res://tests/quest_money_reward_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const QuestDefinitionScript := preload("res://scripts/systems/stage/quest_definition.gd")
const StageTableResource := preload("res://resources/stages/stage_table_template.tres")

const WATCHDOG_SECONDS := 30.0
const MAIN_TASK_IDS: Array[StringName] = [
	&"task_a",
	&"task_level_2",
	&"task_level_3",
	&"task_level_4",
	&"task_level_5",
]
const EXPECTED_CHECKS := 11

var failures := 0
var checks_run := 0
var _finished := false


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label_text: String) -> void:
	checks_run += 1
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func _run() -> void:
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var state := root.get_node("GameState")
	state.money = 0
	state.rewarded_task_ids = {}
	state.help_choice = "accepted"
	state.completed_level = 1
	await process_frame
	await process_frame

	check(state.money == 100, "task completion pays 100")

	state.completed_level = 0
	state.completed_level = 1
	await process_frame
	await process_frame
	check(state.money == 100, "task reward does not repeat")

	var default_definition = QuestDefinitionScript.new()
	check(default_definition.get("money_reward") == 100, "QuestDefinition.money_reward defaults to 100")

	for task_id in MAIN_TASK_IDS:
		var definition = StageTableResource.quest_by_id(task_id)
		check(definition != null and definition.get("money_reward") == 100,
			"%s exposes money_reward 100" % task_id)

	var music_definition = StageTableResource.quest_by_id(&"task_music")
	check(music_definition != null and music_definition.get("money_reward") == 0,
		"Quest_task_music keeps money_reward 0")

	state.money = 0
	state.rewarded_task_ids = {}
	state.campaign_checkpoint = {}
	state.completed_level = 2
	state.record_campaign_checkpoint(2, {})
	scene.get_node("QuestController").complete(&"task_level_4")
	check(state.money == 100, "paid side quest uses the active campaign level")
	check(
		int(state.campaign_checkpoint.get("money", 0)) == 100
		and bool(state.campaign_checkpoint.get("rewarded_task_ids", {}).get(&"task_level_4", false)),
		"paid side quest synchronizes the active checkpoint"
	)

	_finish(scene)


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	push_error("quest money reward test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node) -> void:
	if _finished:
		return
	_finished = true
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("check count: expected %d, got %d" % [EXPECTED_CHECKS, checks_run])
	if is_instance_valid(scene):
		scene.queue_free()
	if failures == 0:
		print("quest money reward checks: all passed")
	else:
		print("quest money reward checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
