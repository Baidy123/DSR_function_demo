extends SceneTree

## Shop catalog: exact initial products, resource lookup, and duplicate filtering.
## Run: godot --headless --path movement_demo --script res://tests/shop_catalog_test.gd

const CatalogScript := preload("res://scripts/shop/shop_catalog.gd")
const ItemScript := preload("res://scripts/shop/shop_item_definition.gd")
const Catalog := preload("res://resources/shop/shop_catalog.tres")

const EXPECTED_CHECKS := 39

var failures := 0
var checks_run := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label_text: String) -> void:
	checks_run += 1
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func _run() -> void:
	var items := Catalog.valid_items()
	check(items.size() == 3, "initial catalog has exactly three products")

	var ids: Array[StringName] = []
	for item in items:
		ids.append(item.id)
	check(ids == [&"first_aid", &"ammo", &"mind_access_device"], "initial catalog keeps its product order")

	var first: ShopItemDefinition = Catalog.item_by_id(&"first_aid")
	check(first != null, "first aid is addressable by ID")
	if first != null:
		check(first.price == 40, "first aid price is 40")
		check(first.unlock_level == 0, "first aid is unlocked at level 0")
		check(first.effect == ItemScript.Effect.ADD_MEDKIT, "first aid adds medical inventory")
		check(first.amount == 1, "first aid grants one medkit per purchase")
		check(first.medkit_data == load("res://resources/player/default_medkit.tres"), "first aid references the existing medical resource")
		check(not first.one_time, "first aid is repeatable")

	var ammo := Catalog.item_by_id(&"ammo")
	check(ammo != null, "ammo is addressable by ID")
	if ammo != null:
		check(ammo.price == 30, "ammo price is 30")
		check(ammo.unlock_level == 0, "ammo is unlocked at level 0")
		check(ammo.effect == ItemScript.Effect.REFILL_AMMO, "ammo uses REFILL_AMMO")
		check(ammo.amount == 0, "ammo has no configured amount")
		check(not ammo.one_time, "ammo is repeatable")

	var device := Catalog.item_by_id(&"mind_access_device")
	check(device != null, "flag product is addressable by ID")
	if device != null:
		check(device.price == 500, "flag product costs 500 in one payment")
		check(device.unlock_level == 0, "flag product is unlocked at level 0")
		check(device.effect == ItemScript.Effect.SET_FLAG, "flag product uses SET_FLAG")
		check(device.flag_key == &"has_mind_access_device", "device grants its configured ownership flag")
		check(device.one_time, "flag product is a one-time product")

	var zero_medkit := ItemScript.new()
	zero_medkit.id = &"zero_medkit"
	zero_medkit.display_name = "Medkit product"
	zero_medkit.price = 10
	zero_medkit.effect = ItemScript.Effect.ADD_MEDKIT
	zero_medkit.medkit_data = load("res://resources/player/default_medkit.tres")
	zero_medkit.amount = 0
	check(not zero_medkit.is_valid(), "medkit products require a positive count")
	zero_medkit.amount = 1
	zero_medkit.medkit_data = null
	check(not zero_medkit.is_valid(), "medkit products require a medical resource")
	zero_medkit.medkit_data = MedkitData.new()
	zero_medkit.medkit_data.use_seconds = 0.0
	check(not zero_medkit.is_valid(), "invalid medical resource settings are rejected")
	zero_medkit.medkit_data = load("res://resources/player/default_medkit.tres")
	check(_visible(zero_medkit, &"medkit_data") and _visible(zero_medkit, &"amount")
		and not _visible(zero_medkit, &"weapon_data") and not _visible(zero_medkit, &"flag_key"),
		"medical products show only medical resource and quantity fields")
	zero_medkit.effect = ItemScript.Effect.WEAPON
	check(_visible(zero_medkit, &"weapon_data") and not _visible(zero_medkit, &"medkit_data")
		and not _visible(zero_medkit, &"amount") and not _visible(zero_medkit, &"flag_key"),
		"weapon products expose the WeaponData drag slot without medical fields")
	zero_medkit.effect = ItemScript.Effect.SET_FLAG
	check(_visible(zero_medkit, &"flag_key") and not _visible(zero_medkit, &"weapon_data")
		and not _visible(zero_medkit, &"medkit_data"), "flag products show only the flag configuration")
	zero_medkit.effect = ItemScript.Effect.REFILL_AMMO
	check(not _visible(zero_medkit, &"medkit_data") and not _visible(zero_medkit, &"weapon_data")
		and not _visible(zero_medkit, &"flag_key") and not _visible(zero_medkit, &"amount"),
		"ammo refill hides unrelated resource and quantity fields")
	check(zero_medkit.medkit_data == load("res://resources/player/default_medkit.tres"),
		"switching effects hides the drag slot without discarding its resource")
	var invalid_flag := ItemScript.new()
	invalid_flag.id = &"invalid_flag"
	invalid_flag.display_name = "Flag product"
	invalid_flag.price = 500
	invalid_flag.effect = ItemScript.Effect.SET_FLAG
	invalid_flag.one_time = true
	check(not invalid_flag.is_valid(), "flag products require a nonempty flag key")
	invalid_flag.flag_key = &"has_mind_access_device"
	invalid_flag.one_time = false
	check(not invalid_flag.is_valid(), "flag products require one-time purchase tracking")

	check(Catalog.item_by_id(&"first_aid") == items[0], "lookup returns the first valid product")
	check(Catalog.item_by_id(&"missing") == null, "unknown product ID returns null")
	check(Catalog.item_by_id(&"") == null, "empty product ID returns null")

	var gun := ItemScript.new()
	gun.id = &"rifle"
	gun.display_name = "Rifle"
	gun.price = 100
	gun.effect = ItemScript.Effect.WEAPON
	gun.weapon_data = preload("res://resources/weapons/test_rifle.tres")
	gun.one_time = true
	var duplicate := gun.duplicate()
	var catalog = CatalogScript.new()
	var weapon_items: Array[ShopItemDefinition] = [gun, duplicate]
	catalog.items = weapon_items
	var valid_weapons := catalog.valid_items()
	check(valid_weapons.size() == 1, "duplicate IDs are filtered")
	check(valid_weapons[0] == gun, "first duplicate ID wins")

	check(gun.is_valid(), "weapon product references WeaponData and is one-time")
	var missing_weapon := ItemScript.new()
	missing_weapon.id = &"missing_weapon"
	missing_weapon.display_name = "Missing Weapon"
	missing_weapon.price = 100
	missing_weapon.effect = ItemScript.Effect.WEAPON
	missing_weapon.one_time = true
	check(not missing_weapon.is_valid(), "weapon product requires WeaponData")
	gun.one_time = false
	check(not gun.is_valid(), "weapon product requires one-time purchase")

	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("check count: expected %d, got %d" % [EXPECTED_CHECKS, checks_run])
	if failures == 0:
		print("shop catalog checks: all passed")
	else:
		print("shop catalog checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)


func _visible(item: Resource, key: StringName) -> bool:
	for property in item.get_property_list():
		if StringName(property.name) == key:
			return (int(property.usage) & PROPERTY_USAGE_EDITOR) != 0
	return false
