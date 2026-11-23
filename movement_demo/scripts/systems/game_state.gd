extends Node

var _transition_sequence := 0
var _transition_prepared: Dictionary = {}
var _transition_signals: Array[Dictionary] = []
var _transition_committing := false
const SAVE_STATE_KEYS := [
	&"completed_level",
	&"available_level",
	&"claimed_reward_levels",
	&"task_a_returned",
	&"money",
	&"rewarded_task_ids",
	&"purchased_shop_item_ids",
	&"campaign_checkpoint",
	&"level_entry_player_state",
	&"talked_to_a",
	&"help_choice",
	&"music_quest_choice",
	&"music_quest_turnin",
	&"items",
	&"flags",
	&"shop_flag_keys",
	&"player_state",
]
const CAMPAIGN_CHECKPOINT_KEYS := [
	&"level",
	&"completed_level",
	&"available_level",
	&"claimed_reward_levels",
	&"shop_flags",
	&"task_a_returned",
	&"money",
	&"rewarded_task_ids",
	&"purchased_shop_item_ids",
	&"player_state",
]
const EQUIPMENT_SNAPSHOT_KEYS := [
	&"primary_weapon",
	&"secondary_weapon",
	&"medkit",
	&"medkit_count",
	&"active_slot",
	&"reserve_ammo",
	&"magazines",
]

## 本次运行是否已经播放过酒馆开场镜头；返回酒馆场景不会重置。
var opening_cinematic_played := false


func claim_opening_cinematic() -> bool:
	if opening_cinematic_played:
		return false
	opening_cinematic_played = true
	return true

func _transition_snapshot() -> Dictionary:
	var snapshot := capture_campaign_state()
	snapshot["campaign_checkpoint"] = campaign_checkpoint.duplicate(true)
	snapshot["level_entry_player_state"] = level_entry_player_state.duplicate(true)
	return snapshot


func capture_save_state(player_snapshot: Dictionary = {}) -> Dictionary:
	var snapshot := {
		"completed_level": completed_level,
		"available_level": available_level,
		"claimed_reward_levels": claimed_reward_levels.duplicate(true),
		"task_a_returned": task_a_returned,
		"money": money,
		"rewarded_task_ids": rewarded_task_ids.duplicate(true),
		"purchased_shop_item_ids": purchased_shop_item_ids.duplicate(true),
		"campaign_checkpoint": campaign_checkpoint.duplicate(true),
		"level_entry_player_state": level_entry_player_state.duplicate(true),
		"talked_to_a": talked_to_a,
		"help_choice": help_choice,
		"music_quest_choice": music_quest_choice,
		"music_quest_turnin": music_quest_turnin,
		"items": items.duplicate(true),
		"flags": flags.duplicate(true),
		"shop_flag_keys": _shop_flag_keys.duplicate(true),
		"player_state": player_snapshot.duplicate(true),
	}
	return snapshot


func validate_save_state(snapshot: Dictionary) -> bool:
	if not _has_exact_keys(snapshot, SAVE_STATE_KEYS):
		return false
	if not _is_int_in_range(snapshot.get(&"completed_level"), 0, 5):
		return false
	if not _is_int_in_range(snapshot.get(&"available_level"), 1, 5):
		return false
	if not _is_non_negative_int(snapshot.get(&"money")):
		return false
	if not snapshot.get(&"talked_to_a") is bool:
		return false
	if not _is_string_in(snapshot.get(&"task_a_returned"), ["", "returned"]):
		return false
	if not _is_string_in(snapshot.get(&"help_choice"), ["", "accepted", "refused"]):
		return false
	if not _is_string_in(snapshot.get(&"music_quest_choice"), ["", "accepted", "refused"]):
		return false
	if not _is_string_in(snapshot.get(&"music_quest_turnin"), ["", "done"]):
		return false
	if not _valid_level_bool_map(snapshot.get(&"claimed_reward_levels")):
		return false
	if not _valid_id_bool_map(snapshot.get(&"rewarded_task_ids")):
		return false
	if not _valid_id_bool_map(snapshot.get(&"purchased_shop_item_ids")):
		return false
	if not _valid_items(snapshot.get(&"items")):
		return false
	if not _valid_flags(snapshot.get(&"flags")):
		return false
	if not _valid_flags(snapshot.get(&"shop_flag_keys")):
		return false
	if not _valid_campaign_checkpoint(snapshot.get(&"campaign_checkpoint")):
		return false
	if not _valid_player_state(snapshot.get(&"level_entry_player_state")):
		return false
	if not _valid_player_state(snapshot.get(&"player_state")):
		return false
	return true


