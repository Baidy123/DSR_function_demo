extends RefCounted

## Short physical corrections only. The action keeps its own target, route and timeout.
static var _regions: Dictionary = {}

var actor
var region: NavigationRegion3D
var relations
var _region_id := 0
var _elapsed := 0.0
var _nearby_elapsed := 0.0
var _nearby: Array[WeakRef] = []
var _desired := Vector3.ZERO
var _intent_frame := -1
var _point := Vector3.INF
var _next_point := Vector3.INF
var _point_remaining := 0.0
var _point_kind: StringName = &""
var _partner: WeakRef
var _yield_origin := Vector3.ZERO
var _yield_axis := Vector3.ZERO
var _return_point := Vector3.INF
var _hold_remaining := 0.0
var _requests: Dictionary = {}
var _failed_partner: WeakRef
var _failed_direction := Vector3.ZERO
var _failed_until := 0.0
var _backed_partner := 0
var _observing_partner := 0
var _observing_frame := -1
var _following_partner: WeakRef
var _following_axis := Vector3.ZERO
var _following_wait := 0.0
var _side_partner: WeakRef
var _side_sign := 1.0

func configure(body, navigation: NavigationRegion3D, board) -> void:
	if actor == body and region == navigation and relations == board: return
	if _regions.has(_region_id) and is_instance_valid(actor):
		_regions[_region_id].erase(actor.get_instance_id())
		if _regions[_region_id].is_empty(): _regions.erase(_region_id)
	actor = body
	region = navigation
	relations = board
	_region_id = region.get_instance_id() if is_instance_valid(region) else 0
	reset()
	if _region_id != 0:
		if not _regions.has(_region_id): _regions[_region_id] = {}
		_regions[_region_id][actor.get_instance_id()] = weakref(actor)

func reset() -> void:
	_elapsed = 0.0
	_nearby_elapsed = 0.0
	_nearby.clear()
	_desired = Vector3.ZERO
	_intent_frame = -1
	_point = Vector3.INF
	_next_point = Vector3.INF
	_point_remaining = 0.0
	_point_kind = &""
	_partner = null
	_return_point = Vector3.INF
	_hold_remaining = 0.0
	_requests.clear()
	_failed_partner = null
	_failed_direction = Vector3.ZERO
	_failed_until = 0.0
	_backed_partner = 0
	_observing_partner = 0
	_observing_frame = -1
	_following_partner = null
	_following_axis = Vector3.ZERO
	_following_wait = 0.0
	_side_partner = null
	_side_sign = 1.0

func _friend(other) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(other) or other == actor: return false
	if not other.is_inside_tree() or other.is_dead or not other.has_method("get_local_movement_velocity"): return false
	if other.local_motion.region != region or not is_instance_valid(region): return false
	return relations != null and relations.can_share_space(actor.get_instance_id(), other.get_instance_id())

func _body(ref: WeakRef):
	return ref.get_ref() if ref != null else null

func _radius(body) -> float:
	return float(body.get_node("CollisionShape3D").shape.radius)

func _neighbors() -> Array[WeakRef]:
	if _elapsed < _nearby_elapsed: return _nearby
	_nearby_elapsed = _elapsed + 0.2
	_nearby.clear()
	if not _regions.has(_region_id): return _nearby
	var entries: Dictionary = _regions[_region_id]
	for id in entries.keys():
		var other = entries[id].get_ref()
		if not is_instance_valid(other) or not other.is_inside_tree():
			entries.erase(id)
			continue
		# Dead bodies may be reset in place; their registration must survive respawn.
		if other.is_dead: continue
		if actor.global_position.distance_squared_to(other.global_position) <= 9.0 and _friend(other):
			_nearby.append(entries[id])
	return _nearby

func _walkable(point: Vector3, from: Vector3 = Vector3.INF, check_path: bool = true) -> bool:
	if not is_instance_valid(region) or not point.is_finite(): return false
	if not from.is_finite(): from = actor.global_position
	var projected: Vector3 = NavigationServer3D.region_get_closest_point(region.get_rid(), point)
	if Vector2(projected.x - point.x, projected.z - point.z).length() > 0.05 or absf(projected.y - point.y) > 0.5: return false
	var motion: Vector3 = point - from
	motion.y = 0.0
	var transform: Transform3D = actor.global_transform
	transform.origin = from
	if actor.test_move(transform, motion): return false
	if not check_path: return true
	var path := NavigationServer3D.map_get_path(region.get_navigation_map(), from, point, true, actor.agent.navigation_layers)
	if path.is_empty() or Vector2(path[-1].x - point.x, path[-1].z - point.z).length() > 0.05: return false
	var distance := 0.0
	for index in range(1, path.size()): distance += path[index - 1].distance_to(path[index])
	return distance <= motion.length() + 0.25

