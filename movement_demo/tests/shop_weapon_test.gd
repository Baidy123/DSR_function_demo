extends SceneTree

## Shop-purchased weapon slot replacement and current-level retry.
## Run: /Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_weapon_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")
const LEVEL_2 := "res://scenes/world/levels/lvl_2.tscn"
const SHOTGUN := preload("res://resources/weapons/test_shotgun.tres")
const SMG := preload("res://resources/weapons/test_smg.tres")
const MELEE := preload("res://resources/weapons/enemy_test_melee.tres")

const WATCHDOG_SECONDS := 40.0
const EXPECTED_CHECKS := 27

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
	await _check_equipment_replacement_and_retry_snapshot()
	await _check_real_level_retry_preserves_paid_weapon()
	_finish()


func _check_equipment_replacement_and_retry_snapshot() -> void:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var player: CharacterBody3D = scene.get_node("Player")
	var equipment: CanvasLayer = player.get_node("Equipment")
	var health: CanvasLayer = player.get_node("Health")
	var state: Node = root.get_node("GameState")
	state.pending_player_state = {}
	state.level_entry_player_state = {}

	check(equipment.has_method(&"replace_weapon_slot"),
		"Equipment exposes replace_weapon_slot")
	if not equipment.has_method(&"replace_weapon_slot"):
		await _release(scene)
		return

	var shotgun: WeaponData = SHOTGUN
	var smg: WeaponData = SMG
	var melee: WeaponData = MELEE
	var original_primary: WeaponData = equipment.primary_weapon
	var original_secondary: WeaponData = equipment.secondary_weapon
	var original_medkit: MedkitData = equipment.medkit
	var original_medkit_count: int = equipment.medkit_count

	equipment.reserve_ammo[&"rifle"] = 11
	equipment.reserve_ammo[&"pistol"] = 7
	equipment.reserve_ammo[&"smg"] = 9
	equipment.reserve_ammo[&"shotgun"] = 2
	var original_reserve: Dictionary = equipment.reserve_ammo.duplicate()
	var original_health: float = health.health

	check(not equipment.replace_weapon_slot(-1, smg),
		"replace_weapon_slot rejects an out-of-range slot")
	check(not equipment.replace_weapon_slot(2, smg),
		"replace_weapon_slot rejects an out-of-range upper slot")
	check(not equipment.replace_weapon_slot(0, null),
		"replace_weapon_slot rejects a null weapon")
	check(not equipment.replace_weapon_slot(0, melee),
		"replace_weapon_slot rejects a dedicated melee weapon")

	check(equipment.replace_weapon_slot(0, shotgun),
		"replace_weapon_slot accepts slot 0")
	check(equipment.primary_weapon == shotgun,
		"slot 0 replacement updates the primary weapon")
	check(equipment.secondary_weapon == original_secondary,
		"slot 0 replacement preserves the secondary weapon")
	check(equipment.reserve_ammo == original_reserve,
		"slot 0 replacement preserves shared reserve ammo")
	check(equipment.medkit == original_medkit and equipment.medkit_count == original_medkit_count,
		"slot 0 replacement preserves the medkit")
	check(equipment._ammo_states[0] != null
			and equipment._ammo_states[0].magazine_rounds == shotgun.magazine_capacity,
		"target slot starts with a full magazine")
	check(is_equal_approx(health.health, original_health),
		"slot replacement preserves unrelated player health")

	check(equipment.replace_weapon_slot(0, original_primary),
		"replace_weapon_slot restores the original primary weapon")
	check(equipment.replace_weapon_slot(1, smg),
		"replace_weapon_slot accepts slot 1")
	check(equipment.secondary_weapon == smg and equipment.primary_weapon == original_primary,
		"slot 1 replacement preserves the primary weapon")
	check(equipment.reserve_ammo == original_reserve,
		"slot 1 replacement preserves shared reserve ammo")

	equipment.replace_weapon_slot(1, original_secondary)
	state.set_level_entry_player_state(equipment.campaign_snapshot())
	equipment.replace_weapon_slot(0, smg)
	check(state.prepare_level_retry_state()
			and state.pending_player_state != equipment.campaign_snapshot(),
		"retry snapshot is staged independently of current equipment")
	await _release(scene)


func _check_real_level_retry_preserves_paid_weapon() -> void:
	var state: Node = root.get_node("GameState")
	state.completed_level = 1
	state.available_level = 2
	state.pending_player_state = {}
	state.level_entry_player_state = {}
	state.campaign_checkpoint = {}

	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var player: CharacterBody3D = scene.get_node("Player")
	var equipment: CanvasLayer = player.get_node("Equipment")
	var paid_weapon: WeaponData = SHOTGUN
	if not equipment.has_method(&"replace_weapon_slot"):
		check(false, "real-level retry requires replace_weapon_slot")
		await _release(scene)
		return
	check(equipment.replace_weapon_slot(0, paid_weapon),
		"purchase replaces the primary slot before entering level 2")

	var portal = scene.get_node("Interactables/LevelPortal")
	check(portal.interact(player), "level 2 portal accepts the purchased loadout")
	var entry_state: Dictionary = state.level_entry_player_state
	var entry_equipment: Dictionary = entry_state.get("equipment", {})
	check(entry_equipment.get("primary_weapon") == paid_weapon,
		"QuestPortal records the purchased loadout at level entry")

	scene = await _wait_for_scene(LEVEL_2)
	check(scene != null, "level 2 loads after the purchase")
	if scene == null:
		await _release(scene)
		return
	await _close_level_guide(scene)
	player = scene.get_node("Player")
	equipment = player.get_node("Equipment")
	check(equipment.primary_weapon == paid_weapon,
		"entering level 2 carries the purchased weapon")

	var health: CanvasLayer = player.get_node("Health")
	health.receive_hit(health.max_health)
	check(player.is_dead() and paused, "death in level 2 pauses for retry")
	var restart_button: Button = health.get_node("DeathScreen/Center/Panel/Content/Restart")
	check(restart_button.can_process(), "current-level restart button is processable")
	restart_button.pressed.emit()

	scene = await _wait_for_scene(LEVEL_2)
	check(scene != null, "current-level retry reloads level 2")
	if scene == null:
		await _release(scene)
		return
	player = scene.get_node("Player")
	equipment = player.get_node("Equipment")
	check(equipment.primary_weapon == paid_weapon,
		"current-level retry preserves the purchased weapon")
	check(state.pending_player_state.is_empty(),
		"current-level retry consumes the staged entry state")
	await _release(scene)


func _close_level_guide(scene: Node) -> void:
	var guide = scene.get_node("LevelFlow/PlayGuide")
	if guide.visible:
		guide.get_node("Backdrop/Panel/Content/Close").pressed.emit()
	await process_frame
	await process_frame


func _wait_for_scene(path: String) -> Node:
	for _frame in range(180):
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			await process_frame
			await process_frame
			return current_scene
		await process_frame
	return null


func _release(scene: Node) -> void:
	paused = false
	if is_instance_valid(scene):
		scene.queue_free()
	current_scene = null
	await process_frame


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	push_error("shop weapon test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("check count: expected %d, got %d" % [EXPECTED_CHECKS, checks_run])
	if failures == 0:
		print("shop weapon checks: all passed")
	else:
		print("shop weapon checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
