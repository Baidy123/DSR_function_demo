class_name RewardOption
extends Resource

enum Effect {
	HEAL,
	REFILL_AMMO,
	SYSTEM_PROGRESS,
}

## 单个奖励选项；ID 在所属关卡的三项中保持稳定。
@export var id: StringName = &""
@export var display_name: String = "奖励"
@export_multiline var description: String = ""
@export var effect: Effect = Effect.SYSTEM_PROGRESS
@export var amount: int = 0
