extends Node3D

const Director = preload("res://scripts/systems/scene_director.gd")

@onready var player: CharacterBody3D = $"../Player"
var _seats: Array[TavernSeat] = []
var _offer: TavernSeat
var _prompt: Label3D


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(&"tavern_seat"):
		if get_parent().is_ancestor_of(node):
			_seats.append(node)
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.font_size = 33
	_prompt.pixel_size = 0.006
	_prompt.modulate = Color("#efc691")
	add_child(_prompt)
	_prompt.hide()


func _physics_process(_delta: float) -> void:
	_offer = null
	if player.is_dead() or player.is_in_dialogue or player.is_vaulting():
		_prompt.hide()
		return
	var seated: TavernSeat = player.current_seat()
	_offer = seated if seated != null else _find_seat()
	_prompt.visible = _offer != null
	if _offer != null:
		_prompt.global_position = _offer.global_position + Vector3.UP * 1.15
		_prompt.text = "F  起身" if seated != null else "F  坐下"


func _find_seat() -> TavernSeat:
	var nearest: TavernSeat
	var best := INF
	for seat in _seats:
		if not is_instance_valid(seat):
			continue
		var score := seat.offer_score(player)
		if score < best:
			best = score
			nearest = seat
	return nearest


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or player.is_dead() or player.is_in_dialogue or player.is_vaulting():
		return
	var seated: TavernSeat = player.current_seat()
	if not event.is_action_pressed("sit"):
		return
	var seat := seated if seated != null else _find_seat()
	if seat == null:
		return
	var director = Director.for_node(self)
	if director == null:
		return
	get_viewport().set_input_as_handled()
	director.request_action(&"script", {"source": self, "target": seat, "player": player,
		"origin": &"interaction", "parameters": {"leave": seated != null}})
