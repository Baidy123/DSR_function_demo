@tool
class_name PresentationAnimationProfile
extends Resource

## 名称来自模型 AnimationPlayer，允许包含动画库前缀，例如 movement/Run。留空使用回退。
@export var idle: StringName = &""
@export var move: StringName = &""
@export var sprint: StringName = &""
@export var aim: StringName = &""
@export var reload: StringName = &""
## 可选近战动作；进度由玩法驱动，不能靠动画方法轨道造成伤害。
@export var melee: StringName = &""
## 缺少蹲姿／翻越素材时使用角色的胶囊占位表现。
@export var crouch: StringName = &""
@export var crouch_move: StringName = &""
@export var vault: StringName = &""
@export var dialogue: StringName = &""
@export var fire: StringName = &""
@export var hit: StringName = &""
@export var dead: StringName = &""
@export var impact: StringName = &""
## 动画切换混合秒数，0表示立即切换。
@export_range(0.0, 1.0, 0.01) var blend_seconds: float = 0.1
## 走路素材对应的实际速度；冲刺素材使用下方独立参考速度。
@export_range(0.1, 20.0, 0.1) var move_reference_speed: float = 3.0
@export_range(0.1, 30.0, 0.1) var sprint_reference_speed: float = 6.0
@export_range(0.1, 3.0, 0.05) var minimum_rate: float = 0.5
@export_range(0.1, 5.0, 0.05) var maximum_rate: float = 2.0


func clip(state: StringName) -> StringName:
	if state in [&"idle", &"move", &"sprint", &"aim", &"reload", &"melee", &"crouch", &"crouch_move", &"vault", &"dialogue", &"fire", &"hit", &"dead", &"impact"]:
		return get(state)
	return &""
