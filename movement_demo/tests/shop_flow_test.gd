extends SceneTree

## Currency shop integration: NPC entry, board rows, effects, visibility,
## validation, and pause ownership through the real main scene.
## Run: godot --headless --path movement_demo --script res://tests/shop_flow_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const ShopControllerScript := preload("res://scripts/shop/shop_controller.gd")
const ShopCatalogScript := preload("res://scripts/shop/shop_catalog.gd")
const ShopItemScript := preload("res://scripts/shop/shop_item_definition.gd")
const Pauses := preload("res://scripts/systems/scene_pause_coordinator.gd")
const SHOTGUN := preload("res://resources/weapons/test_shotgun.tres")
const SMG := preload("res://resources/weapons/test_smg.tres")

const WATCHDOG_SECONDS := 50.0
const EXPECTED_CHECKS := 122


class FailingEffectController extends "res://scripts/shop/shop_controller.gd":
	var fail_item: StringName = &""
	var fail_once: bool = true

	func _apply_effect(state: Node, player: Node3D, item: ShopItemDefinition, slot: int) -> bool:
		if item.id == fail_item and fail_once:
			fail_once = false
			return false
		return super._apply_effect(state, player, item, slot)


var failures := 0
var checks_run := 0
var _finished := false


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
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)
	await _check_real_shop_flow()
	await _check_medkit_inventory_purchase()
	await _check_flag_product_purchase()
	await _check_zero_price_free_purchase()
	await _check_full_ammo_rejection()
	await _check_dead_player_rules()
	await _check_empty_or_locked_catalog()
	await _check_transaction_ordering()
	await _check_edge_failures()
	_finish()