func _has_exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true


func _has_only_keys(value: Dictionary, keys: Array) -> bool:
	for key in value:
		if key not in keys:
			return false
	return true


func _is_int_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return value is int and int(value) >= minimum and int(value) <= maximum


func _is_non_negative_int(value: Variant) -> bool:
	return value is int and int(value) >= 0


func _is_string_in(value: Variant, options: Array) -> bool:
	return value is String and value in options


func _valid_level_bool_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not _is_int_in_range(key, 1, 5) or not value[key] is bool:
			return false
	return true


func _valid_id_bool_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not key is StringName or String(key).is_empty() or not value[key] is bool:
			return false
	return true


func _valid_flags(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not key is StringName or String(key).is_empty() or not value[key] is bool:
			return false
	return true


func _valid_items(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for item_id in value:
		if not item_id is StringName or String(item_id).is_empty():
			return false
		var entry: Variant = value[item_id]
		if not entry is Dictionary or entry.size() != 2 \
				or not entry.get(&"display_name") is String \
				or not _is_int_in_range(entry.get(&"count"), 1, 2147483647):
			return false
	return true


func _valid_campaign_checkpoint(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not _has_exact_keys(value, CAMPAIGN_CHECKPOINT_KEYS):
		return false
	if not _is_int_in_range(value.get(&"level"), 1, 5):
		return false
	if not _is_int_in_range(value.get(&"completed_level"), 0, 5):
		return false
	if not _is_int_in_range(value.get(&"available_level"), 1, 5):
		return false
	if not _is_non_negative_int(value.get(&"money")):
		return false
	if not _is_string_in(value.get(&"task_a_returned"), ["", "returned"]):
		return false
	if not _valid_level_bool_map(value.get(&"claimed_reward_levels")):
		return false
	if not _valid_flags(value.get(&"shop_flags")):
		return false
	if not _valid_id_bool_map(value.get(&"rewarded_task_ids")):
		return false
	if not _valid_id_bool_map(value.get(&"purchased_shop_item_ids")):
		return false
	return _valid_player_state(value.get(&"player_state"))


func _valid_player_state(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not _has_only_keys(value, [&"health", &"equipment"]):
		return false
	if value.has(&"health") and not _valid_health_snapshot(value.get(&"health")):
		return false
	if value.has(&"equipment") and not _valid_equipment_snapshot(value.get(&"equipment")):
		return false
	return not value.is_empty()


func _valid_health_snapshot(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, [&"health"]):
		return false
	var health_value: Variant = value.get(&"health")
	return (health_value is float or health_value is int) \
		and not health_value is bool \
		and is_finite(float(health_value)) \
		and float(health_value) > 0.0 \
		and float(health_value) <= 10000.0


func _valid_equipment_snapshot(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, EQUIPMENT_SNAPSHOT_KEYS):
		return false
	var primary: Variant = value.get(&"primary_weapon")
	var secondary: Variant = value.get(&"secondary_weapon")
	if primary != null and not primary is WeaponData:
		return false
	if secondary != null and not secondary is WeaponData:
		return false
	var medkit: Variant = value.get(&"medkit")
	if medkit != null and not medkit is MedkitData:
		return false
	if not _is_int_in_range(value.get(&"medkit_count"), 0, 999):
		return false
	if not _is_int_in_range(value.get(&"active_slot"), -1, 1):
		return false
	var reserve_ammo: Variant = value.get(&"reserve_ammo")
	if not reserve_ammo is Dictionary:
		return false
	for ammo_id in reserve_ammo:
		if not ammo_id is StringName or String(ammo_id).is_empty() \
				or not _is_non_negative_int(reserve_ammo[ammo_id]):
			return false
	var magazines: Variant = value.get(&"magazines")
	if not magazines is Array or magazines.size() != 2:
		return false
	var capacities := [
		int(primary.magazine_capacity) if primary is WeaponData else 0,
		int(secondary.magazine_capacity) if secondary is WeaponData else 0,
	]
	for slot in range(2):
		if not _is_int_in_range(magazines[slot], 0, capacities[slot]):
			return false
	return true


func prepare_scene_transition(mode: StringName, player_snapshot: Dictionary = {}, level_number: int = 0) -> Dictionary:
	if mode not in [&"enter_level", &"return_tavern", &"retry_level", &"death_return", &"reset_progress", &"plain"]: return {}
	if mode == &"return_tavern" and (level_number < 1 or level_number > 5): return {}
	var before := _transition_snapshot()
	var target := before.duplicate(true)
	match mode:
		&"enter_level":
			target.player_state = player_snapshot.duplicate(true)
			target.level_entry_player_state = player_snapshot.duplicate(true)
			target["last_tavern_state"] = capture_save_state(
				player_snapshot.duplicate(true))
		&"return_tavern":
			target.completed_level = level_number
			if level_number == 1: target.task_a_returned = "returned"
			target.player_state = player_snapshot.duplicate(true)
			var checkpoint := target.duplicate(true)
			checkpoint.erase("campaign_checkpoint")
			checkpoint.erase("level_entry_player_state")
			checkpoint["level"] = level_number
			target.campaign_checkpoint = checkpoint
		&"retry_level":
			if not level_entry_player_state.is_empty(): target.player_state = level_entry_player_state.duplicate(true)
		&"death_return":
			if not campaign_checkpoint.is_empty():
				var defaults := {"completed_level": 0, "available_level": available_level,
					"claimed_reward_levels": {}, "shop_flags": {}, "task_a_returned": "", "money": 0,
					"rewarded_task_ids": {}, "purchased_shop_item_ids": {}, "player_state": {}}
				for key in defaults:
					target[key] = _transition_copy(campaign_checkpoint.get(key, defaults[key]))
		&"reset_progress":
			target = {
				"completed_level": 0,
				"available_level": 1,
				"claimed_reward_levels": {},
				"task_a_returned": "",
				"money": 0,
				"rewarded_task_ids": {},
				"purchased_shop_item_ids": {},
				"campaign_checkpoint": {},
				"level_entry_player_state": {},
				"last_tavern_state": {},
				"talked_to_a": false,
				"help_choice": "",
				"music_quest_choice": "",
				"music_quest_turnin": "",
				"items": {},
				"flags": {},
				"shop_flag_keys": {},
				"player_state": {},
			}
	_transition_sequence += 1
	var prepared := {"id": _transition_sequence, "base": before, "target": target, "mode": mode}
	_transition_prepared[_transition_sequence] = prepared.duplicate(true)
	return prepared

func _transition_copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func validate_scene_transition(prepared: Dictionary) -> bool:
	return not prepared.is_empty() and _transition_prepared.get(prepared.get("id")) == prepared and prepared.get("base") == _transition_snapshot()

func discard_scene_transition(prepared: Dictionary) -> void:
	_transition_prepared.erase(prepared.get("id"))

func commit_scene_transition(prepared: Dictionary) -> bool:
	if not validate_scene_transition(prepared): return false
	_transition_prepared.erase(prepared.id)
	var target: Dictionary = prepared.target
	_transition_committing = true
	if prepared.get("mode") == &"reset_progress":
		reset_game_progress()
	else:
		campaign_checkpoint = target.campaign_checkpoint.duplicate(true)
		level_entry_player_state = target.level_entry_player_state.duplicate(true)
		restore_campaign_state(target)
	_transition_committing = false
	if target.has("last_tavern_state"):
		remember_tavern_state(target.last_tavern_state)
	var notifications := _transition_signals
	_transition_signals = []
	for notification in notifications:
		callv(&"emit_signal", [notification.name] + notification.arguments)
	return true

func _notify_state(name: StringName, arguments: Array) -> void:
	if _transition_committing:
		_transition_signals.append({"name": name, "arguments": arguments})
	else: callv(&"emit_signal", [name] + arguments)

## 对话字段被写入时通知监听者（例如任务控制器按表同步任务状态）；
## 值没有变化时不发信号，避免同一结果反复刷新。旗标与物品另有专用信号。
signal value_changed(key: StringName, value: Variant)
signal money_changed(previous: int, current: int)

var money: int = 0:
	set(value):
		value = maxi(0, value)
		if money == value:
			return
		var previous := money
		money = value
		_notify_state(&"money_changed", [previous, money])

# 本次运行共享的对话状态；重新运行游戏会重置。
var talked_to_a: bool = false:
	set(value):
		if talked_to_a == value:
			return
		talked_to_a = value
		_notify_state(&"value_changed", [&"talked_to_a", value])
# 空字符串：尚未选择；accepted：答应；refused：拒绝。
var help_choice: String = "":
	set(value):
		if help_choice == value:
			return
		help_choice = value
		_notify_state(&"value_changed", [&"help_choice", value])
# 唱片机支线：空字符串＝尚未选择；accepted＝已接取；refused＝已拒绝。
var music_quest_choice: String = "":
	set(value):
		if music_quest_choice == value:
			return
		music_quest_choice = value
		_notify_state(&"value_changed", [&"music_quest_choice", value])
# 唱片机支线交差提交：done＝已提交（是否完成由任务条件按音乐旗标判定）。
var music_quest_turnin: String = "":
	set(value):
		if music_quest_turnin == value:
			return
		music_quest_turnin = value
		_notify_state(&"value_changed", [&"music_quest_turnin", value])
# 任务一交差提交：returned＝已从第1关经传送门返回酒馆。
var task_a_returned: String = "":
	set(value):
		if task_a_returned == value:
			return
		task_a_returned = value
		_notify_state(&"value_changed", [&"task_a_returned", value])
# 第1关领取状态兼容镜像；新的逐关状态以 claimed_reward_levels 为准。
var task_a_reward_claimed: bool = false:
	set(value):
		if task_a_reward_claimed == value:
			return
		task_a_reward_claimed = value
		if value:
			claimed_reward_levels[1] = true
		else:
			claimed_reward_levels.erase(1)
		_notify_state(&"value_changed", [&"task_a_reward_claimed", value])
## 已完成关卡 -> 是否已领取该关奖励。每关独立，只允许领取一次。
var claimed_reward_levels: Dictionary = {}
# 五关主线：最近完成关卡与当前已由 A 解锁的关卡。完成关卡不会自动解锁下一关。
var completed_level: int = 0:
	set(value):
		value = maxi(0, value)
		if completed_level == value:
			return
		completed_level = value
		_notify_state(&"value_changed", [&"completed_level", value])
var available_level: int = 1:
	set(value):
		value = clampi(value, 1, 5)
		if available_level == value:
			return
		available_level = value
		_notify_state(&"value_changed", [&"available_level", value])
## 下一次新玩家实例就绪后消费一次；正常进入关卡或返回酒馆时由传送门写入。
var pending_player_state: Dictionary = {}
## 最近一次正常完成关卡时的酒馆状态；死亡后选择回酒馆时恢复，不随一次性玩家快照消费。
var campaign_checkpoint: Dictionary = {}
## 最近一次进入关卡前离开酒馆时的完整快照；只用于酒馆安全状态保存。
var last_tavern_state: Dictionary = {}
## 已领取任务奖励的任务 ID；与检查点同步，保证死亡回酒馆后不重复领取。
var rewarded_task_ids: Dictionary = {}
## 一次性商店商品购买记录；与检查点同步，保证死亡回酒馆后恢复未购买状态。
var purchased_shop_item_ids: Dictionary = {}
## 进入当前关卡时的一次性玩家快照；死亡重开当前关时恢复，不等同于酒馆检查点。
var level_entry_player_state: Dictionary = {}
var completed_reward_claimed: bool:
	get:
		return has_claimed_reward(completed_level)
## 只读镜像：对话剧本按属性名读取唱片机旗标；旗标本身仍是唯一来源，由交互物写入。
var music_playing: bool:
	get:
		return get_flag(&"music_playing")

## 交互产生的物品与旗标；与对话状态一样，重新运行游戏才重置，死亡重开场景保留。
signal item_gained(item_id: StringName, display_name: String, total: int)
signal flag_changed(flag: StringName, value: bool)

## item_id -> {"display_name": String, "count": int}
var items: Dictionary = {}
## flag -> bool
var flags: Dictionary = {}
## 记录商店负责的旗标键；旗标值唯一保存在 flags，回滚不涉及其他玩法旗标。
var _shop_flag_keys: Dictionary = {}


func grant_shop_flag(flag_key: StringName) -> bool:
	if flag_key == &"" or get_flag(flag_key):
		return false
	_shop_flag_keys[flag_key] = true
	set_flag(flag_key)
	return true


func _capture_shop_flags() -> Dictionary:
	var result: Dictionary = {}
	for key in _shop_flag_keys:
		result[key] = get_flag(key)
	return result


func _restore_shop_flags(snapshot: Dictionary) -> void:
	for key in snapshot:
		_shop_flag_keys[key] = true
	for key in _shop_flag_keys:
		set_flag(key, bool(snapshot.get(key, false)))


## 拾取或获得物品；display_name 留空时保留已有名字。
func add_item(item_id: StringName, display_name: String = "", count: int = 1) -> void:
	if item_id == &"" or count <= 0:
		return
	var entry: Dictionary = items.get(item_id, {"display_name": "", "count": 0})
	if not display_name.is_empty():
		entry["display_name"] = display_name
	entry["count"] = int(entry["count"]) + count
	items[item_id] = entry
	item_gained.emit(item_id, entry["display_name"], entry["count"])


func has_item(item_id: StringName) -> bool:
	return get_item_count(item_id) > 0


func get_item_count(item_id: StringName) -> int:
	var entry: Dictionary = items.get(item_id, {})
	return int(entry.get("count", 0))


## 提示文本使用；未登记过该物品时回退到内部 ID。
func item_display_name(item_id: StringName) -> String:
	var entry: Dictionary = items.get(item_id, {})
	var name_text: String = entry.get("display_name", "")
	return name_text if not name_text.is_empty() else str(item_id)


## 置位旗标；值没有变化时不重复发信号，避免调试面板反复刷新。
func set_flag(flag: StringName, value: bool = true) -> void:
	if flag == &"":
		return
	if flags.get(flag, null) == value:
		return
	flags[flag] = value
	_notify_state(&"flag_changed", [flag, value])


func get_flag(flag: StringName, fallback: bool = false) -> bool:
	return bool(flags.get(flag, fallback))


func is_flag_set(flag: StringName) -> bool:
	return get_flag(flag)


## 增加货币；非正数输入忽略，只在实际变化时发信号。
func add_money(amount: int) -> int:
	if amount <= 0:
		return money
	money += amount
	return money


## 扣除货币；金额必须为正整数，且余额不足时保持原值不变。
func spend_money(amount: int) -> bool:
	if amount <= 0 or money < amount:
		return false
	money -= amount
	return true


## 领取任务奖励；同一任务只成功一次，并同步到匹配完成级别的酒馆检查点。
func claim_task_reward(task_id: StringName, amount: int, completion_level: int) -> bool:
	if amount <= 0 or task_id == &"" or has_task_reward(task_id):
		return false
	if not campaign_checkpoint.is_empty() \
			and int(campaign_checkpoint.get("completed_level", -1)) == completion_level \
			and not bool(campaign_checkpoint.get("rewarded_task_ids", {}).get(task_id, false)):
		var checkpoint_rewards: Dictionary = {}
		var raw_rewards = campaign_checkpoint.get("rewarded_task_ids", {})
		if raw_rewards is Dictionary:
			checkpoint_rewards = raw_rewards.duplicate()
		checkpoint_rewards[task_id] = true
		campaign_checkpoint["rewarded_task_ids"] = checkpoint_rewards
		campaign_checkpoint["money"] = int(campaign_checkpoint.get("money", 0)) + amount
	rewarded_task_ids[task_id] = true
	money += amount
	return true


func has_task_reward(task_id: StringName) -> bool:
	return bool(rewarded_task_ids.get(task_id, false))


func mark_shop_item_purchased(item_id: StringName) -> void:
	if item_id == &"":
		return
	purchased_shop_item_ids[item_id] = true


func has_purchased_shop_item(item_id: StringName) -> bool:
	return bool(purchased_shop_item_ids.get(item_id, false))


## 保存进入当前关卡时的玩家快照，供死亡重开时恢复。
func set_level_entry_player_state(snapshot: Dictionary) -> void:
	level_entry_player_state = snapshot.duplicate(true)


## 把入关快照复制到一次性待恢复状态；没有快照时返回 false。
func prepare_level_retry_state() -> bool:
	if level_entry_player_state.is_empty():
		return false
	pending_player_state = level_entry_player_state.duplicate(true)
	return true


func set_pending_player_state(snapshot: Dictionary) -> void:
	pending_player_state = snapshot.duplicate()


func take_pending_player_state() -> Dictionary:
	var snapshot := pending_player_state
	pending_player_state = {}
	return snapshot


## 返程门在完成任务后记录；快照保留奖励尚未领取、下一关尚未由 A 解锁的时刻。
func record_campaign_checkpoint(level_number: int, player_snapshot: Dictionary) -> void:
	campaign_checkpoint = {
		"level": level_number,
		"completed_level": completed_level,
		"available_level": available_level,
		"claimed_reward_levels": claimed_reward_levels.duplicate(),
		"shop_flags": _capture_shop_flags(),
		"task_a_returned": task_a_returned,
		"money": money,
		"rewarded_task_ids": rewarded_task_ids.duplicate(),
		"purchased_shop_item_ids": purchased_shop_item_ids.duplicate(),
		"player_state": player_snapshot.duplicate(true),
	}


## 死亡后返回酒馆沿用最近完成任务的状态；检查点不清空，加载失败后可再次重试。
func restore_campaign_checkpoint() -> bool:
	if campaign_checkpoint.is_empty():
		return false
	return restore_campaign_state(campaign_checkpoint)


## 捕获当前酒馆相关状态；场景加载失败时用于撤销尚未完成的检查点恢复。
func capture_campaign_state() -> Dictionary:
	return {
		"completed_level": completed_level,
		"available_level": available_level,
		"claimed_reward_levels": claimed_reward_levels.duplicate(),
		"shop_flags": _capture_shop_flags(),
		"task_a_returned": task_a_returned,
		"money": money,
		"rewarded_task_ids": rewarded_task_ids.duplicate(),
		"purchased_shop_item_ids": purchased_shop_item_ids.duplicate(),
		"player_state": pending_player_state.duplicate(true),
	}


func restore_campaign_state(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return false
	completed_level = int(snapshot.get("completed_level", 0))
	available_level = int(snapshot.get("available_level", available_level))
	var restored_claims: Dictionary = snapshot.get("claimed_reward_levels", {}).duplicate()
	claimed_reward_levels = restored_claims
	task_a_reward_claimed = bool(restored_claims.get(1, false))
	_notify_state(&"value_changed", [&"claimed_reward_levels", restored_claims.duplicate()])
	_restore_shop_flags(snapshot.get("shop_flags", {}))
	task_a_returned = str(snapshot.get("task_a_returned", ""))
	money = int(snapshot.get("money", 0))
	rewarded_task_ids = snapshot.get("rewarded_task_ids", {}).duplicate()
	purchased_shop_item_ids = snapshot.get("purchased_shop_item_ids", {}).duplicate()
	var player_snapshot: Dictionary = snapshot.get("player_state", {})
	pending_player_state = player_snapshot.duplicate(true)
	return true


func apply_save_state(snapshot: Dictionary, rebuild_last_tavern: bool = true) -> bool:
	if not validate_save_state(snapshot):
		return false
	reset_game_progress()
	completed_level = int(snapshot.completed_level)
	available_level = int(snapshot.available_level)
	claimed_reward_levels = snapshot.claimed_reward_levels.duplicate(true)
	task_a_reward_claimed = bool(claimed_reward_levels.get(1, false))
	task_a_returned = str(snapshot.task_a_returned)
	money = int(snapshot.money)
	rewarded_task_ids = snapshot.rewarded_task_ids.duplicate(true)
	purchased_shop_item_ids = snapshot.purchased_shop_item_ids.duplicate(true)
	campaign_checkpoint = snapshot.campaign_checkpoint.duplicate(true)
	level_entry_player_state = snapshot.level_entry_player_state.duplicate(true)
	talked_to_a = bool(snapshot.talked_to_a)
	help_choice = str(snapshot.help_choice)
	music_quest_choice = str(snapshot.music_quest_choice)
	music_quest_turnin = str(snapshot.music_quest_turnin)
	items = snapshot.items.duplicate(true)
	flags = snapshot.flags.duplicate(true)
	_shop_flag_keys = snapshot.shop_flag_keys.duplicate(true)
	pending_player_state = snapshot.player_state.duplicate(true)
	if rebuild_last_tavern:
		last_tavern_state = snapshot.duplicate(true)
	return true


func remember_tavern_state(snapshot: Dictionary) -> void:
	if validate_save_state(snapshot):
		last_tavern_state = snapshot.duplicate(true)


func reset_game_progress() -> void:
	completed_level = 0
	available_level = 1
	claimed_reward_levels = {}
	task_a_reward_claimed = false
	task_a_returned = ""
	money = 0
	rewarded_task_ids = {}
	purchased_shop_item_ids = {}
	pending_player_state = {}
	campaign_checkpoint = {}
	level_entry_player_state = {}
	last_tavern_state = {}
	talked_to_a = false
	help_choice = ""
	music_quest_choice = ""
	music_quest_turnin = ""
	items = {}
	flags = {}
	_shop_flag_keys = {}
	opening_cinematic_played = false


func has_claimed_reward(level_number: int) -> bool:
	return bool(claimed_reward_levels.get(level_number, false))


func mark_reward_claimed(level_number: int) -> void:
	if level_number < 1 or has_claimed_reward(level_number):
		return
	claimed_reward_levels[level_number] = true
	if level_number == 1:
		task_a_reward_claimed = true
	_notify_state(&"value_changed", [&"claimed_reward_levels", claimed_reward_levels.duplicate()])


func reset_reward_claims() -> void:
	claimed_reward_levels.clear()
	task_a_reward_claimed = false
	_notify_state(&"value_changed", [&"claimed_reward_levels", {}])


## 供测试与重开流程使用；正常死亡重开不清空。
func clear_interaction_state() -> void:
	items.clear()
	flags.clear()
	_shop_flag_keys.clear()
