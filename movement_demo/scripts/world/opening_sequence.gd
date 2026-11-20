extends Node

const Director = preload("res://scripts/systems/scene_director.gd")
const Dialogue = preload("res://resources/dialogue/opening.dialogue")
const StarterWeapon = preload("res://resources/weapons/test_smg.tres")
const StarterAmmo = preload("res://resources/ammo/types/smg.tres")
const StarterMedkit = preload("res://resources/player/default_medkit.tres")
const ACTIVE := &"opening_active"
const COMPLETE := &"opening_complete"
const BOOTH_APPROACH := Vector3(-0.42, 0, -1.03)
const CAMERA_CUES := {
	"booth": ^"../BarEnvironment/Booths/Booth4/Curtain",
	"merchant": ^"../RewardNPC",
}
const MERCHANT_PLAYER_SEAT := ^"../BarEnvironment/SouthLounge/Tables/Setting1/SouthSofa/Seats/Center"
const SEAT_CUES := {
	"commissioner": [^"../BarEnvironment/Booths/Booth4/Seating/Seats/LeftRear"],
	"merchant": [MERCHANT_PLAYER_SEAT],
}

enum Phase { ARRIVAL, ENTER, BARTENDER, VISITOR, CURTAIN, COMMISSIONER, MERCHANT, CATALOG, DELIVERY, DEPART }

@export var exterior := false

@onready var scene: Node3D = get_parent()
@onready var player: CharacterBody3D = scene.get_node("Player")
@onready var ui: CanvasLayer = scene.get_node("DialogueUI")
@onready var state: Node = get_node("/root/GameState")

var phase: Phase
var _request: SceneRequest
var _motion: Tween
var _entrance: Node3D
var _bartender: Node3D
var _curtain: Node3D
var _commissioner: Node3D
var _merchant: Node3D
var _lounge_rail: Node3D
var _visitor: TavernNPC
var _runner: TavernNPC
var _runner_departure: SceneRequest
var _delivery_crate: MeshInstance3D
var _visitor_start: Vector3
var _runner_start: Vector3
var _portal: Interactable
var _objective: Label
var _marker: Label3D
var _target: Vector3
var _range := 1.6
var _scripted_seat: TavernSeat


func _ready() -> void:
	if exterior:
		_entrance = scene.get_node("Entrance")
		phase = Phase.ARRIVAL
		_clear_equipment()
		player.get_node("Visual").hide()
	else:
		if not state.get_flag(ACTIVE) or state.get_flag(COMPLETE):
			set_physics_process(false)
			set_process_unhandled_input(false)
			return
		_bartender = scene.get_node("BarEnvironment/BarCounter/Bartender")
		_curtain = scene.get_node("BarEnvironment/Booths/Booth4/Curtain")
		_commissioner = scene.get_node("NPC")
		_merchant = scene.get_node("RewardNPC")
		_lounge_rail = scene.get_node("BarEnvironment/SouthLounge/Enclosure/NorthWest")
		_curtain.story_managed = true
		_visitor = scene.get_node("Visitor")
		_runner = scene.get_node("Runner")
		ui.scripted_seat_assigned.connect(_on_scripted_seat_assigned)
		_visitor_start = _visitor.global_position
		_runner_start = _runner.global_position
		_portal = scene.get_node("Interactables/LevelPortal")
		_portal.enabled = false
		_commissioner.set_process_unhandled_input(false)
		_merchant.set_process_unhandled_input(false)
		_visitor.set_physical_presence(true)
		_clear_equipment()
		phase = Phase.BARTENDER
	_create_objective()
	_refresh_objective()


func _clear_equipment() -> void:
	player.get_node("Equipment").apply_campaign_snapshot({
		"primary_weapon": null, "secondary_weapon": null, "medkit_count": 0,
	})


func _physics_process(_delta: float) -> void:
	if _busy():
		return
	if phase == Phase.ARRIVAL or (phase == Phase.VISITOR and _near_target()):
		_start(&"system")
	elif _marker != null:
		_marker.modulate = Color(1.0, 0.83, 0.50) if _near_target() else Color(0.91, 0.85, 0.73)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _busy() or not _near_target():
		return
	if phase in [Phase.ARRIVAL, Phase.VISITOR, Phase.DEPART]:
		return
	get_viewport().set_input_as_handled()
	_start(&"interaction")


