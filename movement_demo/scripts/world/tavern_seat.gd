class_name TavernSeat
extends Marker3D

const Geometry = preload("res://scripts/systems/character_geometry.gd")
const WALK_SPEED := 1.9
const TURN_SECONDS := 0.22
const SIT_SECONDS := 0.44
const FLOOR_CLEARANCE := 0.025
const ENTRY_DEPTHS := [0.68, 0.65, 0.78, 0.55, 0.25, 1.0]
const ENTRY_SIDES := [0.0, 0.48, -0.48, 0.76, -0.76, 1.05, -1.05]

@export_node_path("PhysicsBody3D") var furniture_collision: NodePath
@export_node_path("CharacterBody3D") var initial_occupant_path: NodePath
@export var share_table_with_opposite_sofa := false
@export_range(0.4, 3.0, 0.05) var reach := 1.55
@export_range(0.4, 2.5, 0.01) var npc_exit_distance := 0.9

@onready var _furniture := get_node_or_null(furniture_collision) as PhysicsBody3D
var _occupant: WeakRef
var _return_position: Vector3
var _seat_request: SceneRequest
var _entry_position: Vector3
var _approach_origin: Vector3
var _initial_posture: float
var _sliding_onto_seat := false


func _ready() -> void:
	add_to_group(&"tavern_seat")
	if not initial_occupant_path.is_empty():
		_bind_initial_occupant.call_deferred()


func _bind_initial_occupant() -> void:
	var actor := get_node_or_null(initial_occupant_path) as TavernNPC
	if actor != null and actor.visible and not claim(actor, exit_position_for(actor)):
		push_warning("初始角色无法坐入 %s" % get_path())


func exit_position_for(actor: TavernNPC) -> Vector3:
	return actor.floor_position(global_position - global_basis.z.normalized() * npc_exit_distance)


func begin_scene_action(request: SceneRequest) -> void:
	var actor := request.node(&"player") as CharacterBody3D
	var scripted: bool = request.parent_id != 0 and request.parameters.get("scripted", false)
	if not request.is_current() or actor == null or (actor.is_in_dialogue and not scripted) or actor.is_dead() or actor.is_vaulting():
		request.fail("seat_unavailable")
		return
	var success: bool
	if request.parameters.get("leave", false):
		success = try_leave(actor)
	elif scripted:
		success = await _assign_scripted(request, actor)
	else:
		success = offer_score(actor) < INF and claim(actor, actor.global_position)
	if not request.is_current():
		return
	if success:
		request.complete()
	else:
		request.fail("seat_blocked")


func cancel_scene_action(request: SceneRequest, _reason: StringName) -> void:
	if request == _seat_request:
		_end_seat_motion(request.node(&"player") as CharacterBody3D, false)


func _assign_scripted(request: SceneRequest, actor: CharacterBody3D) -> bool:
	var previous := actor.current_seat() as TavernSeat
	if previous != null:
		return shares_table_with(previous)
	if _seat_request != null or occupant() != null or not _has_room(actor):
		return false
	var return_position := _ground_point(actor, actor.global_position)
	var route := _approach_route(actor, return_position)
	if route.is_empty():
		return false
	_seat_request = request
	_initial_posture = actor.crouch_amount
	_entry_position = route.back()
	_approach_origin = return_position
	actor.set_scripted_seat_motion(true)
	var success := await _approach_and_sit(request, actor, route)
	if _seat_request != request:
		return false
	if success:
		success = claim(actor, return_position)
	_end_seat_motion(actor, success)
	return success