func _check_real_shop_flow() -> void:
	var ctx := await _prepare_main()
	ctx.state.money = 1000
	check(ctx.controller != null, "ShopController is mounted")
	check(ctx.board != null, "ShopBoard is mounted")
	check(ctx.npc != null, "RewardNPC node path is retained")
	if ctx.controller == null or ctx.board == null or ctx.npc == null:
		await _release(ctx.scene)
		return

	check(str(ctx.npc.get_node("Name").text) == "商店", "blue NPC label becomes 商店")
	check(ctx.board.item_count() == 0, "board starts with no rows")
	check(await _open_shop_via_e(ctx), "E interaction opens the shop and pauses")
	check(ctx.board.item_count() == 3, "level 0 shows the three initial products")
	check(ctx.board.balance_text() == "货币：1000", "board shows current money")
	check(ctx.board.purchase_enabled(&"first_aid", -1), "full health still permits buying medkits")
	check(ctx.board.purchase_enabled(&"ammo", -1), "controller enables ammo while it is depleted")
	check(ctx.board.purchase_enabled(&"mind_access_device", -1),
		"controller marks flag product enabled before ownership")

	ctx.health.health = 20.0
	ctx.health._update_display()
	var health_before: float = ctx.health.health
	var medkits_before: int = ctx.equipment.medkit_count
	check(ctx.controller.purchase(&"first_aid", -1), "first aid purchase succeeds")
	check(ctx.equipment.medkit_count == medkits_before + 1 and is_equal_approx(ctx.health.health, health_before),
		"first aid adds one medkit without directly healing")
	check(ctx.state.money == 960, "first aid deducts 40")

	var money_before_ammo: int = ctx.state.money
	check(ctx.controller.purchase(&"ammo", -1), "ammo purchase succeeds")
	check(ctx.state.money == money_before_ammo - 30, "ammo deducts 30")
	check(ctx.equipment.reserve_ammo[&"rifle"] == ctx.equipment.starting_rifle_ammo
		and ctx.equipment.reserve_ammo[&"pistol"] == ctx.equipment.starting_pistol_ammo
		and ctx.equipment.reserve_ammo[&"smg"] == ctx.equipment.starting_smg_ammo
		and ctx.equipment.reserve_ammo[&"shotgun"] == ctx.equipment.starting_shotgun_ammo,
		"ammo restores every initial reserve type")
	check(_magazines_full(ctx.equipment), "ammo refills both magazines and cancels reload")

	check(ctx.controller.purchase(&"mind_access_device", -1), "flag product purchase succeeds")
	check(ctx.state.get_flag(&"has_mind_access_device"), "one purchase grants device ownership")
	check(ctx.state.money == 430, "flag product deducts 500 in one payment")
	check(ctx.state.has_purchased_shop_item(&"mind_access_device") and ctx.board.item_count() == 2,
		"flag product is recorded and hidden after purchase")
	check(not ctx.controller.purchase(&"mind_access_device", -1), "flag product cannot be purchased twice")
	check(ctx.state.money == 430 and ctx.state.get_flag(&"has_mind_access_device"),
		"repeat flag product purchase changes neither money nor ownership")

	ctx.health.health = 10.0
	ctx.health._update_display()
	check(ctx.controller.purchase(&"first_aid", -1), "repeatable first aid purchase succeeds again")
	check(ctx.equipment.medkit_count == medkits_before + 2 and is_equal_approx(ctx.health.health, 10.0),
		"repeat first aid adds another medkit without healing")
	check(ctx.state.money == 390, "repeat first aid deducts again")

	ctx.controller.close_shop()
	await ctx.tree.process_frame
	await ctx.tree.process_frame
	check(not ctx.board.visible and not ctx.tree.paused, "close_shop hides board and unpauses")

	var custom: ShopCatalog = preload("res://resources/shop/shop_catalog.tres").duplicate(true)
	custom.items.append(_weapon_item(&"shop_rifle_primary", SHOTGUN, 100, 1))
	custom.items.append(_weapon_item(&"shop_rifle_secondary", SMG, 120, 1))
	ctx.controller.shop_catalog = custom
	ctx.state.completed_level = 0
	ctx.state.purchased_shop_item_ids = {}
	await ctx.tree.process_frame

	check(await _open_shop_via_e(ctx), "shop reopens after catalog change")
	check(ctx.board.item_count() == 2, "locked weapons and the owned flag product stay hidden")

	ctx.controller.close_shop()
	await ctx.tree.process_frame
	ctx.state.completed_level = 1
	await ctx.tree.process_frame
	check(await _open_shop_via_e(ctx), "shop reopens at unlock level 1")
	check(ctx.board.item_count() == 4, "weapon rows appear at unlock level 1 while the owned flag stays hidden")

	var original_secondary: WeaponData = ctx.equipment.secondary_weapon
	var money_before_weapon: int = ctx.state.money
	check(ctx.controller.purchase(&"shop_rifle_primary", 0), "primary weapon purchase succeeds")
	check(ctx.equipment.primary_weapon == SHOTGUN, "slot 0 receives the purchased weapon")
	check(ctx.equipment.secondary_weapon == original_secondary, "slot 0 purchase preserves secondary")
	check(ctx.state.money == money_before_weapon - 100, "primary weapon deducts 100")
	check(ctx.state.has_purchased_shop_item(&"shop_rifle_primary"),
		"primary weapon purchase is recorded")
	check(ctx.board.item_count() == 3, "one-time primary row disappears after purchase")

	money_before_weapon = ctx.state.money
	check(ctx.controller.purchase(&"shop_rifle_secondary", 1), "secondary weapon purchase succeeds")
	check(ctx.equipment.secondary_weapon == SMG, "slot 1 receives the purchased weapon")
	check(ctx.equipment.primary_weapon == SHOTGUN, "slot 1 purchase preserves primary")
	check(ctx.state.money == money_before_weapon - 120, "secondary weapon deducts 120")
	check(ctx.state.has_purchased_shop_item(&"shop_rifle_secondary"),
		"secondary weapon purchase is recorded")
	check(ctx.board.item_count() == 2, "both one-time weapon rows disappear after purchase")

	var money_before_repeat: int = ctx.state.money
	check(not ctx.controller.purchase(&"shop_rifle_primary", 0), "repeat one-time weapon is rejected")
	check(ctx.state.money == money_before_repeat and ctx.equipment.primary_weapon == SHOTGUN,
		"repeat rejection changes neither money nor equipment")

	money_before_repeat = ctx.state.money
	check(not ctx.controller.purchase(&"shop_rifle_secondary", 2), "invalid weapon slot is rejected")
	check(ctx.state.money == money_before_repeat
		and ctx.equipment.secondary_weapon == SMG
		and ctx.equipment.primary_weapon == SHOTGUN,
		"invalid slot changes neither money nor equipment")

	ctx.state.money = 10
	ctx.health.health = 10.0
	ctx.health._update_display()
	var money_before_poor: int = ctx.state.money
	var stock_before_poor: int = ctx.equipment.medkit_count
	check(not ctx.controller.purchase(&"first_aid", -1), "insufficient funds are rejected")
	check(ctx.state.money == money_before_poor and ctx.equipment.medkit_count == stock_before_poor
		and is_equal_approx(ctx.health.health, 10.0),
		"insufficient funds change neither money, stock nor health")

	var pause_owner := Node.new()
	ctx.scene.add_child(pause_owner)
	var external: int = Pauses.for_tree(ctx.tree).acquire(pause_owner, &"external", false)
	check(external != 0 and ctx.tree.paused, "external pause can join the open shop pause")
	ctx.controller.close_shop()
	check(ctx.tree.paused and not ctx.board.visible,
		"closing shop releases only its own pause and keeps external pause")
	Pauses.for_tree(ctx.tree).release(external)
	check(not ctx.tree.paused, "releasing external pause restores the game")
	pause_owner.queue_free()

	await _release(ctx.scene)


