extends RefCounted

# 在运行中的主场景执行 await load(...).new().run(scene)。测试后停止游戏。
func run(scene: Node) -> Dictionary:
	var checks := {}
	var p = scene.get_node("Player")
	var c = p.get_node_or_null("Combat")
	checks["combat_exists"] = c != null
	if c == null:
		return checks
	p.set_physics_process(false)
	p.position = Vector3(0, 0, -1)
	p.rotation = Vector3.ZERO
	var a = scene.get_node("CombatTest/TargetA")
	var b = scene.get_node("CombatTest/TargetB")
	var wall = scene.get_node("CombatTest/Cover")
	a.position = Vector3(0, 0, -4)
	b.position = Vector3(2, 0, -4)
	wall.position = Vector3(6, 1, 0)
	# Area3D 重叠列表在物理步末更新，等待传送后稳定。
	for i in range(5): await scene.get_tree().physics_frame
	c.begin_frame(0.0, true)
	checks["front_target"] = c.locked_target == a
	checks["initial_50"] = is_equal_approx(c.accuracy, 0.5)
	c.end_frame(2.0, false)
	checks["steady_100"] = is_equal_approx(c.accuracy, 1.0)
	b.position = Vector3(0.5, 0, -2)
	await scene.get_tree().physics_frame
	c.begin_frame(0.0, true)
	checks["keep_current_target"] = c.locked_target == a
	var hits = a.hit_count
	c.shoot()
	checks["full_accuracy_hits"] = a.hit_count == hits + 1
	checks["shot_deducts_25"] = is_equal_approx(c.accuracy, 0.75)
	c.end_frame(1.0, true)
	checks["moving_caps_35"] = is_equal_approx(c.accuracy, 0.35)
	c.accuracy = 0.5
	c.shot_cooldown = 0.0
	c.shoot()
	checks["shot_never_increases_accuracy"] = is_equal_approx(c.accuracy, 0.25)
	wall.position = Vector3(0, 1, -2)
	b.position = Vector3(20, 0, -4)
	await scene.get_tree().physics_frame
	await scene.get_tree().physics_frame
	c.begin_frame(0.0, true)
	checks["cover_breaks_lock"] = c.locked_target == null
	checks["lost_lock_keeps_penalty"] = c.accuracy <= 0.25
	hits = a.hit_count
	c.shot_cooldown = 0.0
	c.shoot()
	checks["unlocked_shot_stops_at_cover"] = c.last_shot_collider == wall and a.hit_count == hits
	wall.position = Vector3(6, 1, 0)
	await scene.get_tree().physics_frame
	await scene.get_tree().physics_frame
	c.begin_frame(0.0, true)
	checks["reacquire_keeps_penalty"] = c.locked_target == a and c.accuracy <= 0.25
	c.begin_frame(0.0, false)
	checks["release_unlocks"] = c.locked_target == null and not c.is_aiming
	a.position = Vector3(4, 0, 0)
	p.rotation = Vector3.ZERO
	await scene.get_tree().physics_frame
	await scene.get_tree().physics_frame
	c.begin_frame(0.0, true)
	checks["outside_cone_not_locked"] = c.locked_target == null
	c.shot_cooldown = 0.0
	var shots = c.shot_count
	c.shoot()
	checks["no_target_can_fire"] = c.shot_count == shots + 1
	p.set_dialogue_active(true)
	c.begin_frame(0.0, true)
	c.shot_cooldown = 0.0
	shots = c.shot_count
	c.shoot()
	checks["dialogue_blocks_combat"] = not c.is_aiming and c.shot_count == shots
	p.set_dialogue_active(false)
	var original = c.weapon
	var alternate = original.duplicate()
	alternate.initial_accuracy = 0.25
	alternate.stabilize_seconds = 1.0
	c.equip_weapon(alternate)
	checks["equip_resets_lock_and_accuracy"] = c.locked_target == null and is_equal_approx(c.accuracy, 0.25)
	checks["original_weapon_unchanged"] = is_equal_approx(original.initial_accuracy, 0.5)
	a.position = Vector3(0, 0, -4)
	await scene.get_tree().physics_frame
	await scene.get_tree().physics_frame
	c.begin_frame(0.0, true)
	c.end_frame(1.0, false)
	checks["equipped_weapon_recovery_used"] = is_equal_approx(c.accuracy, 1.0)
	c.equip_weapon(original)
	return checks


func run_input(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var p = scene.get_node("Player")
	var c = p.get_node("Combat")
	var ui = scene.get_node("DialogueUI")
	var checks := {}
	p.position = Vector3(0, 0, -1)
	p.rotation = Vector3.ZERO
	Input.action_press("aim")
	for i in range(5): await tree.physics_frame
	checks["input_acquires_target"] = c.locked_target == scene.get_node("CombatTest/TargetA")
	Input.action_press("move_right")
	for i in range(25): await tree.physics_frame
	Input.action_release("move_right")
	checks["locked_strafe_moves_right"] = p.position.x > 0.25 and absf(p.position.z + 1.0) < 0.1
	var direction: Vector3 = (scene.get_node("CombatTest/TargetA").global_position - p.global_position).normalized()
	checks["locked_strafe_faces_target"] = (-p.global_basis.z).dot(direction) > 0.99
	checks["actual_movement_caps_accuracy"] = c.accuracy <= 0.351
	for i in range(215): await tree.physics_frame
	checks["actual_rest_recovers_accuracy"] = is_equal_approx(c.accuracy, 1.0)
	var shots = c.shot_count
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	tree.root.push_input(click)
	for i in range(3): await tree.physics_frame
	checks["left_click_fires"] = c.shot_count == shots + 1
	await ui.open_dialogue(p, scene.get_node("NPC").dialogue_resource, "start")
	shots = c.shot_count
	tree.root.push_input(click)
	for i in range(3): await tree.physics_frame
	checks["dialogue_click_does_not_fire"] = c.shot_count == shots and c.locked_target == null
	ui._close_dialogue()
	Input.action_release("aim")
	for i in range(3): await tree.physics_frame
	checks["aim_release_clears_lock"] = c.locked_target == null
	p.position = Vector3(0, 0, -1)
	Input.action_press("move_down")
	for i in range(55): await tree.physics_frame
	Input.action_release("move_down")
	checks["normal_movement_still_works"] = p.position.z > -0.7
	return checks
