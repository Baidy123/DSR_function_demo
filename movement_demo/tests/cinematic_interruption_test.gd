extends SceneTree

const DirectorScene := preload("res://scenes/world/scene_director.tscn")
const ShotScene := preload("res://scenes/cinematic/cinematic_shot_3d.tscn")
const Pauses := preload("res://scripts/systems/scene_pause_coordinator.gd")
const Region := preload("res://scripts/world/shooting_range.gd")
const Wave := preload("res://scripts/world/enemy_wave_definition.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const CameraScene := preload("res://scenes/player/player_camera_rig.tscn")
const SquadScene := preload("res://scenes/world/squad.tscn")
const EnemyScene := preload("res://scenes/enemy/levels/lvl_1/melee.tscn")
const CAPTURE_DIR := "res://logs/cinematic-camera-capture/"

class PlayerSource extends Node3D:
	var is_in_dialogue := false
	var is_facing_npc := false

	func set_dialogue_active(value: bool) -> void:
		is_in_dialogue = value

	func face_npc(_point: Vector3) -> void:
		pass

class HealthSource extends Node:
	signal died
	var is_dead := false

	func die() -> void:
		is_dead = true
		died.emit()

class DialogueSource extends Node:
	signal scene_action_finished(id: int, result: StringName)
	var active_id := 0

	func begin_scene_action(request) -> void:
		active_id = request.id

	func cancel_scene_action(_request, _reason: StringName) -> void:
		active_id = 0

	func complete() -> void:
		var id := active_id
		active_id = 0
		scene_action_finished.emit(id, &"completed")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var settings := root.get_node_or_null("DebugSettings")
	if settings != null:
		settings.enabled = false
	await _case_death_during_phase("enter")
	await _case_death_during_phase("hold")
	await _case_death_during_phase("return")
	await _case_scene_load_cancel()
	await _case_region_reset_cancel()
	await _case_controller_unload_cancel()
	await _case_source_camera_removed()
	await _case_shot_removed_during_play()
	await _case_second_shot_busy()
	await _case_debug_cancel()
	await _case_dialogue_and_shot_coexist()
	await _case_no_pause_death_cancel()
	await _case_no_pause_load_cancel()
	await _case_failed_spawn_has_no_shot()
	await _case_two_waves_same_frame_busy()
	await _case_no_source_camera()
	await _case_source_not_current_external_takeover()
	await _case_pause_menu_blocked()
	await _case_return_source_lost()
	if OS.get_cmdline_user_args().has("--capture"):
		await _run_capture()
	_check(not paused and Pauses.for_tree(self).snapshot().count == 0,
		"the complete interruption matrix leaves no pause owner")
	print("CINEMATIC INTERRUPTION: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func _case_death_during_phase(phase_name: String) -> void:
	var f := await _fixture()
	_configure_long_shot(f.shot)
	_enable_cinematic_shake(f.shot)
	var source_transform: Transform3D = f.source.global_transform
	var source_lens := _source_lens(f.source)
	var player_transform: Transform3D = f.player.global_transform
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	if phase_name == "enter":
		f.director.advance(0.25)
	elif phase_name == "hold":
		f.director.advance(0.75)
	else:
		f.director.advance(1.25)
	_check(f.controller.get_snapshot().phase == StringName(phase_name)
			and request != null and request.status == &"running"
			and f.presentation.get("_shake_position_noise") != null,
		"death fixture reaches %s with deterministic shake active" % phase_name)
	f.health.die()
	_check(request != null and request.status == &"cancelled",
		"death during %s returns cancelled" % phase_name)
	_check(not f.presentation.is_current()
			and f.presentation.global_transform.is_equal_approx(f.source.global_transform)
			and f.presentation.get("_shake_position_noise") == null
			and f.presentation.get("_shake_rotation_noise") == null,
		"death during %s clears presentation shake and restores its source transform" % phase_name)
	_check(f.source.global_transform.is_equal_approx(source_transform)
			and _source_lens(f.source) == source_lens
			and f.player.global_transform.is_equal_approx(player_transform),
		"death during %s leaves the player camera lens and player transform unshaken" % phase_name)
	var death_pause: Array[StringName] = [&"death"]
	_assert_clean(f, "death during " + phase_name, death_pause)
	await _dispose(f)

func _case_scene_load_cancel() -> void:
	var f := await _fixture()
	_enable_cinematic_shake(f.shot)
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	f.director.advance(0.1)
	var elapsed: float = f.controller.get_snapshot().elapsed
	_check(f.presentation.is_cinematic_shot()
			and f.presentation.get("_shake_position_noise") != null,
		"scene load interrupts an active deterministic-shake Shot")
	f.director.scene_loader = func(_path: String, _reload: bool) -> Error:
		return ERR_CANT_OPEN
	f.director.request_change_scene("res://tests/cinematic_missing.tscn")
	var after: Dictionary = f.controller.get_snapshot()
	f.director.advance(0.5)
	_check(request != null and request.status == &"cancelled",
		"scene load cancellation settles the cinematic request")
	_check(after.phase == &"idle" and f.source.is_current()
			and is_equal_approx(f.controller.get_snapshot().elapsed, 0.0)
			and _presentation_clean(f.presentation),
		"scene load stops the Shot clock and restores the player camera")
	var replacement := Camera3D.new()
	replacement.name = "LoadedSceneCamera"
	f.scene.add_child(replacement)
	replacement.make_current()
	f.director.advance(0.5)
	_check(replacement.is_current() and not f.presentation.is_current(),
		"old cinematic ownership cannot steal the loaded scene camera")
	_assert_clean(f, "scene load", [&"loading"], replacement)
	_check(elapsed > 0.0, "scene load interruption began after a real Shot tick")
	await _dispose(f)

func _case_region_reset_cancel() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(
		f.shot, CinematicCameraController.SCOPE_REGION)
	var request = f.director.find_request(admission.request_id)
	f.host.reset_encounter()
	_check(request != null and request.scope == 1
			and request.status == &"cancelled"
			and request.reason == &"region_reset",
		"region reset cancels the regional Shot")
	_check(not f.presentation.is_current()
			and f.presentation.global_transform.is_equal_approx(f.source.global_transform),
		"region reset restores the source camera without a stale shake transform")
	_assert_clean(f, "region reset")
	await _dispose(f)

func _case_controller_unload_cancel() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	var presentation: Camera3D = f.presentation
	f.controller.free()
	await _steps(2)
	var requests: Dictionary = f.director.debug_snapshot().requests
	var baseline: Dictionary = f.view_baseline
	_check(request != null and request.status == &"cancelled",
		"controller unload settles the cinematic request as cancelled")
	_check(f.source.is_current()
			and _presentation_clean(presentation)
			and Pauses.for_tree(self).snapshot().count == 0
			and (requests.requests as Array).is_empty()
			and int(requests.foreground) == 0
			and f.source.global_transform.is_equal_approx(baseline.source_transform)
			and _source_lens(f.source) == baseline.source_lens
			and f.player.global_transform.is_equal_approx(baseline.player_transform),
		"controller unload clears camera, subscriptions, scheduler requests, and pause")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not paused,
		"controller unload leaves mouse and world state clean")
	await _dispose(f, false)

func _case_source_camera_removed() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	var source: Camera3D = f.source
	source.queue_free()
	await _steps(2)
	var requests: Dictionary = f.director.debug_snapshot().requests
	var baseline: Dictionary = f.view_baseline
	_check(request != null and request.status == &"failed"
			and request.reason == &"source_lost",
		"removing the player camera ends playback with source_lost")
	_check(f.controller.get_snapshot().phase == &"idle"
			and not f.presentation.is_current()
			and _presentation_clean(f.presentation)
			and Pauses.for_tree(self).snapshot().count == 0 and not paused
			and (requests.requests as Array).is_empty()
			and int(requests.foreground) == 0
			and f.player.global_transform.is_equal_approx(baseline.player_transform),
		"source removal releases camera and pause ownership without stealing another camera")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"source removal restores visible mouse state")
	await _dispose(f)