func _check_medkit_inventory_purchase() -> void:
	var ctx := await _prepare_main(false)
	var stock_before: int = ctx.equipment.medkit_count
	var health_before: float = ctx.health.health
	var original_medkit: MedkitData = ctx.equipment.medkit
	var custom: ShopCatalog = preload("res://resources/shop/shop_catalog.tres").duplicate(true)
	var product: ShopItemDefinition = custom.item_by_id(&"first_aid")
	product.amount = 3
	product.medkit_data = original_medkit
	ctx.controller.shop_catalog = custom
	ctx.state.record_campaign_checkpoint(int(ctx.state.completed_level), PlayerCampaignState.capture(ctx.player))
	check(await _open_shop_via_e(ctx), "medkit shop opens at full health")
	check(ctx.board.purchase_enabled(&"first_aid", -1), "configured medkit bundle is available at full health")
	check(ctx.controller.purchase(&"first_aid", -1), "configured medkit bundle can be purchased")
	check(ctx.equipment.medkit_count == stock_before + 3 and is_equal_approx(ctx.health.health, health_before),
		"Amount configures medkit count without changing health")
	check(ctx.equipment.get_node("Panel/Content/MedkitCount").text.ends_with(str(stock_before + 3)),
		"existing medical stock label refreshes after purchase")
	var money_before: int = ctx.state.money
	ctx.equipment.name = "UnavailableEquipment"
	check(not ctx.controller.purchase(&"first_aid", -1), "missing inventory rejects medkit purchase")
	check(ctx.state.money == money_before and ctx.equipment.medkit_count == stock_before + 3,
		"missing inventory changes neither money nor stock")
	ctx.equipment.name = "Equipment"
	check(ctx.controller.purchase(&"first_aid", -1), "medkit bundles remain repeatable")
	check(ctx.equipment.medkit_count == stock_before + 6 and ctx.state.money == 420
		and is_equal_approx(ctx.health.health, health_before), "repeat bundle adds the configured count and charges again")
	ctx.controller.close_shop()
	var alternate := MedkitData.new()
	alternate.heal_amount = 75.0
	alternate.use_seconds = 1.0
	product.medkit_data = alternate
	check(await _open_shop_via_e(ctx) and not ctx.board.purchase_enabled(&"first_aid", -1),
		"a different medical resource does not overwrite existing stock")
	check(not ctx.controller.purchase(&"first_aid", -1) and ctx.state.money == 420
		and ctx.equipment.medkit == original_medkit and ctx.equipment.medkit_count == stock_before + 6,
		"incompatible medical resource changes neither stock nor money")
	ctx.controller.close_shop()
	ctx.equipment.medkit_count = 0
	check(await _open_shop_via_e(ctx), "empty inventory accepts a new medical resource")
	check(ctx.controller.purchase(&"first_aid", -1), "medical resource product can fill empty inventory")
	check(ctx.equipment.medkit == alternate and ctx.equipment.medkit_count == 3 and ctx.state.money == 380
		and is_equal_approx(ctx.health.health, health_before), "purchase binds the selected resource without instant healing")
	ctx.controller.close_shop()
	check(ctx.state.restore_campaign_checkpoint(), "checkpoint restore accepts the medical purchase snapshot")
	PlayerCampaignState.apply(ctx.player, ctx.state.take_pending_player_state())
	check(ctx.equipment.medkit_count == stock_before and ctx.equipment.medkit == original_medkit
		and ctx.state.money == 500 and is_equal_approx(ctx.health.health, health_before),
		"hotel refund restores medical resource, stock and money together")
	await _release(ctx.scene)


