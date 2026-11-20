class_name TavernRoute
extends Node3D

enum Finish { STAY, LOOP, DESPAWN }

@export var finish_mode := Finish.STAY
@export_range(0.0, 180.0, 0.1, "or_greater") var loop_interval := 3.0
@export_node_path("TavernStaffDoor") var exit_gate_path: NodePath


func world_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for marker in get_children():
		if marker is Marker3D:
			points.append(marker.global_position)
	return points


func exit_gate() -> TavernStaffDoor:
	return get_node_or_null(exit_gate_path) as TavernStaffDoor if not exit_gate_path.is_empty() else null