func _case_shot_removed_during_play() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	f.shot.free()
	_check(request != null and request.status == &"cancelled",
		"removing the active Shot settles its request as cancelled")
	_check(f.presentation.global_transform.is_equal_approx(f.source.global_transform),
		"Shot removal cannot leave a half-initialized presentation transform")
	_assert_clean(f, "Shot removal")
	await _dispose(f)

func _case_second_shot_busy() -> void:
	var f := await _fixture()
	var second: Camera3D = ShotScene.instantiate()
	second.name = "SecondShot"
	f.host.get_node("CinematicShots").add_child(second)
	var first: Dictionary = f.controller.play_shot(f.shot)
	var first_request = f.director.find_request(first.request_id)
	var second_admission: Dictionary = f.controller.play_shot(second)
	_check(not second_admission.accepted and second_admission.result == &"busy",
		"a second Shot request returns busy without queueing")
	_check(f.controller.get_snapshot().shot == f.shot
			and f.controller.get_snapshot().request_id == first.request_id
			and f.presentation.is_current()
			and Pauses.for_tree(self).snapshot().count == 1,
		"busy admission preserves the active Shot, camera, and single pause token")
	_check(first_request != null and first_request.status == &"running"
			and f.director.debug_snapshot().requests.requests.size() == 1,
		"busy rejection creates no hidden queued Shot request")
	f.controller.cancel_shot(&"test_cleanup")
	_assert_clean(f, "second Shot busy")
	await _dispose(f)