func _check_flag_product_purchase() -> void:
	var ctx := await _prepare_main(false)
	ctx.state.money = 499
	check(await _open_shop_via_e(ctx), "shop opens below the flag product price")
	check(not ctx.board.purchase_enabled(&"mind_access_device", -1), "499 cannot enable the 500 product")
	check(not ctx.controller.purchase(&"mind_access_device", -1), "partial payment is rejected")
	check(ctx.state.money == 499 and not ctx.state.get_flag(&"has_mind_access_device")
		and not ctx.state.has_purchased_shop_item(&"mind_access_device"),
		"partial payment changes neither money, ownership nor purchase records")
	ctx.controller.close_shop()
	ctx.state.money = 500
	ctx.state.set_flag(&"music_playing", false)
	ctx.state.record_campaign_checkpoint(int(ctx.state.completed_level), {})
	check(await _open_shop_via_e(ctx), "shop reopens with exactly 500")
	check(ctx.board.purchase_enabled(&"mind_access_device", -1), "exact price enables the product")
	check(ctx.controller.purchase(&"mind_access_device", -1), "exact price buys the complete product")
	check(ctx.state.money == 0 and ctx.state.get_flag(&"has_mind_access_device")
		and ctx.state.has_purchased_shop_item(&"mind_access_device") and ctx.board.item_count() == 2,
		"one payment sets the ownership flag and hides the product")
	ctx.controller.close_shop()
	ctx.state.set_flag(&"music_playing")
	check(ctx.state.restore_campaign_checkpoint(), "flag product purchase can roll back to its checkpoint")
	check(ctx.state.money == 500 and not ctx.state.get_flag(&"has_mind_access_device") and ctx.state.get_flag(&"music_playing")
		and not ctx.state.has_purchased_shop_item(&"mind_access_device"),
		"checkpoint refunds the full price and restores ownership and purchase eligibility")
	check(await _open_shop_via_e(ctx) and ctx.board.item_count() == 3
		and ctx.board.purchase_enabled(&"mind_access_device", -1),
		"refunded flag product becomes available again")
	await _release(ctx.scene)


