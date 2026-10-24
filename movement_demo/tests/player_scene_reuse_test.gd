extends SceneTree

const PlayerScene = preload("res://scenes/player/player.tscn")
const CameraScene = preload("res://scenes/player/player_camera_rig.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	# An authored level uses normal editable-child overrides, rather than
	# changing ownership of nested CanvasLayers while packing runtime nodes.
	var pistol = load("res://resources/weapons/test_pistol.tres").duplicate(true)
	var rifle = load("res://resources/weapons/test_sidearm.tres").duplicate(true)
	pistol.camera_view_size = 15.0
	rifle.camera_view_size = 21.0
	pistol.camera_transition_seconds = 0.2
	rifle.camera_transition_seconds = 0.2
	var error := ResourceSaver.save(pistol, "res://logs/player_prefab_work/pistol.tres")
	if error == OK: error = ResourceSaver.save(rifle, "res://logs/player_prefab_work/rifle.tres")
	var medical = load("res://resources/player/default_medkit.tres").duplicate(true)
	medical.heal_amount = 35.0
	medical.use_seconds = 1.25
	if error == OK: error = ResourceSaver.save(medical, "res://logs/player_prefab_work/medkit.tres")
	var source_path := "res://logs/player_prefab_work/authored_level.tscn"
	var source := FileAccess.open(source_path, FileAccess.WRITE)
	source.store_string(_level_source())
	source.close()
	var authored := load(source_path) as PackedScene
	var path := "res://logs/player_prefab_work/reuse_level.tscn"
	if error == OK: error = ResourceSaver.save(authored, path)
	check(error == OK, "A new level saves the two independent prefab instances")
	var level = load(path).instantiate()
	var hero = level.get_node("Room/Actors/Hero")
	var camera = level.get_node("Room/Views/Camera3D")
	check(hero.scene_file_path == PlayerScene.resource_path and camera.scene_file_path == CameraScene.resource_path, "Level reload keeps actual prefab instances")
	check(["Combat", "Equipment", "Health", "Visual/Presentation", "PlayerPresentation", "ImpactReceiver"].all(func(part): return hero.has_node(part)) and hero.find_children("*", "Camera3D", true, false).is_empty(), "Player prefab retains its gameplay components independently of cameras")
	check(hero.has_node("Equipment/MedkitIndicator") and not hero.has_node("Health/Medkit") and not hero.has_node("Health/MedkitIndicator") and not hero.has_node("WeaponSlots"), "Equipment owns medical components and replaces the old slot node")
	var medkit = hero.get_node("Equipment/Medkit")
	check(medkit.remaining_count == 7 and medkit.settings.heal_amount == 35.0 and medkit.settings.use_seconds == 1.25, "Level save/reload preserves medical stock, effect and duration under Equipment")
	var equipment = hero.get_node("Equipment")
	check(equipment.medkit == medkit.settings and equipment.medkit_count == medkit.remaining_count, "Medical execution reads the resource and stock mounted directly on Equipment")
	var exported: Array[String] = []
	for property in equipment.get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR: exported.append(property.name)
	check(exported.has("medkit") and exported.has("medkit_count"), "Equipment Inspector directly exposes the medical resource slot and quantity")
	check(["PhantomCameraHost", "CameraGroundAnchor", "PhantomCamera3D"].all(func(part): return camera.has_node(part)), "Camera prefab contains the complete original follow chain")
	root.add_child(level)
	current_scene = level
	hero.get_node("Health").debug_invincible = true
	check(camera.get_follow_actor() == hero and camera._actor == hero and camera.get_node("CameraGroundAnchor").actor == hero, "One relative player path binds weapon view and ground following after player rename/nesting")
	check(is_equal_approx(camera.size, 21.0), "Camera entering first reads the initial secondary weapon without opening zoom")
	check(hero.get_node("Combat").weapon_changed.is_connected(camera._on_weapon_changed), "Reused camera subscribes to the actual player's equipment signal")
	for frame in 6: await physics_frame
	var phantom = camera.get_node("PhantomCamera3D")
	var anchor = camera.get_node("CameraGroundAnchor")
	check(phantom.follow_target == anchor and camera.get_viewport().get_camera_3d() == camera, "Reused host activates the owned camera and ground anchor")
	var basis: Basis = camera.global_basis
	var offset: Vector3 = phantom.follow_offset
	_key(KEY_1)
	check(hero.get_node("Combat").weapon == hero.get_node("Equipment").primary_weapon and is_equal_approx(camera.size, 21.0), "Real slot input starts a smooth weapon-driven view transition")
	for frame in 5: await physics_frame
	check(camera.size > 15.0 and camera.size < 21.0, "Weapon-specific view transition has intermediate values")
	for frame in 16: await physics_frame
	check(is_equal_approx(camera.size, 15.0), "Primary weapon reaches its configured view size")
	var start: Vector3 = hero.global_position
	Input.action_press("move_right")
	for frame in 45: await physics_frame
	Input.action_release("move_right")
	for frame in 18: await physics_frame
	check(hero.global_position.x > start.x + 1.0, "A reused player actually moves through the original input/body code")
	check(anchor.global_position.distance_to(Vector3(hero.global_position.x, hero.get_camera_ground_height(), hero.global_position.z)) < 0.01, "Anchor follows the renamed player's world position under a rotated parent")
	check(camera.global_basis.is_equal_approx(basis) and phantom.follow_offset == offset, "Character turning and parent transforms preserve camera tilt and follow offset")
	_key(KEY_2)
	for frame in 20: await physics_frame
	check(is_equal_approx(camera.size, 21.0), "Secondary weapon continues controlling the separately instanced camera")
	var old_ammo = hero.get_node("Combat").ammo
	level.queue_free()
	await process_frame
	var solo := Node3D.new()
	_add_floor(solo)
	var independent = PlayerScene.instantiate()
	solo.add_child(independent)
	root.add_child(solo)
	current_scene = solo
	for frame in 4: await physics_frame
	check(independent.is_on_floor() and independent.get_node("Combat").weapon != null and independent.get_node("Combat").ammo != old_ammo, "Player also instantiates without a camera and starts fresh combat state")
	var independent_medkit = independent.get_node("Equipment/Medkit")
	check(independent_medkit.remaining_count == 3 and independent_medkit.settings.heal_amount == 50.0 and independent_medkit.settings.use_seconds == 2.0, "Level equipment overrides do not change the reusable player's medical defaults")
	solo.queue_free()
	await process_frame
	print("PLAYER SCENE REUSE: ", checks - failures, "/", checks)
	quit(1 if failures else 0)

func _level_source() -> String:
	# Camera deliberately precedes the player in tree order, and the player
	# is renamed/nested beneath a translated and rotated room.
	return """[gd_scene format=3]
[ext_resource type="PackedScene" path="res://scenes/player/player_camera_rig.tscn" id="camera"]
[ext_resource type="PackedScene" path="res://scenes/player/player.tscn" id="player"]
[ext_resource type="Resource" path="res://logs/player_prefab_work/pistol.tres" id="pistol"]
[ext_resource type="Resource" path="res://logs/player_prefab_work/rifle.tres" id="rifle"]
[ext_resource type="Resource" path="res://logs/player_prefab_work/medkit.tres" id="medical"]
[sub_resource type="BoxShape3D" id="floor"]
size = Vector3(80, 0.5, 80)
[node name="ReusablePlayerLevel" type="Node3D"]
[node name="Room" type="Node3D" parent="."]
position = Vector3(4, 0, -3)
rotation = Vector3(0, 0.65, 0)
[node name="Views" type="Node3D" parent="Room"]
[node name="Camera3D" parent="Room/Views" instance=ExtResource("camera")]
player_path = NodePath("../../Actors/Hero")
[node name="Actors" type="Node3D" parent="Room"]
[node name="Hero" parent="Room/Actors" instance=ExtResource("player")]
position = Vector3(2, 0, 1)
[node name="Equipment" parent="Room/Actors/Hero" index="3"]
primary_weapon = ExtResource("pistol")
secondary_weapon = ExtResource("rifle")
starting_slot = 1
medkit = ExtResource("medical")
medkit_count = 7
[node name="Floor" type="StaticBody3D" parent="."]
[node name="CollisionShape3D" type="CollisionShape3D" parent="Floor"]
position = Vector3(0, -0.25, 0)
shape = SubResource("floor")
[editable path="Room/Actors/Hero"]
"""

func _add_floor(level: Node3D) -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.5, 80)
	shape.shape = box
	shape.position.y = -0.25
	floor.add_child(shape)
	level.add_child(floor)
	floor.owner = level
	shape.owner = level

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
