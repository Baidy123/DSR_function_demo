extends Area3D
## Draw both pleated panels back while the player crosses the threshold.

const Director = preload("res://scripts/systems/scene_director.gd")

@onready var left_panel: Node3D = $Left
@onready var right_panel: Node3D = $Right
@onready var blocker: CollisionShape3D = $SolidCurtain/CollisionShape3D

var draw_tween: Tween
var story_managed := false
var passage_authorized := false


func _ready() -> void:
	body_entered.connect(_on_threshold_changed.bind(true))
	body_exited.connect(_on_threshold_changed.bind(false))


func _on_threshold_changed(body: Node3D, opening: bool) -> void:
	if not passage_authorized or not body.is_in_group(&"player"):
		return
	var director = Director.for_node(self)
	if director == null:
		set_open(opening)
		return
	director.request_action(&"script", {
		"source": self, "target": self,
		"parameters": {"mode": &"method", "method": &"set_open", "arguments": [opening]},
	})


func _unhandled_input(event: InputEvent) -> void:
	if story_managed or passage_authorized or not event.is_action_pressed("interact"):
		return
	for body in get_overlapping_bodies():
		if not body.is_in_group(&"player") or body.is_in_dialogue:
			continue
		var director = Director.for_node(self)
		if director == null:
			return
		get_viewport().set_input_as_handled()
		director.request_action(&"script", {"source": self, "target": self, "origin": &"interaction",
			"parameters": {"mode": &"method", "method": &"authorize_passage"}})
		return


func scene_action_is_background() -> bool:
	return true


func authorize_passage() -> void:
	passage_authorized = true
	set_open(true)


func set_open(opening: bool, during_camera := false) -> void:
	if draw_tween != null:
		draw_tween.kill()

	var width := 0.16 if opening else 1.0
	blocker.set_deferred("disabled", opening)
	draw_tween = create_tween().set_parallel()
	if during_camera:
		draw_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	draw_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	draw_tween.tween_property(left_panel, "scale:x", width, 0.25)
	draw_tween.tween_property(right_panel, "scale:x", width, 0.25)