func _case_debug_cancel() -> void:
	var f := await _fixture()
	var settings := root.get_node("DebugSettings")
	settings.enabled = true
	await process_frame
	var panel = settings.get_node("CinematicCameraDebug")
	panel.refresh()
	var shot_list: OptionButton = panel.get_node("Panel/Content/ShotList")
	var play_button: Button = panel.get_node("Panel/Content/Play")
	var cancel_button: Button = panel.get_node("Panel/Content/Cancel")
	var selected := -1
	for index in shot_list.item_count:
		if shot_list.get_item_text(index).begins_with("TestShot"):
			selected = index
			break
	_check(selected >= 0, "Debug interruption fixture enumerates its Shot")
	if selected >= 0:
		shot_list.select(selected)
		shot_list.item_selected.emit(selected)
		play_button.pressed.emit()
	var admission: Dictionary = f.controller.get_snapshot()
	var request = f.director.find_request(admission.get("request_id", 0))
	cancel_button.pressed.emit()
	_check(request != null and request.status == &"cancelled"
			and admission.phase == &"enter",
		"Debug cancel uses the controller cancellation path and settles the request")
	_check(panel.current_status().contains("cancelled"),
		"Debug panel reports its cancellation result")
	_assert_clean(f, "debug cancel")
	settings.enabled = false
	await process_frame
	await _dispose(f)

func _case_dialogue_and_shot_coexist() -> void:
	var f := await _fixture()
	_configure_short_shot(f.shot)
	var dialogue = f.director.request_action(&"dialogue", {
		"source": f.dialogue_provider, "target": f.dialogue_provider,
		"player": f.player, "origin": &"interaction",
	})
	_check(dialogue.status == &"running" and f.player.is_in_dialogue
			and int(f.director.debug_snapshot().requests.foreground) == dialogue.id
			and not paused,
		"production dialogue locks the player and owns foreground without pausing the world")
	var admission: Dictionary = f.controller.play_shot(f.shot)
	_check(dialogue.status == &"running" and admission.accepted
			and paused
			and Pauses.for_tree(self).snapshot().reasons == [&"dialogue", &"cinematic_shot"],
		"a pausing Shot adds the only world pause during production dialogue")
	f.dialogue_provider.complete()
	_check(dialogue.status == &"completed" and paused
			and f.controller.get_snapshot().phase == &"enter"
			and not f.player.is_in_dialogue
			and Pauses.for_tree(self).snapshot().reasons == [&"cinematic_shot"],
		"dialogue can finish first while the Shot keeps the only real world pause")
	f.director.advance(0.31)
	_assert_clean(f, "dialogue before Shot")
	await _dispose(f)

	f = await _fixture()
	_configure_short_shot(f.shot)
	var shot_admission: Dictionary = f.controller.play_shot(f.shot)
	var shot_request = f.director.find_request(shot_admission.request_id)
	dialogue = f.director.request_action(&"dialogue", {
		"source": f.dialogue_provider, "target": f.dialogue_provider,
		"player": f.player, "origin": &"interaction",
	})
	_check(shot_admission.accepted and dialogue.status == &"running"
			and f.player.is_in_dialogue
			and int(f.director.debug_snapshot().requests.foreground) == dialogue.id
			and Pauses.for_tree(self).snapshot().reasons == [&"cinematic_shot", &"dialogue"],
		"dialogue can start after a pausing Shot and still adds no world pause")
	f.director.advance(0.31)
	_check(shot_request != null and shot_request.status == &"completed"
			and not paused
			and f.dialogue_provider.active_id == dialogue.id
			and f.player.is_in_dialogue
			and Pauses.for_tree(self).snapshot().reasons == [&"dialogue"]
			and not Pauses.for_tree(self).snapshot().reasons.has(&"cinematic_shot"),
		"the Shot can finish first and resume the world while dialogue stays locked")
	f.dialogue_provider.complete()
	_assert_clean(f, "Shot before dialogue")
	await _dispose(f)

	f = await _fixture()
	_configure_short_shot(f.shot)
	f.shot.pause_world = false
	dialogue = f.director.request_action(&"dialogue", {
		"source": f.dialogue_provider, "target": f.dialogue_provider,
		"player": f.player, "origin": &"interaction",
	})
	admission = f.controller.play_shot(f.shot)
	_check(dialogue.status == &"running" and admission.accepted
			and f.player.is_in_dialogue and not paused
			and Pauses.for_tree(self).snapshot().reasons == [&"dialogue"],
		"pause_world=false Shot and production dialogue leave the world running")
	f.dialogue_provider.complete()
	_check(not f.player.is_in_dialogue
			and f.controller.get_snapshot().phase == &"enter",
		"ending dialogue first leaves the unpaused Shot active")
	f.director.advance(0.31)
	_assert_clean(f, "unpaused dialogue before Shot")
	await _dispose(f)

func _case_no_pause_death_cancel() -> void:
	var f := await _fixture()
	f.shot.pause_world = false
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	_check(admission.accepted and f.controller.pause_token() == 0
			and not paused,
		"pause_world=false Shot acquires no cinematic pause")
	f.health.die()
	_check(request != null and request.status == &"cancelled"
			and f.controller.get_snapshot().phase == &"idle",
		"death still cancels a Shot that did not own world pause")
	_assert_clean(f, "unpaused death", [&"death"])
	await _dispose(f)

