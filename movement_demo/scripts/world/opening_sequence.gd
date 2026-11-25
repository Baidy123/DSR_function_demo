extends Node

signal arrival_event_requested
signal scene_transition_requested
signal bartender_event_requested
signal visitor_event_requested
signal visitor_ready
signal visitor_motion_finished
signal visitor_camera_finished
signal visitor_dialogue_finished
signal curtain_event_requested
signal commissioner_event_requested
signal merchant_event_requested
signal delivery_event_requested
signal delivery_arrived
signal runner_clear_table_reached
signal equipment_granted

const Director = preload("res://scripts/systems/scene_director.gd")
const Dialogue = preload("res://resources/dialogue/opening.dialogue")
const ACTIVE := &"opening_active"
const COMPLETE := &"opening_complete"
const BOOTH_APPROACH := Vector3(-0.42, 0, -1.03)
const BARTENDER_HINT_HEIGHT := 2.35
const MERCHANT_PLAYER_SEAT := ^"../BarEnvironment/SouthLounge/Tables/Setting1/SouthSofa/Seats/Center"

enum Phase { ARRIVAL, ENTER, BARTENDER, VISITOR, CURTAIN, COMMISSIONER, MERCHANT, CATALOG, DELIVERY, DEPART }

@export var exterior := false

@onready var scene: Node3D = get_parent()
@onready var player: CharacterBody3D = scene.get_node("Player")
@onready var ui: CanvasLayer = scene.get_node("DialogueUI")
@onready var state: Node = get_node("/root/GameState")
@onready var campaign_save := get_node_or_null("/root/CampaignSaveService")

var phase: Phase
var _request: SceneRequest
var _event_busy := false
var _active_event_ids: Array[StringName] = []
var _motion: Tween
var _entrance: Node3D
var _bartender: Node3D
var _bartender_counter: CollisionShape3D
var _curtain: Node3D
var _commissioner: Node3D
var _merchant: Node3D
var _lounge_rail: Node3D
var _visitor: TavernNPC
var _runner: TavernNPC
var _delivery_crate: MeshInstance3D
var _runner_cleared_table := false
var _visitor_start: Vector3
var _runner_start: Vector3
var _portal: Interactable
var _objective: Label
var _marker: Label3D
var _target: Vector3
var _range := 1.6
var _director: Node


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
		_bartender_counter = scene.get_node("BarEnvironment/BarCounter/Long/Collision")
		_curtain = scene.get_node("BarEnvironment/Booths/Booth4/Curtain")
		_commissioner = scene.get_node("NPC")
		_merchant = scene.get_node("RewardNPC")
		_lounge_rail = scene.get_node("BarEnvironment/SouthLounge/Enclosure/NorthWest")
		_curtain.story_managed = true
		_visitor = scene.get_node("Visitor")
		_runner = scene.get_node("Runner")
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
	if exterior and campaign_save != null and campaign_save.startup_pending:
		return
	if _busy():
		return
	if phase == Phase.ARRIVAL or (phase == Phase.VISITOR and _near_target()):
		_start(&"system")
	elif _marker != null:
		if phase == Phase.BARTENDER:
			_target = _bartender.global_position
			_marker.global_position = _target + Vector3.UP * BARTENDER_HINT_HEIGHT
		_marker.modulate = Color(1.0, 0.83, 0.50) if _near_target() else Color(0.91, 0.85, 0.73)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _busy() or not _near_target():
		return
	if phase in [Phase.ARRIVAL, Phase.VISITOR, Phase.DEPART]:
		return
	get_viewport().set_input_as_handled()
	_start(&"interaction")


func _near_target() -> bool:
	if phase == Phase.BARTENDER:
		return _near_bartender()
	var seat: TavernSeat = player.current_seat()
	if seat != null:
		if phase == Phase.COMMISSIONER:
			return _curtain.get_parent().is_ancestor_of(seat)
		if phase in [Phase.MERCHANT, Phase.CATALOG, Phase.DELIVERY]:
			return seat == get_node_or_null(MERCHANT_PLAYER_SEAT)
		return false
	if phase == Phase.COMMISSIONER and _curtain.to_local(player.global_position).z > -0.35:
		return false
	if phase in [Phase.MERCHANT, Phase.CATALOG, Phase.DELIVERY] and player.global_position.z < _lounge_rail.global_position.z + 0.38:
		return false
	var offset := player.global_position - _target
	return Vector2(offset.x, offset.z).length_squared() <= _range * _range


