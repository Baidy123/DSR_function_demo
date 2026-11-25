@tool
class_name SpawnWaveAction
extends SceneAction

@export_node_path("Node") var wave_path: NodePath
@export var present_spawn := false
@export_node_path("Node3D") var presentation_target_path: NodePath
@export_range(0.0, 10.0, 0.05) var move_seconds := 0.6
@export_range(0.0, 30.0, 0.05) var hold_seconds := 1.2
@export_range(0.0, 10.0, 0.05) var return_seconds := 0.6
@export_range(0.0, 100.0, 0.1) var camera_size := 0.0


func begin(context: SceneActionContext) -> void:
	var wave := context.resolve(wave_path)
	if wave == null:
		context.fail(&"missing_wave")
		return
	context.request(&"wave", wave, {
		"present": present_spawn,
		"target_path": presentation_target_path,
		"options": {
			"move_seconds": move_seconds,
			"hold_seconds": hold_seconds,
			"return_seconds": return_seconds,
			"size": camera_size,
		},
	})