func _approach_route(actor: CharacterBody3D, start: Vector3) -> Array[Vector3]:
	if not start.is_finite():
		return []
	var forward := -global_basis.z.slide(Vector3.UP).normalized()
	var side := forward.cross(Vector3.UP)
	var standing: Vector2 = actor.seat_body_dimensions(false)
	var sitting: Vector2 = actor.seat_body_dimensions(true)
	var space := actor.get_world_3d().direct_space_state
	for depth: float in ENTRY_DEPTHS:
		for lateral: float in ENTRY_SIDES:
			var point := global_position + forward * depth + side * lateral
			point.y = start.y
			var entry := _ground_point(actor, point)
			if not entry.is_finite() or absf(entry.y - start.y) > 0.2:
				continue
			if not Geometry.can_occupy(actor, entry, standing.y, standing.x):
				continue
			var slide := Geometry.capsule_query(actor, entry, sitting.y, sitting.x)
			slide.exclude = _excluded_rids(actor)
			slide.motion = global_position - entry
			var fractions := space.cast_motion(slide)
			if fractions.size() != 2 or fractions[0] < 0.9999:
				continue
			if Geometry.can_sweep(actor, start, entry, standing.y, standing.x):
				return [entry]
			for axis: Vector3 in [forward, side]:
				var corner := _ground_point(actor, start + axis * (entry - start).dot(axis))
				if corner.is_finite() and absf(corner.y - start.y) <= 0.2 \
						and Geometry.can_sweep(actor, start, corner, standing.y, standing.x) \
						and Geometry.can_sweep(actor, corner, entry, standing.y, standing.x):
					return [corner, entry]
	return []


