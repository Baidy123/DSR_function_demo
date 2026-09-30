extends Node

const State = preload("res://scripts/systems/presentation/presentation_state.gd")
const MotionSample = preload("res://scripts/systems/presentation/motion_sample.gd")
@export var presentation_path: NodePath = ^"../Visual/Presentation"
var state = State.new()
var motion = MotionSample.new()
@onready var actor = get_parent()
@onready var presentation = get_node_or_null(presentation_path)


func _ready() -> void:
	process_physics_priority = 100
	motion.reset(actor)
	var combat = actor.get_node_or_null("Combat")
	var health = actor.get_node_or_null("Health")
	if combat != null:
		combat.shot_fired.connect(_on_shot)
		combat.weapon_changed.connect(_on_weapon)
		combat.melee_started.connect(_sync)
		combat.melee_finished.connect(_sync)
	if health != null:
		health.damage_applied.connect(_on_damage)
		health.died.connect(_on_death)


func _physics_process(delta: float) -> void:
	state.local_velocity = motion.sample(actor, delta, actor.move_speed)
	_sync()


func _sync() -> void:
	if presentation == null: return
	state.dead = actor.is_dead()
	state.in_dialogue = actor.is_in_dialogue
	state.sprinting = actor.is_sprinting and state.local_velocity.length() > 0.02
	var combat = actor.get_node_or_null("Combat")
	if combat != null:
		state.aiming = combat.is_aiming
		state.weapon = combat.weapon
		state.reloading = combat.ammo.is_reloading
		state.reload_progress = combat.ammo.reload_progress
		state.melee_active = combat.is_melee_active()
		state.melee_progress = combat.get_melee_progress()
		state.melee_phase = combat.melee_phase
	presentation.apply_state(state)


func _on_shot(_hit: bool, _stability: float) -> void:
	_sync()
	if presentation != null: presentation.play_event(&"fire")


func _on_weapon(_weapon: Resource) -> void:
	if presentation != null: presentation.reset_presentation()
	_sync()


func _on_damage(_damage: float) -> void:
	_sync()
	if presentation != null: presentation.play_event(&"hit")


func _on_death() -> void:
	_sync() # 同步通知可在 Health 暂停世界的同一调用栈中播放死亡。
