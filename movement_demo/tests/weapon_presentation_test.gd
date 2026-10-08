extends SceneTree

const WeaponView = preload("res://scripts/systems/presentation/weapon_presentation.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor := CharacterBody3D.new()
	actor.position = Vector3(4.0, 0.0, 2.0)
	actor.rotation.y = 0.4
	actor.velocity = Vector3(0.4, 0.0, -0.2)
	var collision := CollisionShape3D.new()
	collision.shape = CapsuleShape3D.new()
	actor.add_child(collision)
	var presentation := Node3D.new()
	presentation.position = Vector3(0.1, 0.0, 0.0)
	actor.add_child(presentation)
	var view := WeaponView.new()
	presentation.add_child(view)
	root.add_child(actor)
	var actor_transform := actor.transform
	var actor_velocity := actor.velocity
	var collision_transform := collision.transform
	var collision_shape: Shape3D = collision.shape
	var weapon := WeaponData.new()
	var resource_before := _stored_values(weapon)
	view.apply_weapon(null)
	check(view.model == null and view.get_child_count(true) == 0, "no equipped weapon creates no placeholder")
	var fallback := Vector3(0.15, 0.72, -0.35)
	view.apply_weapon(weapon, null, fallback)
	check(view.using_placeholder and view.model.get_node("Mesh").mesh is BoxMesh, "an equipped weapon without artwork has the box placeholder")
	check(view.position.is_equal_approx(fallback), "placeholder mount uses Presentation-local posture position")
	var same_model: Node3D = view.model
	view.apply_weapon(weapon, null, fallback + Vector3.UP * 0.4)
	check(view.model == same_model and view.position.is_equal_approx(fallback + Vector3.UP * 0.4), "posture changes update the mount without reinstantiating the weapon")
	check(_stored_values(weapon) == resource_before, "reading the weapon does not mutate its configuration")
	weapon.visual_model = _model_scene()
	weapon.visual_position = Vector3(0.05, -0.03, 0.1)
	weapon.visual_rotation_degrees = Vector3(0.0, 30.0, 0.0)
	weapon.visual_scale = Vector3(0.8, 0.9, 1.1)
	var source_before := _stored_values(weapon)
	view.apply_weapon(weapon, null, fallback)
	check(not view.using_placeholder and view.model != same_model, "changing the same weapon's model rebuilds only its appearance")
	var expected_offset := Transform3D(Basis.from_euler(weapon.visual_rotation_degrees * (PI / 180.0)) * Basis.from_scale(weapon.visual_scale), weapon.visual_position)
	check(view.model.transform.is_equal_approx(expected_offset * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))), "weapon offsets compose with the authored model root transform")
	var other := WeaponView.new()
	presentation.add_child(other)
	other.apply_weapon(weapon, null, fallback)
	check(view.model != other.model and view.model.get_node("Mesh") != other.model.get_node("Mesh"), "holders sharing one weapon resource get independent model instances")
	view.model.get_node("Mesh").position.x += 1.0
	check(is_zero_approx(other.model.get_node("Mesh").position.x), "one weapon model's pose does not alter another holder")
	await _skeletal_socket_follow(view, other, weapon, presentation, fallback)
	var character_model := Node3D.new()
	character_model.position = Vector3(0.0, 1.0, 0.0)
	presentation.add_child(character_model)
	var socket := Node3D.new()
	socket.position = Vector3(0.25, 0.3, -0.2)
	socket.rotation.z = 0.3
	character_model.add_child(socket)
	view.apply_weapon(weapon, socket, fallback)
	check(view.global_transform.is_equal_approx(socket.global_transform), "visible character-model socket supplies the weapon mount")
	socket.position.x += 0.2
	view._process(0.016)
	check(view.global_transform.is_equal_approx(socket.global_transform), "socket motion is followed after character animation updates")
	character_model.hide()
	view._process(0.016)
	check(view.transform.is_equal_approx(Transform3D(Basis.IDENTITY, fallback)) and view.model.is_visible_in_tree(), "hidden character artwork falls back to the visible posture mount")
	character_model.show()
	view._process(0.016)
	check(view.global_transform.is_equal_approx(socket.global_transform), "restoring the model resumes its socket")
	var attached_model: Node3D = view.model
	character_model.free()
	view._process(0.016)
	check(view.model == attached_model and view.position.is_equal_approx(fallback), "rebuilding the character model cannot free its sibling weapon or leave a dead socket")
	var alternate := WeaponData.new()
	view.apply_weapon(alternate, null, fallback)
	check(view.using_placeholder and view.model != attached_model and not attached_model.is_inside_tree(), "switching weapons detaches the previous model immediately")
	view.apply_weapon(null)
	check(view.model == null and view.get_child_count(true) == 0, "unequipping immediately clears both model and placeholder")
	for invalid in [_model_scene(&"wrong_root"), _model_scene(&"collision"), _model_scene(&"navigation")]:
		alternate.visual_model = invalid
		view.apply_weapon(alternate, null, fallback)
		check(view.using_placeholder and view.model.get_node("Mesh").mesh is BoxMesh, "invalid root, collision or navigation weapon artwork uses the safe placeholder")
		var rejected_model: Node3D = view.model
		view.apply_weapon(alternate, null, fallback)
		check(view.model == rejected_model, "a rejected source is not re-instantiated every frame")
	var animated := WeaponData.new()
	animated.visual_model = _model_scene(&"animation")
	view.apply_weapon(animated)
	var animation: AnimationPlayer = view.model.get_node("AnimationPlayer")
	check(animation.autoplay.is_empty() and not animation.active and not animation.is_playing(), "weapon-local AnimationPlayer cannot start autonomous playback")
	var source_instance := animated.visual_model.instantiate()
	check(source_instance.get_node("AnimationPlayer").autoplay == "Auto" and source_instance.get_node("AnimationPlayer").active, "disabling instance playback does not edit the source weapon scene")
	source_instance.free()
	view.reset()
	check(view.model == null and view.get_child_count(true) == 0 and view.transform == Transform3D.IDENTITY, "reset removes the previous attachment and mount transform")
	view.apply_weapon(weapon, null, fallback)
	check(not view.using_placeholder and view.model != other.model, "the current equipped weapon can be reapplied after reset")
	check(_stored_values(weapon) == source_before, "socket changes, rebuilds and reset never write weapon data")
	check(actor.transform == actor_transform and actor.velocity == actor_velocity and collision.transform == collision_transform and collision.shape == collision_shape, "weapon presentation never changes body transform, velocity or collision")
	var save_path := "res://logs/weapon_presentation_saved.tres"
	check(ResourceSaver.save(weapon, save_path) == OK, "weapon appearance configuration saves normally")
	var loaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as WeaponData
	check(loaded != null and loaded.visual_model != null and loaded.visual_position == weapon.visual_position and loaded.visual_rotation_degrees == weapon.visual_rotation_degrees and loaded.visual_scale == weapon.visual_scale, "model and all three offsets survive resource reload")
	view.clear()
	view.clear()
	check(view.model == null and view.get_child_count(true) == 0, "repeated cleanup is safe")
	actor.queue_free()
	await process_frame
	await _real_equipment_adapters()
	print("WEAPON PRESENTATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func _skeletal_socket_follow(view, other, weapon: WeaponData, presentation: Node3D, fallback: Vector3) -> void:
	var rig_scene := _skeletal_character_scene()
	var first := rig_scene.instantiate() as Node3D
	var second := rig_scene.instantiate() as Node3D
	presentation.add_child(first)
	presentation.add_child(second)
	second.position.x += 2.0
	var skeleton: Skeleton3D = first.get_node("Rig")
	var second_skeleton: Skeleton3D = second.get_node("Rig")
	var socket: BoneAttachment3D = skeleton.get_node("HandSocket")
	var second_socket: BoneAttachment3D = second_skeleton.get_node("HandSocket")
	var hand := skeleton.find_bone("Hand")
	var animator: AnimationPlayer = first.get_node("AnimationPlayer")
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var source_animation: Animation = animator.get_animation(&"HandMotion")
	var source_key: Vector3 = source_animation.track_get_key_value(0, 1)
	view.apply_weapon(weapon, socket, fallback)
	other.apply_weapon(weapon, second_socket, fallback)
	# Let real skeleton notifications establish the initial BoneAttachment pose.
	# Never assign the attachment's position or force an early skeleton update.
	await process_frame
	await process_frame
	var expected: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(hand)
	check(socket.get_skeleton() == skeleton and socket.bone_idx == hand and socket.global_transform.is_equal_approx(expected), "real BoneAttachment resolves its hand bone in the transformed character hierarchy")
	check(view.global_transform.is_equal_approx(expected), "weapon mount follows the real skeleton's world bone transform")
	var previous_mount: Transform3D = view.global_transform
	var second_pose: Transform3D = second_skeleton.get_bone_pose(hand)
	var second_mount: Transform3D = other.global_transform
	# Advance an actual skeletal position/rotation/scale animation at the start
	# of one process frame, before normal presentation processing. Inspect at the
	# next frame boundary: the helper must not lag one completed rendered frame.
	var advance_animation := func():
		animator.play(&"HandMotion")
		animator.advance(0.5)
	process_frame.connect(advance_animation, CONNECT_ONE_SHOT)
	await process_frame
	await process_frame
	expected = skeleton.global_transform * skeleton.get_bone_global_pose(hand)
	check(not skeleton.get_bone_pose(hand).is_equal_approx(second_pose) and not socket.global_transform.is_equal_approx(previous_mount), "real animation changes the hand bone and BoneAttachment without manually moving the socket")
	check(socket.global_transform.is_equal_approx(expected) and view.global_transform.is_equal_approx(expected), "weapon position, orientation and scale follow the animated bone within one completed process frame")
	check(second_skeleton.get_bone_pose(hand).is_equal_approx(second_pose) and other.global_transform.is_equal_approx(second_mount), "animating one shared character scene does not move the other holder's bones or weapon")
	check(source_animation.track_get_key_value(0, 1) == source_key and view.model != other.model, "skeletal attachment playback preserves shared animation data and independent weapon instances")
	first.free()
	second.free()


func _skeletal_character_scene() -> PackedScene:
	var model := Node3D.new()
	model.name = "SkeletalCharacter"
	model.position = Vector3(0.2, 0.0, 0.1)
	model.rotation.y = 0.25
	model.scale = Vector3(1.1, 1.1, 1.1)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Rig"
	model.add_child(skeleton)
	skeleton.owner = model
	var root_bone := skeleton.add_bone("Root")
	var hand := skeleton.add_bone("Hand")
	skeleton.set_bone_parent(hand, root_bone)
	skeleton.set_bone_rest(root_bone, Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.0, 1.0, 0.0)))
	skeleton.set_bone_rest(hand, Transform3D(Basis.IDENTITY, Vector3(0.3, 0.25, -0.2)))
	skeleton.reset_bone_poses()
	var socket := BoneAttachment3D.new()
	socket.name = "HandSocket"
	socket.bone_name = "Hand"
	skeleton.add_child(socket)
	socket.owner = model
	var animation := Animation.new()
	animation.length = 1.0
	var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(position_track, ^"Rig:Hand")
	animation.track_insert_key(position_track, 0.0, Vector3(0.3, 0.25, -0.2))
	animation.track_insert_key(position_track, 1.0, Vector3(0.55, 0.05, -0.35))
	var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(rotation_track, ^"Rig:Hand")
	animation.track_insert_key(rotation_track, 0.0, Quaternion.IDENTITY)
	animation.track_insert_key(rotation_track, 1.0, Quaternion(Vector3.FORWARD, 0.6))
	var scale_track := animation.add_track(Animation.TYPE_SCALE_3D)
	animation.track_set_path(scale_track, ^"Rig:Hand")
	animation.track_insert_key(scale_track, 0.0, Vector3.ONE)
	animation.track_insert_key(scale_track, 1.0, Vector3(1.2, 0.9, 1.1))
	var library := AnimationLibrary.new()
	library.add_animation(&"HandMotion", animation)
	var animator := AnimationPlayer.new()
	animator.name = "AnimationPlayer"
	animator.add_animation_library(&"", library)
	model.add_child(animator)
	animator.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	return packed