func _case_no_pause_load_cancel() -> void:
	var f := await _fixture()
	f.shot.pause_world = false
	_enable_cinematic_shake(f.shot)
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	f.director.advance(0.1)
	_check(admission.accepted and f.presentation.is_cinematic_shot()
			and f.presentation.get("_shake_position_noise") != null,
		"unpaused scene load interrupts an active deterministic-shake Shot")
	f.director.scene_loader = func(_path: String, _reload: bool) -> Error:
		return ERR_CANT_OPEN
	f.director.request_change_scene("res://tests/cinematic_missing.tscn")
	_check(request != null and request.status == &"cancelled"
			and f.controller.pause_token() == 0
			and f.source.is_current(),
		"loading still cancels a Shot that did not own world pause")
	_assert_clean(f, "unpaused load", [&"loading"])
	await _dispose(f)

func _case_failed_spawn_has_no_shot() -> void:
	var f := await _failed_wave_fixture()
	_check(f.shot is CinematicShot3D
			and f.wave.get_node_or_null(f.wave.cinematic_shot_path) == f.shot,
		"failed-spawn Wave resolves its configured valid CinematicShot3D path")
	var request: bool = f.host.request_wave(f.wave)
	await _steps(8)
	_check(not request and f.controller.get_snapshot().phase == &"idle",
		"failed Wave deployment creates no empty Shot")
	var requests: Dictionary = f.director.debug_snapshot().requests
	_check(not paused and f.source.is_current()
			and Pauses.for_tree(self).snapshot().count == 0
			and (requests.requests as Array).is_empty()
			and int(requests.foreground) == 0,
		"failed Wave deployment acquires no Shot request, pause, or camera takeover")
	_assert_clean(f, "failed spawn")
	await _dispose_wave_fixture(f)

func _case_two_waves_same_frame_busy() -> void:
	var f := await _two_wave_fixture()
	var first_request: bool = f.host.request_wave(f.first_wave)
	var second_request: bool = f.host.request_wave(f.second_wave)
	_check(first_request and second_request,
		"two Waves submit their cinematic requests in the same frame")
	var deployed := await _await_two_waves_active(f)
	var first_id: int = f.controller.get_snapshot().request_id
	_check(deployed and f.controller.get_snapshot().shot == f.first_shot
			and first_id != 0,
		"the first committed Wave owns the single Shot slot")
	_check(_deployed_enemies(f.first_wave).size() > 0
			and _deployed_enemies(f.second_wave).size() > 0
			and f.controller.get_snapshot().request_id == first_id,
		"the second Wave stays deployed when its camera request is busy")
	_check(Pauses.for_tree(self).snapshot().count == 0 and not paused,
		"unpaused same-frame Wave Shots do not create extra pause ownership")
	f.controller.cancel_shot(&"test_cleanup")
	await _steps(4)
	_check(f.controller.get_snapshot().phase == &"idle"
			and _deployed_enemies(f.first_wave).size() > 0
			and _deployed_enemies(f.second_wave).size() > 0,
		"busy is non-destructive and does not queue a later Shot or roll back enemies")
	_assert_clean(f, "same-frame Wave busy")
	await _dispose_wave_fixture(f)

func _case_no_source_camera() -> void:
	var f := await _fixture()
	var source: Camera3D = f.source
	source.clear_current()
	var result: Dictionary = f.controller.play_shot(f.shot)
	_check(not result.accepted and result.result == &"no_source_camera",
		"no current player camera returns no_source_camera")
	_check(f.controller.get_snapshot().phase == &"idle"
			and f.director.debug_snapshot().requests.requests.is_empty()
			and not paused and Pauses.for_tree(self).snapshot().count == 0,
		"no-source rejection creates no request, camera, or pause")
	source.make_current()
	await _dispose(f)

func _case_source_not_current_external_takeover() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	f.director.advance(0.25)
	_check(f.controller.get_snapshot().phase == &"enter"
			and f.presentation.is_cinematic_shot(),
		"takeover fixture is already presenting a non-idle Shot")
	var external := Camera3D.new()
	external.name = "ExternalTakeoverCamera"
	f.scene.add_child(external)
	external.make_current()
	f.director.advance(0.0)
	_check(request != null and request.status == &"failed"
			and request.reason == &"camera_lost",
		"replacing the no-longer-current source stops playback with camera_lost")
	_check(external.is_current() and not f.presentation.is_current()
			and Pauses.for_tree(self).snapshot().count == 0,
		"cinematic cleanup never reclaims a camera owned by the external system")
	_assert_clean(f, "source not current via external takeover", [], external)
	await _dispose(f)

func _case_pause_menu_blocked() -> void:
	var f := await _fixture()
	f.shot.pause_world = false
	var admission: Dictionary = f.controller.play_shot(f.shot)
	f.director.request_pause_menu()
	var menu: CanvasLayer = f.director.get_node("PauseMenu")
	_check(admission.accepted and not menu.visible
			and f.director.get("_menu_token") == 0 and not paused,
		"pause menu cannot stack on an active Shot, including pause_world=false")
	f.controller.cancel_shot(&"test_cleanup")
	_assert_clean(f, "pause menu blocked")
	await _dispose(f)

