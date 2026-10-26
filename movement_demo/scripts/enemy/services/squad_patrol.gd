extends RefCounted

## Coordinator-owned patrol progress. No body updates, action selection or clock.
const POINT_COUNT := 12
const RECENT_COUNT := 2
const REVISIT_SECONDS := 8.0
const ROUTE_MARGIN := 0.5
var _members: Dictionary = {}
var _visits: Dictionary = {}


func reset() -> void:
	_members.clear()
	_visits.clear()


func release(id: int) -> void:
	_members.erase(id)
	for key in _visits.keys():
		if _visits[key].member_id == id: _visits.erase(key)


func sites(context, radius: float, now: float) -> Array[Dictionary]:
	var id: int = context.actor.get_instance_id()
	if not _members.has(id):
		_members[id] = {"center": context._spawn_position, "radius": radius,
			"next_index": 0, "recent": [], "completed_token": []}
	var state: Dictionary = _members[id]
	var result: Array[Dictionary] = []
	for step in POINT_COUNT:
		var index: int = (int(state.next_index) + step) % POINT_COUNT
		var direction := Vector3(cos(TAU * index / POINT_COUNT), 0, sin(TAU * index / POINT_COUNT))
		var point: Vector3 = state.center + direction * state.radius
		var projected := NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), point)
		projected.y = context.actor.global_position.y
		if _distance(point, projected) > 0.4 or _distance(context.actor.global_position, projected) < 0.75: continue
		if state.recent.any(func(visit): return now - visit.at < REVISIT_SECONDS and (visit.index == index or _distance(visit.position, projected) < 0.75)): continue
		result.append({"position": projected, "look_position": projected + direction,
			"site_key": "patrol:%s:%s" % [id, index], "patrol_index": index,
			"patrol_center": state.center, "patrol_radius": state.radius})
	return result


## Called only after the coordinator validates identity, acceptance and arrival.
func complete(id: int, task: Dictionary, now: float) -> void:
	if not _members.has(id) or not task.has("patrol_index"): return
	var state: Dictionary = _members[id]
	var token := [task.get("generation"), task.get("task_id"), task.get("version")]
	if state.completed_token == token: return
	state.completed_token = token
	state.next_index = (int(task.patrol_index) + 1) % POINT_COUNT
	state.recent.append({"index": task.patrol_index, "position": task.position, "at": now})
	while state.recent.size() > RECENT_COUNT: state.recent.pop_front()
	_visits[task.site_key] = {"position": task.position, "visited_at": now, "member_id": id}


func snapshot(id: int) -> Dictionary:
	return _members.get(id, {}).duplicate(true)


func visits() -> Dictionary:
	return _visits.duplicate(true)


## A nearby endpoint must not route around a distant wall or another district.
static func route_within(route: PackedVector3Array, center: Vector3, radius: float) -> bool:
	if route.is_empty(): return false
	for point in route:
		if not point.is_finite() or _distance(point, center) > radius + ROUTE_MARGIN: return false
	return true


static func _distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