func _real_equipment_adapters() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Player")
	var slots = actor.get_node("WeaponSlots")
	var combat = actor.get_node("Combat")
	var view = actor.get_node("Visual/Presentation")
	var enemy = scene.get_node("Arena/Enemy")
	var enemy_view = enemy.get_node("Presentation")
	actor.set_physics_process(false)
	combat.set_physics_process(false)
	enemy.set_physics_process(false)
	enemy.get_node("AI").set_physics_process(false)
	await physics_frame
	await process_frame
	var actor_transform: Transform3D = actor.transform
	var actor_collision: CollisionShape3D = actor.get_node("CollisionShape3D")
	var collision_transform: Transform3D = actor_collision.transform
	var collision_shape: Shape3D = actor_collision.shape
	var primary := WeaponData.new()
	primary.visual_model = _model_scene()
	primary.magazine_capacity = 9
	var secondary := WeaponData.new()
	secondary.magazine_capacity = 7
	var primary_before := _stored_values(primary)
	var secondary_before := _stored_values(secondary)
	slots.primary_weapon = primary
	slots.secondary_weapon = secondary
	check(slots.select_slot(0) and combat.weapon == primary and view._weapon_view != null and not view._weapon_view.using_placeholder, "real primary-slot equipment automatically displays its model through the player adapter")
	combat.ammo.magazine_rounds = 4
	combat.shot_cooldown = 0.7
	var primary_ammo = combat.ammo
	var primary_model: Node3D = view._weapon_view.model
	check(slots.select_slot(1) and combat.weapon == secondary and view._weapon_view.using_placeholder and not primary_model.is_inside_tree(), "real secondary-slot selection replaces artwork with that weapon's placeholder")
	combat.ammo.magazine_rounds = 2
	check(slots.select_slot(0) and view._weapon_view._weapon == primary and not view._weapon_view.using_placeholder, "switching back restores the equipped primary appearance without direct helper calls")
	check(combat.ammo == primary_ammo and combat.ammo.magazine_rounds == 4 and slots._ammo_states[1].magazine_rounds == 2 and is_equal_approx(combat.shot_cooldown, 0.7), "appearance switching preserves both real slot magazines and the shared firing cooldown")
	combat.equip_weapon(null, true)
	check(view._weapon_view.model == null and view._weapon_view.get_child_count(true) == 0, "real player unequip notification removes all weapon appearance")
	check(slots.select_slot(0) and view._weapon_view._weapon == primary and combat.ammo.magazine_rounds == 4, "re-equipping a real slot restores its appearance and retained ammo")
	view.model_scene = preload("res://tests/presentation_fixture.gd").model_scene()
	await physics_frame
	await process_frame
	await physics_frame
	check(view.has_model() and view._weapon_view._weapon == primary and is_instance_valid(view._weapon_view.model), "automatic adapter state restores equipped artwork after character-model rebuild")
	var enemy_weapon := WeaponData.new()
	enemy_weapon.visual_model = _model_scene()
	enemy_weapon.magazine_capacity = 11
	enemy.equip_weapon(enemy_weapon)
	await physics_frame
	await process_frame
	check(enemy_view._weapon_view != null and enemy_view._weapon_view._weapon == enemy_weapon and not enemy_view._weapon_view.using_placeholder, "real enemy equipment is displayed by its normal presentation physics update")
	enemy.ammo.magazine_rounds = 3
	var enemy_ammo = enemy.ammo
	var enemy_model: Node3D = enemy_view._weapon_view.model
	await physics_frame
	check(enemy.ammo == enemy_ammo and enemy.ammo.magazine_rounds == 3, "enemy presentation updates do not replace or refill runtime ammunition")
	enemy.reset_target()
	check(enemy_view._weapon_view._weapon == enemy_weapon and enemy_view._weapon_view.model != enemy_model and not enemy_model.is_inside_tree(), "enemy reset automatically clears and rebuilds the currently equipped appearance")
	check(enemy.ammo.magazine_rounds == 11 and enemy.weapon == enemy_weapon, "enemy reset retains the original gameplay equipment and full-magazine semantics")
	enemy.equip_weapon(null)
	await physics_frame
	await process_frame
	check(enemy_view._weapon_view.model == null, "real enemy unequip clears its model on the normal adapter update")
	enemy.equip_weapon(enemy_weapon)
	await physics_frame
	await process_frame
	check(enemy_view._weapon_view._weapon == enemy_weapon and not enemy_view._weapon_view.using_placeholder and enemy.ammo.magazine_rounds == 11, "real enemy re-equip restores the correct model without altering ammo")
	check(actor.transform == actor_transform and actor_collision.transform == collision_transform and actor_collision.shape == collision_shape, "real weapon model and slot changes leave player body and collision untouched")
	check(_stored_values(primary) == primary_before and _stored_values(secondary) == secondary_before, "real adapters never persist equipment runtime changes into shared weapon resources")
	scene.queue_free()
	await process_frame


func _model_scene(kind: StringName = &"valid") -> PackedScene:
	var model: Node = Node.new() if kind == &"wrong_root" else Node3D.new()
	model.name = "WeaponArtwork"
	if model is Node3D: model.position.y = 0.05
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = BoxMesh.new()
	model.add_child(mesh)
	mesh.owner = model
	if kind == &"collision":
		var body := StaticBody3D.new()
		model.add_child(body)
		body.owner = model
	if kind == &"navigation":
		var agent := NavigationAgent3D.new()
		model.add_child(agent)
		agent.owner = model
	if kind == &"animation":
		var animation := AnimationPlayer.new()
		animation.name = "AnimationPlayer"
		var library := AnimationLibrary.new()
		library.add_animation(&"Auto", Animation.new())
		animation.add_animation_library(&"", library)
		animation.autoplay = "Auto"
		model.add_child(animation)
		animation.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	return packed


func _stored_values(resource: Resource) -> Dictionary:
	var result := {}
	for property in resource.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE: result[property.name] = resource.get(property.name)
	return result


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
