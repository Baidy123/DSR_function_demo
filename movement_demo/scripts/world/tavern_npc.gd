class_name TavernNPC
extends CharacterBody3D

const Director = preload("res://scripts/systems/scene_director.gd")
const ARRIVAL_DISTANCE := 0.12
const DETOUR_FORWARD := 1.75
const VISUAL_RADIUS := 0.35
const SEATED_VISUAL_RADIUS := 0.30
const COLLISION_RADIUS := 0.25
const STANDING_HEIGHT := 1.75
const CROUCH_HEIGHT := 1.0

signal interaction_requested(player: Node3D)

@export var tint := Color("#8b8075")
@export var carry_crate := false
@export var starts_hidden := false
@export var patrol_on_ready := false
@export_node_path("Node3D") var route_path: NodePath
@export_node_path("CollisionShape3D") var floor_path: NodePath = ^"../BarEnvironment/Architecture/Floor/Collision"
## World positions arranged in visiting order. A vacant route keeps this actor at its authored spot.
@export var route: Array[Vector3] = []
@export_range(0.0, 20.0, 0.1) var waypoint_pause := 1.8
@export_range(0.2, 5.0, 0.05) var walk_speed := 1.35

@export_group("特殊 NPC")
@export var special_npc := false
@export var npc_id: StringName
@export var dialogue_resource: DialogueResource
@export var dialogue_start := "start"
@export var keep_authored_position := false
@export_node_path("Node") var shop_controller_path: NodePath

@onready var _body: MeshInstance3D = $Body
@onready var _collider: CollisionShape3D = $CollisionShape3D
@onready var _interaction_area: Area3D = get_node_or_null("InteractionArea")
var _request: SceneRequest
var _seat: TavernSeat
var stage_state: Dictionary = {}
var _points: Array[Vector3] = []
var _detour: Array[Vector3] = []
var _index := 0
var _delay := 0.0
var _patrolling := false
var _vanish_at_end := false
var _loop_wait := 0.0
var _route_gate: TavernStaffDoor
var _route_finish_action: Dictionary = {}
var _floor_plane := Plane(Vector3.UP, 0.0)
var _detour_blocked_time := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_body.mesh = _body.mesh.duplicate()
	_collider.shape = _collider.shape.duplicate()
	if not special_npc:
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		_body.material_override = material
	var crate := get_node_or_null("Crate") as Node3D
	if crate != null:
		crate.visible = carry_crate
	_apply_pose(false)
	var floor_shape := get_node_or_null(floor_path) as CollisionShape3D
	if floor_shape != null and floor_shape.shape is BoxShape3D:
		var top := floor_shape.to_global(Vector3.UP * floor_shape.shape.size.y * 0.5)
		_floor_plane = Plane(floor_shape.global_basis.y.normalized(), top)
		var floor_body := floor_shape.get_parent() as PhysicsBody3D
		if floor_body != null:
			add_collision_exception_with(floor_body)
	set_physical_presence(not starts_hidden)
	if special_npc:
		if npc_id.is_empty():
			npc_id = StringName(name)
		add_to_group(&"npc")
	if _interaction_area != null:
		_interaction_area.monitoring = special_npc
	set_physics_process(false)
	if patrol_on_ready and not starts_hidden and (_authored_route() != null or not route.is_empty()):
		_start_patrol.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not special_npc or (dialogue_resource == null and shop_controller_path.is_empty()) or not visible:
		return
	if event.is_echo() or not event.is_action_pressed("interact"):
		return
	for player in get_tree().get_nodes_in_group(&"player"):
		if player.is_in_dialogue or player.is_dead():
			continue
		var nearby := _interaction_area != null and _interaction_area.overlaps_body(player)
		var same_table := current_seat() != null and player.has_method(&"current_seat") \
			and _seat.shares_table_with(player.current_seat())
		if not nearby and not same_table:
			continue
		interaction_requested.emit(player)
		if not get_viewport().is_input_handled():
			request_dialogue(player)
			get_viewport().set_input_as_handled()
		return


