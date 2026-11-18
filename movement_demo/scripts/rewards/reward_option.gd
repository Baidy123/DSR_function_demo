class_name RewardOption
extends Resource

enum Effect {
	HEAL,
	REFILL_AMMO,
	SET_FLAG,
}

## 单个奖励选项；ID 在所属关卡的三项中保持稳定。
@export var id: StringName = &""
@export var display_name: String = "奖励"
@export_multiline var description: String = ""
@export var effect: Effect = Effect.SET_FLAG
@export var amount: int = 0
@export var flag_key: StringName = &""