func _near_target() -> bool:
	var seat: TavernSeat = player.current_seat()
	if seat != null:
		if phase == Phase.COMMISSIONER:
			return _curtain.get_parent().is_ancestor_of(seat)
		if phase in [Phase.MERCHANT, Phase.CATALOG, Phase.DELIVERY]:
			return seat == get_node_or_null(MERCHANT_PLAYER_SEAT)
		if phase != Phase.BARTENDER:
			return false
	if phase == Phase.COMMISSIONER and _curtain.to_local(player.global_position).z > -0.35:
		return false
	if phase in [Phase.MERCHANT, Phase.CATALOG, Phase.DELIVERY] and player.global_position.z < _lounge_rail.global_position.z + 0.38:
		return false
	var offset := player.global_position - _target
	return Vector2(offset.x, offset.z).length_squared() <= _range * _range


func _busy() -> bool:
	return _request != null and not _request.is_terminal()


func _start(origin: StringName) -> void:
	var director = Director.for_node(self)
	if director == null:
		return
	_request = director.request_action(&"script", {
		"source": self, "target": self, "player": player, "origin": origin,
		"dedupe_key": &"opening_step",
	})
	if not _request.is_terminal():
		_request.finished.connect(_on_step_finished, CONNECT_ONE_SHOT)
		_marker.hide()


func begin_scene_action(request: SceneRequest) -> void:
	if request.kind != &"script" or request.node(&"target") != self or not request.is_current():
		return
	var director = Director.for_node(self)
	if phase == Phase.ENTER:
		state.set_flag(ACTIVE)
		var transition: SceneRequest = director.request_child(request, &"transition", {
			"source": self, "player": player,
			"parameters": {"path": "res://scenes/main.tscn", "return_control_on_failure": true},
		})
		if request.is_current() and transition.is_terminal():
			request.fail(String(transition.reason))
		return

	director.hold_request_controls(request, false, true)
	var completed := false
	match phase:
		Phase.ARRIVAL:
			completed = await _arrival(request)
		Phase.BARTENDER:
			completed = await _say(request, _bartender, "bartender")
		Phase.VISITOR:
			completed = await _visitor_sequence(request)
		Phase.CURTAIN:
			completed = await _say(request, _commissioner, "knock")
			if completed:
				_curtain.authorize_passage()
				await get_tree().physics_frame
				if not request.is_current():
					return
				await _walk(request, player, [
					_curtain.to_global(Vector3(0, 0, 0.56)),
					_curtain.to_global(Vector3(0, 0, -0.63)),
					_curtain.to_global(BOOTH_APPROACH),
				])
		Phase.COMMISSIONER:
			completed = await _say(request, _commissioner, "commissioner")
			if completed and request.is_current():
				await _release_scripted_seat(request)
				if not request.is_current():
					return
				state.help_choice = "accepted"
				state.available_level = 1
				state.talked_to_a = true
		Phase.MERCHANT:
			completed = await _say(request, _merchant, "merchant")
		Phase.CATALOG:
			completed = await _browse(request)
		Phase.DELIVERY:
			completed = await _deliver(request)
	if not request.is_current():
		return
	if not completed:
		request.fail("opening_step_incomplete")
		return
	phase = (int(phase) + 1) as Phase
	request.complete()
	if phase == Phase.CATALOG or phase == Phase.DELIVERY:
		_start_if_current_phase.call_deferred(phase)


func _start_if_current_phase(expected: Phase) -> void:
	if is_inside_tree() and phase == expected and not _busy() and _near_target():
		_start(&"system")


func cancel_scene_action(_request_to_cancel: SceneRequest, _reason: StringName) -> void:
	if _motion != null:
		_motion.kill()
		_motion = null
	if not exterior and is_instance_valid(_curtain):
		if is_instance_valid(_scripted_seat) and is_instance_valid(player) \
				and not player.is_dead() and not player.is_scripted_seat_moving():
			_scripted_seat.try_leave(player)
		_scripted_seat = null
		_curtain.set_open(false)
		if phase == Phase.VISITOR:
			_visitor.global_position = _visitor_start
		elif phase == Phase.DELIVERY:
			_reset_delivery()


func _on_step_finished(_finished: SceneRequest) -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		_refresh_objective()


func _arrival(request: SceneRequest) -> bool:
	if not await _say(request, scene.get_node("Car"), "arrival"):
		return false
	player.get_node("Visual").show()
	await _walk(request, player, [scene.get_node("CarExit").global_position])
	if not request.is_current():
		return false
	await _show_focus(request, _entrance, 11.0, 0.30)
	return request.is_current()


