extends Node

const State = preload("res://scripts/systems/presentation/presentation_state.gd")
const MotionSample = preload("res://scripts/systems/presentation/motion_sample.gd")
@export var presentation_path: NodePath = ^"../Presentation"
## 纯表现剑光；留空不影响敌人近战判定。
@export var melee_effect_scene: PackedScene = preload("res://scenes/effects/melee_slash.tscn")
var _melee_effect: Node3D
var state = State.new()
var motion = MotionSample.new()
@onready var actor = get_parent()
@onready var presentation = get_node_or_null(presentation_path)


func _ready() -> void:
	process_physics_priority = 100
	motion.reset(actor)
	actor.shot_fired.connect(_on_shot)
	actor.hit_received.connect(_on_hit)
	actor.died.connect(_sync)
	actor.reset_completed.connect(_on_reset)
	actor.melee_started.connect(_sync)
	actor.melee_struck.connect(_on_melee_struck)
	actor.melee_finished.connect(_on_melee_finished)


func _physics_process(delta: float) -> void:
	state.local_velocity = motion.sample(actor, delta, actor.move_speed)
	var speed: float = state.local_velocity.length()
	# 进入与退出阈值略有差别，避免普通移动浮点误差反复触发冲刺。
	var margin := 0.02 if state.sprinting else 0.08
	state.sprinting = speed > actor.move_speed + margin and not actor.ammo.is_reloading
	_sync()


func _sync() -> void:
	if presentation == null: return
	state.dead = actor.is_dead
	state.aiming = actor.has_aim
	state.weapon = actor.weapon
	state.reloading = actor.ammo.is_reloading
	state.reload_progress = actor.ammo.reload_progress
	var ai := actor.get_node_or_null("AI")
	var melee = ai.context.melee if ai != null else null
	var melee_state: Dictionary = melee.presentation_state() if melee != null else {}
	state.melee_active = melee_state.get("active", false)
	state.melee_progress = melee_state.get("progress", 0.0)
	state.melee_phase = melee_state.get("phase", 0)
	presentation.apply_state(state)


func _on_melee_struck(_target: Node3D, settings: Dictionary, direction: Vector3) -> void:
	_sync()
	if actor.is_dead or not actor.melee_active or melee_effect_scene == null: return
	_clear_melee_effect()
	var effect := melee_effect_scene.instantiate()
	if not effect is Node3D or not effect.has_method("start"):
		effect.free()
		return
	_melee_effect = effect
	add_child(effect)
	effect.set_as_top_level(true)
	effect.add_to_group("enemy_melee_effect")
	effect.start(actor.global_position + Vector3.UP * 0.85, direction, settings.range, settings.angle)


func _on_melee_finished(cancelled: bool) -> void:
	if cancelled: _clear_melee_effect()
	_sync()


func _clear_melee_effect() -> void:
	if is_instance_valid(_melee_effect): _melee_effect.queue_free()
	_melee_effect = null


func _on_shot() -> void:
	_sync()
	if presentation != null: presentation.play_event(&"fire")


func _on_hit(damage: float, _attacker: Vector3) -> void:
	_sync()
	if damage > 0.0 and presentation != null: presentation.play_event(&"hit")


func _on_reset() -> void:
	_clear_melee_effect()
	motion.reset(actor)
	state = State.new()
	if presentation != null: presentation.reset_presentation()
	_sync()
