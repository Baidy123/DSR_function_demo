extends Node

## Health 的子组件；库存、计时属于本实例，生命结算只调用 Health。
signal state_changed

const MedkitSettings = preload("res://scripts/player/medkit_data.gd")

const INTERRUPTING_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right", &"sprint",
	&"aim", &"fire", &"reload", &"melee", &"crouch", &"vault", &"interact",
	&"weapon_primary", &"weapon_secondary", &"weapon_next", &"weapon_previous",
]

## 场景内为出生数量，远程检查器中为当前剩余量；重开恢复场景保存值。
@export_range(0, 999, 1) var remaining_count: int = 3:
	set(value):
		remaining_count = maxi(0, value)
		if is_node_ready():
			if remaining_count == 0: cancel()
			state_changed.emit()
## 可复用的医疗效果与时间资源；留空不能使用，不影响原生命系统。
@export var settings: MedkitSettings = preload("res://resources/player/default_medkit.tres")

var _using := false
var _elapsed := 0.0
var _duration := 0.0
var _heal_amount := 0.0
@onready var health = get_parent()
@onready var player = health.get_parent()
@onready var combat = player.get_node_or_null("Combat")

func _ready() -> void:
	# 在原身体／战斗物理更新之后复核；Health 的 Always 不应让医疗绕过暂停。
	process_physics_priority = 20
	health.hit_received.connect(_on_hit_received)
	health.died.connect(cancel)

func _input(event: InputEvent) -> void:
	if not _using or event.is_echo() or get_tree().paused: return
	if event.is_action_pressed("use_medkit"):
		cancel()
		# 防止同一次 H 在后续 unhandled 阶段重新开始。
		get_viewport().set_input_as_handled()
		return
	for action in INTERRUPTING_ACTIONS:
		if event.is_action_pressed(action):
			cancel()
			# 其他动作继续交给原移动、战斗、切槽和交互处理器。
			return

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("use_medkit"): return
	request_use()
	get_viewport().set_input_as_handled()

func request_use() -> bool:
	if _using or get_tree().paused or not _can_treat() or _has_action_input(): return false
	if settings == null or not is_finite(settings.heal_amount) or settings.heal_amount <= 0.0: return false
	if not is_finite(settings.use_seconds) or settings.use_seconds <= 0.0: return false
	_duration = settings.use_seconds
	_heal_amount = settings.heal_amount
	_elapsed = 0.0
	_using = true
	state_changed.emit()
	return true

func cancel() -> void:
	if not _using: return
	_using = false
	_elapsed = 0.0
	state_changed.emit()

func is_using() -> bool:
	return _using

func get_progress() -> float:
	return clampf(_elapsed / _duration, 0.0, 1.0) if _using and _duration > 0.0 else 0.0

func _physics_process(delta: float) -> void:
	if not _using: return
	if health.is_dead or player.is_in_dialogue:
		cancel()
		return
	if get_tree().paused: return
	# 逐键检查，反向键抵消、脚本输入或动作失败也不能继续治疗。
	if _has_action_input() or not _can_treat():
		cancel()
		return
	if not is_finite(delta) or delta <= 0.0: return
	_elapsed = minf(_duration, _elapsed + delta)
	if _elapsed < _duration and not is_equal_approx(_elapsed, _duration): return
	_using = false
	_elapsed = 0.0
	if health.restore_health(_heal_amount) > 0.0:
		remaining_count -= 1
	state_changed.emit()

func _can_treat() -> bool:
	if health.is_dead or health.health >= health.max_health or remaining_count <= 0 or player.is_in_dialogue: return false
	if not player.is_on_floor() or player.is_vaulting() or player.is_facing_npc: return false
	if player.current_speed > 0.02 or Vector2(player.velocity.x, player.velocity.z).length() > 0.02: return false
	# 身体的实际姿态量决定是否仍在蹲起，不借用表现层的动画状态。
	if player.crouch_amount > 0.0001 and player.crouch_amount < 0.9999: return false
	if combat != null:
		if combat.is_aiming or combat.shot_requested or combat.fire_held: return false
		if combat.is_melee_active() or combat.is_waiting_for_melee_stand(): return false
		if combat.ammo.is_reloading or combat.ammo.reload_checkpoint > 0.0: return false
	return true

func _has_action_input() -> bool:
	for action in INTERRUPTING_ACTIONS:
		if Input.is_action_pressed(action): return true
	return false

func _on_hit_received(_damage: float) -> void:
	cancel()

func _exit_tree() -> void:
	_using = false
	_elapsed = 0.0
