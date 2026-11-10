class_name ShopItemDefinition
extends Resource

enum Effect { HEAL, REFILL_AMMO, SYSTEM_PROGRESS, WEAPON }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_range(0, 999999, 1) var price: int = 0
@export_range(0, 5, 1) var unlock_level: int = 0
@export var effect: Effect = Effect.HEAL
@export_range(0, 9999, 1) var amount: int = 0
@export var weapon_data: WeaponData
@export var one_time: bool = false


func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or price < 0:
		return false
	if effect == Effect.WEAPON:
		return weapon_data != null and one_time
	if effect in [Effect.HEAL, Effect.SYSTEM_PROGRESS]:
		return amount > 0
	return effect == Effect.REFILL_AMMO
