class_name QuestDefinition
extends Resource

## 任务定义：只声明判定来源（接取、拒绝、完成），运行状态由 QuestController 持有。

@export var id: StringName = &""
@export var display_name: String = ""
## 所属阶段序号，与 StageDefinition.index 对应。
@export var stage_index: int = 1
## 任务目标场地标识，用于记录；阶段定义里也有同名信息时以阶段为准。
@export var target_area: StringName = &""

@export_group("接取")
## 读取哪个状态字段判断接取，例如 help_choice；留空表示不由状态字段驱动。
@export var accept_source: StringName = &""
## 状态字段等于该值时任务进入“进行中”。
@export var accept_value: String = ""
## 状态字段等于其中任一值时任务记为“已拒绝”；空数组表示不处理拒绝。
@export var refuse_values: Array[String] = []

@export_group("完成")
## 玩家离开任务场地返回时自动完成；关闭后只能由 complete() 或外部显式完成。
@export var complete_on_return: bool = true
## 完成前还必须置位的旗标；空数组表示不额外限制。
@export var required_flags: Array[StringName] = []