func _check_zero_price_free_purchase() -> void:
	var ctx := await _prepare_main(false)
	var state: Node = ctx.state
	state.money = 0
	ctx.health.health = 10.0
	ctx.health._update_display()

	var catalog := ShopCatalogScript.new()
	var free_medkit := ShopItemScript.new()
	free_medkit.id = &"free_medkit"
	free_medkit.display_name = "免费急救"
	free_medkit.description = "免费获得 5 个医疗包"
	free_medkit.price = 0
	free_medkit.effect = ShopItemScript.Effect.ADD_MEDKIT
	free_medkit.amount = 5
	free_medkit.medkit_data = ctx.equipment.medkit
	var stock_before: int = ctx.equipment.medkit_count
	catalog.items.append(free_medkit)
	catalog.items.append(_weapon_item(&"free_weapon", SHOTGUN, 0, 0))
	ctx.controller.shop_catalog = catalog

	check(ctx.controller.open_shop_for_player(ctx.player), "zero-price shop opens")
	check(ctx.controller.purchase(&"free_medkit", -1), "zero-price consumable succeeds")
	check(ctx.equipment.medkit_count == stock_before + 5 and is_equal_approx(ctx.health.health, 10.0) and state.money == 0,
		"zero-price consumable applies without charging")
	check(ctx.controller.purchase(&"free_weapon", 0), "zero-price weapon succeeds")
	check(ctx.equipment.primary_weapon == SHOTGUN and state.money == 0,
		"zero-price weapon replaces slot without charging")
	check(state.has_purchased_shop_item(&"free_weapon"), "zero-price one-time weapon is recorded")

	await _release(ctx.scene)


func _check_full_ammo_rejection() -> void:
	var ctx := await _prepare_main(false)
	var state: Node = ctx.state
	state.money = 500
	check(ctx.equipment.has_method(&"can_refill_all_ammo"), "Equipment exposes can_refill_all_ammo")
	if ctx.equipment.has_method(&"can_refill_all_ammo"):
		check(ctx.equipment.can_refill_all_ammo(), "full ammo reports fully refilled")

	check(ctx.controller.open_shop_for_player(ctx.player), "full ammo shop opens")
	check(not ctx.board.purchase_enabled(&"ammo", -1), "controller disables ammo while already full")
	var money_before: int = state.money
	check(not ctx.controller.purchase(&"ammo", -1), "full ammo rejects ammo purchase")
	check(state.money == money_before, "full ammo rejection does not charge")

	ctx.equipment.reserve_ammo[&"rifle"] = 0
	if ctx.equipment.has_method(&"can_refill_all_ammo"):
		check(not ctx.equipment.can_refill_all_ammo(), "partial ammo reports missing")
	money_before = state.money
	check(ctx.controller.purchase(&"ammo", -1), "partial ammo purchase succeeds")
	check(state.money == money_before - 30 and ctx.equipment.reserve_ammo[&"rifle"] == ctx.equipment.starting_rifle_ammo,
		"partial ammo purchase charges once and restores the missing type")

	await _release(ctx.scene)


func _check_dead_player_rules() -> void:
	var dead_ctx := await _prepare_main(false)
	dead_ctx.health.receive_hit(dead_ctx.health.max_health * 10.0)
	await dead_ctx.tree.process_frame
	await dead_ctx.tree.process_frame
	check(dead_ctx.player.is_dead(), "player is dead before opening shop")
	check(not dead_ctx.controller.open_shop_for_player(dead_ctx.player), "dead player cannot open shop")
	check(not dead_ctx.board.visible, "dead player does not show the shop")
	await _release(dead_ctx.scene)

	var open_ctx := await _prepare_main(false)
	check(open_ctx.controller.open_shop_for_player(open_ctx.player), "alive player opens shop")
	check(open_ctx.board.visible and open_ctx.tree.paused, "alive shop is visible and paused")
	open_ctx.health.receive_hit(open_ctx.health.max_health * 10.0)
	await open_ctx.tree.process_frame
	await open_ctx.tree.process_frame
	check(not open_ctx.board.visible, "shop closes when the player dies")
	check(open_ctx.tree.paused, "death pause remains after shop closes")
	await _release(open_ctx.scene)


