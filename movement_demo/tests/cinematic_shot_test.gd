extends SceneTree

const Shot = preload("res://scripts/systems/cinematic/cinematic_shot_3d.gd")
const ShotScene = preload("res://scenes/cinematic/cinematic_shot_3d.tscn")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func _run() -> void:
	var shot: Camera3D = ShotScene.instantiate()
	root.add_child(shot)
	check(shot is Camera3D and not shot.current, "Shot scene is an inactive Camera3D")
	check(shot.is_in_group(&"cinematic_shot"), "Shot joins the cinematic_shot group")
	check(not shot.is_processing() and not shot.is_physics_processing(), "Shot does not self-tick")
	check(shot.configuration_error() == &"", "Default Shot configuration is valid")
	var snapshot: Dictionary = shot.runtime_snapshot()
	check(snapshot.has("transform") and snapshot.has("size") and snapshot.has("enter_seconds"),
		"Runtime snapshot contains pose, lens and timing")
	shot.enter_seconds = NAN
	check(shot.configuration_error() == &"invalid_enter_seconds", "Invalid enter time is rejected")
	shot.free()
	print("CINEMATIC SHOT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
