@tool
class_name WaitAction
extends SceneAction

@export_range(0.0, 3600.0, 0.05) var seconds := 0.0


func begin(context: SceneActionContext) -> void:
	context.state[&"remaining"] = maxf(seconds, 0.0)
	if seconds <= 0.0:
		context.complete()


func advance(context: SceneActionContext, delta: float) -> void:
	var remaining := maxf(float(context.state.get(&"remaining", seconds)) - maxf(delta, 0.0), 0.0)
	context.state[&"remaining"] = remaining
	if remaining <= 0.0:
		context.complete()
