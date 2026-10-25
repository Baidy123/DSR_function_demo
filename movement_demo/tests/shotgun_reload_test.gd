extends SceneTree

const Ammo = preload("res://scripts/weapons/weapon_ammo.gd")
var checks := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	_ammo()
	await _actors()
	print("SHOTGUN RELOAD: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func _gun() -> WeaponData:
	var gun := WeaponData.new()
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	gun.ammo_type = WeaponData.AmmoType.SHOTGUN
	gun.magazine_capacity = 6
	gun.aim_range = 18
	gun.reload_seconds = 9
	gun.shot_noise = null
	gun.shotgun.shell_by_shell_reload = true
	gun.shotgun.shell_reload_seconds = 0.5
	return gun

func _ammo() -> void:
	var gun := _gun()
	var pool := {WeaponData.AmmoType.SHOTGUN: 10}
	var ammo := Ammo.new(gun, pool)
	ammo.magazine_rounds = 0
	check(ammo.start_reload() and is_equal_approx(ammo.reload_remaining_seconds(), 3), "Empty tube predicts six insertions using the shell time")
	ammo.advance_reload(0.49)
	check(ammo.magazine_rounds == 0 and pool[3] == 10, "An unfinished shell is neither loaded nor charged")
	ammo.advance_reload(0.01)
	check(ammo.magazine_rounds == 1 and pool[3] == 9 and ammo.is_reloading and is_zero_approx(ammo.reload_progress), "First completed shell loads exactly one and restarts per-shell progress")
	ammo.advance_reload(1.25)
	check(ammo.magazine_rounds == 3 and pool[3] == 7 and is_equal_approx(ammo.reload_progress, 0.5), "A long frame preserves completed shells and the next shell fraction")
	check(is_equal_approx(ammo.reload_remaining_seconds(), 1.25) and is_equal_approx(ammo.reload_remaining_seconds(false), 1.5), "Remaining and interrupted reload estimates use actual missing shells")
	ammo.cancel_reload()
	check(ammo.magazine_rounds == 3 and ammo.can_fire() and ammo.reload_progress == 0 and pool[3] == 7, "Cancel retains completed shells and discards unfinished progress")
	ammo.start_reload()
	ammo.advance_reload(100)
	check(ammo.magazine_rounds == 6 and pool[3] == 4 and not ammo.is_reloading, "Large elapsed time cannot overfill or overcharge")
	ammo.magazine_rounds = 0
	pool[3] = 2
	ammo.start_reload()
	ammo.advance_reload(1)
	check(ammo.magazine_rounds == 2 and pool[3] == 0 and not ammo.is_reloading and ammo.can_fire(), "Reserve exhaustion finishes reload and keeps loaded rounds usable")
	pool[3] = 2
	ammo.start_reload()
	pool[3] = 0
	ammo.advance_reload(0)
	check(not ammo.is_reloading and ammo.magazine_rounds == 2, "Another weapon draining the shared pool cannot leave a stuck reload")
	var unlimited := Ammo.new(gun, {}, true)
	unlimited.magazine_rounds = 0
	unlimited.start_reload()
	unlimited.advance_reload(0.5, 0.5)
	check(unlimited.magazine_rounds == 0 and is_equal_approx(unlimited.reload_progress, 0.5), "Slow reload multiplier applies to each shell")
	unlimited.advance_reload(0.5, 0.5)
	check(unlimited.magazine_rounds == 1 and unlimited.is_reloading, "Unlimited enemy reserve still loads one shell at a time")
	gun.shotgun.shell_by_shell_reload = false
	var normal := Ammo.new(gun, {}, true)
	normal.magazine_rounds = 0
	normal.start_reload()
	normal.advance_reload(0.5)
	check(normal.magazine_rounds == 0 and normal.is_reloading, "Disabled option keeps original whole-magazine timing")
	normal.advance_reload(8.5)
	check(normal.magazine_rounds == 6 and not normal.is_reloading, "Disabled option still refills the whole magazine on completion")
	gun.shotgun.shell_by_shell_reload = true
	gun.fire_mode = WeaponData.FireMode.SEMI_AUTO
	check(not normal.reloads_one_shell_at_a_time(), "Stored shotgun settings do not affect original fire modes")
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	DirAccess.make_dir_recursive_absolute("res://logs/shotgun_reload")
	var error := ResourceSaver.save(gun, "res://logs/shotgun_reload/gun.tres")
	var restored = ResourceLoader.load("res://logs/shotgun_reload/gun.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(error == OK and restored.shotgun.shell_by_shell_reload and restored.shotgun.shell_reload_seconds == 0.5, "Reload settings save and reload with the existing weapon resource")

func _actors() -> void:
	var scene = load("res://scenes/presentation/shotgun_range.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var combat = player.get_node("Combat")
	combat.sprint_reload_speed_multiplier = 0.5 # 本用例固定倍率，不改玩家预制的实际调参。
	var equipment = player.get_node("Equipment")
	var gun := _gun()
	equipment.primary_weapon = gun
	equipment.select_slot(0)
	equipment.reserve_ammo[3] = 30
	combat.ammo.magazine_rounds = 0
	for frame in 5: await physics_frame
	Input.action_press("aim")
	_press(combat, &"reload")
	check(combat.ammo.is_reloading and combat.accuracy == 0, "Actual R input starts tube reload and applies original stability rules")
	combat.end_frame(0.2, false)
	_press(combat, &"fire")
	check(combat.ammo.is_reloading and combat.ammo.magazine_rounds == 0, "Empty trigger cannot interrupt before the first shell is loaded")
	combat.end_frame(0.3, false)
	equipment._update_display()
	check(combat.ammo.magazine_rounds == 1 and equipment.get_node("Panel/Content/Hint").text.contains("逐发"), "Player HUD shows per-shell reload and live ammunition")
	var before: int = combat.shot_count
	_press(combat, &"fire")
	combat.begin_frame(0, true)
	combat.end_frame(0, false)
	check(not combat.ammo.is_reloading and combat.shot_count == before + 1 and combat.ammo.magazine_rounds == 0, "A fresh aimed trigger interrupts reload and fires one loaded shell")
	_release(combat)
	combat.request_reload()
	combat.end_frame(0.8, false)
	var first = combat.ammo
	equipment.select_slot(1)
	check(not first.is_reloading and first.magazine_rounds == 1 and first.reload_checkpoint == 0 and first.reload_progress == 0, "Switching cancels only the unfinished shell and retains completed ammunition")
	equipment.select_slot(0)
	check(not first.is_reloading and first.can_fire(), "Switching back does not force a half-magazine reload checkpoint")
	combat.request_reload()
	combat.end_frame(0.3, false)
	player.is_sprinting = true
	combat.end_frame(0.1, true)
	check(not first.is_reloading and first.magazine_rounds == 1 and first.reload_checkpoint == 0, "Sprinting interrupts fast shell reload without consuming the partial shell")
	combat.request_reload()
	combat.end_frame(0.5, true)
	check(first.magazine_rounds == 1 and is_equal_approx(first.reload_progress, 0.5), "Starting reload while sprinting uses the existing slow multiplier")
	player.is_sprinting = false
	combat.end_frame(0.5, false)
	check(first.magazine_rounds == 2 and first.is_reloading and combat.is_slow_reload(), "Stopping sprint keeps the selected slow pace for the reload")
	paused = true
	combat.end_frame(4, false)
	check(first.magazine_rounds == 2 and is_zero_approx(first.reload_progress), "World pause does not advance shell insertion")
	paused = false
	player.set_dialogue_active(true)
	check(not first.is_reloading and first.magazine_rounds == 2, "Dialogue cancels insertion while preserving completed ammunition")
	player.set_dialogue_active(false)
	combat.request_reload()
	combat.end_frame(0.2, false)
	check(first.is_reloading, "Holding aim before R does not immediately cancel tube reload")
	Input.action_release("aim")
	var aim_button := InputEventMouseButton.new()
	aim_button.button_index = MOUSE_BUTTON_RIGHT
	aim_button.pressed = true
	var reserve_before: int = first.reserve_count()
	before = combat.shot_count
	combat._unhandled_input(aim_button)
	Input.action_press("aim")
	combat.begin_frame(0, true)
	check(not first.is_reloading and first.magazine_rounds == 2 and first.reserve_count() == reserve_before and first.reload_progress == 0, "Right mouse interrupts a partial shell without losing loaded rounds or consuming reserve")
	check(combat.is_aiming and combat.shot_count == before and not combat.shot_requested, "Right mouse resumes normal aiming without firing a shell")
	combat.ammo.magazine_rounds = 0
	combat.request_reload()
	combat.end_frame(0.5, false)
	combat._unhandled_input(aim_button)
	check(not first.is_reloading and first.magazine_rounds == 1, "Right mouse also interrupts exactly between completed shells")
	combat.ammo.magazine_rounds = 0
	combat.request_reload()
	combat.end_frame(0.1, false)
	combat._unhandled_input(aim_button)
	check(not first.is_reloading and first.magazine_rounds == 0, "Right mouse can cancel an empty tube without creating a round")
	var original = equipment.secondary_weapon
	equipment.select_slot(1)
	combat.ammo.magazine_rounds = 0
	combat.request_reload()
	combat._unhandled_input(aim_button)
	check(combat.weapon == original and combat.ammo.is_reloading, "Right mouse keeps the original non-shotgun reload behavior")
	combat.cancel_reload()
	Input.action_release("aim")
	var enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
	enemy.weapon = gun
	enemy.get_node("AI").process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.shooting_enabled = true
	enemy.ammo.magazine_rounds = 0
	check(enemy.request_reload(), "Real enemy can start the same tube reload")
	enemy.update_weapon(0.5)
	check(enemy.ammo.magazine_rounds == 1 and enemy.ammo.is_reloading and not enemy.can_fire(), "Enemy inserts a shell without ending its ongoing reload")
	check(enemy.get_node("Label").text.contains("逐发") and enemy.get_node("Label").text.contains("2.5"), "Enemy status displays actual whole-tube remaining time")
	var action = preload("res://scripts/enemy/actions/enemy_reload_action.gd").new()
	action.context = {"actor": enemy}
	check(is_equal_approx(action._reload_seconds(), 2.5), "Existing reload planning reads the new actual remaining duration")
	enemy.cancel_reload()
	check(enemy.ammo.magazine_rounds == 1 and enemy.ammo.can_fire(), "Enemy interruption preserves loaded shells")
	enemy.request_reload()
	enemy.update_weapon(2.5)
	check(enemy.ammo.magazine_rounds == 6 and not enemy.ammo.is_reloading, "Enemy reload naturally ends at full capacity")
	action.context = null
	scene.queue_free()
	await process_frame

func _press(combat: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	combat._unhandled_input(event)

func _release(combat: Node) -> void:
	var event := InputEventAction.new()
	event.action = &"fire"
	combat._unhandled_input(event)
