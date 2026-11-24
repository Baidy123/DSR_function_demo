extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")
const ShotScene = preload("res://scenes/cinematic/cinematic_shot_3d.tscn")

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var player_camera := Camera3D.new()
	scene.add_child(player_camera)
	player_camera.position = Vector3(0, 8, 8)
	player_camera.look_at(Vector3.ZERO)
	player_camera.make_current()

	var director = Director.new()
	director.configure(scene, {"scene_root": scene})
	scene.add_child(director)
	director.initialize()
	director.set_process(false)

	var shot := ShotScene.instantiate() as CinematicShot3D
	scene.add_child(shot)
	shot.position = Vector3(5, 2, 7)
	shot.pause_world = false
	shot.enter_seconds = 0.1
	shot.hold_seconds = 0.2
	shot.return_seconds = 0.1
	var authored: SceneRequest = director.request_cinematic_shot(shot)
	var camera := root.get_camera_3d()
	_check(authored.status == &"running" and not paused and camera != player_camera,
		"自定义机位由导演切入，并遵守不暂停的配置")

	var target := Marker3D.new()
	scene.add_child(target)
	var target_view: SceneRequest = director.request_action(&"presentation", {
		"source": scene, "target": target, "parameters": {
			"move_seconds": 0.1, "hold_seconds": 0.2, "return_seconds": 0.1,
		},
	})
	_check(target_view.status == &"queued", "指路镜头与自定义机位共用前台队列")
	director.advance(0.15)
	_check(root.get_camera_3d() == camera and camera.global_position.is_equal_approx(shot.global_position),
		"在停留阶段使用手摆机位")
	for _step in range(10):
		director.advance(0.1)
		if target_view.has_started(): break
	_check(authored.status == &"completed" and target_view.status == &"running"
		and root.get_camera_3d() == camera and paused, "旧镜头复用同一相机并照常暂停")
	director.cancel_request(target_view.id)
	_check(target_view.status == &"cancelled" and root.get_camera_3d() == player_camera
		and not paused, "取消旧镜头归还相机和暂停")

	shot.pause_world = true
	var interrupted: SceneRequest = director.request_cinematic_shot(shot)
	shot.free()
	_check(interrupted.status == &"cancelled" and interrupted.reason == &"target_exited"
		and root.get_camera_3d() == player_camera and not paused, "机位离场沿原取消路径恢复")
	scene.free()
	current_scene = null
	print("DIRECTOR SHOT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func _check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1
