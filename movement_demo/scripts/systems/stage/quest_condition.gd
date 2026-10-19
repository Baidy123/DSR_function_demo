class_name QuestCondition
extends Resource

## 任务条件：一条条件只描述一个可判定的事实，不引用任何控制器，也不保存运行状态。
## 任务定义按数组引用条件，任务控制器逐条判定；缺 key 的条件视为不满足。

enum Source {
	STATE_FIELD, ## 状态字段（对话写入）的字符串值相等
	FLAG, ## 旗标等于给定真假
	ITEM, ## 持有物品数量不少于 min_count
	INTERACTED, ## 曾与 key 标识的交互物交互过
	ZONE_ENTERED, ## 曾进入 key 标识的区域
	ZONE_LEFT, ## 曾离开 key 标识的区域
}

const SOURCE_NAMES: Dictionary = {
	Source.STATE_FIELD: "状态字段",
	Source.FLAG: "旗标",
	Source.ITEM: "物品",
	Source.INTERACTED: "交互过",
	Source.ZONE_ENTERED: "曾进入区域",
	Source.ZONE_LEFT: "曾离开区域",
}

## 关闭后本条条件不参与判定，便于临时停用。
@export var enabled: bool = true
@export var source: Source = Source.STATE_FIELD
## 字段名 / 旗标名 / 物品 id / 交互物 interact_id / 区域 zone_id。
@export var key: StringName = &""
## STATE_FIELD 用：期望的字符串值。
@export var state_value: String = ""
## FLAG 用：期望的布尔值。
@export var flag_value: bool = true
## ITEM 用：需要的最少数量。
@export var min_count: int = 1
## 配置备注，只用于阅读。
@export var note: String = ""


static func field(field_name: StringName, value: String) -> QuestCondition:
	var condition := _create(Source.STATE_FIELD, field_name)
	condition.state_value = value
	return condition


static func flag(flag_name: StringName, value: bool = true) -> QuestCondition:
	var condition := _create(Source.FLAG, flag_name)
	condition.flag_value = value
	return condition


static func item(item_id: StringName, count: int = 1) -> QuestCondition:
	var condition := _create(Source.ITEM, item_id)
	condition.min_count = count
	return condition


static func interacted(interact_id: StringName) -> QuestCondition:
	return _create(Source.INTERACTED, interact_id)


static func zone_entered(zone_id: StringName) -> QuestCondition:
	return _create(Source.ZONE_ENTERED, zone_id)


static func zone_left(zone_id: StringName) -> QuestCondition:
	return _create(Source.ZONE_LEFT, zone_id)


## 记录、调试与配置检查使用的中文描述。
func describe() -> String:
	var source_name: String = SOURCE_NAMES.get(source, "未知条件")
	if key == &"":
		return "%s(未填 key)" % source_name
	match source:
		Source.STATE_FIELD:
			return "%s %s == %s" % [source_name, key, state_value]
		Source.FLAG:
			return "%s %s == %s" % [source_name, key, "真" if flag_value else "假"]
		Source.ITEM:
			return "%s %s >= %d" % [source_name, key, min_count]
		_:
			return "%s %s" % [source_name, key]


static func _create(source_id: int, key_id: StringName) -> QuestCondition:
	var condition := QuestCondition.new()
	condition.source = source_id
	condition.key = key_id
	return condition
