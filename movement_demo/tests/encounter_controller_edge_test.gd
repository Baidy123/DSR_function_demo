extends SceneTree

## Isolated compatibility checks for the retained reward-board controller.
const PlayerScene := preload("res://scenes/player/player.tscn")
const BoardScene := preload("res://scenes/ui/reward_board.tscn")
const ControllerScript := preload("res://scripts/systems/stage/encounter_controller.gd")
const RewardTableResource := preload("res://resources/rewards/level_rewards.tres")

const MAX_FRAMES := 60
const EXPECTED_CHECKS := 16

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _requires_completed_level()
	await _rejects_dead_player()
	await _rejects_missing_board()
	await _keeps_external_pause()
	await _claims_only_once()
	if checks != EXPECTED_CHECKS:
		failures += 1
		push_error("check count: expected %d, got %d" % [EXPECTED_CHECKS, checks])
	print("ENCOUNTER CONTROLLER EDGE: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _requires_completed_level() -> void:
	var context := await _prepare()
	_check(not context.controller.can_offer_reward(), "未完成关卡不能领取")
	_check(not context.controller.open_reward_for_player(context.player), "未完成关卡拒绝打开")
	_check(not context.board.visible and not paused, "拒绝时不显示也不暂停")
	await _release(context.scene)


func _rejects_dead_player() -> void:
	var context := await _prepare(1)
	context.health.receive_hit(context.health.max_health)
	_check(context.player.is_dead(), "真实伤害使玩家死亡")
	_check(not context.controller.open_reward_for_player(context.player), "死亡玩家不能领取奖励")
	_check(not context.board.visible, "死亡玩家不显示面板")
	await _release(context.scene)


func _rejects_missing_board() -> void:
	var context := await _prepare(1)
	context.controller.reward_board = null
	_check(not context.controller.open_reward_for_player(context.player), "缺少面板时拒绝打开")
	_check(not paused, "缺少面板时不暂停")
	await _release(context.scene)


func _keeps_external_pause() -> void:
	var context := await _prepare(1)
	context.health.receive_hit(50.0)
	var before: float = context.health.health
	paused = true
	_check(context.controller.open_reward_for_player(context.player), "外部暂停时仍可打开")
	_check(context.board.visible, "外部暂停时面板可见")
	_check(context.controller.select_reward(&"first_aid"), "外部暂停时选择成功")
	_check(context.health.health > before and paused, "奖励生效且不解除外部暂停")
	await _release(context.scene)


func _claims_only_once() -> void:
	var context := await _prepare(1)
	_check(context.controller.open_reward_for_player(context.player), "未领取时打开奖励")
	_check(context.controller.select_reward(&"system_progress"), "首次选择成功")
	_check(not context.controller.select_reward(&"ammo"), "打开状态不能重复提交")
	_check(not context.controller.open_reward_for_player(context.player), "已领取后不能再次打开")
	await _release(context.scene)


func _prepare(completed_level: int = 0) -> Dictionary:
	var scene := Node3D.new()
	var player: CharacterBody3D = PlayerScene.instantiate()
	player.set_physics_process(false)
	scene.add_child(player)
	var board: CanvasLayer = BoardScene.instantiate()
	scene.add_child(board)
	var controller: Node = ControllerScript.new()
	controller.reward_table = RewardTableResource
	controller.reward_board_path = NodePath("../RewardBoard")
	scene.add_child(controller)
	root.add_child(scene)
	current_scene = scene
	var state := root.get_node("GameState")
	state.completed_level = completed_level
	state.reset_reward_claims()
	state.money = 0
	await process_frame
	await process_frame
	return {
		"scene": scene,
		"player": player,
		"health": player.get_node("Health"),
		"board": board,
		"controller": controller,
	}


func _release(scene: Node) -> void:
	paused = false
	if is_instance_valid(scene):
		scene.queue_free()
	current_scene = null
	for _frame in range(3):
		await process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)
