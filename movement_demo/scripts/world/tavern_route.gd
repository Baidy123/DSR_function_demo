class_name TavernRoute
extends Node3D

enum Finish { STAY, LOOP, DESPAWN, SIT, ACTIVITY }

@export var finish_mode := Finish.STAY
@export_range(0.0, 180.0, 0.1, "or_greater") var loop_interval := 3.0
@export_node_path("TavernStaffDoor") var exit_gate_path: NodePath
## For SIT, place the last waypoint close to and in front of this seat.
@export_node_path("TavernSeat") var finish_seat_path: NodePath
## For ACTIVITY, a director script provider can access the arriving NPC as its request source.
@export_node_path("Node") var finish_activity_path: NodePath
## Optional public method without required arguments. Leave empty to use the script provider.
@export var finish_activity_method: StringName


func world_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for marker in get_children():
		if marker is Marker3D:
			points.append(marker.global_position)
	return points


func exit_gate() -> TavernStaffDoor:
	return get_node_or_null(exit_gate_path) as TavernStaffDoor if not exit_gate_path.is_empty() else null


func finish_action() -> Dictionary:
	match finish_mode:
		Finish.SIT:
			var seat := get_node_or_null(finish_seat_path) as TavernSeat if not finish_seat_path.is_empty() else null
			return {"target": seat, "parameters": {"npc_seat": true}}
		Finish.ACTIVITY:
			var activity := get_node_or_null(finish_activity_path) if not finish_activity_path.is_empty() else null
			var parameters := {}
			if not finish_activity_method.is_empty():
				parameters = {"mode": &"method", "method": finish_activity_method}
			return {"target": activity, "parameters": parameters}
	return {}
