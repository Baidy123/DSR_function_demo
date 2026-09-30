extends Node3D

const State = preload("res://scripts/systems/presentation/presentation_state.gd")
const MODES := ["待机", "走路", "冲刺", "瞄准", "开火", "换弹", "受击", "交谈", "死亡"]
var elapsed: float = 0.0
var mode: int = -1
var event_timer: float = 0.0
var spark_timer: float = 0.0
var state = State.new()


func _ready() -> void:
	$Camera3D.look_at(Vector3(0.6, 0.9, 0))


func _process(delta: float) -> void:
	elapsed += delta
	var next := int(elapsed / 2.0) % MODES.size()
	if next != mode:
		mode = next
		$Presentation.reset_presentation()
		state = State.new()
		event_timer = 0.0
		$CanvasLayer/Label.text = "模型与动画接口示例\n当前动作：%s\n右侧：命中粒子示例\n\n使用简单网格演示接口，动作每两秒切换。\n正式角色的外观与动作由你配置的素材决定。" % MODES[mode]
	state.local_velocity = Vector3(0, 0, -6 if mode == 2 else -3) if mode in [1, 2] else Vector3.ZERO
	state.sprinting = mode == 2
	state.aiming = mode == 3
	state.reloading = mode == 5
	state.reload_progress = fmod(elapsed, 2.0) / 2.0
	state.in_dialogue = mode == 7
	state.dead = mode == 8
	$Presentation.apply_state(state)
	event_timer -= delta
	if event_timer <= 0.0:
		if mode == 4: $Presentation.play_event(&"fire")
		if mode == 6: $Presentation.play_event(&"hit")
		event_timer = 0.6
	spark_timer -= delta
	if spark_timer <= 0.0:
		var event = $ImpactEffects.capture_hit({"position": Vector3(2, 1, -0.78), "normal": Vector3.BACK}, Vector3.FORWARD, self)
		$ImpactEffects.dispatch_impact(event)
		spark_timer = 0.4