func _check_empty_or_locked_catalog() -> void:
	var ctx := await _prepare_main(false)
	var money_before: int = ctx.state.money

	var controller := ShopControllerScript.new()
	controller.shop_catalog = ShopCatalogScript.new()
	controller.shop_board_path = NodePath("../ShopBoard")
	ctx.scene.add_child(controller)
	await process_frame

	check(controller.open_shop_for_player(ctx.player), "valid empty catalog opens the board")
	check(ctx.board.visible, "empty catalog board is visible")
	check(not ctx.tree.paused, "empty catalog does not acquire a pause token")
	check(ctx.board.item_count() == 0, "empty catalog renders no rows")
	check(str(ctx.board.result_label.text) == "暂无商品", "empty catalog shows the empty-catalog text")
	check(int(ctx.state.money) == money_before, "empty catalog does not mutate money")
	controller.close_shop()
	check(not ctx.board.visible and not ctx.tree.paused,
		"closing an empty shop is safe without a pause token")

	var locked_catalog := ShopCatalogScript.new()
	locked_catalog.items.append(_weapon_item(&"locked_weapon", SHOTGUN, 100, 5))
	controller.shop_catalog = locked_catalog
	ctx.state.completed_level = 0
	await process_frame
	check(controller.open_shop_for_player(ctx.player), "all-locked catalog opens the board")
	check(ctx.board.item_count() == 0 and not ctx.tree.paused,
		"all-locked catalog shows an empty, unpaused board")
	controller.close_shop()
	controller.queue_free()
	await process_frame

	await _release(ctx.scene)


func _check_transaction_ordering() -> void:
	var ctx := await _prepare_main(false)
	var state: Node = ctx.state
	state.money = 500
	ctx.health.health = 10.0
	ctx.health._update_display()

	var catalog := ShopCatalogScript.new()
	var failing_medkit := ShopItemScript.new()
	failing_medkit.id = &"failing_medkit"
	failing_medkit.display_name = "失败急救"
	failing_medkit.description = "应用阶段会失败，用于验证退款顺序"
	failing_medkit.price = 40
	failing_medkit.effect = ShopItemScript.Effect.ADD_MEDKIT
	failing_medkit.amount = 2
	failing_medkit.medkit_data = ctx.equipment.medkit
	failing_medkit.one_time = true
	catalog.items.append(failing_medkit)

	var controller := FailingEffectController.new()
	controller.shop_catalog = catalog
	controller.shop_board_path = NodePath("../ShopBoard")
	controller.fail_item = &"failing_medkit"
	ctx.scene.add_child(controller)
	await process_frame

	check(controller.open_shop_for_player(ctx.player), "failing-effect controller opens the shop")
	var money_before: int = state.money
	var health_before: float = ctx.health.health
	var stock_before: int = ctx.equipment.medkit_count
	check(not controller.purchase(&"failing_medkit", -1), "unexpected effect failure rejects the purchase")
	check(state.money == money_before, "paid purchase refunds the exact amount after an unexpected failure")
	check(ctx.equipment.medkit_count == stock_before and is_equal_approx(ctx.health.health, health_before), "failed purchase mutates neither stock nor health")
	check(not state.has_purchased_shop_item(&"failing_medkit"),
		"failed one-time purchase is not marked purchased")

	controller.close_shop()
	controller.queue_free()
	await process_frame
	await _release(ctx.scene)


func _check_edge_failures() -> void:
	var ctx := await _prepare_main()
	var money_before: int = ctx.state.money
	check(not ctx.controller.open_shop_for_player(null), "missing player is rejected")
	check(not ctx.tree.paused and ctx.state.money == money_before,
		"missing player does not pause or mutate")

	var missing_board := ShopControllerScript.new()
	missing_board.shop_catalog = preload("res://resources/shop/shop_catalog.tres")
	missing_board.shop_board_path = NodePath()
	ctx.scene.add_child(missing_board)
	await process_frame
	check(not missing_board.open_shop_for_player(ctx.player), "missing board is rejected")
	check(not ctx.tree.paused and ctx.state.money == money_before,
		"missing board does not pause or mutate")
	missing_board.queue_free()
	await process_frame

	var missing_catalog := ShopControllerScript.new()
	missing_catalog.shop_board_path = NodePath("../ShopBoard")
	ctx.scene.add_child(missing_catalog)
	await process_frame
	check(not missing_catalog.open_shop_for_player(ctx.player), "missing catalog is rejected")
	check(not ctx.tree.paused and ctx.state.money == money_before,
		"missing catalog does not pause or mutate")
	missing_catalog.queue_free()
	await process_frame

	await _release(ctx.scene)