func _case_return_source_lost() -> void:
	var f := await _fixture()
	f.shot.enter_seconds = 0.0
	f.shot.hold_seconds = 0.0
	f.shot.return_seconds = 1.0
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	f.director.advance(0.0)
	_check(f.controller.get_snapshot().phase == &"return",
		"RETURN source-loss fixture reaches RETURN")
	var source: Camera3D = f.source
	source.free()
	var requests: Dictionary = f.director.debug_snapshot().requests
	var baseline: Dictionary = f.view_baseline
	_check(request != null and request.status == &"failed"
			and request.reason == &"source_lost",
		"losing the player camera during RETURN safely cancels as source_lost")
	_check(f.controller.get_snapshot().phase == &"idle"
			and not f.presentation.is_current()
			and _presentation_clean(f.presentation)
			and not paused and Pauses.for_tree(self).snapshot().count == 0
			and (requests.requests as Array).is_empty()
			and int(requests.foreground) == 0
			and f.player.global_transform.is_equal_approx(baseline.player_transform),
		"RETURN source loss releases presentation and pause without invalid access")
	await _dispose(f)

func _fixture() -> Dictionary:
	var scene := Node3D.new()
	scene.name = "CinematicInterruptionFixture"
	root.add_child(scene)
	current_scene = scene
	var source := Camera3D.new()
	source.name = "PlayerCamera"
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.size = 12.0
	source.position = Vector3(0.0, 8.0, 6.0)
	source.rotation_degrees.x = -55.0
	source.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	scene.add_child(source)
	var player := PlayerSource.new()
	player.name = "Player"
	scene.add_child(player)
	var health := HealthSource.new()
	health.name = "Health"
	player.add_child(health)
	var dialogue := DialogueSource.new()
	dialogue.name = "DialogueProvider"
	scene.add_child(dialogue)
	var host := DirectorScene.instantiate()
	host.name = "SceneDirector"
	host.set("guide_path", NodePath())
	host.set("result_view_path", NodePath())
	host.set("complete_when_all_waves_cleared", false)
	host.set("scene_rules", [])
	scene.add_child(host)
	var shot: Camera3D = ShotScene.instantiate()
	shot.name = "TestShot"
	shot.position = Vector3(8.0, 5.0, -4.0)
	shot.rotation_degrees = Vector3(-48.0, 25.0, 0.0)
	shot.size = 7.0
	host.get_node("CinematicShots").add_child(shot)
	await _steps(3)
	source.make_current()
	host.director.set_process(false)
	host.director.set_physics_process(false)
	return {
		"scene": scene,
		"source": source,
		"player": player,
		"health": health,
		"dialogue_provider": dialogue,
		"host": host,
		"director": host.director,
		"controller": host.get_node("CinematicCameraController"),
		"presentation": host.get_node("CinematicCameraController/PresentationCamera"),
		"shot": shot,
		"view_baseline": _view_baseline(source, player),
	}

func _configure_long_shot(shot: Camera3D) -> void:
	shot.enter_seconds = 0.5
	shot.hold_seconds = 0.5
	shot.return_seconds = 0.5

func _configure_short_shot(shot: Camera3D) -> void:
	shot.enter_seconds = 0.1
	shot.hold_seconds = 0.1
	shot.return_seconds = 0.1

func _enable_cinematic_shake(shot: Camera3D) -> void:
	shot.shake_enabled = true
	shot.shake_position_amplitude = Vector3(0.5, 0.25, 0.4)
	shot.shake_rotation_degrees = Vector3(8.0, 6.0, 5.0)
	shot.shake_frequency = 9.0
	shot.shake_fade_in_seconds = 0.05
	shot.shake_fade_out_seconds = 0.1
	shot.shake_seed = 7341

func _source_lens(source: Camera3D) -> Dictionary:
	return {
		"projection": source.projection,
		"keep_aspect": source.keep_aspect,
		"size": source.size,
		"fov": source.fov,
		"h_offset": source.h_offset,
		"v_offset": source.v_offset,
		"frustum_offset": source.frustum_offset,
		"near": source.near,
		"far": source.far,
		"cull_mask": source.cull_mask,
		"environment": source.environment,
		"attributes": source.attributes,
		"compositor": source.compositor,
	}

func _view_baseline(source: Camera3D, player: Node3D) -> Dictionary:
	return {
		"source_transform": source.global_transform,
		"source_lens": _source_lens(source),
		"player_transform": player.global_transform,
	}

func _presentation_clean(presentation) -> bool:
	if not is_instance_valid(presentation): return true
	var options = presentation.get("_shot_options")
	return not presentation.is_presenting() \
		and presentation.get("_shake_position_noise") == null \
		and presentation.get("_shake_rotation_noise") == null \
		and options is Dictionary and (options as Dictionary).is_empty()

