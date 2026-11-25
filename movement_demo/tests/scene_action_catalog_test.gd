extends SceneTree

class DirectorStub extends Node:
	var requests: Array[SceneRequest] = []
	var contexts: Array[Dictionary] = []
	var wave_states: Dictionary = {}
	var errors: Array[String] = []

	func can_run_actions() -> bool:
		return true

	func request_action(kind: StringName, request_context: Dictionary = {}) -> SceneRequest:
		var scene_request := SceneRequest.new()
		scene_request._id = requests.size() + 1
		scene_request._status = &"running"
		scene_request.kind = kind
		requests.append(scene_request)
		contexts.append(request_context)
		return scene_request

	func cancel_request(id: int, reason: StringName = &"cancelled") -> void:
		for scene_request in requests:
			if scene_request.id == id and not scene_request.is_terminal():
				scene_request._settle(&"cancelled", reason)

	func wave_status(wave: Node) -> StringName:
		return wave_states.get(wave, &"unknown")

	func report_action_error(label: String, reason: String) -> void:
		errors.append("%s:%s" % [label, reason])

class Fixture:
	var root: Node
	var host: Node
	var director: DirectorStub
	var runner: SceneEventRunner

class DialogueProbe extends Resource:
	func get_next_dialogue_line() -> Variant:
		return null

class ProviderProbe extends Node:
	func begin_scene_action(_request: SceneRequest) -> void:
		pass
	func cancel_scene_action(_request: SceneRequest, _reason: StringName) -> void:
		pass

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_flow_actions()
	await _test_combat_and_presentation_actions()
	await _test_audio_and_transition_actions()
	print("Scene action catalog: %d failures" % failures)
	quit(1 if failures else 0)


func _fixture(action: SceneAction) -> Fixture:
	var f := Fixture.new()
	f.root = Node.new()
	root.add_child(f.root)
	f.host = Node.new()
	f.host.name = "Host"
	f.root.add_child(f.host)
	f.director = DirectorStub.new()
	f.host.add_child(f.director)
	f.runner = SceneEventRunner.new(f.director, f.host)
	var definition := SceneEventDefinition.new()
	definition.event_id = &"catalog"
	definition.label = "Catalog"
	definition.start_mode = SceneEventDefinition.StartMode.AUTO
	definition.actions = [action]
	f.runner.configure([definition])
	return f


func _dispose(f: Fixture) -> void:
	f.runner.release()
	for child in f.host.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	f.root.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.05).timeout


func _test_flow_actions() -> void:
	var wait := WaitAction.new()
	wait.seconds = 0.0
	var f := _fixture(wait)
	f.runner.advance(0.0)
	check(not f.runner.snapshot().events[0].active, "zero-duration wait completes in its first step")
	await _dispose(f)

	var signal_action := WaitSignalAction.new()
	var source := Node.new()
	source.name = "SignalSource"
	source.add_user_signal(&"finished_work")
	f = _fixture(signal_action)
	f.host.add_child(source)
	var trigger := SceneEventTrigger.new()
	trigger.source_path = ^"SignalSource"
	trigger.signal_name = &"finished_work"
	signal_action.trigger = trigger
	f.runner.configure([_definition(signal_action)])
	f.runner.advance(0.0)
	check(f.runner.snapshot().events[0].active, "wait-signal remains pending before its signal")
	source.emit_signal(&"finished_work")
	f.runner.advance(0.0)
	check(not f.runner.snapshot().events[0].active, "wait-signal completes on its configured signal")
	await _dispose(f)

	f = _fixture(CompleteSceneAction.new())
	f.runner.advance(0.0)
	check(f.director.requests[0].kind == &"completion", "complete-scene submits the completion request kind")
	f.director.requests[0]._settle(&"completed")
	f.runner.advance(0.0)
	await _dispose(f)


