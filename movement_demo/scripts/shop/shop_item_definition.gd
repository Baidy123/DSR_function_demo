@tool
class_name ShopItemDefinition
extends Resource

enum Effect { ADD_MEDKIT, REFILL_AMMO, SET_FLAG, WEAPON }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_range(0, 999999, 1) var price: int = 0
@export_range(0, 5, 1) var unlock_level: int = 0
@export var effect: Effect = Effect.ADD_MEDKIT:
	set(value):
		effect = value
		notify_property_list_changed()
## ADD_MEDKIT 商品每次购买增加的数量。
@export_range(0, 9999, 1) var amount: int = 0
## 拖入已有 MedkitData .tres；购买后入库，疗效与使用时间读取此资源。
@export var medkit_data: MedkitData
@export var weapon_data: WeaponData
## SET_FLAG 商品购买后将此旗标设为 true，供任务、对话与玩法查询。
@export var flag_key: StringName = &""
@export var one_time: bool = false


func _validate_property(property: Dictionary) -> void:
	var required_effects := {
		&"amount": Effect.ADD_MEDKIT,
		&"medkit_data": Effect.ADD_MEDKIT,
		&"weapon_data": Effect.WEAPON,
		&"flag_key": Effect.SET_FLAG,
	}
	var key := StringName(property.name)
	if required_effects.has(key) and effect != required_effects[key]:
		property.usage &= ~PROPERTY_USAGE_EDITOR


func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or price < 0:
		return false
	if effect == Effect.WEAPON:
		return weapon_data != null and one_time
	if effect == Effect.SET_FLAG:
		return flag_key != &"" and one_time
	if effect == Effect.ADD_MEDKIT:
		return amount > 0 and medkit_data != null \
			and is_finite(medkit_data.heal_amount) and medkit_data.heal_amount > 0.0 \
			and is_finite(medkit_data.use_seconds) and medkit_data.use_seconds > 0.0
	return effect == Effect.REFILL_AMMO
