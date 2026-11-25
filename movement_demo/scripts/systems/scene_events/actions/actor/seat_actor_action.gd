@tool
class_name SeatActorAction
extends SceneAction

enum Mode { SIT, LEAVE }

@export_node_path("CharacterBody3D") var actor_path: NodePath
@export_node_path("TavernSeat") var seat_path: NodePath
@export var mode: Mode = Mode.SIT


func begin(context: SceneActionContext) -> void:
	var actor := context.resolve(actor_path) as CharacterBody3D
	var seat := context.resolve(seat_path) as TavernSeat
	if mode == Mode.LEAVE and actor != null and actor.has_method(&"current_seat"):
		var current := actor.call(&"current_seat") as TavernSeat
		if current != null:
			seat = current
	if actor == null or seat == null:
		context.fail(&"missing_actor_or_seat")
		return
	var parameters := {"leave": mode == Mode.LEAVE}
	if actor is TavernNPC:
		parameters["npc_seat"] = true
	else:
		parameters["scripted"] = true
	context.request(&"script", seat, parameters, {"source": actor, "player": actor},
		mode == Mode.LEAVE)
