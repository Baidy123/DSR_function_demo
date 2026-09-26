extends RefCounted

## 只读地选择本帧要更新的动作；启动条件、权限撤销由 AI 原流程处理。
## 先保留原优先顺序，不在这里加入评分、随机数或动作执行。
func select_action(ai: Node) -> StringName:
	if ai.cover.is_active():
		return &"cover"
	match ai.state:
		ai.State.PATROL:
			return &"patrol"
		ai.State.INVESTIGATE, ai.State.TRACK, ai.State.SEARCH:
			return &"search"
		ai.State.APPROACH, ai.State.REPOSITION, ai.State.HOLD_POSITION:
			return _select_combat_action(ai)
	return &""


func _select_combat_action(ai: Node) -> StringName:
	if ai.current_suppression.is_active():
		return ai.current_suppression.action_id
	if ai.actions[&"attack_position"].is_active():
		return &"attack_position"
	return &"engage"
