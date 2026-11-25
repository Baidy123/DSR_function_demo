@tool
class_name WaitSignalAction
extends SceneAction

const Subscription = preload("res://scripts/systems/scene_event_subscription.gd")

@export var trigger: SceneEventTrigger


func begin(context: SceneActionContext) -> void:
	if trigger == null:
		context.fail(&"missing_signal_trigger")
		return
	var subscription = Subscription.new()
	var error: String = subscription.connect_trigger(
		context.host, trigger, _signal_received.bind(context, subscription))
	if not error.is_empty():
		subscription.clear()
		context.fail(StringName(error))
		return
	context.state[&"subscription"] = subscription


func cancel(context: SceneActionContext, _reason: StringName) -> void:
	var subscription = context.state.get(&"subscription")
	if subscription != null:
		subscription.clear()


func _signal_received(context: SceneActionContext, subscription) -> void:
	if not context.is_current():
		return
	subscription.clear()
	context.complete()
