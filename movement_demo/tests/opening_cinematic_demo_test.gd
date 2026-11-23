extends SceneTree

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const DemoScene: PackedScene = preload("res://scenes/cinematic/opening_cinematic_demo.tscn")
const Pause = preload("res://scripts/systems/scene_pause_coordinator.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func _run() -> void:
	var state := root.get_node_or_null("GameState")
	check(state != null, "GameState is available")
	if state == null:
		_finish()
		return
	var played_ready: bool = state.get("opening_cinematic_played") != null
	check(played_ready, "GameState records whether the opening demo played")
	if played_ready:
		state.opening_cinematic_played = false
	var defaults = DemoScene.instantiate()
	check(is_equal_approx(defaults.fade_seconds, 0.8)
			and is_equal_approx(defaults.pan_seconds, 2.0)
			and is_equal_approx(defaults.hold_seconds, 1.0)
			and is_equal_approx(defaults.return_seconds, 1.0),
		"Opening uses the required 0.8/2/1/1 default timings")
	defaults.free()

	var skipped := MainScene.instantiate()
	var skipped_demo = skipped.get_node_or_null("OpeningCinematicDemo")
	root.add_child(skipped)
	current_scene = skipped
	await process_frame
	check(skipped_demo != null and not skipped_demo.visible
			and not state.opening_cinematic_played,
		"Script-test main scenes skip the opening unless explicitly enabled")
	skipped.free()
	current_scene = null
	await process_frame

	var scene := MainScene.instantiate()
	var demo = scene.get_node_or_null("OpeningCinematicDemo")
	check(demo != null, "Main scene provides OpeningCinematicDemo")
	if demo == null:
		scene.free()
		_finish()
		return
	demo.run_in_script_tests = true
	demo.fade_seconds = 0.12
	demo.pan_seconds = 0.18
	demo.hold_seconds = 0.4
	demo.return_seconds = 0.12
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: Node3D = scene.get_node("Player")
	check(demo.visible and player.get("is_in_dialogue") == true and not paused,
		"Opening locks the player on the first black frame before world pause")
	check(demo.visible and demo.debug_snapshot().fade_alpha > 0.5,
		"Opening starts from a black overlay and begins fading")
	var controller := scene.get_node("SceneDirector/CinematicCameraController")
	var npc: Node3D = scene.get_node("NPC")
	var source: Camera3D = scene.get_node("Camera3D")
	var phases: Array[StringName] = []
	controller.shot_phase_changed.connect(func(_id: int, phase: StringName) -> void:
		phases.append(phase))
	var hold_view := {}
	var results: Array[StringName] = []
	var paused_and_locked := false
	demo.finished.connect(func(result: StringName) -> void: results.append(result))
	for _frame in 240:
		if controller.get_snapshot().phase != &"idle" and paused and player.get("is_in_dialogue") == true:
			paused_and_locked = true
		if hold_view.is_empty() and controller.get_snapshot().phase == &"hold":
			var camera := root.get_camera_3d()
			if camera != null:
				hold_view = {
					"npc_screen": camera.unproject_position(npc.global_position),
					"center": root.get_visible_rect().size * 0.5,
				}
		if not results.is_empty():
			break
		await process_frame
	check(results == [&"completed"] and demo.debug_snapshot().phase == &"done"
			and phases.has(&"enter") and phases.has(&"hold") and phases.has(&"return"),
		"Opening plays enter, hold and return phases")
	check(paused_and_locked, "Opening keeps the player locked while the cinematic pauses the world")
	var npc_screen: Vector2 = hold_view.get("npc_screen", Vector2.INF)
	var center: Vector2 = hold_view.get("center", Vector2.INF)
	if npc_screen.is_finite() and center.is_finite():
		print("OPENING HOLD SCREEN DELTA ", npc_screen.distance_to(center),
			" npc=", npc_screen, " center=", center)
	check(npc_screen.is_finite() and center.is_finite()
			and npc_screen.distance_to(center) < 2.0,
		"Hold shot centers the task NPC ground anchor")
	check(source.is_current() and not paused and not player.get("is_in_dialogue")
		and not demo.visible and state.opening_cinematic_played,
		"Opening returns the player camera and records the demo as played")
	check(controller.get_snapshot().phase == &"idle"
		and Pause.for_tree(self).snapshot().count == 0,
		"Opening releases cinematic camera and pause ownership")
	scene.free()
	current_scene = null
	await process_frame

	var returned := MainScene.instantiate()
	var returned_demo = returned.get_node_or_null("OpeningCinematicDemo")
	check(returned_demo != null, "Returned tavern scene still contains the optional demo")
	if returned_demo != null:
		returned_demo.run_in_script_tests = true
		root.add_child(returned)
		current_scene = returned
		await process_frame
		var returned_controller := returned.get_node("SceneDirector/CinematicCameraController")
		check(not returned_demo.visible
				and returned_controller.get_snapshot().phase == &"idle"
				and not paused,
			"Returning to tavern does not replay the opening cinematic")
	returned.free()
	current_scene = null

	state.opening_cinematic_played = false
	var cancelled_scene := MainScene.instantiate()
	var cancelled_demo = cancelled_scene.get_node("OpeningCinematicDemo")
	cancelled_demo.run_in_script_tests = true
	cancelled_demo.fade_seconds = 0.05
	cancelled_demo.pan_seconds = 0.4
	root.add_child(cancelled_scene)
	current_scene = cancelled_scene
	var cancelled_controller := cancelled_scene.get_node("SceneDirector/CinematicCameraController")
	for _frame in 120:
		if cancelled_controller.get_snapshot().phase != &"idle":
			break
		await process_frame
	var cancelled_results: Array[StringName] = []
	cancelled_demo.finished.connect(func(result: StringName) -> void:
		cancelled_results.append(result))
	cancelled_controller.cancel_shot(&"opening_test_cancel")
	for _frame in 60:
		if not cancelled_results.is_empty():
			break
		await process_frame
	var cancelled_player: Node3D = cancelled_scene.get_node("Player")
	var cancelled_source: Camera3D = cancelled_scene.get_node("Camera3D")
	check(cancelled_results == [&"cancelled"] and not cancelled_demo.visible
			and cancelled_demo.debug_snapshot().phase == &"error"
			and cancelled_source.is_current() and not paused
			and not cancelled_player.get("is_in_dialogue")
			and cancelled_controller.get_snapshot().phase == &"idle",
		"Opening cancellation hides the overlay and releases control")
	cancelled_scene.free()
	current_scene = null

	state.opening_cinematic_played = false
	var error_scene := MainScene.instantiate()
	var error_demo = error_scene.get_node("OpeningCinematicDemo")
	error_demo.run_in_script_tests = true
	error_demo.fade_seconds = 0.05
	error_demo.source_camera_path = ^"../MissingCamera"
	var error_results: Array[StringName] = []
	error_demo.finished.connect(func(result: StringName) -> void:
		error_results.append(result))
	root.add_child(error_scene)
	current_scene = error_scene
	for _frame in 120:
		if not error_results.is_empty():
			break
		await process_frame
	var error_player: Node3D = error_scene.get_node("Player")
	check(error_results == [&"missing_scene_binding"] and not error_demo.visible
			and error_demo.debug_snapshot().phase == &"error"
			and not error_player.get("is_in_dialogue"),
		"Opening missing binding fails cleanly and releases the player")
	error_scene.free()
	current_scene = null
	state.opening_cinematic_played = false
	_finish()


func _finish() -> void:
	print("OPENING CINEMATIC: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
