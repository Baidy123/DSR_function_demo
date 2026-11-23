extends Node3D

const State = preload("res://scripts/systems/presentation/presentation_state.gd")
const MODES := [
	[&"idle", "待机"], [&"move", "走路"], [&"sprint", "冲刺"],
	[&"aim", "瞄准"], [&"fire", "开火"], [&"reload", "换弹"],
	[&"hit", "受击"], [&"dialogue", "交谈"], [&"melee", "近战"],
	[&"crouch_enter", "蹲下过渡"], [&"crouch", "蹲姿"],
	[&"crouch_move", "蹲行"], [&"crouch_aim", "蹲姿瞄准"],
	[&"crouch_fire", "蹲姿开火"], [&"crouch_reload", "蹲姿换弹"],
	[&"crouch_hit", "蹲姿受击"], [&"crouch_exit", "起身过渡"],
	[&"vault", "翻越轨迹"], [&"vault_fall", "翻越中断下落"],
	[&"crouch_land", "蹲姿落地"], [&"land", "站姿落地"],
	[&"impact", "表面命中动作"], [&"dead", "死亡"],
]
var elapsed: float = 0.0
var mode: int = -1
var event_timer: float = 0.0
var spark_timer: float = 0.0
var state = State.new()
var weapon := WeaponData.new()


func _ready() -> void:
	$Camera3D.look_at(Vector3(0.6, 0.9, 0))
	weapon.display_name = "预览方块武器"


func _process(delta: float) -> void:
	elapsed += delta
	var next := int(elapsed / 2.0) % MODES.size()
	var changed := next != mode
	if changed:
		mode = next
		$Presentation.reset_presentation()
		state = State.new()
		state.weapon = weapon
		event_timer = 0.0
		$CanvasLayer/Label.text = "模型与动画接口示例\n当前动作：%s\n右侧：命中粒子示例\n\n站高1.75米，蹲高1米；动作每两秒切换。\n手中方块为未配置武器素材的占位模型。\n这里只演示素材与动画，不执行攻击或碰撞。" % MODES[mode][1]
	var key: StringName = MODES[mode][0]
	var progress := fmod(elapsed, 2.0) / 2.0
	_preview_state(key, progress)
	$Presentation.apply_state(state)
	if changed and key in [&"land", &"crouch_land"]: $Presentation.play_event(&"land")
	event_timer -= delta
	if event_timer <= 0.0:
		if key in [&"fire", &"crouch_fire"]: $Presentation.play_event(&"fire")
		if key in [&"hit", &"crouch_hit"]: $Presentation.play_event(&"hit")
		if key == &"impact": $Presentation.play_event(&"impact")
		event_timer = 0.6
	spark_timer -= delta
	if spark_timer <= 0.0:
		var event = $ImpactEffects.capture_hit({"position": Vector3(2, 1, -0.78), "normal": Vector3.BACK}, Vector3.FORWARD, self)
		$ImpactEffects.dispatch_impact(event)
		spark_timer = 0.4


func _preview_state(key: StringName, progress: float) -> void:
	state.local_velocity = Vector3.ZERO
	if key == &"move": state.local_velocity = Vector3.FORWARD * 3.0
	if key == &"sprint": state.local_velocity = Vector3.FORWARD * 6.0
	if key == &"crouch_move": state.local_velocity = Vector3.FORWARD * 1.5
	state.sprinting = key == &"sprint"
	state.aiming = key in [&"aim", &"crouch_aim", &"fire", &"crouch_fire"]
	state.reloading = key in [&"reload", &"crouch_reload"]
	state.reload_progress = progress
	state.melee_active = key == &"melee"
	state.melee_progress = progress
	state.in_dialogue = key == &"dialogue"
	state.dead = key == &"dead"
	state.crouch_amount = 1.0 if String(key).begins_with("crouch") else 0.0
	state.posture_transition = &""
	if key == &"crouch_enter":
		state.crouch_amount = progress
		state.posture_transition = key
	elif key == &"crouch_exit":
		state.crouch_amount = 1.0 - progress
		state.posture_transition = key
	state.vaulting = key in [&"vault", &"vault_fall"]
	state.vault_falling = key == &"vault_fall"
	state.vault_progress = progress if key == &"vault" else 0.4
	if state.vaulting: state.crouch_amount = 1.0
	state.weapon_mount_position = Vector3(0, lerpf(1.3, 0.72, state.crouch_amount), 0)
	# 只移动预览挂点示意腾空，真实角色的高度仍必须由身体执行器提供。
	$Presentation.position.y = sin(progress * PI) * 1.2 if key == &"vault" else 0.0
	if key == &"vault_fall": $Presentation.position.y = (1.0 - progress) * 1.2
