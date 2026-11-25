extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")
const ReturnPortal = preload("res://scripts/world/tavern_return_portal.gd")
const UI = preload("res://scenes/ui/dialogue_ui.tscn")
var checks := 0
var failures := 0

class Player extends Node3D:
	var is_in_dialogue := false
	var is_facing_npc := false
	func set_dialogue_active(value: bool) -> void: is_in_dialogue = value

class Guide extends Node:
	signal finished
	var allowed := true
	var calls := 0
	func condition() -> bool: return allowed
	func run_once() -> void: calls += 1
	func begin() -> void: pass
	func cancel() -> void: pass

class DelayedLoader extends RefCounted:
	signal release_load
	func load_scene(_path: String, _reload: bool) -> Error:
		await release_load
		return OK

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func fixture(events: Array = []) -> Dictionary:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var player := Player.new()
	player.add_to_group(&"player")
	scene.add_child(player)
	var source := Guide.new()
	scene.add_child(source)
	var ui = UI.instantiate()
	scene.add_child(ui)
	var director = Director.new()
	director.configure(scene, {"scene_root": scene, "events": events})
	scene.add_child(director)
	director.initialize()
	return {"scene": scene, "player": player, "source": source, "ui": ui, "director": director}

func interactable(f: Dictionary, script = null):
	var item = script.new() if script != null else Interactable.new()
	for title in ["Name", "Prompt"]:
		var label := Label3D.new()
		label.name = title
		item.add_child(label)
	f.scene.add_child(item)
	return item

func _review_cancellation_and_condition() -> void:
	var state := root.get_node("GameState")
	for source_exit in [false, true]:
		var f := fixture()
		var loader := DelayedLoader.new()
		f.director.scene_loader = loader.load_scene
		var before: Dictionary = state.capture_campaign_state()
		var request = f.director.request_action(&"transition", {"source": f.source,
			"parameters": {"path": "res://tests/scene_transition_target.tscn", "mode": &"enter_level", "player_snapshot": {"cancelled": true}}})
		await process_frame
		await process_frame
		if source_exit: f.source.free()
		else: f.director.cancel_request(request.id, &"user_cancelled")
		check(request.status == &"cancelled" and f.director.state == &"running" and not paused,
			"unaccepted load cancellation restores request, scene and controls (source exit=%s)" % source_exit)
		loader.release_load.emit()
		await process_frame
		check(state.capture_campaign_state() == before, "cancelled late loader cannot publish campaign state")
		f.scene.free()
		current_scene = null
		await process_frame
	var f := fixture()
	var rule := SceneFlowRule.new()
	rule.label = "Queued predicate"
	rule.condition_target = f.source.get_path()
	rule.condition_method = &"condition"
	var action := SceneFlowAction.new()
	action.kind = SceneFlowAction.Kind.CALL_METHOD
	action.target_path = f.source.get_path()
	action.method = &"run_once"
	rule.actions.append(action)
	f.director._flows.configure([rule])
	var guide = f.director.request_action(&"guide", {"source": f.source, "target": f.source,
		"parameters": {"pause_world": false}})
	f.director.advance(0.0)
	var queued = f.director._flows._entries[0].request
	check(queued != null and queued.status == &"queued", "rule action queues behind active dialogue-like control")
	f.source.allowed = false
	f.source.finished.emit()
	f.director.advance(0.0)
	check(f.source.calls == 0 and queued.status == &"cancelled" and queued.reason == &"condition_changed",
		"queued action revalidates its predicate before side effects")
	f.scene.free()
	current_scene = null
	await process_frame
	var typed_action := ChangeSceneAction.new()
	typed_action.scene_path = "res://tests/scene_transition_target.tscn"
	var definition := SceneEventDefinition.new()
	definition.event_id = &"typed_transition"
	definition.label = "Typed transition"
	definition.start_mode = SceneEventDefinition.StartMode.AUTO
	definition.actions = [typed_action]
	var typed := fixture([definition])
	var terminals: Array[Array] = []
	typed.director.typed_event_finished.connect(func(id: StringName, status: StringName, reason: StringName) -> void:
		terminals.append([id, status, reason]))
	typed.director.scene_loader = func(_path: String, _reload: bool) -> Error: return ERR_CANT_OPEN
	for _frame in range(5): await process_frame
	var typed_snapshot: Dictionary = typed.director.debug_snapshot()
	var typed_state: Dictionary = typed_snapshot.events.events[0] if not typed_snapshot.events.events.is_empty() else {}
	var typed_boundary_ok: bool = (not typed_state.get("active", true) and typed_state.get("fired", false)
		and terminals.size() == 1 and terminals[0][0] == &"typed_transition"
		and terminals[0][1] == &"failed" and not String(terminals[0][2]).is_empty()
		and typed_snapshot.events.errors.size() == 1
		and String(typed_snapshot.last_error).begins_with("Typed transition:"))
	check(typed_boundary_ok,
		"typed ChangeSceneAction runs through event_sequences and keeps the director's prepare failure boundary")
	typed.scene.free()
	current_scene = null
	await process_frame
	var waiting_action := WaitAction.new()
	waiting_action.seconds = 30.0
	var waiting_definition := SceneEventDefinition.new()
	waiting_definition.event_id = &"typed_waiting_sibling"
	waiting_definition.label = "Waiting sibling"
	waiting_definition.start_mode = SceneEventDefinition.StartMode.AUTO
	waiting_definition.actions = [waiting_action]
	var success_action := ChangeSceneAction.new()
	success_action.scene_path = "res://tests/scene_transition_target.tscn"
	var success_definition := SceneEventDefinition.new()
	success_definition.event_id = &"typed_success_transition"
	success_definition.label = "Successful typed transition"
	success_definition.start_mode = SceneEventDefinition.StartMode.AUTO
	success_definition.actions = [success_action]
	# Put the waiter first so it is active before the transition cancels other events.
	var successful := fixture([waiting_definition, success_definition])
	var success_terminals: Array[Array] = []
	successful.director.typed_event_finished.connect(func(id: StringName, status: StringName, reason: StringName) -> void:
		success_terminals.append([id, status, reason]))
	successful.director.scene_loader = func(_path: String, _reload: bool) -> Error: return OK
	for _frame in range(5): await process_frame
	check(success_terminals.count([&"typed_waiting_sibling", &"cancelled", &"event_runner_cancelled"]) == 1
		and success_terminals.count([&"typed_success_transition", &"completed", &""]) == 1
		and success_terminals.size() == 2,
		"typed transition preserves only its initiating event and completes it exactly once")
	successful.scene.free()
	current_scene = null
	await process_frame

