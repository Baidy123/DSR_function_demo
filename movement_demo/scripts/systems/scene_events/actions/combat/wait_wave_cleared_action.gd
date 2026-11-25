@tool
class_name WaitWaveClearedAction
extends SceneAction

@export_node_path("Node") var wave_path: NodePath


func begin(context: SceneActionContext) -> void:
	_check(context)


func advance(context: SceneActionContext, _delta: float) -> void:
	_check(context)


func _check(context: SceneActionContext) -> void:
	var wave := context.resolve(wave_path)
	if wave == null or not is_instance_valid(context.director) \
			or not context.director.has_method(&"wave_status"):
		context.fail(&"missing_wave")
		return
	var status: StringName = context.director.call(&"wave_status", wave)
	if status == &"cleared":
		context.complete()
	elif status in [&"unknown", &"error"]:
		context.fail(&"invalid_wave_status")
