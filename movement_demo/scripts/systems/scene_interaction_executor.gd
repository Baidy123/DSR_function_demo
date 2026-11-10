extends RefCounted

const Request = preload("res://scripts/systems/scene_request.gd")
var _director: WeakRef
var _links: Dictionary = {}

func _init(director: Node) -> void:
	_director = weakref(director)

func begin_scene_action(request: Request) -> void:
	var target := request.node(&"target")
	var player := request.node(&"player")
	var director = _director.get_ref()
	if target == null or player == null or not target.has_method("begin_scene_action") or not target.has_method("cancel_scene_action") or not target.has_signal("scene_action_finished"):
		request.fail("invalid_interaction_provider")
		return
	var callback := _finished.bind(request.id)
	target.connect(&"scene_action_finished", callback)
	_links[request.id] = {"target": weakref(target), "callback": callback}
	request.finished.connect(_cleanup)
	if request.kind == &"dialogue":
		if not player.has_method("set_dialogue_active"):
			request.fail("player_missing_dialogue_control")
			return
		director.hold_request_controls(request, false, true)
		if request.parameters.get("face_source", false):
			var source := request.node(&"source") as Node3D
			if source != null and player.has_method("face_npc"):
				player.face_npc(source.global_position)
				while request.is_current() and is_instance_valid(player) and player.get("is_facing_npc") == true:
					await director.get_tree().physics_frame
				if not request.is_current(): return
	target = request.node(&"target")
	if target != null and request.is_current(): target.begin_scene_action(request)

func end_scene_action(request: Request) -> void:
	var target := request.node(&"target")
	if target != null and target.has_method("finish_scene_action"):
		target.finish_scene_action(request)
	else: request.complete()

func cancel_scene_action(request: Request, reason: StringName) -> void:
	var target := request.node(&"target")
	if is_instance_valid(target) and target.has_method("cancel_scene_action"):
		target.cancel_scene_action(request, reason)

func _finished(id: int, result: StringName, expected: int) -> void:
	if id != expected: return
	var director = _director.get_ref()
	var request = director.find_request(id) if is_instance_valid(director) else null
	if request == null: return
	if result == &"completed": request.complete()
	elif result == &"cancelled": director.cancel_request(id, &"provider_cancelled")
	else: request.fail(String(result))

func _cleanup(request: Request) -> void:
	var link: Dictionary = _links.get(request.id, {})
	_links.erase(request.id)
	if link.is_empty(): return
	var target = link.target.get_ref()
	if is_instance_valid(target) and target.is_connected(&"scene_action_finished", link.callback):
		target.disconnect(&"scene_action_finished", link.callback)