func _prepare_main(deplete: bool = true) -> Dictionary:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	var tree := scene.get_tree()
	await tree.process_frame
	await tree.process_frame

	var state: Node = root.get_node("GameState")
	var player: CharacterBody3D = scene.get_node("Player")
	var npc: Node3D = scene.get_node("RewardNPC")
	var equipment: Node = player.get_node("Equipment")
	state.money = 500
	state.completed_level = 0
	state.available_level = 1
	state.purchased_shop_item_ids = {}
	state.rewarded_task_ids = {}
	state.clear_interaction_state()
	if deplete:
		_deplete_ammo(equipment)
	else:
		_ensure_ammo_states(equipment)
	player.set_physics_process(false)
	player.global_position = npc.global_position + Vector3(0.0, 0.0, 0.9)
	for _frame in range(8):
		await tree.physics_frame
	return {
		"scene": scene,
		"tree": tree,
		"state": state,
		"controller": scene.get_node_or_null("ShopController"),
		"board": scene.get_node_or_null("ShopBoard"),
		"player": player,
		"npc": npc,
		"health": player.get_node("Health"),
		"equipment": equipment,
	}


func _open_shop_via_e(ctx: Dictionary) -> bool:
	_press_interact()
	for _frame in range(8):
		await ctx.tree.process_frame
	return bool(ctx.board.visible) and bool(ctx.tree.paused)


func _weapon_item(item_id: StringName, weapon: WeaponData, price: int, unlock_level: int) -> ShopItemDefinition:
	var item := ShopItemScript.new()
	item.id = item_id
	item.display_name = "商店武器 " + str(item_id)
	item.description = "覆盖所选武器槽"
	item.price = price
	item.unlock_level = unlock_level
	item.effect = ShopItemScript.Effect.WEAPON
	item.weapon_data = weapon
	item.one_time = true
	return item


func _deplete_ammo(equipment: Node) -> void:
	if equipment.has_method(&"select_slot"):
		equipment.select_slot(1)
		equipment.select_slot(0)
	for slot in range(2):
		var ammo_state = equipment.get("_ammo_states")[slot]
		if ammo_state != null:
			ammo_state.magazine_rounds = 0
			ammo_state.is_reloading = true
	for ammo_type in equipment.reserve_ammo.keys():
		equipment.reserve_ammo[ammo_type] = 0


func _ensure_ammo_states(equipment: Node) -> void:
	if equipment.has_method(&"select_slot"):
		equipment.select_slot(1)
		equipment.select_slot(0)


func _magazines_full(equipment: Node) -> bool:
	for slot in range(2):
		var data = equipment.call("_weapon_at", slot)
		var ammo_state = equipment.get("_ammo_states")[slot]
		if data != null and (ammo_state == null or ammo_state.magazine_rounds != data.magazine_capacity or ammo_state.is_reloading):
			return false
	return true


func _press_interact() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	Input.flush_buffered_events()


func _release(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.get_tree().paused = false
		scene.queue_free()
	current_scene = null
	await process_frame


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(current_scene):
		current_scene.get_tree().paused = false
	push_error("shop flow test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(current_scene):
		current_scene.get_tree().paused = false
		current_scene.queue_free()
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("check count: expected %d, got %d" % [EXPECTED_CHECKS, checks_run])
	if failures == 0:
		print("shop flow checks: all passed")
	else:
		print("shop flow checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