func _visitor_sequence(request: SceneRequest) -> bool:
	_curtain.set_open(true, true)
	var director = Director.for_node(self)
	var camera: SceneRequest = director.request_child(request, &"presentation", {
		"source": self, "target": _curtain,
		"parameters": {"size": 8.0, "move_seconds": 0.45, "hold_seconds": 0.78, "return_seconds": 0.45},
	})
	var side := 0.68 if _curtain.to_local(player.global_position).x <= 0.0 else -0.68
	await _walk(request, _visitor, [
		_curtain.to_global(Vector3(side, 0, -0.57)),
		_curtain.to_global(Vector3(side, 0, 0.92)),
	], true)
	await camera.wait_result()
	if not request.is_current():
		return false
	if not await _say(request, _visitor, "visitor"):
		return false
	_curtain.set_open(false)
	director.request_action(&"script", {
		"source": self, "target": _visitor, "dedupe_key": &"visitor_departure",
	})
	return true


func _browse(request: SceneRequest) -> bool:
	var director = Director.for_node(self)
	var action: SceneRequest = director.request_child(request, &"shop", {
		"source": _merchant, "target": scene.get_node("ShopController"), "player": player,
		"parameters": {"browse_only": true},
	})
	var result := await action.wait_result()
	return request.is_current() and result.status == &"completed"


func _deliver(request: SceneRequest) -> bool:
	if not await _say(request, _merchant, "prices"):
		return false
	_runner.set_physical_presence(true)
	var aisle: Marker3D = scene.get_node("TavernRoutes/RunnerToStaffDoor/Point01")
	var delivery_point: Marker3D = scene.get_node(
		"BarEnvironment/SouthLounge/Tables/Setting1/Table/RunnerDeliveryPoint")
	var director = Director.for_node(self)
	var arrival: SceneRequest = director.request_child(request, &"script", {
		"source": self, "target": _runner,
		"parameters": {"points": [aisle.global_position, delivery_point.global_position]},
	})
	var result := await arrival.wait_result()
	if not request.is_current():
		return false
	if result.status != &"completed":
		_reset_delivery()
		return false
	var facing := -delivery_point.global_basis.z
	_runner.rotation.y = atan2(-facing.x, -facing.z)
	_set_down_delivery_crate(delivery_point.get_parent() as Node3D)
	var clear_table: SceneRequest = director.request_action(&"script", {
		"source": self, "target": _runner, "dedupe_key": &"runner_clear_table",
		"parameters": {"points": [aisle.global_position]},
	})
	_runner_departure = clear_table
	clear_table.finished.connect(_continue_runner_departure)
	if not await _say(request, _merchant, "delivery"):
		if request.is_current():
			_reset_delivery()
		return false
	var cleared := await clear_table.wait_result()
	if not request.is_current():
		return false
	if cleared.status != &"completed":
		_reset_delivery()
		return false
	await _release_scripted_seat(request)
	if not request.is_current():
		return false
	_clear_delivery_crate()
	var equipment := player.get_node("Equipment")
	equipment.apply_campaign_snapshot({
		"primary_weapon": StarterWeapon,
		"secondary_weapon": null,
		"active_slot": 0,
		"magazines": [StarterWeapon.magazine_capacity, 0],
		"reserve_ammo": {StarterAmmo.ammo_id: 60},
		"medkit": StarterMedkit,
		"medkit_count": 1,
	})
	state.set_flag(COMPLETE)
	_portal.enabled = true
	_commissioner.set_process_unhandled_input(true)
	_merchant.set_process_unhandled_input(true)
	return true


func _continue_runner_departure(cleared_table: SceneRequest) -> void:
	if _runner_departure == cleared_table and cleared_table.status == &"completed":
		_runner_departure = Director.for_node(self).request_action(&"script", {
			"source": self, "target": _runner, "dedupe_key": &"runner_departure",
		})


func _set_down_delivery_crate(table: Node3D) -> void:
	var carried := _runner.get_node("Crate") as MeshInstance3D
	var tabletop := table.get_node("Collision").shape as BoxShape3D
	_delivery_crate = carried.duplicate() as MeshInstance3D
	_delivery_crate.name = "DeliveredCrate"
	table.add_child(_delivery_crate)
	_delivery_crate.transform = Transform3D(Basis.IDENTITY,
		Vector3(tabletop.size.x * 0.3, (tabletop.size.y + carried.get_aabb().size.y) * 0.5, 0.0))
	_runner.drop_crate()


func _clear_delivery_crate() -> void:
	if is_instance_valid(_delivery_crate):
		_delivery_crate.queue_free()
		_delivery_crate = null


