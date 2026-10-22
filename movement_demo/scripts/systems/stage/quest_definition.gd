class_name QuestDefinition
extends Resource

## 任务定义：只声明判定条件与阶段窗口，运行状态由 QuestController 持有。
## 条件数组用「全部满足」解释；空数组表示该判定不由条件驱动。

@export var id: StringName = &""
@export var display_name: String = ""
## 所属阶段序号，与 StageDefinition.index 对应；支线任务与所属主线填同一个序号。
@export var stage_index: int = 1
## 任务目标场地标识，用于记录与面板显示。
@export var target_area: StringName = &""

@export_group("阶段窗口")
## 阶段序号小于该值时任务未解锁，不参与条件评估；0 表示不限。
@export var unlock_stage: int = 0
## 阶段序号大于等于该值时任务失效，转为已失效；0 表示不限。
@export var expire_stage: int = 0

@export_group("条件")
## 全部满足时进入进行中。
@export var accept_conditions: Array[QuestCondition] = []
## 全部满足时记为已拒绝。
@export var refuse_conditions: Array[QuestCondition] = []
## 已接取后全部满足时完成。
@export var complete_conditions: Array[QuestCondition] = []
