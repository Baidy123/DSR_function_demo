extends SceneTree

const ControllerScene = preload("res://scenes/cinematic/cinematic_camera_controller.tscn")
const ShotScene = preload("res://scenes/cinematic/cinematic_shot_3d.tscn")
const SceneDirectorScene = preload("res://scenes/world/scene_director.tscn")
const Pauses = preload("res://scripts/systems/scene_pause_coordinator.gd")
const FlowAction = preload("res://scripts/systems/scene_flow_action.gd")
const FlowRule = preload("res://scripts/systems/scene_flow_rule.gd")

var checks := 0
var failures := 0

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

class GuideSource extends Node:
	signal finished
	var begins := 0
	var cancels := 0
	func begin() -> void:
		begins += 1
	func cancel() -> void:
		cancels += 1

class MalformedShot extends CinematicShot3D:
	func runtime_snapshot() -> Dictionary:
		return {
			"transform": global_transform,
			"enter_seconds": 0.0,
			"hold_seconds": 0.0,
			"return_seconds": 0.0,
			"pause_world": false,
		}

class ReentrantScript extends Node:
	var controller: Node
	var shot: Camera3D
	var request
	var admission: Dictionary
	func scene_action_is_background() -> bool:
		return true
	func begin_scene_action(value) -> void:
		request = value
		admission = controller.play_shot(shot)
	func cancel_scene_action(_value, _reason: StringName) -> void:
		request = null
	func complete_script() -> void:
		var active = request
		request = null
		active.complete()

