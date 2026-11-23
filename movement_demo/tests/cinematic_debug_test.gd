extends SceneTree

const DebugScene = preload("res://scenes/debug/cinematic_camera_debug.tscn")
const DirectorScene = preload("res://scenes/world/scene_director.tscn")
const ShotScene = preload("res://scenes/cinematic/cinematic_shot_3d.tscn")
const Pauses = preload("res://scripts/systems/scene_pause_coordinator.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var settings = root.get_node_or_null("DebugSettings")
	check(settings != null, "DebugSettings autoload is available")
	check(OS.is_debug_build(), "debug panel tests run in a debug build")
	if settings == null or not OS.is_debug_build():
		_finish()
		return
	settings.enabled = false
	var panel = settings.get_node_or_null("CinematicCameraDebug")
	check(panel != null, "DebugSettings owns the cinematic panel only in debug builds")
	if panel == null:
		_finish()
		return

	var fixture := await _create_fixture("CinematicDebugScene")
	var outside := await _create_outside_scene()
	settings.enabled = true
	await process_frame
	panel.refresh()

	var shot_list: OptionButton = panel.get_node("Panel/Content/ShotList")
	var status: Label = panel.get_node("Panel/Content/Status")
	var play_button: Button = panel.get_node("Panel/Content/Play")
	var cancel_button: Button = panel.get_node("Panel/Content/Cancel")
	var expected := PackedStringArray(["AlphaShot", "BrokenShot", "ZuluShot"])
	check(panel.visible, "Enabling Debug shows the cinematic panel")
	check(panel.shot_names() == expected, "Debug panel sorts current-scene shots by node path")
	check(not panel.shot_names().has("OutsideShot"), "Debug panel ignores shots outside the current scene")
	check(shot_list.item_count == expected.size()
			and shot_list.get_item_text(0).contains("/CinematicShots/AlphaShot"),
		"Debug panel displays each Shot path")
	check(panel.current_status() == "idle" and status.text == "idle",
		"Debug panel shows idle")

	var source: Camera3D = fixture.source
	var controller = fixture.controller
	var presentation: Camera3D = controller.get_node("PresentationCamera")
	var original_source_transform := source.global_transform
	shot_list.select(0)
	shot_list.item_selected.emit(0)
	play_button.pressed.emit()
	var active: Dictionary = controller.get_snapshot()
	check(active.phase == &"enter" and active.shot == fixture.alpha,
		"Play delegates the selected Shot to the controller")
	check(presentation.is_current() and presentation.is_cinematic_shot(),
		"Controller owns the active cinematic camera")
	check(panel.current_status().begins_with("enter"),
		"Debug panel reads the controller phase")

	var active_request: int = active.request_id
	play_button.pressed.emit()
	var busy: Dictionary = controller.get_snapshot()
	check(busy.request_id == active_request and busy.phase == &"enter",
		"Busy debug play does not replace the active Shot")
	check(panel.current_status().contains("busy"),
		"Debug panel displays a busy rejection")

	cancel_button.pressed.emit()
	check(controller.get_snapshot().phase == &"idle" and source.is_current(),
		"Cancel delegates to the controller and restores the source camera")
	check(source.global_transform.is_equal_approx(original_source_transform),
		"Debug cancel does not write the source camera")
	await process_frame
	check(panel.current_status().contains("cancelled"),
		"Debug panel retains the recent cancellation result")
	check(Pauses.for_tree(self).snapshot().count == 0 and not paused,
		"Play and cancel leave no debug-owned pause")

	fixture.broken.enter_seconds = NAN
	panel.refresh()
	shot_list.select(1)
	shot_list.item_selected.emit(1)
	play_button.pressed.emit()
	check(controller.get_snapshot().phase == &"idle" and source.is_current(),
		"Invalid Shot errors do not change camera ownership")
	check(panel.current_status().contains("invalid_enter_seconds"),
		"Debug panel displays controller admission errors")

	settings.enabled = false
	await process_frame
	check(not panel.visible, "Disabling Debug hides the cinematic panel")
	check(panel.shot_names().is_empty() and panel.current_status() == "idle",
		"Disabling Debug clears list and status state")
	check(not paused and Pauses.for_tree(self).snapshot().count == 0,
		"Disabling Debug creates no pause")

	settings.enabled = true
	await process_frame
	panel.refresh()
	fixture.alpha.pause_world = true
	shot_list.select(0)
	shot_list.item_selected.emit(0)
	play_button.pressed.emit()
	check(paused and controller.get_snapshot().phase == &"enter",
		"A pausing Shot is owned by the controller, not the panel")
	settings.enabled = false
	await process_frame
	check(paused and controller.get_snapshot().phase == &"enter"
			and presentation.is_cinematic_shot(),
		"Disabling Debug does not override existing controller ownership")

	settings.enabled = true
	await process_frame
	check(panel.visible and panel.current_status().begins_with("enter"),
		"Re-enabling Debug rebinds the active controller state")
	shot_list.select(2)
	shot_list.item_selected.emit(2)
	check(panel.current_status().contains("pause_world=true"),
		"Debug status reads the active controller pause_world instead of the selected Shot")
	fixture.scene.free()
	await process_frame
	check(not paused and Pauses.for_tree(self).snapshot().count == 0,
		"Clearing the scene releases controller camera and pause state")
	check(panel.shot_names().is_empty() and panel.current_status() == "idle",
		"Clearing the scene clears panel references while Debug remains enabled")

	settings.enabled = true
	await process_frame
	panel.refresh()
	check(panel.shot_names().is_empty() and panel.current_status() == "idle",
		"Debug can remain visible without a current scene")
	check(panel.find_children("*", "Camera3D", true, false).is_empty()
			and Pauses.for_tree(self).snapshot().count == 0,
		"Debug UI does not own a camera or pause")

	var replacement := await _create_fixture("CinematicDebugReplacement")
	await process_frame
	panel.refresh()
	check(panel.shot_names() == expected,
		"Debug panel refreshes its Shot list when scene A is replaced by scene B")
	shot_list.select(0)
	shot_list.item_selected.emit(0)
	play_button.pressed.emit()
	check(replacement.controller.get_snapshot().phase == &"enter"
			and replacement.source.is_current() == false,
		"Debug panel rebinds playback to the replacement scene controller")
	cancel_button.pressed.emit()
	await process_frame
	check(replacement.controller.get_snapshot().phase == &"idle"
			and replacement.source.is_current()
			and Pauses.for_tree(self).snapshot().count == 0,
		"Replacement scene cancellation restores its camera and releases pause")
	replacement.scene.free()
	await process_frame

	settings.enabled = false
	current_scene = null
	outside.free()
	await process_frame
	_finish()

func _create_fixture(scene_name: String) -> Dictionary:
	var scene := Node3D.new()
	scene.name = scene_name
	root.add_child(scene)
	current_scene = scene
	var source := Camera3D.new()
	source.name = "PlayerCamera"
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.size = 12.0
	scene.add_child(source)
	var host := DirectorScene.instantiate()
	scene.add_child(host)
	var shots := host.get_node("CinematicShots")
	var zulu: Camera3D = ShotScene.instantiate()
	zulu.name = "ZuluShot"
	zulu.pause_world = false
	shots.add_child(zulu)
	var broken: Camera3D = ShotScene.instantiate()
	broken.name = "BrokenShot"
	broken.pause_world = false
	shots.add_child(broken)
	var alpha: Camera3D = ShotScene.instantiate()
	alpha.name = "AlphaShot"
	alpha.pause_world = false
	shots.add_child(alpha)
	for _frame in range(3): await process_frame
	source.make_current()
	host.director.set_process(false)
	host.director.set_physics_process(false)
	return {
		"scene": scene,
		"source": source,
		"host": host,
		"controller": host.get_node("CinematicCameraController"),
		"alpha": alpha,
		"broken": broken,
		"zulu": zulu,
	}

func _create_outside_scene() -> Node3D:
	var scene := Node3D.new()
	scene.name = "OutsideDebugScene"
	root.add_child(scene)
	var shot: Camera3D = ShotScene.instantiate()
	shot.name = "OutsideShot"
	scene.add_child(shot)
	await process_frame
	return scene

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func _finish() -> void:
	print("CINEMATIC DEBUG: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