func request_dialogue(player: Node3D):
	if not special_npc:
		return null
	var director = Director.for_node(self)
	if director == null:
		return null
	var shop := get_node_or_null(shop_controller_path) if not shop_controller_path.is_empty() else null
	if shop != null:
		var shop_request: SceneRequest = director.request_action(&"shop", {
			"source": self, "target": shop, "player": player, "origin": &"interaction", "dedupe_key": &"npc_shop",
		})
		if shop_request.reason == &"busy" or (shop_request.has_started() and shop_request.status != &"failed"):
			return shop_request
	if dialogue_resource == null:
		return null
	return director.request_action(&"dialogue", {"source": self, "target": get_node_or_null("../DialogueUI"),
		"player": player, "origin": &"interaction", "dedupe_key": &"npc_dialogue",
		"parameters": {"resource": dialogue_resource, "start": dialogue_start, "face_source": true}})


func resolve_stage_position(fallback: Vector3) -> Vector3:
	return global_position if current_seat() != null or keep_authored_position else fallback


func apply_stage_state(state: Dictionary) -> void:
	set_physical_presence(bool(state.get("present", true)))
	var point = state.get("position")
	if point is Vector3 and current_seat() == null:
		global_position = resolve_stage_position(point)
	var facing = state.get("facing")
	if current_seat() == null and facing is Vector3 and not facing.is_zero_approx():
		look_at(Vector3(facing.x, global_position.y, facing.z), Vector3.UP)
	var dialogue = state.get("dialogue")
	if dialogue is String and not dialogue.is_empty():
		dialogue_resource = load(dialogue)
	stage_state = state.duplicate()


func current_seat() -> TavernSeat:
	return _seat if is_instance_valid(_seat) else null


func seat_body_dimensions(crouched: bool) -> Vector2:
	return Vector2(COLLISION_RADIUS, CROUCH_HEIGHT if crouched else STANDING_HEIGHT)


func drop_crate() -> void:
	var crate := get_node_or_null("Crate") as Node3D
	if crate != null:
		crate.hide()


func sit_at_seat(seat: TavernSeat, point: Vector3, heading: float) -> void:
	_seat = seat
	global_position = point
	global_rotation.y = heading
	_apply_pose(true)
	reset_physics_interpolation()


func stand_from_seat(point: Vector3) -> void:
	_seat = null
	global_position = point
	_apply_pose(false)
	reset_physics_interpolation()


func _apply_pose(crouched: bool) -> void:
	var dimensions := seat_body_dimensions(crouched)
	if _body.mesh is CapsuleMesh:
		_body.mesh.radius = SEATED_VISUAL_RADIUS if crouched else VISUAL_RADIUS
		_body.mesh.height = dimensions.y
		_body.position.y = dimensions.y * 0.5
	_collider.shape.radius = dimensions.x
	_collider.shape.height = dimensions.y
	_collider.position.y = dimensions.y * 0.5 + 0.03
	var presentation := get_node_or_null("NpcPresentation")
	if presentation != null:
		presentation.set_seated_pose(crouched)


func set_physical_presence(present: bool) -> void:
	visible = present
	collision_layer = 1 if present else 0
	if not present and current_seat() != null:
		var exit := _seat.exit_position_for(self)
		_seat.release(self)
		stand_from_seat(exit)


func _start_patrol() -> void:
	var director = Director.for_node(self)
	if director != null:
		director.request_action(&"script", {"source": self, "target": self,
			"parameters": {"patrol": true} if _authored_route() == null else {},
			"dedupe_key": &"patrol"})


func _authored_route() -> TavernRoute:
	return get_node_or_null(route_path) as TavernRoute if not route_path.is_empty() else null


func route_points() -> Array[Vector3]:
	var authored := _authored_route()
	return authored.world_points() if authored != null else route.duplicate()


func scene_action_is_background() -> bool:
	return true


func begin_scene_action(request: SceneRequest) -> void:
	if not request.is_current() or request.node(&"target") != self:
		return
	if _request != null and _request.is_current():
		request.fail("actor_is_moving")
		return
	var points: Array[Vector3] = []
	points.assign(request.parameters.get("points", route_points()))
	if points.is_empty():
		request.fail("route_empty")
		return
	var authored: TavernRoute = null if request.parameters.has("points") else _authored_route()
	var mode := authored.finish_mode if authored != null else TavernRoute.Finish.STAY
	var patrolling: bool = request.parameters.get("patrol", mode == TavernRoute.Finish.LOOP)
	var vanish: bool = not patrolling and request.parameters.get("vanish_at_end", mode == TavernRoute.Finish.DESPAWN)
	var finish_action := authored.finish_action() if authored != null and not patrolling and not vanish else {}
	if not finish_action.is_empty() and not is_instance_valid(finish_action.target):
		request.fail("route_finish_target_missing")
		return
	if current_seat() != null and not _seat.try_leave(self):
		request.fail("actor_seat_exit_blocked")
		return
	_request = request
	_patrolling = patrolling
	_loop_wait = authored.loop_interval if authored != null else waypoint_pause
	_vanish_at_end = vanish
	_points = points
	_route_gate = authored.exit_gate() if authored != null and _vanish_at_end else null
	_route_finish_action = finish_action
	_detour.clear()
	_index = 0
	_delay = 0
	_detour_blocked_time = 0
	_open_gate_on_last_leg()
	set_physics_process(true)