func _test_combat_and_presentation_actions() -> void:
	var spawn := SpawnWaveAction.new()
	spawn.wave_path = ^"Wave"
	spawn.present_spawn = true
	var f := _fixture(spawn)
	var wave := Node.new()
	wave.name = "Wave"
	f.host.add_child(wave)
	f.director.wave_states[wave] = &"waiting"
	f.runner.advance(0.0)
	check(f.director.requests[0].kind == &"wave" and f.runner.snapshot().events[0].active,
		"spawn-wave waits for the real wave request boundary")
	check(bool(f.director.contexts[0].parameters.present), "spawn-wave forwards presentation intent")
	f.director.requests[0]._settle(&"completed")
	f.runner.advance(0.0)
	await _dispose(f)

	var wait_wave := WaitWaveClearedAction.new()
	wait_wave.wave_path = ^"Wave"
	f = _fixture(wait_wave)
	wave = Node.new()
	wave.name = "Wave"
	f.host.add_child(wave)
	f.director.wave_states[wave] = &"active"
	f.runner.advance(0.0)
	check(f.runner.snapshot().events[0].active, "wait-wave-cleared remains pending while active")
	f.director.wave_states[wave] = &"cleared"
	f.runner.advance(0.0)
	check(not f.runner.snapshot().events[0].active, "wait-wave-cleared completes only at cleared")
	await _dispose(f)

	var camera := CameraAction.new()
	camera.target_path = ^"Focus"
	f = _fixture(camera)
	var focus := Node3D.new()
	focus.name = "Focus"
	f.host.add_child(focus)
	f.runner.advance(0.0)
	check(f.director.requests[0].kind == &"presentation", "camera submits the presentation request kind")
	f.runner.cancel_all(&"catalog_cancel")
	check(f.director.requests[0].status == &"cancelled", "cancelling a camera action cancels its owned request")
	await _dispose(f)

	camera = CameraAction.new()
	camera.target_path = ^"Missing"
	f = _fixture(camera)
	f.runner.advance(0.0)
	check(f.director.requests.is_empty() and not f.director.errors.is_empty(), "camera rejects a missing target before submission")
	await _dispose(f)

	var dialogue := DialogueAction.new()
	dialogue.target_path = ^"DialogueUI"
	dialogue.dialogue = Resource.new()
	f = _fixture(dialogue)
	var dialogue_ui := Node.new()
	dialogue_ui.name = "DialogueUI"
	f.host.add_child(dialogue_ui)
	f.runner.advance(0.0)
	check(f.director.requests.is_empty() and not f.director.errors.is_empty(), "dialogue rejects an invalid resource")
	await _dispose(f)

	dialogue = DialogueAction.new()
	dialogue.target_path = ^"UIRoot/DialogueUI"
	dialogue.player_path = ^"Player"
	dialogue.source_path = ^"Speaker"
	dialogue.dialogue = DialogueProbe.new()
	dialogue.face_source = true
	dialogue.camera_cues = {"merchant": ^"CameraTarget"}
	dialogue.seat_cues = {"commissioner": [^"CommissionerSeat"]}
	f = _fixture(dialogue)
	var ui_root := Node.new()
	ui_root.name = "UIRoot"
	f.host.add_child(ui_root)
	dialogue_ui = Node.new()
	dialogue_ui.name = "DialogueUI"
	ui_root.add_child(dialogue_ui)
	var player := Node.new()
	player.name = "Player"
	f.host.add_child(player)
	var speaker := Node3D.new()
	speaker.name = "Speaker"
	f.host.add_child(speaker)
	var camera_target := Node3D.new()
	camera_target.name = "CameraTarget"
	f.host.add_child(camera_target)
	var commissioner_seat := Node.new()
	commissioner_seat.name = "CommissionerSeat"
	f.host.add_child(commissioner_seat)
	f.runner.advance(0.0)
	check(f.director.requests[0].kind == &"dialogue" \
		and f.director.contexts[0].player == player and f.director.contexts[0].source == speaker \
		and bool(f.director.contexts[0].parameters.face_source) \
		and f.director.contexts[0].parameters.camera_cues == {"merchant": ^"../../CameraTarget"} \
		and f.director.contexts[0].parameters.seat_cues == {"commissioner": [^"../../CommissionerSeat"]},
		"dialogue converts host-authored cue paths for its nested UI provider")
	f.director.requests[0]._settle(&"completed")
	f.runner.advance(0.0)
	await _dispose(f)

	var provider_action := RunProviderAction.new()
	provider_action.target_path = ^"ShopProvider"
	provider_action.player_path = ^"Player"
	provider_action.request_kind = RunProviderAction.RequestKind.SHOP
	provider_action.parameters = {"browse_only": true}
	f = _fixture(provider_action)
	var provider := ProviderProbe.new()
	provider.name = "ShopProvider"
	f.host.add_child(provider)
	player = Node3D.new()
	player.name = "Player"
	f.host.add_child(player)
	f.runner.advance(0.0)
	check(f.director.requests[0].kind == &"shop" \
		and f.director.contexts[0].player == player \
		and f.director.contexts[0].target == provider \
		and bool(f.director.contexts[0].parameters.browse_only) \
		and not f.director.contexts[0].parameters.has("mode"),
		"RunProviderAction authors a browse-only shop request entirely in the inspector")
	f.director.requests[0]._settle(&"completed")
	f.runner.advance(0.0)
	await _dispose(f)


