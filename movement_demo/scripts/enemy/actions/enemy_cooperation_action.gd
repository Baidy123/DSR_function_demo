extends "res://scripts/enemy/actions/enemy_action.gd"

## Optional trained flanking executor. It never offers personal tactics or
## chooses a destination; the squad supplies a validated complete route.
func command_roles() -> Array[StringName]:
	return [&"flank", &"move", &"guard"]

func command_work(_delta: float, visible: bool, _arrived: bool) -> Dictionary:
	if visible and actor.can_use_firearms(): return {"fire": {"owner": action_id, "mode": &"visible"}}
	if visible and context.melee.can_request(visible): return {"melee": {"owner": action_id}}
	return {}