func _run() -> void:
	if OS.get_cmdline_user_args().has("--review-only"):
		await _review_cancellation_and_condition()
		print("Review transition/condition: %d checks; %d failures" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	await _review_cancellation_and_condition()
	var state := root.get_node("GameState")
	state.clear_interaction_state()
	var f := fixture()
	var item = interactable(f)
	item.one_shot = true
	item.hide_on_interact = true
	var give := GiveItemEffect.new()
	give.item_id = &"director_test_item"
	item.effects.append(give)
	var active = f.director.request_action(&"guide", {"source": f.source, "target": f.source,
		"parameters": {"pause_world": false}})
	check(not item.interact(f.player) and not item.has_interacted and item.visible and state.get_item_count(&"director_test_item") == 0,
		"busy rejection cannot grant items, consume one_shot or hide an interaction")
	f.director.cancel_request(active.id)
	check(state.has_method("prepare_scene_transition"), "campaign state must expose pure transition preparation")
	if not state.has_method("prepare_scene_transition"):
		f.scene.free()
		quit(1)
		return
	var show := ShowDialogueEffect.new()
	show.dialogue_resource = load("res://resources/dialogue/wine_glass.dialogue")
	item.effects.append(show)
	check(item.interact(f.player), "composed interaction starts after approval")
	for _frame in range(4): await process_frame
	check(f.ui.dialogue_panel.visible and state.get_item_count(&"director_test_item") == 1 and not item.has_interacted,
		"give-then-dialogue inherits its parent foreground without deadlock or premature success")
	f.ui._close_dialogue()
	for _frame in range(3): await process_frame
	check(item.has_interacted and not item.visible and not f.player.is_in_dialogue, "composed interaction commits success after its child dialogue ends")
	var portal = interactable(f, ReturnPortal)
	portal.level_number = 1
	var change := ChangeSceneEffect.new()
	change.scene_path = "res://tests/scene_transition_target.tscn"
	portal.effects.append(change)
	state.completed_level = 0
	state.money = 27
	state.pending_player_state = {"sentinel": 1}
	state.level_entry_player_state = {"sentinel": 2}
	var before: Dictionary = state.capture_campaign_state()
	var checkpoint: Dictionary = state.campaign_checkpoint.duplicate(true)
	var entry: Dictionary = state.level_entry_player_state.duplicate(true)
	active = f.director.request_action(&"guide", {"source": f.source, "target": f.source, "parameters": {"pause_world": false}})
	check(not portal.interact(f.player) and state.capture_campaign_state() == before and state.campaign_checkpoint == checkpoint and state.level_entry_player_state == entry,
		"rejected portal leaves campaign, pending, entry and checkpoint unchanged")
	f.director.cancel_request(active.id)
	f.director._completion_pauses_world = false
	f.director.request_completion()
	for _frame in range(4): await process_frame
	check(f.director.state == &"completed" and not paused, "cleared level remains playable before return portal activation")
	var calls: Array[Dictionary] = []
	f.director.scene_loader = func(path: String, reload: bool) -> Error:
		calls.append({"path": path, "reload": reload})
		return ERR_CANT_OPEN
	check(portal.interact(f.player), "approved portal starts an asynchronous load request")
	check(not portal.interact(f.player), "duplicate portal activation cannot start another load")
	for _frame in range(5): await process_frame
	check(calls.size() == 1 and state.capture_campaign_state() == before and state.campaign_checkpoint == checkpoint and state.level_entry_player_state == entry,
		"failed portal load cannot commit progress, rewards or snapshots")
	check(not paused and portal.can_interact(f.player), "failed ordinary portal returns control and permits retry")
	check(portal.interact(f.player), "failed portal can retry its original destination")
	for _frame in range(5): await process_frame
	check(calls.size() == 2 and calls[0] == calls[1], "retry preserves original path and reload mode")
	f.scene.free()
	current_scene = null
	await process_frame
	f = fixture()
	var loader := DelayedLoader.new()
	f.director.scene_loader = loader.load_scene
	var delayed = f.director.request_action(&"transition", {"source": f.source,
		"parameters": {"path": "res://tests/scene_transition_target.tscn", "mode": &"enter_level", "player_snapshot": {"late": 99}}})
	await process_frame
	await process_frame
	var unchanged: Dictionary = state.capture_campaign_state()
	f.scene.free()
	current_scene = null
	loader.release_load.emit()
	await process_frame
	check(delayed.status == &"cancelled" and state.capture_campaign_state() == unchanged and not paused,
		"late async loader cannot commit after its scene exits or retain pause")
	f = fixture()
	if has_meta(&"transition_ready_seen"): remove_meta(&"transition_ready_seen")
	var snapshot := {"health": {"health": 73.0}}
	var request = f.director.request_action(&"transition", {"source": f.source,
		"parameters": {"path": "res://tests/scene_transition_target.tscn", "mode": &"enter_level", "player_snapshot": snapshot}})
	for _frame in range(12):
		if has_meta(&"transition_ready_seen"): break
		await process_frame
	check(has_meta(&"transition_ready_seen"), "real scene transition reaches target ready callback")
	if has_meta(&"transition_ready_seen"):
		var seen: Dictionary = get_meta(&"transition_ready_seen")
		check(request.status == &"completed" and seen.pending == snapshot and seen.entry == snapshot,
			"successful state commit precedes target ready and expected source exit is not cancellation")
		check(state.take_pending_player_state().is_empty(), "target consumes the prepared pending snapshot only once")
	if is_instance_valid(current_scene): current_scene.free()
	current_scene = null
	await process_frame
	print("Scene transition requests: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