func _near_bartender() -> bool:
	var cabinet := _bartender_counter.shape as BoxShape3D
	var player_at_bar := _bartender_counter.to_local(player.global_position)
	var bartender_at_bar := _bartender_counter.to_local(_bartender.global_position)
	var from_customer_edge := player_at_bar.x - cabinet.size.x * 0.5
	var offset := Vector2(from_customer_edge, player_at_bar.z - bartender_at_bar.z)
	return from_customer_edge >= 0.0 and offset.length_squared() <= _range * _range


func _busy() -> bool:
	return _event_busy or (_request != null and not _request.is_terminal())


func _start(origin: StringName) -> void:
	var director = Director.for_node(self)
	if director == null:
		return
	_bind_director(director)
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
	if request.parameters.get("mode", &"") == &"provider":
		_begin_event_adapter(request)
		return
	if _event_busy:
		request.fail("opening_event_busy")
		return
	var director = Director.for_node(self)
	if director == null:
		request.fail("missing_scene_director")
		return
	_bind_director(director)
	var family := _event_family(phase)
	for event_id in family:
		if not director.can_accept_event(event_id):
			request.fail("opening_event_unavailable:%s" % event_id)
			_refresh_objective()
			return
	_event_busy = true
	_active_event_ids = family.duplicate()
	_marker.hide()
	match phase:
		Phase.ARRIVAL:
			arrival_event_requested.emit()
		Phase.ENTER:
			scene_transition_requested.emit()
		Phase.BARTENDER:
			bartender_event_requested.emit()
		Phase.VISITOR:
			visitor_event_requested.emit()
		Phase.CURTAIN:
			curtain_event_requested.emit()
		Phase.COMMISSIONER:
			commissioner_event_requested.emit()
		Phase.MERCHANT:
			merchant_event_requested.emit()
		Phase.DELIVERY:
			_reset_delivery()
			delivery_event_requested.emit()
		_:
			_event_busy = false
			_active_event_ids.clear()
			request.fail("opening_phase_has_no_direct_event")
			_refresh_objective()
			return
	request.complete()


func cancel_scene_action(_request_to_cancel: SceneRequest, _reason: StringName) -> void:
	if _motion != null:
		_motion.kill()
		_motion = null
	if is_instance_valid(player):
		player.set_scripted_seat_motion(false)
	if not exterior and is_instance_valid(_curtain):
		_curtain.set_open(false)
		if phase == Phase.VISITOR:
			_visitor.global_position = _visitor_start
		elif phase == Phase.DELIVERY:
			_reset_delivery()


func _on_step_finished(_finished: SceneRequest) -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		_refresh_objective()


func _begin_event_adapter(request: SceneRequest) -> void:
	match request.parameters.get("opening_command", &""):
		&"exit_car":
			player.get_node("Visual").show()
			await _move_player(request, [scene.get_node("CarExit").global_position])
			if request.is_current():
				request.complete()
		&"finish_arrival":
			_finish_event(Phase.ENTER)
			request.complete()
		&"finish_bartender":
			_finish_event(Phase.VISITOR)
			request.complete()
		&"open_visitor_curtain":
			_curtain.set_open(true, true)
			var side := 0.68 if _curtain.to_local(player.global_position).x <= 0.0 else -0.68
			scene.get_node("OpeningMarkers/VisitorCurtainRoute/VisitorCurtainNear").global_position = \
				_curtain.to_global(Vector3(side, 0, -0.57))
			scene.get_node("OpeningMarkers/VisitorCurtainRoute/VisitorCurtainFar").global_position = \
				_curtain.to_global(Vector3(side, 0, 0.92))
			visitor_ready.emit()
			request.complete()
		&"visitor_motion_finished":
			visitor_motion_finished.emit()
			request.complete()
		&"visitor_camera_finished":
			visitor_camera_finished.emit()
			request.complete()
		&"close_visitor_curtain":
			_curtain.set_open(false)
			request.complete()
		&"finish_visitor_dialogue":
			_finish_event(Phase.CURTAIN)
			visitor_dialogue_finished.emit()
			request.complete()
		&"enter_booth":
			_curtain.authorize_passage()
			await get_tree().physics_frame
			if not request.is_current():
				return
			await _move_player(request, [
				_curtain.to_global(Vector3(0, 0, 0.56)),
				_curtain.to_global(Vector3(0, 0, -0.63)),
				_curtain.to_global(BOOTH_APPROACH),
			])
			if request.is_current():
				_finish_event(Phase.COMMISSIONER)
				request.complete()
		&"finish_commissioner":
			state.help_choice = "accepted"
			state.available_level = 1
			state.talked_to_a = true
			_finish_event(Phase.MERCHANT)
			request.complete()
		&"enter_catalog":
			phase = Phase.CATALOG
			_refresh_objective()
			request.complete()
		&"enter_delivery":
			phase = Phase.DELIVERY
			_refresh_objective()
			request.complete()
		&"request_delivery":
			_runner_cleared_table = false
			delivery_event_requested.emit()
			request.complete()
		&"drop_delivery_crate":
			var delivery_point: Marker3D = scene.get_node(
				"BarEnvironment/SouthLounge/Tables/Setting1/Table/RunnerDeliveryPoint")
			var facing := -delivery_point.global_basis.z
			_runner.rotation.y = atan2(-facing.x, -facing.z)
			_set_down_delivery_crate(delivery_point.get_parent() as Node3D)
			delivery_arrived.emit()
			request.complete()
		&"runner_clear_table":
			_runner_cleared_table = true
			runner_clear_table_reached.emit()
			request.complete()
		&"clear_delivery_crate":
			_clear_delivery_crate()
			request.complete()
		&"finalize_equipment":
			state.set_flag(COMPLETE)
			_portal.enabled = true
			_commissioner.set_process_unhandled_input(true)
			_merchant.set_process_unhandled_input(true)
			phase = Phase.DEPART
			_event_busy = false
			_active_event_ids.clear()
			_refresh_objective()
			equipment_granted.emit()
			request.complete()
		_:
			request.fail("unknown_opening_event_command")