func _start_side(other, axis: Vector3, kind: StringName) -> bool:
	var side := axis.normalized().cross(Vector3.UP)
	var clearance := _radius(actor) + _radius(other) + 0.25
	var preferred: float = _side_sign if _body(_side_partner) == other else 1.0
	# A nearby recess can begin just ahead of the body. Validate both short
	# segments before committing, including the capsule around its corner.
	for longitudinal in [0.0, -0.45, 0.45]:
		var mouth: Vector3 = actor.global_position + axis.normalized() * longitudinal
		if longitudinal != 0.0 and not _walkable(mouth): continue
		for sign_value in [preferred, -preferred]:
			var point: Vector3 = mouth + side * clearance * sign_value
			if not _walkable(point, mouth): continue
			_point = mouth if longitudinal != 0.0 else point
			_next_point = point if longitudinal != 0.0 else Vector3.INF
			_point_remaining = 1.1
			_point_kind = kind
			_partner = weakref(other)
			_side_partner = weakref(other)
			_side_sign = sign_value
			_yield_origin = actor.global_position
			_yield_axis = axis.normalized()
			_return_point = mouth if kind == &"yield" else Vector3.INF
			return true
	return false

func _fail_or_back(other, axis: Vector3) -> void:
	_failed_partner = weakref(other)
	_failed_direction = _desired.normalized() if not _desired.is_zero_approx() else axis.normalized()
	_failed_until = _elapsed + 1.5
	if _backed_partner == other.get_instance_id(): return
	_backed_partner = other.get_instance_id()
	var away: Vector3 = actor.global_position - other.global_position
	away.y = 0.0
	var point: Vector3 = actor.global_position + away.normalized() * 0.45
	if not _walkable(point): return
	_point = point
	_next_point = Vector3.INF
	_point_remaining = 0.6
	_point_kind = &"back"
	_partner = weakref(other)

func request_pass(requester, direction: Vector3) -> void:
	if not _friend(requester) or direction.is_zero_approx() or not actor.can_move() or actor._hit_push_remaining > 0.0: return
	var id: int = requester.get_instance_id()
	if _requests.has(id): return # Repeated pressure cannot extend this request.
	_requests[id] = {"actor": weakref(requester), "direction": direction.normalized(), "until": _elapsed + 1.1, "frame": Engine.get_physics_frames()}

func _receive_pass() -> void:
	for id in _requests.keys():
		var request: Dictionary = _requests[id]
		var other = request.actor.get_ref()
		if request.until <= _elapsed or Engine.get_physics_frames() - int(request.frame) > Engine.physics_ticks_per_second * 1.1 or not _friend(other) or actor.global_position.distance_to(other.global_position) > 2.5 or Engine.get_physics_frames() - other.local_motion._intent_frame > 2:
			_requests.erase(id)
			continue
		var direction: Vector3 = request.direction
		if other.local_motion._desired.is_zero_approx() or other.local_motion._desired.normalized().dot(direction) < 0.5:
			_requests.erase(id)
			continue
		if not _desired.is_zero_approx():
			if _desired.normalized().dot(direction) > 0.6: continue
			if actor.get_instance_id() < id: continue
		if _body(_failed_partner) == other and _elapsed < _failed_until: continue
		if not _start_side(other, direction, &"yield"): _fail_or_back(other, direction)
		return

func _blocked_friend(neighbors: Array[WeakRef], desired: Vector3):
	if desired.is_zero_approx(): return null
	var axis := desired.normalized()
	var nearest = null
	var nearest_distance := INF
	for ref in neighbors:
		var other = _body(ref)
		if not is_instance_valid(other): continue
		var offset: Vector3 = other.global_position - actor.global_position
		if absf(offset.y) > 1.0: continue
		offset.y = 0.0
		var along := offset.dot(axis)
		var width := _radius(actor) + _radius(other) + 0.06
		if along <= 0.0 or along > 1.8 or (offset - axis * along).length() > width: continue
		if not _friend(other): continue
		if along < nearest_distance:
			nearest = other
			nearest_distance = along
	if nearest == null: return null
	var collision := KinematicCollision3D.new()
	if not actor.test_move(actor.global_transform, axis * minf(1.15, nearest_distance), collision): return null
	return nearest if collision.get_collider() == nearest else null

