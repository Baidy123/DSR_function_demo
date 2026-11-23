class_name StateRule
extends Resource

## NPC 状态规则：条件全部满足时把状态应用到目标 NPC。
## 表内按顺序匹配，后面的规则覆盖前面的规则；未命中的字段保持上一条规则或 NPC 自身状态。

enum { ANY_PHASE = -1 }

## 记录与排查用的规则 id；留空时记录里显示“未命名规则”。
@export var id: StringName = &""
## 关闭后本规则不参与匹配，便于临时停用一条规则。
@export var enabled: bool = true

@export_group("条件")
## 限定阶段序号；0 表示不限制。
@export var stage_index: int = 0
## 限定环节，取值见 StagePhase.Id；-1 表示不限制。
@export var phase: int = ANY_PHASE
## 限定任务状态；留空表示不限制，需与 quest_status 一起使用。
@export var quest_id: StringName = &""
## 限定该任务处于哪个状态：not_started / in_progress / refused / completed。
@export var quest_status: StringName = &""
## 需要已置位的旗标，由状态节点解释；空数组表示不限制。
@export var required_flags: Array[StringName] = []
## 需要持有的物品，由状态节点解释；空数组表示不限制。
@export var required_items: Array[StringName] = []

@export_group("目标")
## 目标 NPC 的 npc_id；留空表示本条规则应用到全部 NPC。
@export var target_npc: StringName = &""

@export_group("状态")
## 应用后在不在场；默认在场，设为关闭即让目标 NPC 退场。
@export var present: bool = true
## 勾选后使用下面的世界坐标覆盖站位。
@export var position_set: bool = false
@export var position: Vector3 = Vector3.ZERO
## 勾选后让 NPC 转向该世界坐标点。
@export var facing_set: bool = false
@export var facing: Vector3 = Vector3.ZERO
## 覆盖对话资源；留空表示不改动该 NPC 当前对话。
@export var dialogue: DialogueResource
