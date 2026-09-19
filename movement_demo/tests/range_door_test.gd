extends RefCounted

func run(scene: Node) -> Dictionary:
	var tree = scene.get_tree()
	var p = scene.get_node("Player")
	var door = scene.get_node("CombatTest/Walls/Door")
	var checks := {}
	var press_e = func():
		var event := InputEventKey.new()
		event.physical_keycode = KEY_E
		event.pressed = true
		tree.root.push_input(event)
	for i in range(5): await tree.physics_frame
	checks["starts_closed"] = not door.is_open
	press_e.call()
	for i in range(25): await tree.physics_frame
	checks["e_opens_door"] = door.is_open and is_equal_approx(door.get_node("Panel").position.x, door.slide_distance)
	Input.action_press("move_up")
	for i in range(35): await tree.physics_frame
	Input.action_release("move_up")
	for i in range(15): await tree.physics_frame
	checks["can_walk_through_open_door"] = p.position.z < -1.0 and p.get_node("Combat").can_combat()
	press_e.call()
	for i in range(25): await tree.physics_frame
	checks["e_closes_from_inside"] = not door.is_open and is_zero_approx(door.get_node("Panel").position.x)
	press_e.call()
	for i in range(25): await tree.physics_frame
	p.set_physics_process(false)
	p.position = Vector3(0, 0, -0.5)
	for i in range(5): await tree.physics_frame
	press_e.call()
	checks["cannot_close_on_player"] = door.is_open
	p.position = Vector3(5, 0, 2)
	for i in range(5): await tree.physics_frame
	press_e.call()
	checks["far_e_does_not_toggle"] = door.is_open
	p.position = Vector3(0, 0, 0.5)
	for i in range(5): await tree.physics_frame
	p.set_dialogue_active(true)
	press_e.call()
	checks["dialogue_does_not_toggle_door"] = door.is_open
	p.set_dialogue_active(false)
	p.position = Vector3(4, 0, 0.6)
	p.rotation = Vector3.ZERO
	p.set_physics_process(true)
	Input.action_press("move_up")
	for i in range(50): await tree.physics_frame
	Input.action_release("move_up")
	checks["wall_blocks_walking"] = p.position.z > -0.15
	var hit: Dictionary = p.get_node("Combat")._ray_to(Vector3(4, 0.8, -3))
	checks["wall_blocks_shots"] = not hit.is_empty() and hit.collider == scene.get_node("CombatTest/Walls/FrontRight")
	return checks
