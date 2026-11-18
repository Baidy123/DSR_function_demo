extends SceneTree

## Tavern layout integration: the south entrance keeps the player on the floor,
## and nearby interactables do not compete for the same player position.
## Run: godot --headless --path movement_demo --script res://tests/tavern_layout_test.gd

const MAIN_SCENE := preload("res://scenes/main.tscn")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label_text: String) -> void:
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func _run() -> void:
	var scene := MAIN_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	var player: CharacterBody3D = scene.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 0.0, 6.5)
	await physics_frame
	var exit_collision := player.move_and_collide(Vector3(0.0, 0.0, 4.0))
	check(exit_collision != null and player.global_position.z < 8.0,
		"south entrance collision keeps the player on the tavern floor")

	var npc_b: Node3D = scene.get_node("NPCB")
	var record: Area3D = scene.get_node("Interactables/RecordPlayer")
	var npc_sensor: SphereShape3D = npc_b.get_node("InteractionArea/CollisionShape3D").shape
	var record_sensor: SphereShape3D = record.get_node("CollisionShape3D").shape
	var player_shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	var planar_distance := Vector2(npc_b.global_position.x, npc_b.global_position.z).distance_to(
		Vector2(record.global_position.x, record.global_position.z))
	var minimum_separation := npc_sensor.radius + record_sensor.radius + player_shape.radius * 2.0
	check(planar_distance > minimum_separation,
		"NPC B and RecordPlayer cannot both overlap the player interaction body")


	var booths: Node3D = scene.get_node_or_null("BarEnvironment/Booths")
	check(booths != null and booths.get_child_count() == 6
		and booths.get_children().all(func(booth: Node) -> bool: return booth.has_node("Curtain")), "six booths have privacy curtains")
	var bar := scene.get_node("BarEnvironment")
	var sofas := bar.get_node("SofaSeats")
	check(sofas.get_children().all(func(sofa: Node) -> bool:
		return sofa.has_node("Upholstery/LeftSeat") and sofa.has_node("Upholstery/RightSeat")),
		"ordinary sofas have seats on both sides of the rear bench")
	var tables := bar.get_node("Tables")
	check(tables.get_child_count() == 2 and bar.has_node("TerminalColumn/Column/Collision"),
		"two hall tables flank the terminal column")
	check(tables.has_node("Table1/Seats/North/Seat")
		and bar.has_node("BarCounter/Stool1/Seat"),
		"table and counter stools use the shared swivel design")
	var bartender := bar.get_node_or_null("BarCounter/Bartender/Body") as MeshInstance3D
	check(bartender != null and bartender.mesh is CapsuleMesh
		and is_equal_approx((bartender.mesh as CapsuleMesh).radius, 0.35) and scene.has_node("NPC"),
		"the bartender uses a capsule and is separate from the quest giver")
	var sofa := bar.get_node_or_null("Booths/Booth1/Seating/Sofa") as MeshInstance3D
	check(sofa != null and sofa.mesh is ArrayMesh and sofa.mesh.get_surface_count() == 3,
		"private booths use the continuous upholstered sofa mesh")

	var lounge := bar.get_node("SouthLounge")
	var lounge_tables := lounge.get_node("Tables")
	check(lounge_tables.get_child_count() == 3 and lounge_tables.get_children().all(
		func(setting: Node) -> bool:
			return setting.has_node("NorthSofa/Backrest") and setting.has_node("SouthSofa/Backrest")
	), "three lounge tables each have a pair of single-sided sofas")
	player.global_position = Vector3(12.08, 0.0, 1.0)
	await physics_frame
	check(player.move_and_collide(Vector3(0, 0, 2.0)) == null,
		"the player can enter the lounge through the northern opening")
	player.global_position = Vector3(12.08, 0.0, 7.2)
	await physics_frame
	check(player.move_and_collide(Vector3(0, 0, -1.5)) != null,
		"the southern railing blocks access from the entrance corridor")
	var portal: Node3D = scene.get_node("Interactables/LevelPortal")
	check(absf(portal.position.x) < 0.01 and portal.position.z > 7.0,
		"the original quest portal forms the south entrance")
	if booths != null and booths.has_node("Booth1/Curtain"):
		var curtain: Area3D = booths.get_node("Booth1/Curtain")
		var panel: Node3D = curtain.get_node("Left")
		var inward := -curtain.global_basis.z
		player.global_position = curtain.global_position
		await create_timer(0.35).timeout
		check(panel.scale.x < 0.2, "booth curtain opens while the player crosses")
		player.global_position = curtain.global_position + inward * 1.26
		await create_timer(0.35).timeout
		check(is_equal_approx(panel.scale.x, 1.0), "booth curtain closes with the player inside")
		for side in [-0.91, 0.91]:
			player.global_position = curtain.to_global(Vector3(side, 0.0, -1.26))
			await physics_frame
			check(player.move_and_collide(inward * 2.12) == null,
				"player can reach the side bench at x = %s" % side)
			check(player.move_and_collide(inward * 0.8) != null,
				"the rear bench stops the player at x = %s" % side)

	print("tavern layout checks: ", "all passed" if failures == 0 else "%d failed" % failures)
	scene.queue_free()
	quit(1 if failures else 0)
