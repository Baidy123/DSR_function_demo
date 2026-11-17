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

	print("tavern layout checks: ", "all passed" if failures == 0 else "%d failed" % failures)
	scene.queue_free()
	quit(1 if failures else 0)
