extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func _run() -> void:
	var state := root.get_node("GameState")
	state.reset_game_progress()
	state.completed_level = 2
	state.available_level = 3
	state.money = 275
	state.help_choice = "accepted"
	state.music_quest_choice = "accepted"
	state.talked_to_a = true
	state.task_a_returned = "returned"
	state.claimed_reward_levels = {1: true}
	state.rewarded_task_ids = {&"task_a": true}
	state.purchased_shop_item_ids = {&"medkit_pack": true}
	state.items = {&"coin": {"display_name": "硬币", "count": 3}}
	state.flags = {&"music_playing": true, &"shop_mind_access": true}
	state._shop_flag_keys = {&"shop_mind_access": true}
	state.campaign_checkpoint = {"completed_level": 2, "money": 100}
	state.level_entry_player_state = {"health": {"health": 61.0}}
	var player_snapshot := {
		"health": {"health": 73.0},
		"equipment": {"current_slot": 1},
	}

	var snapshot: Dictionary = state.capture_save_state(player_snapshot)
	check(state.validate_save_state(snapshot), "完整游戏快照通过校验")
	check(int(snapshot.money) == 275 and snapshot.flags.music_playing,
		"快照包含货币、对话、物品和旗标")

	state.reset_game_progress()
	check(state.money == 0 and state.completed_level == 0 and state.available_level == 1
			and state.items.is_empty() and state.flags.is_empty()
			and state.campaign_checkpoint.is_empty() and state.last_tavern_state.is_empty(),
		"重置清理全部游戏状态")

	check(state.apply_save_state(snapshot), "合法快照可以恢复")
	check(state.money == 275 and state.completed_level == 2 and state.available_level == 3
			and state.pending_player_state == player_snapshot
			and state.last_tavern_state == snapshot,
		"恢复快照并重建最后酒馆状态")

	state.reset_game_progress()
	state.money = 45
	var prepared: Dictionary = state.prepare_scene_transition(&"enter_level", player_snapshot)
	check(not prepared.is_empty() and state.commit_scene_transition(prepared),
		"进入关卡事务可提交")
	check(int(state.last_tavern_state.get("money", -1)) == 45
			and state.last_tavern_state.get("player_state") == player_snapshot,
		"进入关卡时记录离开酒馆前的完整快照")

	print("CAMPAIGN SAVE STATE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
