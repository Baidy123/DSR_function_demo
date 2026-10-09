extends SceneTree

var checks := 0
var failed := 0
var scene
var player
var health
var medkit

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	scene = packed.instantiate()
	scene.get_node("Player/Health").max_health = 100.0
	scene.get_node("Player/Health").debug_mode = false
	root.add_child(scene)
	current_scene = scene
	_bind()
	await _frames(15)
	_check("real Main has the medical module and original node paths", medkit != null and player.has_node("Combat") and player.has_node("WeaponSlots") and player.has_node("Visual/Body"))
	player.receive_hit(75.0)
	_key(KEY_H, true)
	_key(KEY_H, false)
	await _frames(60)
	_check("automatic physics advances actual two-second treatment", medkit.is_using() and medkit.get_progress() > 0.4 and medkit.get_progress() < 0.65 and health.health == 25.0)
	if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--capture"):
		paused = true
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://logs/medkit_20261009")
		root.get_texture().get_image().save_png("res://logs/medkit_20261009/treatment.png")
		paused = false
	await _frames(65)
	_check("real elapsed physics completes one heal and consumes one", not medkit.is_using() and health.health == 75.0 and medkit.remaining_count == 2)
	var stock_label = player.get_node("WeaponSlots/Panel/Content/MedkitCount")
	_check("ordinary non-debug weapon HUD shows stock but hides completed ring", stock_label.is_visible_in_tree() and not health.get_node("MedkitIndicator").visible)
	var panel = player.get_node("WeaponSlots/Panel")
	var viewport_size: Vector2 = root.get_visible_rect().size
	var stock_rect: Rect2 = stock_label.get_global_rect()
	_check("stock label is inside the bottom-right weapon panel", panel.get_global_rect().encloses(stock_rect) and stock_rect.get_center().x > viewport_size.x * 0.5 and stock_rect.get_center().y > viewport_size.y * 0.5)
	_check("medical stock is not duplicated in the health HUD", not health.has_node("Status/Content/MedkitCount"))
	var original: Node = packed.instantiate()
	var second = original.get_node("Player")
	original.remove_child(second)
	original.free()
	second.name = "SecondPlayer"
	second.position = player.position + Vector3(4, 0, 0)
	second.get_node("Health/Medkit").remaining_count = 5
	scene.add_child(second)
	second.get_node("Health").hide()
	await _frames(10)
	var second_medkit = second.get_node("Health/Medkit")
	_check("instances can share settings without sharing stock", second_medkit.settings == medkit.settings and second_medkit.remaining_count == 5 and medkit.remaining_count == 2)
	_check("quantity is a node field rather than mutable resource state", medkit.settings.get("remaining_count") == null and medkit.settings.get("progress") == null)
	var data = medkit.settings.duplicate()
	data.heal_amount = 35.0
	data.use_seconds = 1.25
	DirAccess.make_dir_recursive_absolute("res://logs/medkit_20261009")
	var result := ResourceSaver.save(data, "res://logs/medkit_20261009/roundtrip.tres")
	var restored = ResourceLoader.load("res://logs/medkit_20261009/roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("effect and duration survive resource save and reload", result == OK and restored.heal_amount == 35.0 and restored.use_seconds == 1.25)
	medkit.request_use()
	await _frames(30)
	var progress: float = medkit.get_progress()
	paused = true
	for frame in 15: await process_frame
	_check("real pause keeps progress and stock unchanged", medkit.is_using() and is_equal_approx(medkit.get_progress(), progress) and medkit.remaining_count == 2)
	paused = false
	player.receive_melee_hit(10.0, player.global_position + Vector3.RIGHT, 0.25, 0.2)
	_check("existing melee hit cancels before knockback without consuming", not medkit.is_using() and medkit.remaining_count == 2 and health.health == 65.0)
	await _frames(30)
	_check("other instance retains its own stock after a cancelled use", second_medkit.remaining_count == 5)
	second.queue_free()
	await process_frame
	_check("treatment can begin again after knockback ends", medkit.request_use())
	var ui = scene.get_node("DialogueUI")
	await ui.open_dialogue(player, load("res://resources/dialogue/npc_b.dialogue"), "start")
	await _frames(2)
	_check("real dialogue flow cancels treatment and hides status", player.is_in_dialogue and not medkit.is_using() and not health.get_node("Status").visible)
	# Close through the existing dialogue input instead of altering UI internals.
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(2)
	_check("closing dialogue does not revive a pending heal", not player.is_in_dialogue and not medkit.is_using())
	medkit.request_use()
	player.receive_hit(1000.0)
	_check("actual death pauses world and clears treatment", health.is_dead and paused and not medkit.is_using() and medkit.remaining_count == 2)
	root.get_node("GameState").help_choice = "accepted"
	var old_id: int = scene.get_instance_id()
	health.get_node("DeathScreen/Center/Panel/Content/Restart").pressed.emit()
	for frame in 10: await process_frame
	scene = current_scene
	_bind()
	await _frames(5)
	_check("restart creates a new scene and restores saved initial stock", scene.get_instance_id() != old_id and not paused and medkit.remaining_count == 3 and not medkit.is_using())
	_check("restart preserves original health and dialogue rules", health.health == health.max_health and root.get_node("GameState").help_choice == "accepted")
	player.receive_hit(25.0)
	medkit.request_use()
	_check("new scene can begin treatment", medkit.is_using())
	scene.queue_free()
	await process_frame
	await process_frame
	_check("unloading an active treatment leaves no timed callback or live module", not is_instance_valid(medkit))
	print("PLAYER MEDKIT LIFECYCLE: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)

func _bind() -> void:
	player = scene.get_node("Player")
	health = player.get_node("Health")
	medkit = health.get_node("Medkit")
	var enemy = scene.get_node("Arena/Enemy")
	enemy.shooting_enabled = false
	enemy.set_physics_process(false)
	enemy.get_node("AI").set_physics_process(false)

func _frames(count: int) -> void:
	for frame in count: await physics_frame
	await process_frame

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1
	print(("PASS " if passed else "FAIL ") + label)
