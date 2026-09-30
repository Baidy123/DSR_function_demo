extends RefCounted

static func model_scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "ExampleModel"
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	torso.position.y = 0.8
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.28
	mesh.height = 1.6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.65, 0.95)
	mesh.material = material
	torso.mesh = mesh
	root.add_child(torso)
	torso.owner = root
	var arm := MeshInstance3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0.35, 1.1, -0.12)
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.16, 0.65)
	box.material = material
	arm.mesh = box
	root.add_child(arm)
	arm.owner = root
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
		animation.track_insert_key(track, 0.0, Vector3(0, 0.8, 0))
		animation.track_insert_key(track, 0.5, Vector3(0.01 * index, 0.82 + 0.005 * index, 0))
		animation.track_insert_key(track, 1.0, Vector3(0, 0.8, 0))
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
		library.add_animation(names[index], animation)
	player.add_animation_library(&"", library)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


static func profile() -> PresentationAnimationProfile:
	var result := PresentationAnimationProfile.new()
	result.idle = &"Idle"
	result.move = &"Walk"
	result.sprint = &"Run"
	result.aim = &"Aim"
	result.reload = &"Reload"
	result.dialogue = &"Talk"
	result.fire = &"Shoot"
	result.hit = &"Hit"
	result.dead = &"Death"
	result.impact = &"Impact"
	result.blend_seconds = 0.0
	return result