func _ground_point(actor: CharacterBody3D, point: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.18,
		point - Vector3.UP * 0.5, actor.collision_mask, [actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position + Vector3.UP * FLOOR_CLEARANCE if not hit.is_empty() else Vector3.INF


func _approach_and_sit(request: SceneRequest, actor: CharacterBody3D, route: Array[Vector3]) -> bool:
	for point in route:
		var offset := point - actor.global_position
		if offset.length() > 0.04:
			var walk_heading := atan2(-offset.x, -offset.z)
			if not await _move_seat_pose(request, actor, point, walk_heading, _initial_posture,
					maxf(0.16, offset.length() / WALK_SPEED)):
				return false
	var facing := -global_basis.z
	var heading := atan2(-facing.x, -facing.z)
	if not await _move_seat_pose(request, actor, actor.global_position, heading, _initial_posture, TURN_SECONDS):
		return false
	_sliding_onto_seat = true
	if is_instance_valid(_furniture):
		actor.add_collision_exception_with(_furniture)
	return await _move_seat_pose(request, actor, global_position, heading, 1.0, SIT_SECONDS)


func _move_seat_pose(request: SceneRequest, actor: CharacterBody3D, point: Vector3, heading: float,
		posture: float, duration: float) -> bool:
	var start := actor.global_position
	var start_heading: float = actor.get_seat_motion_heading()
	var start_posture: float = actor.crouch_amount
	var elapsed := 0.0
	while elapsed < duration:
		await get_tree().physics_frame
		if not request.is_current() or not is_instance_valid(actor) or actor.is_dead():
			return false
		if get_tree().paused:
			continue
		elapsed += get_physics_process_delta_time()
		var weight := smoothstep(0.0, duration, elapsed)
		var turn_weight := smoothstep(0.0, minf(duration, TURN_SECONDS), elapsed)
		actor.apply_seat_motion_pose(lerp_angle(start_heading, heading, turn_weight), lerpf(start_posture, posture, weight))
		var delta := start.lerp(point, weight) - actor.global_position
		if not delta.is_zero_approx() and actor.move_and_collide(delta) != null:
			return false
	return true


func _end_seat_motion(actor: CharacterBody3D, seated: bool) -> void:
	if is_instance_valid(actor) and actor.is_inside_tree():
		if not seated and _sliding_onto_seat:
			_recover_interrupted_slide(actor)
		actor.set_scripted_seat_motion(false)
	_sliding_onto_seat = false
	_seat_request = null


func _recover_interrupted_slide(actor: CharacterBody3D) -> void:
	actor.move_and_collide(_entry_position - actor.global_position)
	var dimensions: Vector2 = actor.seat_body_dimensions(false)
	var clear := Geometry.can_occupy(actor, actor.global_position, dimensions.y, dimensions.x)
	if not clear:
		# A moving body can occupy the entry after we have committed to the slide.
		# Finish in the reserved seat if returning to the floor is temporarily blocked.
		if claim(actor, _approach_origin):
			return
		clear = Geometry.can_occupy(actor, _approach_origin, dimensions.y, dimensions.x)
		if clear:
			actor.global_position = _approach_origin
			actor.reset_physics_interpolation()
	if is_instance_valid(_furniture):
		actor.remove_collision_exception_with(_furniture)
	if clear:
		actor.apply_seat_motion_pose(actor.get_seat_motion_heading(), _initial_posture)


func occupant() -> CharacterBody3D:
	return _occupant.get_ref() as CharacterBody3D if _occupant != null else null


func shares_table_with(other: TavernSeat) -> bool:
	if other == null:
		return false
	if get_parent() == other.get_parent():
		return true
	if not share_table_with_opposite_sofa or not other.share_table_with_opposite_sofa:
		return false
	var table_group := get_parent().get_parent().get_parent()
	return table_group.has_node("Table") and table_group == other.get_parent().get_parent().get_parent()


func offer_score(actor: CharacterBody3D) -> float:
	if _seat_request != null or occupant() != null or not actor.has_method(&"seat_body_dimensions"):
		return INF
	var offset := global_position - actor.global_position
	var flat := Vector3(offset.x, 0.0, offset.z)
	var forward := -actor.global_basis.z
	forward.y = 0.0
	var alignment := forward.normalized().dot(flat.normalized())
	if flat.length_squared() > reach * reach or absf(offset.y) > 1.4 or alignment < 0.4:
		return INF
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 1.30,
		global_position + Vector3.UP * 0.67, actor.collision_mask, _excluded_rids(actor))
	if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return INF
	return flat.length() + 0.7 * (1.0 - alignment) if _has_room(actor) else INF


func claim(actor: CharacterBody3D, exit_position: Vector3) -> bool:
	if _seat_request != null and _seat_request.node(&"player") != actor:
		return false
	if occupant() != null or not actor.has_method(&"sit_at_seat") or actor.current_seat() != null or not _has_room(actor):
		return false
	_occupant = weakref(actor)
	_return_position = exit_position
	actor.tree_exiting.connect(_on_actor_exiting, CONNECT_ONE_SHOT)
	if is_instance_valid(_furniture):
		actor.add_collision_exception_with(_furniture)
	var facing := -global_basis.z
	actor.sit_at_seat(self, global_position, atan2(-facing.x, -facing.z))
	return true


func try_leave(actor: CharacterBody3D) -> bool:
	if actor != occupant():
		return false
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var dimensions: Vector2 = actor.seat_body_dimensions(false)
	for offset in [Vector3.ZERO, side * 0.44, -side * 0.44, -forward * 0.18, forward * 0.44]:
		var destination: Vector3 = _return_position + offset + Vector3.UP * 0.025
		if not Geometry.can_occupy(actor, destination, dimensions.y, dimensions.x):
			continue
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.55,
			destination + Vector3.UP * 1.22, actor.collision_mask, _excluded_rids(actor))
		if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		release(actor)
		actor.stand_from_seat(destination)
		return true
	return false


func release(actor: CharacterBody3D) -> void:
	if actor != occupant():
		return
	if actor.tree_exiting.is_connected(_on_actor_exiting):
		actor.tree_exiting.disconnect(_on_actor_exiting)
	if is_instance_valid(_furniture):
		actor.remove_collision_exception_with(_furniture)
	_occupant = null


func _on_actor_exiting() -> void:
	var actor := occupant()
	if actor != null:
		release(actor)


func _has_room(actor: CharacterBody3D) -> bool:
	var dimensions: Vector2 = actor.seat_body_dimensions(true)
	var query := Geometry.capsule_query(actor, global_position, dimensions.y, dimensions.x)
	query.exclude = _excluded_rids(actor)
	return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _excluded_rids(actor: CharacterBody3D) -> Array[RID]:
	var result: Array[RID] = [actor.get_rid()]
	if is_instance_valid(_furniture):
		result.append(_furniture.get_rid())
	return result