func _assert_clean(f: Dictionary, label: String, expected_reasons: Array[StringName] = [],
		expected_camera: Camera3D = null) -> void:
	var snapshot: Dictionary = f.controller.get_snapshot()
	var pauses: Dictionary = Pauses.for_tree(self).snapshot()
	var requests: Dictionary = f.director.debug_snapshot().requests
	var baseline: Dictionary = f.get("view_baseline", {})
	var source = f.get("source")
	var player = f.get("player")
	var camera: Camera3D = expected_camera if expected_camera != null else f.get("source")
	_check(snapshot.phase == &"idle", label + ": controller idle")
	_check(is_instance_valid(camera) and camera.is_current(),
		label + ": expected camera restored")
	_check(not baseline.is_empty() and is_instance_valid(source) and is_instance_valid(player)
			and source.global_transform.is_equal_approx(baseline.source_transform)
			and _source_lens(source) == baseline.source_lens
			and player.global_transform.is_equal_approx(baseline.player_transform),
		label + ": player camera Transform/lens and player Transform unchanged")
	_check((requests.get("requests", []) as Array).is_empty()
			and int(requests.get("foreground", 0)) == 0,
		label + ": no cinematic or foreground request retained")
	_check(pauses.reasons == expected_reasons,
		label + ": pause ledger has only the expected owners")
	_check(paused == (not expected_reasons.is_empty()),
		label + ": world pause matches expected ownership")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		label + ": mouse mode visible")
	var presentation_clear := true
	var presentation = f.get("presentation")
	if not is_instance_valid(presentation) and is_instance_valid(f.controller):
		presentation = f.controller.get_node_or_null("PresentationCamera")
	if is_instance_valid(presentation):
		presentation_clear = _presentation_clean(presentation)
	_check(presentation_clear,
		label + ": PresentationCamera inactive with no retained shake state")

func _dispose(f: Dictionary, controller_valid: bool = true) -> void:
	if controller_valid and is_instance_valid(f.controller) \
			and f.controller.get_snapshot().phase != &"idle":
		f.controller.cancel_shot(&"test_cleanup")
	if is_instance_valid(f.scene):
		f.scene.free()
	current_scene = null
	await _steps(2)
	_check(not paused and Pauses.for_tree(self).snapshot().count == 0,
		"fixture teardown releases every pause")

func _failed_wave_fixture() -> Dictionary:
	var region: Node3D = Region.new()
	region.name = "FailedCinematicWaveRegion"
	_add_region_environment(region)
	var player: CharacterBody3D = PlayerScene.instantiate() as CharacterBody3D
	player.name = "Player"
	player.position = Vector3(0.0, 0.0, 7.0)
	player.get_node("Health").set("debug_mode", false)
	region.add_child(player)
	var source: Camera3D = CameraScene.instantiate() as Camera3D
	source.name = "Camera3D"
	region.add_child(source)
	var shots := Node3D.new()
	shots.name = "CinematicShots"
	region.add_child(shots)
	var failed_shot := _add_wave_shot(shots, "FailedSpawnShot", Vector3(7.0, 5.0, -4.0))
	var host: Node3D = DirectorScene.instantiate() as Node3D
	host.name = "SceneDirector"
	host.set("guide_path", NodePath())
	host.set("result_view_path", NodePath())
	host.set("complete_when_all_waves_cleared", false)
	host.set("scene_rules", [])
	region.add_child(host)
	var wave: Node3D = Wave.new()
	wave.name = "FailedWave"
	wave.set("start_mode", Wave.StartMode.REQUEST)
	wave.set("cinematic_shot_path", ^"../../CinematicShots/FailedSpawnShot")
	host.add_child(wave)
	root.add_child(region)
	current_scene = region
	await _steps(4)
	source.make_current()
	return {
		"region": region,
		"host": host,
		"director": host.get("director"),
		"controller": host.get_node("CinematicCameraController"),
		"wave": wave,
		"shot": failed_shot,
		"source": source,
		"player": player,
		"view_baseline": _view_baseline(source, player),
	}

func _two_wave_fixture() -> Dictionary:
	var region: Node3D = Region.new()
	region.name = "SameFrameCinematicWaveRegion"
	_add_region_environment(region)
	var player: CharacterBody3D = PlayerScene.instantiate() as CharacterBody3D
	player.name = "Player"
	player.position = Vector3(0.0, 0.0, 7.0)
	player.get_node("Health").set("debug_mode", false)
	region.add_child(player)
	var source: Camera3D = CameraScene.instantiate() as Camera3D
	source.name = "Camera3D"
	region.add_child(source)
	var shots := Node3D.new()
	shots.name = "CinematicShots"
	region.add_child(shots)
	var first_shot := _add_wave_shot(shots, "FirstShot", Vector3(7.0, 5.0, -4.0))
	var second_shot := _add_wave_shot(shots, "SecondShot", Vector3(-7.0, 5.0, 4.0))
	var host: Node3D = DirectorScene.instantiate() as Node3D
	host.name = "SceneDirector"
	host.set("guide_path", NodePath())
	host.set("result_view_path", NodePath())
	host.set("complete_when_all_waves_cleared", false)
	host.set("spawn_retry_seconds", 0.05)
	host.set("scene_rules", [])
	region.add_child(host)
	var first_wave := _add_real_wave(host, "FirstWave", [Vector3(4.0, 0.0, -4.0)])
	var second_wave := _add_real_wave(host, "SecondWave", [Vector3(6.0, 0.0, 4.0)])
	first_wave.set("cinematic_shot_path", ^"../../CinematicShots/FirstShot")
	second_wave.set("cinematic_shot_path", ^"../../CinematicShots/SecondShot")
	root.add_child(region)
	current_scene = region
	await _steps(4)
	source.make_current()
	return {
		"region": region,
		"host": host,
		"director": host.get("director"),
		"controller": host.get_node("CinematicCameraController"),
		"source": source,
		"player": player,
		"view_baseline": _view_baseline(source, player),
		"first_wave": first_wave,
		"second_wave": second_wave,
		"first_shot": first_shot,
		"second_shot": second_shot,
	}