func resolve(desired: Vector3, delta: float, speed_limit: float) -> Vector3:
	_elapsed += maxf(0.0, delta)
	_desired = desired
	_intent_frame = Engine.get_physics_frames()
	if not is_instance_valid(region) or not actor.can_move() or actor._hit_push_remaining > 0.0:
		reset()
		return desired
	if (not _regions.has(_region_id) or _regions[_region_id].size() <= 1) and _requests.is_empty():
		if _partner != null or _following_partner != null:
			reset()
			_desired = desired
			_intent_frame = Engine.get_physics_frames()
		return desired
	var partner = _body(_partner)
	if not _friend(partner):
		_point = Vector3.INF
		_next_point = Vector3.INF
		_return_point = Vector3.INF
		_hold_remaining = 0.0
	if _hold_remaining > 0.0:
		_hold_remaining -= delta
		if _hold_remaining > 0.0 and _friend(partner) and (partner.global_position - _yield_origin).dot(_yield_axis) < _radius(actor) + _radius(partner) + 0.2:
			return Vector3.ZERO
		_hold_remaining = 0.0
		# Leave a recess through its validated mouth, rather than cutting the
		# wall corner diagonally while resuming the unchanged action direction.
		_point = _return_point
		_return_point = Vector3.INF
		_point_kind = &"return"
		_point_remaining = 1.1
	if _point.is_finite():
		_point_remaining -= delta
		var difference: Vector3 = _point - actor.global_position
		difference.y = 0.0
		if difference.length() < 0.08 or _point_remaining <= 0.0:
			_point = _next_point if difference.length() < 0.08 else Vector3.INF
			_next_point = Vector3.INF
			_point_remaining = 1.1
			if not _point.is_finite() and _point_kind == &"yield":
				_hold_remaining = 1.2
				return Vector3.ZERO
		elif _walkable(actor.global_position + difference.limit_length(0.2), Vector3.INF, false):
			var speed: float = minf(speed_limit, desired.length()) if not desired.is_zero_approx() else minf(speed_limit, actor.move_speed * actor.get_effective_movement_multiplier(1.0))
			return difference.normalized() * minf(speed, difference.length() / maxf(0.001, delta))
		else:
			_point = Vector3.INF
			_next_point = Vector3.INF
			if _friend(partner):
				_failed_partner = weakref(partner)
				_failed_direction = desired.normalized()
				_failed_until = _elapsed + 1.5
	if _point.is_finite(): return Vector3.ZERO
	_receive_pass()
	if _point.is_finite(): return Vector3.ZERO
	if desired.is_zero_approx(): return desired
	var failed = _body(_failed_partner)
	if _elapsed < _failed_until and _friend(failed) and not _failed_direction.is_zero_approx() and desired.normalized().dot(_failed_direction) > 0.8:
		var offset: Vector3 = failed.global_position - actor.global_position
		offset.y = 0.0
		var along := offset.dot(desired.normalized())
		if along > 0.0 and along < 2.5 and (offset - desired.normalized() * along).length() < _radius(actor) + _radius(failed) + 0.15:
			return Vector3.ZERO
	_failed_partner = null
	var other = _blocked_friend(_neighbors(), desired)
	if other == null: return desired
	var other_intent: Vector3 = other.local_motion._desired
	if Engine.get_physics_frames() - other.local_motion._intent_frame > 2:
		if _observing_partner != other.get_instance_id():
			_observing_partner = other.get_instance_id()
			_observing_frame = Engine.get_physics_frames()
		# A body that runs later this frame has not submitted its intent yet.
		# Briefly wait rather than mistaking normal following for a parked ally.
		if Engine.get_physics_frames() - _observing_frame < 2: return Vector3.ZERO
		other_intent = Vector3.ZERO
	else:
		_observing_partner = 0
	if not other_intent.is_zero_approx() and desired.normalized().dot(other_intent.normalized()) > 0.6:
		_following_partner = weakref(other)
		_following_axis = desired.normalized()
		_following_wait = 0.0
		var gap: float = actor.global_position.distance_to(other.global_position) - _radius(actor) - _radius(other) - 0.08
		return desired.normalized() * minf(desired.length(), maxf(0.0, minf(other_intent.length(), gap / 0.25)))
	if other_intent.is_zero_approx() and _body(_following_partner) == other and desired.normalized().dot(_following_axis) > 0.6:
		var gap: float = actor.global_position.distance_to(other.global_position) - _radius(actor) - _radius(other) - 0.08
		# The leader may simply have reached its destination. Use the remaining
		# free gap first, so the follower can stop behind it without a detour.
		if gap > 0.05: return desired.normalized() * minf(desired.length(), gap / 0.25)
		_following_wait += delta
		if _following_wait < 0.25: return Vector3.ZERO
		_following_partner = null
	if not other_intent.is_zero_approx() and desired.normalized().dot(other_intent.normalized()) < -0.4:
		if actor.get_instance_id() < other.get_instance_id():
			other.local_motion.request_pass(actor, desired)
			return Vector3.ZERO
		if not _start_side(other, other_intent, &"yield"): _fail_or_back(other, other_intent)
		return Vector3.ZERO
	if _start_side(other, desired, &"pass"): return Vector3.ZERO
	other.local_motion.request_pass(actor, desired)
	# A stationary friend gets a bounded chance to use its own legal space.
	if _body(_failed_partner) != other: _fail_or_back(other, desired)
	return Vector3.ZERO