class QueueShotAndForeground extends Node:
	var controller: Node
	var director: Node
	var shot: Camera3D
	var foreground_target: Node
	var shot_request
	var foreground_request
	var request

	func scene_action_is_background() -> bool:
		return true

	func begin_scene_action(value) -> void:
		request = value
		shot_request = director.request_action(&"cinematic_shot", {
			"source": controller,
			"target": shot,
			"origin": &"cinematic",
			"parameters": {"snapshot": shot.runtime_snapshot()},
		})
		foreground_request = director.request_action(&"shop", {
			"source": foreground_target,
			"target": foreground_target,
			"origin": &"rule",
		})

	func cancel_scene_action(_value, _reason: StringName) -> void:
		request = null

	func complete_script() -> void:
		var active = request
		request = null
		if active != null:
			active.complete()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _test_scene_hierarchy()
	await _test_wave_runtime_ignores_controller_children()
	await _test_accepted_shot()
	await _test_paused_clock_advances()
	await _test_second_shot_is_busy()
	await _test_dialogue_and_shot_coexist()
	await _test_region_reset_preserves_scene_shot()
	await _test_flow_shot_carries_rule_scope()
	await _test_death_cancels_shot()
	await _test_loading_cancels_shot()
	await _test_unload_cancels_shot()
	await _test_foreground_blocks_shot()
	await _test_dialogue_queued_foreground_and_shot_exclusion()
	await _test_shot_blocks_foreground()
	await _test_pause_menu_blocked()
	await _test_pause_menu_prevents_shot()
	await _test_completion_waits_for_unpaused_shot()
	await _test_invalid_shot_rejected_before_request()
	await _test_no_source_camera_rejected_before_request()
	await _test_unpaused_shot_clock()
	await _test_shot_removal_cancels()
	await _test_stale_camera_completion_ignored()
	await _test_unstarted_admission_is_not_queued()
	await _test_finished_listener_can_start_next_shot()
	await _test_explicit_cancel_settles_request_cancelled()
	await _test_controller_unload_settles_request_cancelled()
	await _test_direct_duplicate_preserves_active_request()
	await _test_start_listener_cancel_settles_request()
	await _test_phase_listener_director_cancel_settles_request()
	var host := Node.new()
	host.name = "SceneDirector"
	root.add_child(host)
	var controller = ControllerScene.instantiate()
	host.add_child(controller)
	var shot: Camera3D = ShotScene.instantiate()
	shot.name = "DebugShot"
	host.add_child(shot)
	check(controller.get_snapshot().phase == &"idle", "Controller starts idle")
	var rejected: Dictionary = controller.play_shot(shot)
	check(not rejected.accepted and rejected.result == &"no_director",
		"Standalone controller rejects without a director")
	print("CINEMATIC CONTROLLER: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _test_scene_hierarchy() -> void:
	var scene := Node3D.new()
	scene.name = "CinematicFixture"
	root.add_child(scene)
	var host := SceneDirectorScene.instantiate()
	scene.add_child(host)
	for _frame in range(3): await process_frame
	var controller = host.get_node_or_null("CinematicCameraController")
	check(controller != null and controller.get_parent() == host,
		"SceneDirector exposes a visible CinematicCameraController child")
	check(controller != null and controller.get_node_or_null("PresentationCamera") != null,
		"Controller owns its PresentationCamera child")
	check(host.get_node_or_null("CinematicShots") != null,
		"SceneDirector provides a CinematicShots authoring container")
	check(controller != null and controller.get("_director") == host.director,
		"SceneDirector binds its internal core to the controller")
	host.free()
	scene.free()
	await process_frame

func _test_wave_runtime_ignores_controller_children() -> void:
	var f := await _fixture()
	f.host.capture_templates(f.scene)
	var runtime: Dictionary = f.host._runtime.debug_snapshot()
	check(runtime.captured and runtime.errors.is_empty() and runtime.state != "ERROR",
		"Wave runtime treats the controller and shot container as scene infrastructure")
	await _dispose(f)

func _test_accepted_shot() -> void:
	var f := await _fixture()
	var controller = f.controller
	var shot = f.shot
	var admission: Dictionary = controller.play_shot(shot)
	var snapshot: Dictionary = controller.get_snapshot()
	check(admission.accepted and admission.result == &"started" and admission.request_id > 0,
		"A valid Shot is accepted through the real SceneDirector")
	check(snapshot.phase == &"enter" and snapshot.shot == shot
			and snapshot.request_id == admission.request_id,
		"Accepted Shot owns the controller request state")
	var camera: Camera3D = controller.get_node("PresentationCamera")
	check(camera.is_current() and camera.is_cinematic_shot(),
		"Accepted Shot creates the one current PresentationCamera")
	controller.cancel_shot(&"test_cleanup")
	await _dispose(f)

func _test_paused_clock_advances() -> void:
	var f := await _fixture()
	f.shot.enter_seconds = 0.1
	f.shot.hold_seconds = 0.1
	f.shot.return_seconds = 0.1
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	check(admission.accepted and paused, "Pausing Shot owns the world pause")
	f.director.advance(0.1)
	check(f.controller.get_snapshot().phase == &"hold",
		"SceneDirector advances the Shot clock while the tree is paused")
	f.director.advance(0.1)
	check(f.controller.get_snapshot().phase == &"return",
		"Paused Shot clock continues across phase boundaries")
	f.director.advance(0.1)
	check(f.controller.get_snapshot().phase == &"idle" and f.source.is_current()
			and request != null and request.status == &"completed"
			and request.get_result().get("cinematic_result") == &"completed",
		"Paused Shot clock completes the request and restores the player camera")
	await _dispose(f)

func _test_second_shot_is_busy() -> void:
	var f := await _fixture()
	var first: Dictionary = f.controller.play_shot(f.shot)
	var camera: Camera3D = f.controller.get_node("PresentationCamera")
	var second: Dictionary = f.controller.play_shot(f.shot)
	check(not second.accepted and second.result == &"busy",
		"A second Shot is rejected without queueing")
	check(f.controller.get_snapshot().request_id == first.request_id
			and camera.is_cinematic_shot() and camera.is_current(),
		"Busy rejection preserves the active Shot and camera ownership")
	check(Pauses.for_tree(self).snapshot().count == 1,
		"Busy rejection does not acquire another pause token")
	f.controller.cancel_shot(&"test_cleanup")
	await _dispose(f)

func _test_dialogue_and_shot_coexist() -> void:
	var f := await _fixture()
	f.shot.enter_seconds = 0.0
	f.shot.hold_seconds = 0.1
	f.shot.return_seconds = 0.0
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var dialogue = f.director.request_action(&"dialogue", {
		"source": f.dialogue_provider, "target": f.dialogue_provider,
		"player": f.player, "origin": &"interaction",
	})
	check(admission.accepted and dialogue.has_started() and dialogue.status == &"running"
			and f.player.is_in_dialogue
			and int(f.director.debug_snapshot().requests.foreground) == dialogue.id
			and Pauses.for_tree(self).snapshot().reasons == [&"cinematic_shot", &"dialogue"],
		"Production dialogue can start during a Shot, locks the player, and adds no world pause")
	f.director.advance(0.1)
	check(f.controller.get_snapshot().phase == &"idle" and f.source.is_current(),
		"Dialogue plus Shot advances the Shot clock to completion")
	check(not paused and dialogue.status == &"running" and f.player.is_in_dialogue
			and Pauses.for_tree(self).snapshot().reasons == [&"dialogue"],
		"Shot completion resumes the world while production dialogue stays locked")
	f.dialogue_provider.complete()
	check(dialogue.status == &"completed" and not f.player.is_in_dialogue,
		"Dialogue completion releases its own deferred controls")
	await _dispose(f)
	f = await _fixture()
	dialogue = f.director.request_action(&"dialogue", {
		"source": f.dialogue_provider, "target": f.dialogue_provider,
		"player": f.player, "origin": &"interaction",
	})
	admission = f.controller.play_shot(f.shot)
	check(dialogue.has_started() and admission.accepted
			and f.controller.get_snapshot().phase == &"enter"
			and f.player.is_in_dialogue and paused
			and Pauses.for_tree(self).snapshot().reasons == [&"dialogue", &"cinematic_shot"],
		"A pausing Shot adds the sole world pause behind production dialogue")
	f.controller.cancel_shot(&"test_cleanup")
	f.dialogue_provider.complete()
	await _dispose(f)

func _test_region_reset_preserves_scene_shot() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	var presentation: Camera3D = f.controller.get_node("PresentationCamera")
	check(admission.accepted and request != null and request.scope == 0,
		"Direct play_shot admission is explicitly scene-scoped")
	f.director.reset_region()
	check(request != null and request.status == &"running"
			and f.controller.get_snapshot().phase != &"idle"
			and presentation.is_current(),
		"Region reset preserves a direct scene-scoped Shot")
	check(paused and Pauses.for_tree(self).snapshot().reasons == [&"cinematic_shot"],
		"Preserving a scene Shot also preserves only its own pause owner")
	f.controller.cancel_shot(&"test_cleanup")
	var region_entry = f.director.request_action(&"cinematic_shot", {
		"source": f.controller,
		"target": f.shot,
		"origin": &"wave",
		"scope": 1,
		"scope_owner": f.director.region_owner(),
		"parameters": {"snapshot": f.shot.runtime_snapshot()},
	})
	check(region_entry.status == &"running" and region_entry.scope == 1,
		"A region-scoped cinematic request starts")
	f.director.reset_region()
	check(region_entry.status == &"cancelled"
			and region_entry.reason == &"region_reset"
			and f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current(),
		"Region reset still cancels a regional Shot and restores the player camera")
	await _dispose(f)

func _test_flow_shot_carries_rule_scope() -> void:
	for rule_scope in [FlowRule.Scope.SCENE, FlowRule.Scope.REGION]:
		var f := await _fixture()
		var action := FlowAction.new()
		action.kind = FlowAction.Kind.PLAY_CINEMATIC_SHOT
		action.target_path = ^"CinematicShots/TestShot"
		var rule := FlowRule.new()
		rule.label = "scope-%s" % rule_scope
		rule.scope = rule_scope
		rule.actions.append(action)
		f.director._flows.configure([rule])
		f.director.advance(0.0)
		var request = f.director.find_request(f.controller.get_snapshot().request_id)
		check(request != null and request.scope == rule_scope
				and f.controller.get_snapshot().phase != &"idle",
			"PLAY_CINEMATIC_SHOT carries its rule scope: %s" % rule_scope)
		f.director.reset_region()
		if rule_scope == FlowRule.Scope.SCENE:
			check(request != null and request.status == &"running"
					and f.controller.get_snapshot().phase != &"idle",
				"Region reset preserves a scene-scoped flow Shot")
			f.controller.cancel_shot(&"test_cleanup")
		else:
			check(request != null and request.status == &"cancelled"
					and f.controller.get_snapshot().phase == &"idle",
				"Region reset cancels a region-scoped flow Shot")
		await _dispose(f)

func _test_death_cancels_shot() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	f.health.die()
	check(f.controller.get_snapshot().phase == &"idle" and f.source.is_current()
			and request != null and request.status == &"cancelled",
		"Death cancels the Shot request and restores the player camera")
	check(f.director.state == &"dead" and paused
			and Pauses.for_tree(self).snapshot().reasons == [&"death"],
		"Death cancellation preserves only terminal death ownership")
	await _dispose(f)

func _test_loading_cancels_shot() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	f.director.scene_loader = func(_path: String, _reload: bool) -> Error:
		return ERR_CANT_OPEN
	f.director.request_change_scene("res://tests/cinematic_missing.tscn")
	check(f.controller.get_snapshot().phase == &"idle" and f.source.is_current()
			and request != null and request.status == &"cancelled",
		"Loading cancels the Shot request and restores the player camera")
	check(f.director.state == &"loading" and paused
			and Pauses.for_tree(self).snapshot().reasons == [&"loading"],
		"Loading cancellation preserves only terminal load ownership")
	await _dispose(f)

func _test_unload_cancels_shot() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	f.scene.free()
	await process_frame
	check(request != null and request.status == &"cancelled" and not paused
			and Pauses.for_tree(self).snapshot().count == 0,
		"Scene unload cancels the Shot request and releases every pause")

func _test_foreground_blocks_shot() -> void:
	var f := await _fixture()
	var shop_request = f.director.request_action(&"shop", {
		"source": f.dialogue_provider, "target": f.dialogue_provider,
		"player": f.player, "origin": &"rule",
	})
	var admission: Dictionary = f.controller.play_shot(f.shot)
	check(shop_request.has_started() and not admission.accepted and admission.result == &"busy",
		"A non-dialogue foreground request blocks a new cinematic Shot")
	check(f.controller.get_snapshot().phase == &"idle" and f.source.is_current()
			and not paused,
		"Foreground admission rejection creates no camera or pause")
	f.director.cancel_request(shop_request.id, &"test_cleanup")
	var guide := GuideSource.new()
	f.scene.add_child(guide)
	var guide_request = f.director.request_action(&"guide", {
		"source": f.host, "target": guide, "origin": &"rule",
		"parameters": {"pause_world": false},
	})
	admission = f.controller.play_shot(f.shot)
	check(guide_request.has_started() and guide.begins == 1
			and not admission.accepted and admission.result == &"busy",
		"An active guide also blocks a new cinematic Shot")
	f.director.cancel_request(guide_request.id, &"test_cleanup")
	await _dispose(f)

func _test_dialogue_queued_foreground_and_shot_exclusion() -> void:
	for queued_kind in [&"shop", &"guide", &"presentation"]:
		var f := await _fixture()
		var dialogue = f.director.request_action(&"dialogue", {
			"source": f.dialogue_provider, "target": f.dialogue_provider,
			"player": f.player, "origin": &"interaction",
		})
		var queued
		if queued_kind == &"guide":
			var guide := GuideSource.new()
			guide.name = "QueuedGuide"
			f.scene.add_child(guide)
			queued = f.director.request_action(&"guide", {
				"source": f.host, "target": guide, "origin": &"rule",
				"parameters": {"pause_world": false},
			})
		elif queued_kind == &"presentation":
			queued = f.director.request_action(&"presentation", {
				"source": f.host, "target": f.player, "origin": &"rule",
			})
		else:
			queued = f.director.request_action(&"shop", {
				"source": f.dialogue_provider, "target": f.dialogue_provider,
				"player": f.player, "origin": &"rule",
			})
		var admission: Dictionary = f.controller.play_shot(f.shot)
		check(dialogue.status == &"running" and queued.status == &"queued"
				and not admission.accepted and admission.result == &"busy",
			"A queued %s foreground blocks Shot admission" % queued_kind)
		check(f.controller.get_snapshot().phase == &"idle"
				and f.source.is_current() and not paused
				and f.director.debug_snapshot().requests.requests.size() == 2,
			"A queued %s rejection creates no camera or pause ownership" % queued_kind)
		f.director.cancel_request(queued.id, &"test_cleanup")
		f.dialogue_provider.complete()
		await _dispose(f)

	var f := await _fixture()
	var dialogue = f.director.request_action(&"dialogue", {
		"source": f.dialogue_provider, "target": f.dialogue_provider,
		"player": f.player, "origin": &"interaction",
	})
	var queueing := QueueShotAndForeground.new()
	queueing.name = "QueueShotAndForeground"
	queueing.controller = f.controller
	queueing.director = f.director
	queueing.shot = f.shot
	queueing.foreground_target = f.dialogue_provider
	f.scene.add_child(queueing)
	var outer = f.director.request_action(&"script", {
		"source": f.host, "target": queueing, "origin": &"rule",
		"parameters": {"mode": &"provider"},
	})
	check(dialogue.status == &"running" and outer.status == &"running"
			and queueing.shot_request.status == &"queued"
			and queueing.foreground_request.status == &"queued",
		"Dialogue can queue a Shot followed by a non-dialogue foreground")
	f.dialogue_provider.complete()
	queueing.complete_script()
	f.director.advance(0.0)
	check(f.controller.get_snapshot().phase != &"idle"
			and queueing.foreground_request.status == &"queued"
			and f.dialogue_provider.active_id == 0,
		"A queued non-dialogue foreground cannot start while the Shot is active")
	f.director.cancel_request(queueing.foreground_request.id, &"test_cleanup")
	f.controller.cancel_shot(&"test_cleanup")
	await _dispose(f)

func _test_shot_blocks_foreground() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var shop_request = f.director.request_action(&"shop", {
		"source": f.dialogue_provider, "target": f.dialogue_provider,
		"player": f.player, "origin": &"rule",
	})
	check(admission.accepted and shop_request.status == &"rejected"
			and shop_request.reason == &"cinematic_busy",
		"An active Shot rejects non-dialogue foreground requests")
	check(f.dialogue_provider.active_id == 0
			and f.controller.get_snapshot().request_id == admission.request_id,
		"Foreground busy rejection has no provider side effect and preserves the Shot")
	var guide := GuideSource.new()
	f.scene.add_child(guide)
	var guide_request = f.director.request_action(&"guide", {
		"source": f.host, "target": guide, "origin": &"rule",
		"parameters": {"pause_world": false},
	})
	check(guide_request.status == &"rejected" and guide_request.reason == &"cinematic_busy"
			and guide.begins == 0,
		"A Shot rejects a guide before it can take foreground ownership")
	f.controller.cancel_shot(&"test_cleanup")
	await _dispose(f)

func _test_pause_menu_blocked() -> void:
	var f := await _fixture()
	f.shot.pause_world = false
	var admission: Dictionary = f.controller.play_shot(f.shot)
	f.director.request_pause_menu()
	var menu: CanvasLayer = f.director.get_node("PauseMenu")
	check(admission.accepted and not paused and not menu.visible
			and f.director.get("_menu_token") == 0,
		"Pause menu cannot open during an unpaused cinematic Shot")
	if menu.visible:
		f.director.resume_from_pause_menu()
	f.controller.cancel_shot(&"test_cleanup")
	await _dispose(f)

func _test_pause_menu_prevents_shot() -> void:
	var f := await _fixture()
	f.director.request_pause_menu()
	var menu: CanvasLayer = f.director.get_node("PauseMenu")
	var admission: Dictionary = f.controller.play_shot(f.shot)
	check(menu.visible and paused and f.director.get("_menu_token") != 0
			and not admission.accepted and admission.result == &"busy",
		"A scripted Shot is rejected while the normal pause menu owns control")
	check(f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current()
			and Pauses.for_tree(self).snapshot().reasons == [&"pause_menu"],
		"Pause-menu rejection switches no camera and leaks no cinematic pause")
	check(f.director.debug_snapshot().requests.requests.is_empty(),
		"Pause-menu rejection creates no queued or active cinematic request")
	if f.controller.get_snapshot().phase != &"idle":
		f.controller.cancel_shot(&"test_reset")
	f.director.resume_from_pause_menu()

	var owner := Node.new()
	owner.name = "ExternalPauseOwner"
	f.scene.add_child(owner)
	var token: int = Pauses.for_tree(self).acquire(owner, &"test_pause_owner", true, true)
	admission = f.controller.play_shot(f.shot)
	check(token != 0 and paused and not admission.accepted and admission.result == &"busy",
		"A managed non-dialogue pause owner blocks scripted Shot admission")
	check(f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current()
			and Pauses.for_tree(self).snapshot().reasons == [&"test_pause_owner"],
		"Managed-pause rejection preserves the existing owner and player camera")
	Pauses.for_tree(self).release(token)
	await _dispose(f)

func _test_completion_waits_for_unpaused_shot() -> void:
	var f := await _fixture()
	f.shot.pause_world = false
	f.shot.enter_seconds = 0.1
	f.shot.hold_seconds = 0.1
	f.shot.return_seconds = 0.1
	var action := FlowAction.new()
	action.kind = FlowAction.Kind.COMPLETE_SCENE
	var rule := FlowRule.new()
	rule.label = "completion-barrier"
	rule.actions.append(action)
	f.director._flows.configure([rule])
	var admission: Dictionary = f.controller.play_shot(f.shot)
	f.director.advance(0.0)
	await process_frame
	f.director.advance(0.0)
	check(admission.accepted and f.controller.get_snapshot().phase == &"enter"
			and f.director.state == &"running"
			and bool(f.director.debug_snapshot().completion_pending),
		"COMPLETE_SCENE does not promote an active unpaused Shot to victory")
	f.director.advance(0.31)
	check(f.director.state == &"completed"
			and f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current(),
		"COMPLETE_SCENE promotes only after the unpaused Shot finishes and restores the player camera")
	await _dispose(f)

	f = await _fixture()
	f.shot.pause_world = false
	f.shot.enter_seconds = 0.1
	f.shot.hold_seconds = 0.1
	f.shot.return_seconds = 0.1
	f.director._bindings["auto_complete_waves"] = true
	admission = f.controller.play_shot(f.shot)
	f.host._runtime.encounter_completed.emit()
	check(admission.accepted and f.controller.get_snapshot().phase == &"enter"
			and f.director.state == &"running"
			and bool(f.director.debug_snapshot().completion_pending),
		"Automatic wave completion waits for an active unpaused Shot")
	await process_frame
	f.director.advance(0.1)
	check(f.controller.get_snapshot().phase != &"idle"
			and f.director.state == &"running",
		"Automatic completion remains pending during the Shot's later phases")
	f.director.advance(0.21)
	check(f.director.state == &"completed"
			and f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current(),
		"Automatic completion finishes after the Shot and camera restoration")
	await _dispose(f)

func _test_invalid_shot_rejected_before_request() -> void:
	var f := await _fixture()
	var malformed := MalformedShot.new()
	malformed.name = "MalformedShot"
	f.host.get_node("CinematicShots").add_child(malformed)
	var malformed_result: Dictionary = f.controller.play_shot(malformed)
	check(not malformed_result.accepted and malformed_result.result == &"invalid_shot"
			and f.director.debug_snapshot().requests.requests.is_empty(),
		"Malformed runtime Snapshot is rejected before creating a request")
	var direct_snapshot: Dictionary = f.shot.runtime_snapshot()
	direct_snapshot.erase("shake_frequency")
	var direct_malformed = f.director.request_action(&"cinematic_shot", {
		"source": f.controller,
		"target": f.shot,
		"origin": &"cinematic",
		"parameters": {"snapshot": direct_snapshot},
	})
	check(direct_malformed.status == &"failed"
			and direct_malformed.reason == &"invalid_shot"
			and f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current() and not paused
			and f.director.debug_snapshot().requests.requests.is_empty(),
		"A direct malformed cinematic snapshot rejects before ownership")
	direct_snapshot = f.shot.runtime_snapshot()
	direct_snapshot["shake_frequency"] = 0.0
	var direct_zero = f.director.request_action(&"cinematic_shot", {
		"source": f.controller,
		"target": f.shot,
		"origin": &"cinematic",
		"parameters": {"snapshot": direct_snapshot},
	})
	check(direct_zero.status == &"failed"
			and direct_zero.reason == &"invalid_shot"
			and f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current() and not paused
			and f.director.debug_snapshot().requests.requests.is_empty(),
		"A direct zero-frequency snapshot rejects before camera or pause ownership")
	if f.controller.get_snapshot().phase != &"idle":
		f.controller.cancel_shot(&"test_reset")
	f.shot.enter_seconds = NAN
	var invalid_result: Dictionary = f.controller.play_shot(f.shot)
	check(not invalid_result.accepted and invalid_result.result == &"invalid_enter_seconds"
			and f.director.debug_snapshot().requests.requests.is_empty()
			and not paused and f.source.is_current(),
		"Invalid Shot timing is rejected without camera or pause side effects")
	await _dispose(f)

func _test_no_source_camera_rejected_before_request() -> void:
	var f := await _fixture()
	f.source.clear_current()
	var result: Dictionary = f.controller.play_shot(f.shot)
	check(not result.accepted and result.result == &"no_source_camera"
			and f.director.debug_snapshot().requests.requests.is_empty()
			and not paused,
		"Missing source camera rejects before request creation and pause")
	await _dispose(f)

func _test_unpaused_shot_clock() -> void:
	var f := await _fixture()
	f.shot.pause_world = false
	f.shot.enter_seconds = 0.1
	f.shot.hold_seconds = 0.1
	f.shot.return_seconds = 0.1
	var admission: Dictionary = f.controller.play_shot(f.shot)
	check(admission.accepted and f.controller.pause_token() == 0 and not paused,
		"pause_world=false Shot acquires no cinematic pause token")
	f.director.advance(0.1)
	f.director.advance(0.1)
	check(f.controller.get_snapshot().phase == &"return",
		"Unpaused Shot clock advances through the normal director path")
	f.director.advance(0.1)
	check(f.controller.get_snapshot().phase == &"idle" and f.source.is_current(),
		"Unpaused Shot completes and restores the player camera")
	await _dispose(f)

func _test_shot_removal_cancels() -> void:
	var f := await _fixture()
	f.controller.play_shot(f.shot)
	f.shot.free()
	check(f.controller.get_snapshot().phase == &"idle" and f.source.is_current()
			and not paused,
		"Removing the active Shot cancels it and releases camera and pause ownership")
	await _dispose(f)

func _test_stale_camera_completion_ignored() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var camera: Camera3D = f.controller.get_node("PresentationCamera")
	camera.presentation_finished.emit(admission.request_id + 100, &"completed")
	check(f.controller.get_snapshot().phase == &"enter" and camera.is_cinematic_shot(),
		"Stale PresentationCamera completion cannot finish the active Shot")
	f.controller.cancel_shot(&"test_cleanup")
	await _dispose(f)

func _test_unstarted_admission_is_not_queued() -> void:
	var f := await _fixture()
	var script := ReentrantScript.new()
	script.controller = f.controller
	script.shot = f.shot
	script.name = "ReentrantScript"
	f.scene.add_child(script)
	var outer = f.director.request_action(&"script", {
		"source": f.host, "target": script, "origin": &"rule",
		"parameters": {"mode": &"provider"},
	})
	check(outer.has_started() and not script.admission.accepted
			and script.admission.result == &"busy",
		"Re-entrant admission reports busy instead of pretending the Shot started")
	script.complete_script()
	f.director.advance(0.0)
	check(f.controller.get_snapshot().phase == &"idle" and f.source.is_current()
			and f.director.debug_snapshot().requests.requests.is_empty(),
		"Busy re-entrant admission is cancelled rather than left in the scheduler queue")
	await _dispose(f)

func _test_finished_listener_can_start_next_shot() -> void:
	var f := await _fixture()
	var second := ShotScene.instantiate()
	second.name = "SecondShot"
	f.host.get_node("CinematicShots").add_child(second)
	f.shot.enter_seconds = 0.05
	f.shot.hold_seconds = 0.05
	f.shot.return_seconds = 0.05
	second.enter_seconds = 0.0
	second.hold_seconds = 1.0
	second.return_seconds = 0.0
	var first: Dictionary = f.controller.play_shot(f.shot)
	var first_request = f.director.find_request(first.request_id)
	var second_admissions: Array[Dictionary] = []
	var finished: Array[Dictionary] = []
	var callback := func(id: int, result: StringName) -> void:
		finished.append({"id": id, "result": result})
		second_admissions.append(f.controller.play_shot(second))
	f.controller.shot_finished.connect(callback)
	f.director.advance(1.0)
	if f.controller.shot_finished.is_connected(callback):
		f.controller.shot_finished.disconnect(callback)
	check(first_request != null and first_request.status == &"completed"
			and first_request.get_result().get("status") == &"completed",
		"Shot completion settles the old request before the public signal")
	var waiter: Dictionary = {}
	if first_request != null and first_request.is_terminal():
		waiter = await first_request.wait_result()
	check(waiter.get("status") == &"completed",
		"A first-request waiter resumes instead of hanging")
	check(not second_admissions.is_empty()
			and second_admissions[0].get("accepted", false),
		"A completion listener can immediately start the next Shot")
	check(f.controller.get_snapshot().shot == second,
		"The listener-started Shot becomes the controller's active Shot")
	check(not second_admissions.is_empty()
			and f.controller.get_snapshot().request_id
				== second_admissions[0].get("request_id", 0),
		"The listener-started Shot owns a clean request id")
	f.controller.cancel_shot(&"test_cleanup")
	await _dispose(f)

func _test_explicit_cancel_settles_request_cancelled() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	var cancelled: bool = f.controller.cancel_shot(&"manual")
	check(cancelled and f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current(),
		"Explicit cancel restores the player camera and clears controller state")
	check(request != null and request.status == &"cancelled"
			and request.get_result().get("status") == &"cancelled",
		"Explicit cancel settles the SceneRequest as cancelled, not failed")
	check(not paused and Pauses.for_tree(self).snapshot().count == 0,
		"Explicit cancel releases its pause token")
	await _dispose(f)

func _test_controller_unload_settles_request_cancelled() -> void:
	var f := await _fixture()
	var admission: Dictionary = f.controller.play_shot(f.shot)
	var request = f.director.find_request(admission.request_id)
	f.controller.free()
	await process_frame
	check(request != null and request.status == &"cancelled"
			and request.get_result().get("status") == &"cancelled",
		"Controller-only unload settles its SceneRequest as cancelled")
	check(f.source.is_current() and not paused
			and Pauses.for_tree(self).snapshot().count == 0,
		"Controller-only unload restores the camera and releases its pause")
	await _dispose(f)

func _test_direct_duplicate_preserves_active_request() -> void:
	var f := await _fixture()
	f.shot.enter_seconds = 0.05
	f.shot.hold_seconds = 0.05
	f.shot.return_seconds = 0.05
	var context := {
		"source": f.controller,
		"target": f.shot,
		"origin": &"system",
		"parameters": {"snapshot": f.shot.runtime_snapshot()},
	}
	var first = f.director.request_action(&"cinematic_shot", context)
	var second = f.director.request_action(&"cinematic_shot", context)
	check(first.status == &"running"
			and f.controller.get_snapshot().request_id == first.id,
		"The first direct cinematic request owns the active slot")
	check(second.status == &"rejected" and second.reason == &"busy",
		"A duplicate direct cinematic request is rejected as busy")
	check(f.controller.get_snapshot().request_id == first.id,
		"Rejected duplicate admission cannot overwrite the first request id")
	f.director.advance(1.0)
	check(first.status == &"completed" and first.get_result().get("status") == &"completed"
			and f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current(),
		"The original direct request still completes normally")
	await _dispose(f)

func _test_start_listener_cancel_settles_request() -> void:
	var f := await _fixture()
	var requests: Array = []
	var cancellations: Array[bool] = []
	var callback := func(id: int, _shot: CinematicShot3D) -> void:
		requests.append(f.director.find_request(id))
		cancellations.append(f.controller.cancel_shot(&"start_listener"))
	f.controller.shot_started.connect(callback)
	var admission: Dictionary = f.controller.play_shot(f.shot)
	if f.controller.shot_started.is_connected(callback):
		f.controller.shot_started.disconnect(callback)
	var request = requests[0] if not requests.is_empty() else null
	check(cancellations == [true]
			and request != null and request.status == &"cancelled"
			and request.get_result().get("status") == &"cancelled",
		"shot_started cancellation settles the request as cancelled")
	check(not admission.get("accepted", true)
			and f.controller.get_snapshot().phase == &"idle"
			and f.source.is_current() and not paused
			and Pauses.for_tree(self).snapshot().count == 0,
		"shot_started cancellation returns camera and pause ownership")
	var next: Dictionary = f.controller.play_shot(f.shot)
	check(next.get("accepted", false)
			and f.controller.get_snapshot().request_id == next.get("request_id", 0),
		"A start-listener cancellation leaves no stale request slot")
	f.controller.cancel_shot(&"test_cleanup")
	await _dispose(f)

func _test_phase_listener_director_cancel_settles_request() -> void:
	var f := await _fixture()
	var requests: Array = []
	var callback := func(id: int, phase: StringName) -> void:
		if phase != &"enter": return
		requests.append(f.director.find_request(id))
		f.director.cancel_request(id, &"phase_listener")
	f.controller.shot_phase_changed.connect(callback)
	f.controller.play_shot(f.shot)
	if f.controller.shot_phase_changed.is_connected(callback):
		f.controller.shot_phase_changed.disconnect(callback)
	var request = requests[0] if not requests.is_empty() else null
	check(request != null and request.status == &"cancelled"
			and request.get_result().get("status") == &"cancelled",
		"Director cancellation from a phase listener settles the request")
	check(f.controller.get_snapshot().phase == &"idle" and f.source.is_current()
			and not paused and Pauses.for_tree(self).snapshot().count == 0,
		"Phase-listener director cancellation stops the camera and releases ownership")
	var next: Dictionary = f.controller.play_shot(f.shot)
	check(next.get("accepted", false)
			and f.controller.get_snapshot().request_id == next.get("request_id", 0),
		"Phase-listener cancellation cannot poison future cinematic admission")
	f.controller.cancel_shot(&"test_cleanup")
	await _dispose(f)

func _fixture() -> Dictionary:
	var scene := Node3D.new()
	scene.name = "CinematicFixture"
	root.add_child(scene)
	var source := Camera3D.new()
	source.name = "PlayerCamera"
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.size = 12.0
	scene.add_child(source)
	var player := PlayerSource.new()
	player.name = "Player"
	scene.add_child(player)
	var health := HealthSource.new()
	health.name = "Health"
	player.add_child(health)
	var dialogue_provider := DialogueSource.new()
	dialogue_provider.name = "DialogueProvider"
	scene.add_child(dialogue_provider)
	var host := SceneDirectorScene.instantiate()
	scene.add_child(host)
	var shot: Camera3D = ShotScene.instantiate()
	shot.name = "TestShot"
	host.get_node("CinematicShots").add_child(shot)
	for _frame in range(3): await process_frame
	source.make_current()
	host.director.set_process(false)
	host.director.set_physics_process(false)
	return {
		"scene": scene,
		"host": host,
		"director": host.director,
		"controller": host.get_node("CinematicCameraController"),
		"source": source,
		"shot": shot,
		"player": player,
		"health": health,
		"dialogue_provider": dialogue_provider,
	}

func _dispose(f: Dictionary) -> void:
	f.scene.free()
	await process_frame
	check(Pauses.for_tree(self).snapshot().count == 0 and not paused,
		"Cinematic fixture teardown releases every pause and restores the tree")

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1
