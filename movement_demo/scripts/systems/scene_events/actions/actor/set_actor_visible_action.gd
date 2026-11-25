@tool
class_name SetActorVisibleAction
extends SceneAction

@export_node_path("Node3D") var actor_path: NodePath
@export var visible := true


func begin(context: SceneActionContext) -> void:
	var actor := context.resolve(actor_path)
	if actor == null:
		context.fail(&"missing_actor")
		return
	if actor.has_method(&"set_physical_presence"):
		actor.call(&"set_physical_presence", visible)
	elif _has_property(actor, &"visible"):
		actor.set(&"visible", visible)
	else:
		context.fail(&"actor_has_no_visibility")
		return
	context.complete()


func _has_property(target: Object, property_name: StringName) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false
