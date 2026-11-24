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
	state.campaign_checkpoint = {
		"level": 2,
		"completed_level": 2,
		"available_level": 3,
		"claimed_reward_levels": {1: true},
		"shop_flags": {&"shop_mind_access": true},
		"task_a_returned": "returned",
		"money": 100,
		"rewarded_task_ids": {&"task_a": true},
		"purchased_shop_item_ids": {&"medkit_pack": true},
		"player_state": _valid_player_snapshot(61.0),
	}
	state.level_entry_player_state = _valid_player_snapshot(61.0)
	var player_snapshot := _valid_player_snapshot(73.0)

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
			and state.pending_player_state.get("health", {}).get("health") == 73.0
			and state.last_tavern_state.get("player_state", {}).get("health", {}).get("health") == 73.0,
		"恢复快照并重建最后酒馆状态")

	var malformed := snapshot.duplicate(true)
	malformed.player_state = {"health": {"health": "73"}}
	_reject_without_mutation(state, malformed, "错误玩家生命类型拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.player_state = {"health": {"health": 0.0}}
	_reject_without_mutation(state, malformed, "越界玩家生命拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.player_state = {"equipment": {
		"primary_weapon": null,
		"secondary_weapon": null,
		"medkit": null,
		"medkit_count": 0,
		"active_slot": 0,
		"reserve_ammo": {&"pistol": "12"},
		"magazines": [0, 0],
	}}
	_reject_without_mutation(state, malformed, "错误备弹数量拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.player_state = {"equipment": {
		"primary_weapon": null,
		"secondary_weapon": null,
		"medkit": null,
		"medkit_count": 0,
		"active_slot": 0,
		"reserve_ammo": {},
		"magazines": ["full", 0],
	}}
	_reject_without_mutation(state, malformed, "错误弹匣数量拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.items = {&"coin": {"display_name": "硬币", "count": "3"}}
	_reject_without_mutation(state, malformed, "错误物品数量拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.flags = {&"music_playing": "yes"}
	_reject_without_mutation(state, malformed, "错误旗标值拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.rewarded_task_ids = {&"task_a": "yes"}
	_reject_without_mutation(state, malformed, "错误任务奖励记录拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.purchased_shop_item_ids = {&"medkit_pack": 1}
	_reject_without_mutation(state, malformed, "错误商店购买记录拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.campaign_checkpoint.money = "100"
	_reject_without_mutation(state, malformed, "错误检查点字段拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.campaign_checkpoint.erase("level")
	_reject_without_mutation(state, malformed, "缺失检查点字段拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.level_entry_player_state = {"health": {"health": "61"}}
	_reject_without_mutation(state, malformed, "错误关卡快照拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.completed_level = 6
	_reject_without_mutation(state, malformed, "越界完成关卡拒绝且不改状态")

	malformed = snapshot.duplicate(true)
	malformed.help_choice = "yes"
	_reject_without_mutation(state, malformed, "未知对话枚举拒绝且不改状态")

	state.reset_game_progress()
	state.money = 45
	var prepared: Dictionary = state.prepare_scene_transition(&"enter_level", player_snapshot)
	check(not prepared.is_empty() and state.commit_scene_transition(prepared),
		"进入关卡事务可提交")
	check(int(state.last_tavern_state.get("money", -1)) == 45
			and state.last_tavern_state.get("player_state", {}).get("health", {}).get("health") == 73.0,
		"进入关卡时记录离开酒馆前的完整快照")

	print("CAMPAIGN SAVE STATE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func _valid_player_snapshot(health_value: float) -> Dictionary:
	return {"health": {"health": health_value}}


func _reject_without_mutation(state: Node, snapshot: Dictionary, label: String) -> void:
	state.reset_game_progress()
	state.money = 41
	state.available_level = 4
	state.items = {&"stable": {"display_name": "稳定", "count": 1}}
	state.flags = {&"stable": true}
	state.help_choice = "refused"
	var accepted: bool = state.apply_save_state(snapshot)
	check(not accepted
			and state.money == 41
			and state.available_level == 4
			and state.items.get(&"stable", {}).get("count") == 1
			and state.flags.get(&"stable") == true
			and state.help_choice == "refused"
			and state.pending_player_state.is_empty()
			and state.last_tavern_state.is_empty(),
		label)