func _reset_delivery() -> void:
	if _runner_departure != null and not _runner_departure.is_terminal():
		Director.for_node(self).cancel_request(_runner_departure.id, &"delivery_interrupted")
	_runner_departure = null
	_clear_delivery_crate()
	_runner.get_node("Crate").show()
	_runner.set_physical_presence(false)
	_runner.global_position = _runner_start


func _say(request: SceneRequest, source: Node, cue: String) -> bool:
	var director = Director.for_node(self)
	var action: SceneRequest = director.request_child(request, &"dialogue", {
		"source": source, "target": ui, "player": player,
		"parameters": {"resource": Dialogue, "start": cue, "face_source": cue != "arrival",
			"camera_cues": CAMERA_CUES, "seat_cues": SEAT_CUES},
	})
	var result := await action.wait_result()
	return request.is_current() and result.status == &"completed"


func _on_scripted_seat_assigned(_cue: String) -> void:
	_scripted_seat = player.current_seat()


func _release_scripted_seat(request: SceneRequest) -> void:
	if not is_instance_valid(_scripted_seat) or player.current_seat() != _scripted_seat:
		return
	var director = Director.for_node(self)
	var action: SceneRequest = director.request_child(request, &"script", {
		"source": self, "target": _scripted_seat, "player": player,
		"parameters": {"scripted": true, "leave": true},
	})
	var result := await action.wait_result()
	if result.status == &"completed":
		_scripted_seat = null


func _show_focus(request: SceneRequest, subject: Node3D, size: float, hold: float) -> void:
	var director = Director.for_node(self)
	var action: SceneRequest = director.request_child(request, &"presentation", {
		"source": self, "target": subject,
		"parameters": {"size": size, "move_seconds": 0.55, "hold_seconds": hold, "return_seconds": 0.45},
	})
	await action.wait_result()


func _walk(request: SceneRequest, actor: Node3D, points: Array[Vector3], during_camera := false) -> void:
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if during_camera:
		_motion.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var previous := actor.global_position
	for position in points:
		var point := position if exterior else _visitor.floor_position(position)
		_motion.tween_property(actor, "global_position", point,
			maxf(0.2, previous.distance_to(point) / 4.0))
		previous = point
	while request.is_current() and _motion.is_running():
		await get_tree().process_frame
	if request.is_current():
		_motion = null


func _create_objective() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.06, 0.075, 0.93)
	style.border_color = Color(0.76, 0.58, 0.32)
	style.border_width_left = 3
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	_objective = Label.new()
	_objective.add_theme_font_size_override("font_size", 19)
	panel.add_child(_objective)
	_marker = Label3D.new()
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.font_size = 36
	_marker.no_depth_test = true
	_marker.pixel_size = 0.006
	add_child(_marker)


func _refresh_objective() -> void:
	if _marker == null:
		return
	_range = 1.65
	var height := 2.05
	var text := ""
	var label := ""
	match phase:
		Phase.ARRIVAL:
			_objective.get_parent().hide()
			_marker.hide()
			return
		Phase.ENTER:
			text = "进入酒吧"
			label = "E  进入酒吧"
			_target = _entrance.global_position
		Phase.BARTENDER:
			text = "向吧台后的酒保打听大姐头"
			label = "E  询问酒保"
			_target = Vector3(-0.95, 0, -3.28)
		Phase.VISITOR, Phase.CURTAIN:
			text = "到酒吧东北角的门帘卡座找大姐头" if phase == Phase.VISITOR else "敲门帘旁的隔断"
			label = "门帘卡座" if phase == Phase.VISITOR else "E  敲隔断"
			_target = _curtain.to_global(Vector3(0, 0, 0.83))
			_range = 2.05 if phase == Phase.VISITOR else 1.55
		Phase.COMMISSIONER:
			text = "与大姐头交谈"
			label = "E  大姐头"
			_target = _curtain.to_global(BOOTH_APPROACH)
			_range = 1.15
		Phase.MERCHANT, Phase.CATALOG, Phase.DELIVERY:
			text = "去南侧围栏内最左边的卡座找商人"
			label = "E  商人"
			_target = _lounge_rail.global_position + Vector3(1.6, 0, 0.95)
			_target.x = maxf(_target.x, _merchant.global_position.x + 1.58)
			_range = 1.5
		Phase.DEPART:
			text = "从酒吧正门出发，前往铁港仓库取货"
			_objective.text = text
			_marker.hide()
			return
	_objective.get_parent().show()
	_objective.text = text
	_marker.global_position = _target + Vector3.UP * height
	_marker.text = label
	_marker.show()
