@tool
class_name CameraAction
extends SceneAction

@export_node_path("Node3D") var target_path: NodePath
@export var cinematic_shot := false
@export_range(0.0, 10.0, 0.05) var move_seconds := 0.6
@export_range(0.0, 30.0, 0.05) var hold_seconds := 1.2
@export_range(0.0, 10.0, 0.05) var return_seconds := 0.6
@export_range(0.0, 100.0, 0.1) var camera_size := 0.0


func begin(context: SceneActionContext) -> void:
	var target := context.resolve(target_path)
	if target == null:
		context.fail(&"missing_camera_target")
		return
	var parameters := {
		"move_seconds": move_seconds,
		"hold_seconds": hold_seconds,
		"return_seconds": return_seconds,
		"size": camera_size,
	}
	if cinematic_shot:
		parameters["camera_shot"] = true
	context.request(&"presentation", target, parameters)
