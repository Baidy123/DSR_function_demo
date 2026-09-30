extends Node

## 关闭后连默认效果也不播放；不改变伤害、碰撞或 AI。
@export var enabled: bool = true
## 留空使用当前场景 ImpactEffects 的默认配置（默认配置也可以为空）。
@export var profile: ImpactProfile
## 可选命中动作，路径相对于 Receiver；人物通常留空，避免与受伤动作重复。
@export var presentation_path: NodePath


func notify_impact() -> void:
	if not enabled or presentation_path.is_empty(): return
	var presentation := get_node_or_null(presentation_path)
	if presentation != null and presentation.has_method("play_event"):
		presentation.play_event(&"impact")
