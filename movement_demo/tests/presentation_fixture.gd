extends RefCounted

static func model_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "ExampleModel"
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	torso.position.y = 0.875
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.28
	mesh.height = 1.75
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.65, 0.95)
	mesh.material = material
	torso.mesh = mesh
	root.add_child(torso)
	torso.owner = root
	var arm := MeshInstance3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0.35, 1.175, -0.12)
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.16, 0.65)
	box.material = material
	arm.mesh = box
	root.add_child(arm)
	arm.owner = root
	var socket := Node3D.new()
	socket.name = "WeaponSocket"
	socket.position = Vector3(0.35, 1.3, -0.4)
	root.add_child(socket)
	socket.owner = root
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.owner = root
	var library := AnimationLibrary.new()
	var names := ["Idle", "Walk", "Run", "Aim", "Reload", "Talk", "Shoot", "Hit", "Death", "Impact"]
	for index in names.size():
		var animation := Animation.new()
		animation.length = 1.0
		var track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, ^"Torso:position")
		animation.track_insert_key(track, 0.0, Vector3(0, 0.875, 0))
		animation.track_insert_key(track, 0.5, Vector3(0.01 * index, 0.895 + 0.005 * index, 0))
		animation.track_insert_key(track, 1.0, Vector3(0, 0.875, 0))
		var rotation := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(rotation, ^"Arm:rotation")
		animation.track_insert_key(rotation, 0.0, Vector3.ZERO)
		animation.track_insert_key(rotation, 0.5, Vector3(0.08 * index, 0, 0))
		animation.track_insert_key(rotation, 1.0, Vector3.ZERO)
		if names[index] == "Death":
			var fall := animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(fall, ^"Torso:rotation")
			animation.track_insert_key(fall, 0.0, Vector3.ZERO)
			animation.track_insert_key(fall, 1.0, Vector3(PI / 2, 0, 0))
		else:
			_track(animation, ^"Torso:rotation", [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
		_track(animation, ^"Torso:mesh:height", [1.75, 1.75, 1.75])
		_track(animation, ^"Arm:position", [arm.position, arm.position, arm.position])
		_track(animation, ^"WeaponSocket:position", [socket.position, socket.position, socket.position])
		_track(animation, ^"WeaponSocket:rotation", [Vector3.ZERO, Vector3(0.08 * index, 0, 0), Vector3.ZERO])
		library.add_animation(names[index], animation)
	for clip in ["Melee", "Crouch", "CrouchWalk", "CrouchEnter", "CrouchExit", "CrouchAim", "CrouchShoot", "CrouchReload", "CrouchHit", "Vault", "VaultFall", "Land", "CrouchLand"]:
		library.add_animation(clip, _action_animation(clip))
	player.add_animation_library(&"", library)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## 简单几何演示，不驱动物理身体；所有片段仍为一秒。
static func _action_animation(clip: String) -> Animation:
	var animation := Animation.new()
	animation.length = 1.0
	var height := 1.0 if clip.begins_with("Crouch") or clip.begins_with("Vault") else 1.75
	var heights := [height, height, height]
	if clip == "CrouchEnter": heights = [1.75, 1.375, 1.0]
	if clip == "CrouchExit": heights = [1.0, 1.375, 1.75]
	var torsos: Array = []
	var arms: Array = []
	var sockets: Array = []
	for value in heights:
		var fraction: float = (float(value) - 1.0) / 0.75
		torsos.append(Vector3(0, float(value) * 0.5, 0))
		arms.append(Vector3(0.35, lerpf(0.625, 1.175, fraction), -0.12))
		sockets.append(Vector3(0.35, lerpf(0.72, 1.3, fraction), -0.4))
	var arm_turns := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var body_turns := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var times := PackedFloat32Array([0.0, 0.5, 1.0])
	match clip:
		"Melee":
			times = PackedFloat32Array([0.0, 0.324, 1.0])
			arm_turns = [Vector3(0, -0.8, -0.2), Vector3(0, 0.9, -0.2), Vector3.ZERO]
		"CrouchWalk":
			torsos[1] += Vector3(0.025, 0.025, 0)
			arm_turns[1] = Vector3(0.15, 0, 0)
		"CrouchAim":
			arm_turns = [Vector3(-0.12, 0, 0), Vector3(-0.12, 0, 0), Vector3(-0.12, 0, 0)]
		"CrouchShoot":
			arm_turns[1] = Vector3(-0.25, 0, 0)
			sockets[1] += Vector3(0, 0.025, 0.08)
		"CrouchReload":
			arm_turns[1] = Vector3(0.9, 0, 0.35)
		"CrouchHit":
			body_turns[1] = Vector3(-0.16, 0, 0.08)
		"Vault":
			body_turns[1] = Vector3(-0.3, 0, 0)
			arm_turns = [Vector3(-0.2, 0, 0), Vector3(-0.6, 0, 0), Vector3.ZERO]
		"VaultFall":
			body_turns = [Vector3(0.12, 0, 0), Vector3(0.18, 0, 0), Vector3(0.12, 0, 0)]
			arm_turns = [Vector3(0, 0, -0.15), Vector3(0, 0, -0.25), Vector3(0, 0, -0.15)]
		"Land", "CrouchLand":
			body_turns[1] = Vector3(0.15, 0, 0)
			arm_turns[1] = Vector3(0.2, 0, -0.1)
	_track(animation, ^"Torso:position", torsos, times)
	_track(animation, ^"Torso:mesh:height", heights, times)
	_track(animation, ^"Torso:rotation", body_turns, times)
	_track(animation, ^"Arm:position", arms, times)
	_track(animation, ^"Arm:rotation", arm_turns, times)
	_track(animation, ^"WeaponSocket:position", sockets, times)
	_track(animation, ^"WeaponSocket:rotation", arm_turns, times)
	return animation


static func _track(animation: Animation, path: NodePath, values: Array,
		times := PackedFloat32Array([0.0, 0.5, 1.0])) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	for index in values.size(): animation.track_insert_key(track, times[index], values[index])


static func profile() -> PresentationAnimationProfile:
	var result := PresentationAnimationProfile.new()
	result.idle = &"Idle"
	result.move = &"Walk"
	result.sprint = &"Run"
	result.aim = &"Aim"
	result.reload = &"Reload"
	result.melee = &"Melee"
	result.crouch = &"Crouch"
	result.crouch_move = &"CrouchWalk"
	result.crouch_enter = &"CrouchEnter"
	result.crouch_exit = &"CrouchExit"
	result.crouch_aim = &"CrouchAim"
	result.crouch_fire = &"CrouchShoot"
	result.crouch_reload = &"CrouchReload"
	result.crouch_hit = &"CrouchHit"
	result.vault = &"Vault"
	result.vault_fall = &"VaultFall"
	result.land = &"Land"
	result.crouch_land = &"CrouchLand"
	result.dialogue = &"Talk"
	result.fire = &"Shoot"
	result.hit = &"Hit"
	result.dead = &"Death"
	result.impact = &"Impact"
	result.blend_seconds = 0.0
	return result