func _finish_event(next_phase: Phase) -> void:
	phase = next_phase
	_event_busy = false
	_active_event_ids.clear()
	_refresh_objective()


func _bind_director(director: Node) -> void:
	if _director == director:
		return
	_director = director
	if not director.typed_event_finished.is_connected(_on_typed_event_finished):
		director.typed_event_finished.connect(_on_typed_event_finished)
	if not director.action_failed.is_connected(_on_director_action_failed):
		director.action_failed.connect(_on_director_action_failed)


func _on_typed_event_finished(event_id: StringName, status: StringName, reason: StringName) -> void:
	if not _event_busy or status == &"completed" or event_id not in _active_event_ids:
		return
	if phase == Phase.ENTER and status == &"cancelled":
		return
	_retry_current_event_family(event_id)


func _on_director_action_failed(rule: String, _reason: String) -> void:
	if _event_busy and phase == Phase.ENTER and rule == "loading":
		_retry_current_event_family(&"opening_scene_transition")


func _retry_current_event_family(failed_event_id: StringName) -> void:
	if not is_instance_valid(_director):
		return
	var retry_ids := _active_event_ids.duplicate()
	var delivery_ids := _event_family(Phase.DELIVERY)
	if failed_event_id in delivery_ids:
		retry_ids = delivery_ids
		phase = Phase.DELIVERY
		_reset_delivery()
	elif failed_event_id == &"opening_merchant_catalog":
		phase = Phase.MERCHANT
		_reset_delivery()
	for event_id in retry_ids:
		_director.reset_event(event_id)
	_event_busy = false
	_active_event_ids.clear()
	_refresh_objective()


func _event_family(value: Phase) -> Array[StringName]:
	match value:
		Phase.ARRIVAL:
			return [&"opening_arrival"]
		Phase.ENTER:
			return [&"opening_scene_transition"]
		Phase.BARTENDER:
			return [&"opening_bartender_guidance"]
		Phase.VISITOR:
			return [&"opening_visitor_entrance", &"opening_visitor_motion", &"opening_visitor_camera",
				&"opening_visitor_dialogue", &"opening_visitor_departure"]
		Phase.CURTAIN:
			return [&"opening_curtain_entry"]
		Phase.COMMISSIONER:
			return [&"opening_commissioner_seating"]
		Phase.MERCHANT, Phase.CATALOG:
			return [&"opening_merchant_catalog", &"opening_delivery_arrival",
				&"opening_runner_departure", &"opening_delivery_equipment"]
		Phase.DELIVERY:
			return [&"opening_delivery_arrival", &"opening_runner_departure",
				&"opening_delivery_equipment"]
	return []


func _move_player(request: SceneRequest, points: Array[Vector3]) -> void:
	player.set_scripted_seat_motion(true)
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var previous := player.global_position
	for position in points:
		var point := position if exterior else _visitor.floor_position(position)
		_motion.tween_property(player, "global_position", point,
			maxf(0.2, previous.distance_to(point) / 4.0))
		previous = point
	while request.is_current() and _motion.is_running():
		await get_tree().process_frame
	player.set_scripted_seat_motion(false)
	if request.is_current():
		_motion = null


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
	_runner_cleared_table = false
	_clear_delivery_crate()
	_runner.get_node("Crate").show()
	_runner.set_physical_presence(false)
	_runner.global_position = _runner_start


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
			_target = _bartender.global_position
			height = BARTENDER_HINT_HEIGHT
			_range = 2.05
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
	_marker.visible = not _event_busy