func _add_wave_shot(parent: Node, label: String, position: Vector3) -> Camera3D:
	var shot: Camera3D = ShotScene.instantiate()
	shot.name = label
	shot.position = position
	shot.rotation_degrees = Vector3(-45.0, 20.0, 0.0)
	shot.set("pause_world", false)
	shot.set("enter_seconds", 5.0)
	shot.set("hold_seconds", 5.0)
	shot.set("return_seconds", 5.0)
	parent.add_child(shot)
	return shot

func _add_real_wave(host: Node3D, label: String, positions: Array[Vector3]) -> Node3D:
	var wave: Node3D = Wave.new()
	wave.name = label
	wave.set("start_mode", Wave.StartMode.REQUEST)
	wave.set("search_on_spawn", false)
	host.add_child(wave)
	var squad: Node3D = SquadScene.instantiate() as Node3D
	squad.name = "Squad"
	var profile: Resource = (squad.get("profile") as Resource).duplicate(true)
	profile.set("level", 1)
	squad.set("profile", profile)
	wave.add_child(squad)
	for index in positions.size():
		var enemy: CharacterBody3D = EnemyScene.instantiate() as CharacterBody3D
		enemy.name = "Enemy%d" % (index + 1)
		enemy.position = positions[index]
		enemy.get_node("NavigationAgent3D").set("path_height_offset", 0.0)
		squad.add_child(enemy)
	return wave

