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
	var curtained_booths := booths.get_children().filter(
		func(booth: Node) -> bool: return booth.has_node("Curtain"))
	check(booths.has_node("Booth4/Curtain") and curtained_booths.size() == 1,
		"only the northeast booth has a privacy curtain")
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
	var hall_top := tables.get_node("Table1/Top/Mesh") as MeshInstance3D
	var hall_seat := tables.get_node("Table1/Seats/North") as Node3D
	check(hall_top.mesh is CylinderMesh and hall_top.global_position.y > 1.0
		and hall_seat.scale.y > 1.25, "hall seating uses round high tables with tall stools")
	var terminal := bar.get_node("TerminalColumn")
	check(terminal.get_node("Stools").get_child_count() == 8
		and terminal.has_node("WraparoundDesk/North/Collision")
		and terminal.has_node("WraparoundDesk/South/Collision")
		and terminal.has_node("Projections/East/Panel3")
		and terminal.has_node("Projections/West/Panel3"),
		"the terminal wall has wraparound seating and projections on both faces")
	for aisle_x in [7.0, 13.18]:
		# Sweep above the floor contact margin so this assertion measures walls and furniture.
		var walker := scene.get_node("Walker") as TavernNPC
		var start := walker.floor_position(Vector3(aisle_x, 0, -7.4))
		var finish := walker.floor_position(Vector3(aisle_x, 0, 0.3))
		player.global_position = start + Vector3.UP * 0.025
		await physics_frame
		check(player.move_and_collide(finish - start) == null,
			"the aisle beside the terminal stays clear at x = %s" % aisle_x)
	var bartender := bar.get_node_or_null("BarCounter/Bartender/Body") as MeshInstance3D
	check(bartender != null and bartender.mesh is CapsuleMesh
		and is_equal_approx((bartender.mesh as CapsuleMesh).radius, 0.35) and scene.has_node("NPC"),
		"the bartender uses a capsule and is separate from the quest giver")
	var sofa := bar.get_node_or_null("Booths/Booth4/Seating/Sofa") as MeshInstance3D
	check(sofa != null and sofa.mesh is ArrayMesh and sofa.mesh.get_surface_count() == 3,
		"private booths use the continuous upholstered sofa mesh")

	var lounge := bar.get_node("SouthLounge")
	var lounge_tables := lounge.get_node("Tables")
	check(lounge_tables.get_child_count() == 3 and lounge_tables.get_children().all(
		func(setting: Node) -> bool:
			return setting.has_node("NorthSofa/Backrest") and setting.has_node("SouthSofa/Backrest")
	), "three lounge tables each have a pair of single-sided sofas")
	for entrance_x in [7.81, 12.91]:
		var walker := scene.get_node("Walker") as TavernNPC
		var start := walker.floor_position(Vector3(entrance_x, 0, 1.0))
		var finish := walker.floor_position(Vector3(entrance_x, 0, 5.8))
		player.global_position = start + Vector3.UP * 0.025
		await physics_frame
		check(player.move_and_collide(finish - start) == null,
			"the player can cross the lounge through the opening at x = %s" % entrance_x)
	player.global_position = Vector3(12.08, 0.0, 7.2)
	await physics_frame
	check(player.move_and_collide(Vector3(0, 0, -1.5)) != null,
		"the southern railing blocks access from the entrance corridor")
	check(record.has_node("Body/Cabinet") and record.get_node("Body/Cabinet") is CSGPolygon3D,
		"the record player uses an arched cabinet")
	var commissioner_name := scene.get_node("NPC/Name") as Label3D
	check(commissioner_name.text == "委托人", "the commissioner label only names the commissioner")
	var portal: Node3D = scene.get_node("Interactables/LevelPortal")
	check(absf(portal.position.x) < 0.01 and portal.position.z > 7.0,
		"the original quest portal forms the south entrance")
	if booths != null and booths.has_node("Booth4/Curtain"):
		var curtain: Area3D = booths.get_node("Booth4/Curtain")
		var panel: Node3D = curtain.get_node("Left")
		var inward := -curtain.global_basis.z
		player.global_position = curtain.global_position
		await physics_frame
		await physics_frame
		await create_timer(0.35).timeout
		var blocker := curtain.get_node("SolidCurtain/CollisionShape3D") as CollisionShape3D
		check(is_equal_approx(panel.scale.x, 1.0) and not blocker.disabled,
			"approaching the curtain keeps it closed and blocking")
		var interact := InputEventAction.new()
		interact.action = &"interact"
		interact.pressed = true
		root.push_input(interact)
		await create_timer(0.35).timeout
		check(panel.scale.x < 0.2 and blocker.disabled, "interacting opens the booth curtain and clears the passage")
		player.global_position = curtain.global_position + inward * 1.26
		await create_timer(0.35).timeout
		check(is_equal_approx(panel.scale.x, 1.0), "booth curtain closes with the player inside")
		for side in [-0.97, 0.97]:
			player.global_position = curtain.to_global(Vector3(side, 0.0, -1.26))
			await physics_frame
			check(player.move_and_collide(inward * 2.12) == null,
				"player can reach the side bench at x = %s" % side)
			check(player.move_and_collide(inward * 0.8) != null,
				"the rear bench stops the player at x = %s" % side)

	print("tavern layout checks: ", "all passed" if failures == 0 else "%d failed" % failures)
	scene.queue_free()
	quit(1 if failures else 0)