func _test_audio_and_transition_actions() -> void:
	var audio := PlayAudioAction.new()
	audio.target_path = ^"Audio"
	audio.wait_for_finished = true
	var f := _fixture(audio)
	var player := AudioStreamPlayer.new()
	player.name = "Audio"
	player.stream = AudioStreamWAV.new()
	f.host.add_child(player)
	f.runner.advance(0.0)
	check(f.runner.snapshot().events[0].active, "audio play can wait for the player's finished boundary")
	# Simulate the engine's natural finished boundary: playback has already stopped
	# before AudioStreamPlayer emits finished.
	player.stop()
	player.finished.emit()
	f.runner.advance(0.0)
	check(not f.runner.snapshot().events[0].active, "audio finished advances the event")
	await _dispose(f)

	audio = PlayAudioAction.new()
	audio.target_path = ^"Audio"
	audio.wait_for_finished = true
	f = _fixture(audio)
	player = AudioStreamPlayer.new()
	player.name = "Audio"
	player.stream = AudioStreamWAV.new()
	f.host.add_child(player)
	f.runner.advance(0.0)
	f.runner.cancel_all()
	check(not player.playing and player.finished.get_connections().is_empty(),
		"cancel stops owned playback and releases its finished subscription")
	await _dispose(f)

	audio = PlayAudioAction.new()
	audio.target_path = ^"Audio"
	audio.command = PlayAudioAction.Command.STOP
	f = _fixture(audio)
	player = AudioStreamPlayer.new()
	player.name = "Audio"
	player.stream = AudioStreamWAV.new()
	f.host.add_child(player)
	player.play()
	f.runner.advance(0.0)
	check(not player.playing, "audio STOP halts the selected player and completes immediately")
	await _dispose(f)

	var change := ChangeSceneAction.new()
	change.scene_path = "res://tests/scene_transition_target.tscn"
	change.return_control_on_failure = true
	f = _fixture(change)
	f.runner.advance(0.0)
	check(f.director.requests[0].kind == &"transition" \
		and f.director.contexts[0].parameters.path == change.scene_path \
		and bool(f.director.contexts[0].parameters.return_control_on_failure),
		"change-scene submits the authored transition path and failure-control policy")
	f.director.requests[0]._settle(&"failed", &"prepare_failed")
	f.runner.advance(0.0)
	check(not f.director.errors.is_empty(), "transition failure reaches the event failure policy")
	await _dispose(f)

	var restart := RestartSceneAction.new()
	f = _fixture(restart)
	f.runner.advance(0.0)
	check(f.director.requests[0].kind == &"transition" \
		and bool(f.director.contexts[0].parameters.reload),
		"restart-scene submits explicit reload parameters")
	f.director.requests[0]._settle(&"completed")
	f.runner.advance(0.0)
	await _dispose(f)


func _definition(action: SceneAction) -> SceneEventDefinition:
	var definition := SceneEventDefinition.new()
	definition.event_id = &"catalog"
	definition.label = "Catalog"
	definition.start_mode = SceneEventDefinition.StartMode.AUTO
	definition.actions = [action]
	return definition


func check(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
