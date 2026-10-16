extends SceneTree

## 任务条件资源检查：来源枚举、静态构造、默认值与描述文本。
## 运行：godot --headless --path movement_demo --script res://tests/quest_conditions_test.gd

const QuestConditionScript := preload("res://scripts/systems/stage/quest_condition.gd")

## 断言总数；脚本报错会中断检查函数，最后用它兜住「报错却显示全绿」的假通过。
const EXPECTED_CHECKS := 16

var failures: int = 0
var checks_run: int = 0


func _initialize() -> void:
	run_checks()
	if failures == 0:
		print("quest condition checks: all passed")
	else:
		print("quest condition checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)


func check(condition: bool, label_text: String) -> void:
	checks_run += 1
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func run_checks() -> void:
	_check_defaults()
	_check_factories()
	_check_describe()
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])


func _check_defaults() -> void:
	var condition = QuestConditionScript.new()
	check(condition.enabled, "条件默认启用")
	check(condition.source == QuestConditionScript.Source.STATE_FIELD, "默认来源为状态字段")
	check(condition.key == &"", "默认 key 为空")
	check(condition.flag_value, "旗标默认期望为真")
	check(condition.min_count == 1, "物品默认最少数量为 1")


func _check_factories() -> void:
	var field = QuestConditionScript.field(&"help_choice", "accepted")
	check(
		field.source == QuestConditionScript.Source.STATE_FIELD
		and field.key == &"help_choice"
		and field.state_value == "accepted",
		"field() 构造状态字段条件"
	)
	var flag = QuestConditionScript.flag(&"music_playing", false)
	check(
		flag.source == QuestConditionScript.Source.FLAG
		and flag.key == &"music_playing"
		and not flag.flag_value,
		"flag() 构造旗标条件并保留真假"
	)
	var item = QuestConditionScript.item(&"keycard", 2)
	check(
		item.source == QuestConditionScript.Source.ITEM
		and item.key == &"keycard"
		and item.min_count == 2,
		"item() 构造物品条件并保留数量"
	)
	check(
		QuestConditionScript.interacted(&"record_player").source == QuestConditionScript.Source.INTERACTED,
		"interacted() 构造交互条件"
	)
	check(
		QuestConditionScript.zone_entered(&"arena").source == QuestConditionScript.Source.ZONE_ENTERED,
		"zone_entered() 构造进入区域条件"
	)
	check(
		QuestConditionScript.zone_left(&"arena").source == QuestConditionScript.Source.ZONE_LEFT,
		"zone_left() 构造离开区域条件"
	)


func _check_describe() -> void:
	check(
		QuestConditionScript.field(&"help_choice", "accepted").describe() == "状态字段 help_choice == accepted",
		"状态字段条件描述包含字段与取值"
	)
	check(
		QuestConditionScript.flag(&"music_playing", false).describe() == "旗标 music_playing == 假",
		"旗标条件描述包含真假"
	)
	check(
		QuestConditionScript.item(&"keycard", 2).describe() == "物品 keycard >= 2",
		"物品条件描述包含数量"
	)
	check(
		QuestConditionScript.zone_entered(&"arena").describe() == "曾进入区域 arena",
		"区域条件描述包含区域 id"
	)
	check(
		QuestConditionScript.zone_entered(&"").describe() == "曾进入区域(未填 key)",
		"缺 key 的条件描述可见"
	)
