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
const EXPECTED_CHECKS := 92


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
	await _check_zero_price_free_purchase()
	await _check_full_ammo_rejection()
	await _check_dead_player_rules()
	await _check_empty_or_locked_catalog()
	await _check_transaction_ordering()
	await _check_edge_failures()
	_finish()


func _check_real_shop_flow() -> void:
	var ctx := await _prepare_main()
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
	check(ctx.board.balance_text() == "货币：500", "board shows current money")
	check(not ctx.board.purchase_enabled(&"first_aid", -1), "controller disables first aid while health is full")
	check(ctx.board.purchase_enabled(&"ammo", -1), "controller enables ammo while it is depleted")
	check(ctx.board.purchase_enabled(&"system_progress", -1),
		"controller marks system progress enabled before it reaches maximum")

	ctx.health.health = 20.0
	ctx.health._update_display()
	var health_before: float = ctx.health.health
	check(ctx.controller.purchase(&"first_aid", -1), "first aid purchase succeeds")
	check(is_equal_approx(ctx.health.health, minf(ctx.health.max_health, health_before + 35.0)),
		"first aid heals 35")
	check(ctx.state.money == 460, "first aid deducts 40")

	var money_before_ammo: int = ctx.state.money
	check(ctx.controller.purchase(&"ammo", -1), "ammo purchase succeeds")
	check(ctx.state.money == money_before_ammo - 30, "ammo deducts 30")
	check(ctx.equipment.reserve_ammo[&"rifle"] == ctx.equipment.starting_rifle_ammo
		and ctx.equipment.reserve_ammo[&"pistol"] == ctx.equipment.starting_pistol_ammo
		and ctx.equipment.reserve_ammo[&"smg"] == ctx.equipment.starting_smg_ammo
		and ctx.equipment.reserve_ammo[&"shotgun"] == ctx.equipment.starting_shotgun_ammo,
		"ammo restores every initial reserve type")
	check(_magazines_full(ctx.equipment), "ammo refills both magazines and cancels reload")

	check(ctx.controller.purchase(&"system_progress", -1), "system progress purchase succeeds")
	check(int(ctx.state.system_progress) == 20, "system progress adds 20")
	check(ctx.state.money == 380, "system progress deducts 50")

	ctx.health.health = 10.0
	ctx.health._update_display()
	check(ctx.controller.purchase(&"first_aid", -1), "repeatable first aid purchase succeeds again")
	check(is_equal_approx(ctx.health.health, 45.0), "repeat first aid heals again")
	check(ctx.state.money == 340, "repeat first aid deducts again")

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
	check(ctx.board.item_count() == 3, "weapon rows stay hidden before unlock level")

	ctx.controller.close_shop()
	await ctx.tree.process_frame
	ctx.state.completed_level = 1
	await ctx.tree.process_frame
	check(await _open_shop_via_e(ctx), "shop reopens at unlock level 1")
	check(ctx.board.item_count() == 5, "weapon rows appear at unlock level 1")

	var original_secondary: WeaponData = ctx.equipment.secondary_weapon
	var money_before_weapon: int = ctx.state.money
	check(ctx.controller.purchase(&"shop_rifle_primary", 0), "primary weapon purchase succeeds")
	check(ctx.equipment.primary_weapon == SHOTGUN, "slot 0 receives the purchased weapon")
	check(ctx.equipment.secondary_weapon == original_secondary, "slot 0 purchase preserves secondary")
	check(ctx.state.money == money_before_weapon - 100, "primary weapon deducts 100")
	check(ctx.state.has_purchased_shop_item(&"shop_rifle_primary"),
		"primary weapon purchase is recorded")
	check(ctx.board.item_count() == 4, "one-time primary row disappears after purchase")

	money_before_weapon = ctx.state.money
	check(ctx.controller.purchase(&"shop_rifle_secondary", 1), "secondary weapon purchase succeeds")
	check(ctx.equipment.secondary_weapon == SMG, "slot 1 receives the purchased weapon")
	check(ctx.equipment.primary_weapon == SHOTGUN, "slot 1 purchase preserves primary")
	check(ctx.state.money == money_before_weapon - 120, "secondary weapon deducts 120")
	check(ctx.state.has_purchased_shop_item(&"shop_rifle_secondary"),
		"secondary weapon purchase is recorded")
	check(ctx.board.item_count() == 3, "both one-time weapon rows disappear after purchase")

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
	check(not ctx.controller.purchase(&"first_aid", -1), "insufficient funds are rejected")
	check(ctx.state.money == money_before_poor and is_equal_approx(ctx.health.health, 10.0),
		"insufficient funds change neither money nor health")

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


func _check_zero_price_free_purchase() -> void:
	var ctx := await _prepare_main(false)
	var state: Node = ctx.state
	state.money = 0
	ctx.health.health = 10.0
	ctx.health._update_display()

	var catalog := ShopCatalogScript.new()
	var free_heal := ShopItemScript.new()
	free_heal.id = &"free_heal"
	free_heal.display_name = "免费急救"
	free_heal.description = "免费恢复 5 点生命"
	free_heal.price = 0
	free_heal.effect = ShopItemScript.Effect.HEAL
	free_heal.amount = 5
	catalog.items.append(free_heal)
	catalog.items.append(_weapon_item(&"free_weapon", SHOTGUN, 0, 0))
	ctx.controller.shop_catalog = catalog

	check(ctx.controller.open_shop_for_player(ctx.player), "zero-price shop opens")
	check(ctx.controller.purchase(&"free_heal", -1), "zero-price consumable succeeds")
	check(is_equal_approx(ctx.health.health, 15.0) and state.money == 0,
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
	var failing_heal := ShopItemScript.new()
	failing_heal.id = &"failing_heal"
	failing_heal.display_name = "失败急救"
	failing_heal.description = "应用阶段会失败，用于验证退款顺序"
	failing_heal.price = 40
	failing_heal.effect = ShopItemScript.Effect.HEAL
	failing_heal.amount = 35
	failing_heal.one_time = true
	catalog.items.append(failing_heal)

	var controller := FailingEffectController.new()
	controller.shop_catalog = catalog
	controller.shop_board_path = NodePath("../ShopBoard")
	controller.fail_item = &"failing_heal"
	ctx.scene.add_child(controller)
	await process_frame

	check(controller.open_shop_for_player(ctx.player), "failing-effect controller opens the shop")
	var money_before: int = state.money
	var health_before: float = ctx.health.health
	check(not controller.purchase(&"failing_heal", -1), "unexpected effect failure rejects the purchase")
	check(state.money == money_before, "paid purchase refunds the exact amount after an unexpected failure")
	check(is_equal_approx(ctx.health.health, health_before), "failed purchase does not mutate player health")
	check(not state.has_purchased_shop_item(&"failing_heal"),
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
	state.system_progress = 0
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