func _add_region_environment(region: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(24.0, 0.2, 24.0)
	floor_shape.shape = floor_box
	floor_body.position.y = -0.1
	floor_body.add_child(floor_shape)
	region.add_child(floor_body)
	var navigation := NavigationRegion3D.new()
	navigation.name = "NavigationRegion3D"
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([
		Vector3(-11, 0, -11), Vector3(11, 0, -11),
		Vector3(11, 0, 11), Vector3(-11, 0, 11),
	])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	region.add_child(navigation)
	var zone := Area3D.new()
	zone.name = "CombatZone"
	zone.collision_layer = 0
	var zone_shape := CollisionShape3D.new()
	zone_shape.name = "CollisionShape3D"
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(22.0, 4.0, 22.0)
	zone_shape.shape = zone_box
	zone_shape.position.y = 1.0
	zone.add_child(zone_shape)
	region.add_child(zone)

func _deployed_enemies(wave: Node) -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	var squad := wave.get_node_or_null("Squad")
	if squad == null: return result
	for child in squad.get_children():
		if child is CharacterBody3D: result.append(child)
	return result

func _await_two_waves_active(f: Dictionary) -> bool:
	for _frame in 180:
		if f.host.call("wave_status", f.first_wave) == &"active" \
				and f.host.call("wave_status", f.second_wave) == &"active":
			return true
		await _steps(1)
	print("DIAGNOSTIC ", f.host.call("debug_snapshot"))
	return false

func _dispose_wave_fixture(f: Dictionary) -> void:
	if is_instance_valid(f.controller) \
			and f.controller.get_snapshot().phase != &"idle":
		f.controller.cancel_shot(&"test_cleanup")
	f.region.queue_free()
	await _steps(4)
	current_scene = null
	_check(not paused and Pauses.for_tree(self).snapshot().count == 0,
		"Wave interruption fixture releases pause ownership")

func _steps(count: int) -> void:
	for _frame in count:
		await physics_frame
	await process_frame

func _run_capture() -> void:
	_check(DisplayServer.get_name() != "headless",
		"cinematic capture requires a real rendering backend")
	if DisplayServer.get_name() == "headless":
		return
	root.size = Vector2i(1152, 720)
	root.content_scale_size = root.size
	var scene := Node3D.new()
	scene.name = "CinematicRenderCapture"
	root.add_child(scene)
	current_scene = scene
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.075, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.72)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	scene.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.4
	scene.add_child(light)
	_add_capture_box(scene, Vector3(0.0, -0.2, 0.0), Vector3(22.0, 0.3, 18.0),
		Color(0.16, 0.18, 0.2))
	for index in 9:
		var position := Vector3(float(index % 3 - 1) * 5.0, 0.8 + float(index / 3) * 0.25,
			-3.5 + float(index / 3) * 3.0)
		_add_capture_box(scene, position, Vector3(1.4, 1.6 + float(index % 3) * 0.3, 1.4),
			Color.from_hsv(float(index) / 9.0, 0.65, 0.9))
	var source := Camera3D.new()
	source.name = "PlayerCamera"
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.size = 18.0
	source.position = Vector3(0.0, 11.0, 14.0)
	scene.add_child(source)
	source.look_at(Vector3(0.0, 0.0, 0.0))
	var host: Node3D = DirectorScene.instantiate() as Node3D
	host.name = "SceneDirector"
	host.set("guide_path", NodePath())
	host.set("result_view_path", NodePath())
	host.set("complete_when_all_waves_cleared", false)
	host.set("scene_rules", [])
	scene.add_child(host)
	var shots := host.get_node("CinematicShots")
	var composition: Camera3D = ShotScene.instantiate()
	composition.name = "CompositionShot"
	composition.enter_seconds = 0.5
	composition.hold_seconds = 2.0
	composition.return_seconds = 0.5
	composition.size = 12.0
	composition.position = Vector3(9.0, 6.0, -8.0)
	shots.add_child(composition)
	composition.look_at(Vector3(0.0, 0.0, 0.0))
	var zoom: Camera3D = ShotScene.instantiate()
	zoom.name = "ZoomShot"
	zoom.enter_seconds = 0.0
	zoom.hold_seconds = 1.0
	zoom.return_seconds = 0.0
	zoom.size = 7.0
	shots.add_child(zoom)
	var shake: Camera3D = ShotScene.instantiate()
	shake.name = "ShakeShot"
	shake.enter_seconds = 0.0
	shake.hold_seconds = 2.0
	shake.return_seconds = 1.0
	shake.size = 12.0
	shake.position = Vector3(-8.0, 6.0, -7.0)
	shake.shake_enabled = true
	shake.shake_position_amplitude = Vector3(0.65, 0.4, 0.55)
	shake.shake_rotation_degrees = Vector3(5.0, 7.0, 3.0)
	shake.shake_frequency = 5.0
	shake.shake_fade_in_seconds = 0.1
	shake.shake_fade_out_seconds = 0.2
	shake.shake_seed = 90210
	shots.add_child(shake)
	shake.look_at(Vector3(0.0, 0.0, 0.0))
	await _steps(4)
	source.make_current()
	host.director.set_process(false)
	host.director.set_physics_process(false)
	var controller = host.get_node("CinematicCameraController")
	var presentation: Camera3D = controller.get_node("PresentationCamera")
	var before := await _frame_image()
	var admission: Dictionary = controller.play_shot(composition)
	_check(admission.accepted, "rendered composition Shot starts")
	host.director.advance(0.5)
	var free_camera := await _frame_image()
	_check(_difference(before, free_camera) > 0.01,
		"rendered free-camera composition changes the player view")
	host.director.advance(2.5)
	_check(source.is_current() and controller.get_snapshot().phase == &"idle",
		"rendered composition Shot completes and returns")
	zoom.global_transform = source.global_transform
	admission = controller.play_shot(zoom)
	_check(admission.accepted, "rendered orthographic zoom Shot starts")
	host.director.advance(0.0)
	var zoomed := await _frame_image()
	_check(is_equal_approx(presentation.size, 7.0)
			and _difference(free_camera, zoomed) > 0.01,
		"orthographic zoom has the authored size and a visibly different composition")
	host.director.advance(1.0)
	_check(source.is_current(), "rendered zoom Shot returns to the source")
	admission = controller.play_shot(shake)
	_check(admission.accepted, "rendered deterministic shake Shot starts")
	host.director.advance(0.8)
	var shaken_transform := presentation.global_transform
	var shaken := await _frame_image()
	controller.cancel_shot(&"capture_restart")
	admission = controller.play_shot(shake)
	host.director.advance(0.8)
	_check(admission.accepted and presentation.global_transform.is_equal_approx(shaken_transform),
		"same shake seed and midpoint reproduce the authored camera transform")
	_check(_difference(zoomed, shaken) > 0.005,
		"rendered shake midpoint is visibly distinct from the zoom view")
	host.director.advance(2.2)
	_check(source.is_current(), "rendered shake Shot returns to the source camera")
	var returned := await _frame_image()
	_check(_difference(before, returned) < 0.003 and source.is_current(),
		"rendered return matches the original player view")
	var directory := ProjectSettings.globalize_path(CAPTURE_DIR)
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	var captures := {
		"00-player-baseline": before,
		"01-free-camera-composition": free_camera,
		"02-orthographic-zoom": zoomed,
		"03-deterministic-shake-midpoint": shaken,
		"04-returned-player-view": returned,
	}
	for label: String in captures:
		var image: Image = captures[label]
		if image.save_png(directory.path_join(label + ".png")) != OK:
			error = FAILED
	_check(error == OK and captures.size() == 5,
		"five real-render cinematic captures were saved")
	scene.free()
	current_scene = null
	paused = false
	await _steps(2)
	_check(Pauses.for_tree(self).snapshot().count == 0,
		"render capture fixture releases every pause")

func _add_capture_box(parent: Node3D, at: Vector3, box_size: Vector3, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = at
	parent.add_child(mesh_instance)

func _frame_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _difference(first: Image, second: Image) -> float:
	if first.get_size() != second.get_size() or first.is_empty(): return INF
	var total := 0.0
	var samples := 0
	for y in range(0, first.get_height(), 4):
		for x in range(0, first.get_width(), 4):
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			samples += 3
	return total / float(samples)

func _check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1
