extends Node

## 对话字段被写入时通知监听者（例如任务控制器按表同步任务状态）；
## 值没有变化时不发信号，避免同一结果反复刷新。旗标与物品另有专用信号。
signal value_changed(key: StringName, value: Variant)
signal system_progress_changed(previous: int, current: int)
signal money_changed(previous: int, current: int)

const SYSTEM_PROGRESS_MAX: int = 100
var system_progress: int = 0
var money: int = 0:
	set(value):
		value = maxi(0, value)
		if money == value:
			return
		var previous := money
		money = value
		money_changed.emit(previous, money)

# 本次运行共享的对话状态；重新运行游戏会重置。
var talked_to_a: bool = false:
	set(value):
		if talked_to_a == value:
			return
		talked_to_a = value
		value_changed.emit(&"talked_to_a", value)
# 空字符串：尚未选择；accepted：答应；refused：拒绝。
var help_choice: String = "":
	set(value):
		if help_choice == value:
			return
		help_choice = value
		value_changed.emit(&"help_choice", value)
# 唱片机支线：空字符串＝尚未选择；accepted＝已接取；refused＝已拒绝。
var music_quest_choice: String = "":
	set(value):
		if music_quest_choice == value:
			return
		music_quest_choice = value
		value_changed.emit(&"music_quest_choice", value)
# 唱片机支线交差提交：done＝已提交（是否完成由任务条件按音乐旗标判定）。
var music_quest_turnin: String = "":
	set(value):
		if music_quest_turnin == value:
			return
		music_quest_turnin = value
		value_changed.emit(&"music_quest_turnin", value)
# 任务一交差提交：returned＝已从第1关经传送门返回酒馆。
var task_a_returned: String = "":
	set(value):
		if task_a_returned == value:
			return
		task_a_returned = value
		value_changed.emit(&"task_a_returned", value)
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
		value_changed.emit(&"task_a_reward_claimed", value)
## 已完成关卡 -> 是否已领取该关奖励。每关独立，只允许领取一次。
var claimed_reward_levels: Dictionary = {}
# 五关主线：最近完成关卡与当前已由 A 解锁的关卡。完成关卡不会自动解锁下一关。
var completed_level: int = 0:
	set(value):
		value = maxi(0, value)
		if completed_level == value:
			return
		completed_level = value
		value_changed.emit(&"completed_level", value)
var available_level: int = 1:
	set(value):
		value = clampi(value, 1, 5)
		if available_level == value:
			return
		available_level = value
		value_changed.emit(&"available_level", value)
## 下一次新玩家实例就绪后消费一次；正常进入关卡或返回酒馆时由传送门写入。
var pending_player_state: Dictionary = {}
## 最近一次正常完成关卡时的酒馆状态；死亡后选择回酒店时恢复，不随一次性玩家快照消费。
var campaign_checkpoint: Dictionary = {}
## 已领取任务奖励的任务 ID；与检查点同步，保证死亡回酒店后不重复领取。
var rewarded_task_ids: Dictionary = {}
## 一次性商店商品购买记录；与检查点同步，保证死亡回酒店后恢复未购买状态。
var purchased_shop_item_ids: Dictionary = {}
## 进入当前关卡时的一次性玩家快照；死亡重开当前关时恢复，不等同于酒店检查点。
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


func add_system_progress(amount: int) -> void:
	if amount <= 0 or system_progress >= SYSTEM_PROGRESS_MAX:
		return
	var previous := system_progress
	system_progress = mini(SYSTEM_PROGRESS_MAX, previous + amount)
	if system_progress != previous:
		system_progress_changed.emit(previous, system_progress)


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
	flag_changed.emit(flag, value)


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


## 领取任务奖励；同一任务只成功一次，并同步到匹配完成级别的酒店检查点。
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
		"system_progress": system_progress,
		"task_a_returned": task_a_returned,
		"money": money,
		"rewarded_task_ids": rewarded_task_ids.duplicate(),
		"purchased_shop_item_ids": purchased_shop_item_ids.duplicate(),
		"player_state": player_snapshot.duplicate(true),
	}


## 死亡后返回酒店沿用最近完成任务的状态；检查点不清空，加载失败后可再次重试。
func restore_campaign_checkpoint() -> bool:
	if campaign_checkpoint.is_empty():
		return false
	return restore_campaign_state(campaign_checkpoint)


## 捕获当前酒店相关状态；场景加载失败时用于撤销尚未完成的检查点恢复。
func capture_campaign_state() -> Dictionary:
	return {
		"completed_level": completed_level,
		"available_level": available_level,
		"claimed_reward_levels": claimed_reward_levels.duplicate(),
		"system_progress": system_progress,
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
	value_changed.emit(&"claimed_reward_levels", restored_claims.duplicate())
	var restored_progress := int(snapshot.get("system_progress", system_progress))
	if system_progress != restored_progress:
		var previous := system_progress
		system_progress = restored_progress
		system_progress_changed.emit(previous, system_progress)
	task_a_returned = str(snapshot.get("task_a_returned", ""))
	money = int(snapshot.get("money", 0))
	rewarded_task_ids = snapshot.get("rewarded_task_ids", {}).duplicate()
	purchased_shop_item_ids = snapshot.get("purchased_shop_item_ids", {}).duplicate()
	var player_snapshot: Dictionary = snapshot.get("player_state", {})
	pending_player_state = player_snapshot.duplicate(true)
	return true


func has_claimed_reward(level_number: int) -> bool:
	return bool(claimed_reward_levels.get(level_number, false))


func mark_reward_claimed(level_number: int) -> void:
	if level_number < 1 or has_claimed_reward(level_number):
		return
	claimed_reward_levels[level_number] = true
	if level_number == 1:
		task_a_reward_claimed = true
	value_changed.emit(&"claimed_reward_levels", claimed_reward_levels.duplicate())


func reset_reward_claims() -> void:
	claimed_reward_levels.clear()
	task_a_reward_claimed = false
	value_changed.emit(&"claimed_reward_levels", {})


## 供测试与重开流程使用；正常死亡重开不清空。
func clear_interaction_state() -> void:
	items.clear()
	flags.clear()
