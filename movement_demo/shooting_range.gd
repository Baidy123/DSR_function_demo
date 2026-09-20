extends Node3D

var players_inside: Array[Node3D] = []


func _ready() -> void:
	$CombatZone.body_entered.connect(_on_player_entered)
	$CombatZone.body_exited.connect(_on_player_exited)


func _on_player_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not players_inside.has(body):
		players_inside.append(body)


func _on_player_exited(body: Node3D) -> void:
	if not players_inside.has(body):
		return
	players_inside.erase(body)
	if players_inside.is_empty():
		# 离开当前区域时刷新自己的靶子或敌人，不影响其他区域。
		for target in get_children():
			# 重开卸载场景也会发出离场信号；已出树的目标无需刷新。
			if target.is_inside_tree() and target.has_method("reset_target"):
				target.reset_target()
