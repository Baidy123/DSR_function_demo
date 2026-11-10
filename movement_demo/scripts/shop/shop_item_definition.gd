class_name ShopItemDefinition
extends Resource

enum Effect { HEAL, REFILL_AMMO, SET_FLAG, WEAPON }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_range(0, 999999, 1) var price: int = 0
@export_range(0, 5, 1) var unlock_level: int = 0
@export var effect: Effect = Effect.HEAL
@export_range(0, 9999, 1) var amount: int = 0
@export var weapon_data: WeaponData
## SET_FLAG 商品购买后将此旗标设为 true，供任务、对话与玩法查询。
@export var flag_key: StringName = &""
@export var one_time: bool = false


func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or price < 0:
		return false
	if effect == Effect.WEAPON:
		return weapon_data != null and one_time
	if effect == Effect.SET_FLAG:
		return flag_key != &"" and one_time
	if effect == Effect.HEAL:
		return amount > 0
	return effect == Effect.REFILL_AMMO