func cancel_scene_action(request: SceneRequest, _reason: StringName) -> void:
	if request == _request:
		_stop()


func _physics_process(delta: float) -> void:
	if _request == null or not _request.is_current():
		_stop()
		return
	if _delay > 0:
		_delay -= delta
		return
	var goal := _detour[0] if not _detour.is_empty() else _points[_index]
	var offset := goal - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= ARRIVAL_DISTANCE:
		if not _detour.is_empty():
			_detour.pop_front()
		else:
			_next_waypoint()
		return
	var direction := offset / distance
	var step := minf(walk_speed * delta, distance)
	if test_move(global_transform, _floor_motion(global_transform, direction * minf(0.86, distance))):
		if _detour.is_empty() and _find_detour(direction, distance):
			return
		if test_move(global_transform, _floor_motion(global_transform, direction * step)):
			_detour_blocked_time += delta
			if _detour_blocked_time > 0.25:
				_detour.clear()
				_detour_blocked_time = 0.0
			return
	_detour_blocked_time = 0.0
	rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), 7.0 * delta)
	move_and_collide(_floor_motion(global_transform, direction * step))


func _find_detour(direction: Vector3, distance: float) -> bool:
	var side := Vector3(-direction.z, 0, direction.x)
	for width in [0.75, -0.75, 1.08, -1.08]:
		var sideways := side * float(width)
		var forward := direction * minf(distance, DETOUR_FORWARD)
		var side_motion := _floor_motion(global_transform, sideways)
		var adjacent := global_transform.translated(side_motion)
		var forward_motion := _floor_motion(adjacent, forward)
		var alongside := adjacent.translated(forward_motion)
		var return_motion := _floor_motion(alongside, -sideways)
		if test_move(global_transform, side_motion) or test_move(adjacent, forward_motion) or test_move(alongside, return_motion):
			continue
		_detour.assign([adjacent.origin, alongside.origin, alongside.origin + return_motion])
		return true
	return false


func floor_position(point: Vector3) -> Vector3:
	point.y -= _floor_plane.distance_to(point) / _floor_plane.normal.y
	return point


func _floor_motion(from: Transform3D, planar: Vector3) -> Vector3:
	return floor_position(from.origin + planar) - from.origin


func _next_waypoint() -> void:
	_index += 1
	if _index == _points.size():
		if not _patrolling:
			_finish()
			return
		_index = 0
		_delay = _loop_wait
		return
	_open_gate_on_last_leg()
	if _patrolling:
		_delay = waypoint_pause


func _open_gate_on_last_leg() -> void:
	if is_instance_valid(_route_gate) and _index == _points.size() - 1:
		_route_gate.open_for(self)


func _finish() -> void:
	var finished := _request
	set_physics_process(false)
	if _vanish_at_end:
		set_physical_presence(false)
	var failure := ""
	if not _route_finish_action.is_empty():
		failure = await _run_route_finish_action(finished)
	if _request != finished or not finished.is_current():
		return
	_stop()
	if failure.is_empty():
		finished.complete()
	else:
		finished.fail(failure)


func _run_route_finish_action(parent: SceneRequest) -> String:
	var director = Director.for_node(self)
	if director == null or not is_instance_valid(_route_finish_action.target):
		return "route_finish_target_missing"
	var context := _route_finish_action.duplicate()
	context["source"] = self
	var child: SceneRequest = director.request_child(parent, &"script", context)
	var result := await child.wait_result()
	if result.status == &"completed":
		return ""
	var reason := String(result.reason)
	return reason if not reason.is_empty() else "route_finish_action_failed"


func _stop() -> void:
	if is_instance_valid(_route_gate):
		_route_gate.close_for(self)
	_route_gate = null
	_route_finish_action.clear()
	set_physics_process(false)
	_request = null
	_detour.clear()
