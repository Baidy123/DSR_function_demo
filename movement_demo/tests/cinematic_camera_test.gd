extends SceneTree

const Shot = preload("res://scripts/systems/cinematic/cinematic_shot_3d.gd")
const Presentation = preload("res://scenes/player/presentation_camera.tscn")

var checks := 0
var failures := 0
var results: Array[Dictionary] = []
var world: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var source := Camera3D.new()
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.size = 12.0
	source.position = Vector3(0, 8, 6)
	source.rotation_degrees.x = -55.0
	world.add_child(source)
	source.make_current()
	var shot: Camera3D = Shot.new()
	shot.position = Vector3(8, 5, -4)
	shot.rotation_degrees = Vector3(-48, 25, 0)
	shot.size = 6.0
	shot.enter_seconds = 1.0
	shot.hold_seconds = 1.0
	shot.return_seconds = 1.0
	world.add_child(shot)
	var camera: Camera3D = Presentation.instantiate()
	world.add_child(camera)
	camera.presentation_finished.connect(func(id: int, result: StringName):
		results.append({"id": id, "result": result}))
	check(camera.start_cinematic_shot(source, shot.runtime_snapshot(), 41), "Shot starts")
	check(camera.is_current() and camera.global_transform.is_equal_approx(source.global_transform),
		"Enter starts from the player view")
	camera.advance_presentation(1.0)
	check(camera.is_cinematic_shot() and is_equal_approx(camera.size, 6.0),
		"Enter ends at the authored pose and size")
	source.global_position += Vector3(3, 0, 0)
	source.size = 14.0
	camera.advance_presentation(1.0)
	check(camera.global_transform.is_equal_approx(shot.global_transform), "Hold uses the authored pose")
	camera.advance_presentation(1.0)
	check(source.is_current() and source.get_viewport().get_camera_3d() == source,
		"Return restores the latest player camera")
	print("CINEMATIC CAMERA: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1
