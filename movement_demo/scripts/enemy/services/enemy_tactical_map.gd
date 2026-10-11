extends RefCounted

## One instance per NavigationRegion3D. Static geometry only: no actors, evidence,
## observation ledger, paths or permission to stand/fire. All work, including
## source audits, is advanced by the caller's existing Spatial allowance.
const CELL_SIZE := 4.0
const MAX_POINTS := 24
const MAX_SOURCES := 1024
const MAX_TEMPLATES := 2048
const MAX_POLYGON_VERTICES := 32
const MAX_POLYGON_CELLS := 256
const MAX_BUCKET := 24
const MAX_QUERY_CELLS := 81
const MAX_QUERY_RESULTS := 24
const MAX_SHAPE_CELLS := 64
const CACHE_REGIONS := 2
static var _retained: Array[Dictionary] = []

var _region: WeakRef
var _tree: SceneTree
var _mesh: NavigationMesh
var _header: Array = []
var _identity := ""
var _navigation_revision := 0
var _revision := 0
var _last_frame := -1
var _vertices := PackedVector3Array()
var _polygon_cursor := 0
var _polygon_work: Dictionary = {}
var _walk: Array[Dictionary] = []
var _sources: Dictionary = {}
var _source_ids: Array[int] = []
var _source_cursor := 0
var _events: Dictionary = {}
var _templates: Dictionary = {}
var _buckets: Dictionary = {}
var _chunk_revisions: Dictionary = {}
var _chunk_sources: Dictionary = {}
var _reuse: Dictionary = {}
var _mesh_dirty := true
var _turn := 0
var _saturated := false
var _stats := {"points": 0, "usec": 0, "world_queries": 0, "built": 0,
	"reused": 0, "audited": 0, "nav_rebuilds": 0}


func bind_region(region: NavigationRegion3D) -> void:
	if _region != null and _region.get_ref() == region: return
	release()
	if not is_instance_valid(region): return
	_region = weakref(region)
	_tree = region.get_tree()
	_identity = _map_identity(region)
	for entry: Dictionary in _retained:
		if entry.identity == _identity:
			_reuse = entry.templates
			break
	_walk.append({"node": weakref(region), "child": 0})
	_tree.node_added.connect(_node_added)
	_tree.node_removed.connect(_node_removed)


## Same-map combat reset deliberately retains static preparation.
func reset() -> void:
	pass


func release() -> void:
	if _tree != null and is_instance_valid(_tree):
		if _tree.node_added.is_connected(_node_added): _tree.node_added.disconnect(_node_added)
		if _tree.node_removed.is_connected(_node_removed): _tree.node_removed.disconnect(_node_removed)
	if _mesh != null and _mesh.changed.is_connected(_navigation_changed):
		_mesh.changed.disconnect(_navigation_changed)
	for source: Dictionary in _sources.values(): _disconnect_shape(source)
	if not _identity.is_empty() and not _templates.is_empty():
		for index in range(_retained.size() - 1, -1, -1):
			if _retained[index].identity == _identity: _retained.remove_at(index)
		_retained.push_front({"identity": _identity, "templates": _templates})
		if _retained.size() > CACHE_REGIONS: _retained.pop_back()
	_region = null
	_tree = null
	_mesh = null
	_identity = ""
	_header = []
	_vertices = PackedVector3Array()
	_polygon_cursor = 0
	_polygon_work = {}
	_walk = []
	_sources = {}
	_source_ids = []
	_source_cursor = 0
	_events = {}
	_templates = {}
	_buckets = {}
	_chunk_revisions = {}
	_chunk_sources = {}
	_reuse = {}
	_mesh_dirty = true
	_last_frame = -1
	_saturated = false


## deadline_usec is absolute. This is not a second independent 2 ms allowance.
## Even header reads and one-node tree traversal consume a point. Repeat calls
## from other members in the same physics frame cannot advance the shared job.
func advance_preparation(max_points: int, deadline_usec: int, frame_id: int = -1) -> Dictionary:
	var started := Time.get_ticks_usec()
	var frame := Engine.get_physics_frames() if frame_id < 0 else frame_id
	var result := {"points": 0, "usec": 0, "world_queries": 0, "ready": ready()}
	if max_points <= 0 or started >= deadline_usec or frame == _last_frame: return result
	var region := _get_region()
	if region == null or not region.is_inside_tree(): return result
	_last_frame = frame
	_check_navigation(region)
	result.points = 1
	result.world_queries = 1
	while result.points < mini(MAX_POINTS, max_points) and Time.get_ticks_usec() < deadline_usec:
		# Alternate source maintenance and topology, so neither can starve.
		_turn += 1
		if _turn % 2 == 0 and _has_navigation_work():
			_prepare_navigation(region)
		else:
			_maintain_one(region)
		result.points += 1
	result.usec = Time.get_ticks_usec() - started
	result.ready = ready()
	_stats.points += result.points
	_stats.usec += result.usec
	_stats.world_queries += result.world_queries
	return result


func ready() -> bool:
	return _region != null and _mesh != null and not _mesh_dirty \
		and not _has_navigation_work() and _walk.is_empty() and _events.is_empty()


func navigation_revision() -> int:
	return _navigation_revision


func revision() -> int:
	return _revision


func statistics() -> Dictionary:
	var value := _stats.duplicate()
	value.merge({"templates": _templates.size(), "sources": _sources.size(),
		"ready": ready(), "saturated": _saturated, "retained_regions": _retained.size()})
	return value


## Fixed 9x9 local chunk window, at most 24 entries/chunk, and 24 results.
## This reads prepared values only, including when preparation is incomplete.
## A sector is a polygon-local geometric template, NOT a connected room claim.
func query_sectors(origin: Vector3, radius: float, navigation_layers: int = 1, limit: int = 6) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var region := _get_region()
	if region == null or not region.is_inside_tree(): return result
	if not origin.is_finite() or radius <= 0.0 or limit <= 0 or _mesh_dirty: return result
	if _header.is_empty() or not bool(_header[2]) or (int(_header[3]) & navigation_layers) == 0: return result
	var center := _cell(origin)
	var candidates: Array[Dictionary] = []
	var cells := 0
	for x in range(-4, 5):
		for z in range(-4, 5):
			cells += 1
			if cells > MAX_QUERY_CELLS: break
			var cell := center + Vector2i(x, z)
			for key: String in _buckets.get(cell, []):
				var value: Dictionary = _templates.get(key, {})
				if value.is_empty(): continue
				if _template_dirty(value): continue
				var distance: float = Vector2(value.position.x - origin.x, value.position.z - origin.z).length_squared()
				if distance > radius * radius: continue
				candidates.append({"distance": distance, "key": key})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.key < b.key if is_equal_approx(a.distance, b.distance) else a.distance < b.distance)
	for index in mini(mini(limit, MAX_QUERY_RESULTS), candidates.size()):
		var value: Dictionary = _templates[candidates[index].key].duplicate(true)
		value.source_revision = _template_revision(value)
		value.navigation_revision = _navigation_revision
		result.append(value)
	return result


func template_valid(sector_key: String, source_revision: int, nav_revision: int = -1) -> bool:
	var region := _get_region()
	if region == null or not region.is_inside_tree(): return false
	if _mesh_dirty or (nav_revision >= 0 and nav_revision != _navigation_revision): return false
	var value: Dictionary = _templates.get(sector_key, {})
	return not value.is_empty() and not _template_dirty(value) and _template_revision(value) == source_revision


## Bounded prepared static collision/cover summaries for nearby sectors.
func query_geometry(origin: Vector3, radius: float, limit: int = 6) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not origin.is_finite() or radius <= 0.0 or limit <= 0: return result
	var examined := 0
	var seen: Dictionary = {}
	var center := _cell(origin)
	for x in range(-4, 5):
		for z in range(-4, 5):
			for id: int in _chunk_sources.get(center + Vector2i(x, z), {}):
				if seen.has(id): continue
				seen[id] = true
				examined += 1
				if examined > 64 or result.size() >= mini(limit, 12): return result
				var source: Dictionary = _sources.get(id, {})
				if source.is_empty() or source.get("dirty", true): continue
				var geometry: Dictionary = source.get("geometry", {})
				if geometry.is_empty(): continue
				var bounds: AABB = geometry.bounds
				var point := Vector3(clampf(origin.x, bounds.position.x, bounds.end.x), origin.y, clampf(origin.z, bounds.position.z, bounds.end.z))
				if point.distance_to(origin) <= radius: result.append(geometry.duplicate(true))
	return result


func _get_region() -> NavigationRegion3D:
	return _region.get_ref() as NavigationRegion3D if _region != null else null


func _map_identity(region: NavigationRegion3D) -> String:
	var scene: Node = region
	while scene.get_parent() != null and scene.scene_file_path.is_empty(): scene = scene.get_parent()
	return "%s|%s|%s" % [scene.scene_file_path, scene.get_path_to(region), region.global_transform]


func _navigation_changed() -> void:
	# Querying after an actual resource change immediately refuses old topology.
	_mesh_dirty = true


func _check_navigation(region: NavigationRegion3D) -> void:
	var mesh := region.navigation_mesh
	var header := [mesh.get_instance_id() if mesh != null else 0, region.global_transform,
		region.enabled, region.navigation_layers, NavigationServer3D.map_get_iteration_id(region.get_navigation_map())]
	if header != _header: _mesh_dirty = true
	if not _mesh_dirty: return
	if _mesh != mesh:
		if _mesh != null and _mesh.changed.is_connected(_navigation_changed): _mesh.changed.disconnect(_navigation_changed)
		_mesh = mesh
		if _mesh != null: _mesh.changed.connect(_navigation_changed)
	_header = header
	_vertices = mesh.get_vertices() if mesh != null else PackedVector3Array()
	_navigation_revision += 1
	_revision += 1
	_stats.nav_rebuilds += 1
	_templates = {}
	_buckets = {}
	_polygon_cursor = 0
	_polygon_work = {}
	_mesh_dirty = false


func _has_navigation_work() -> bool:
	return _mesh != null and (not _polygon_work.is_empty() or _polygon_cursor < _mesh.get_polygon_count())


func _prepare_navigation(region: NavigationRegion3D) -> void:
	if _polygon_work.is_empty():
		if _polygon_cursor >= _mesh.get_polygon_count(): return
		var polygon_index := _polygon_cursor
		_polygon_cursor += 1
		var indices := _mesh.get_polygon(polygon_index)
		if indices.size() < 3 or indices.size() > MAX_POLYGON_VERTICES:
			_saturated = true
			return
		var vertices := PackedVector3Array()
		var center := Vector3.ZERO
		for index: int in indices:
			if index < 0 or index >= _vertices.size(): return
			var point: Vector3 = region.global_transform * _vertices[index]
			vertices.append(point)
			center += point / indices.size()
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for point: Vector3 in vertices: bounds = bounds.expand(point)
		var first := _cell(bounds.position)
		var last := _cell(bounds.end)
		_polygon_work = {"index": polygon_index, "vertices": vertices, "center": center,
			"first": first, "last": last, "cursor": 0, "signature": hash([vertices, region.navigation_layers])}
		_store_sector(_polygon_work, center, "center")
		return
	var work := _polygon_work
	var width: int = work.last.x - work.first.x + 1
	var count: int = width * (work.last.y - work.first.y + 1)
	if work.cursor >= mini(count, MAX_POLYGON_CELLS):
		if count > MAX_POLYGON_CELLS: _saturated = true
		_polygon_work = {}
		return
	var cell := Vector2i(work.first.x + int(work.cursor) % width, work.first.y + int(work.cursor) / width)
	work.cursor += 1
	var point := Vector3((cell.x + 0.5) * CELL_SIZE, work.center.y, (cell.y + 0.5) * CELL_SIZE)
	var plane := Plane(work.vertices[0], work.vertices[1], work.vertices[2])
	if absf(plane.normal.y) > 0.001:
		point.y = (plane.d - plane.normal.x * point.x - plane.normal.z * point.z) / plane.normal.y
	if _inside_polygon(point, work.vertices): _store_sector(work, point, "%d:%d" % [cell.x, cell.y])


func _store_sector(work: Dictionary, point: Vector3, suffix: String) -> void:
	if _templates.size() >= MAX_TEMPLATES:
		_saturated = true
		return
	var key := "nav:%d:%s" % [work.index, suffix]
	var cell := _cell(point)
	var bucket: Array = _buckets.get(cell, [])
	if bucket.size() >= MAX_BUCKET:
		_saturated = true
		return
	var input_signature := hash([work.signature, point])
	var previous: Dictionary = _reuse.get(key, {})
	var value: Dictionary
	if previous.get("input_signature", -1) == input_signature:
		value = previous
		_stats.reused += 1
	else:
		var candidates: Array[Vector3] = [point]
		# Two alternatives stay inside the SAME convex baked polygon. They are
		# possibilities only; actor radius/path/visibility still need validation.
		for index in mini(2, work.vertices.size()):
			var alternative: Vector3 = point.lerp(work.vertices[index], 0.25)
			if alternative.distance_to(point) > 0.2: candidates.append(alternative)
		var sample_ids: Array[String] = []
		var cells: Array[Vector2i] = []
		for candidate: Vector3 in candidates:
			sample_ids.append("%d:%d:%d:%d" % [int(round(candidate.x * 100.0)), int(round(candidate.y * 100.0)), int(round(candidate.z * 100.0)), int(_header[3])])
			var candidate_cell := _cell(candidate)
			if not cells.has(candidate_cell): cells.append(candidate_cell)
		var connections: Array[Dictionary] = []
		for index in mini(8, work.vertices.size()):
			connections.append({"from": work.vertices[index], "to": work.vertices[(index + 1) % work.vertices.size()], "kind": &"polygon_edge"})
		value = {"sector_key": key, "position": point, "candidates": candidates,
			"samples": candidates.duplicate(), "sample_ids": sample_ids, "cell": cell, "cells": cells,
			"grid_key": "nav:%d:%.2f" % [int(_header[3]), CELL_SIZE],
			"polygon_id": work.index, "input_signature": input_signature,
			"connection_summary": connections, "static_only": true}
		_stats.built += 1
	_templates[key] = value
	bucket.append(key)
	_buckets[cell] = bucket


func _inside_polygon(point: Vector3, vertices: PackedVector3Array) -> bool:
	var polygon := PackedVector2Array()
	for vertex: Vector3 in vertices: polygon.append(Vector2(vertex.x, vertex.z))
	return Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), polygon)


func _template_revision(value: Dictionary) -> int:
	var versions: Array = [value.input_signature]
	for cell: Vector2i in value.cells: versions.append(_chunk_revisions.get(cell, 0))
	return hash(versions)


func _template_dirty(value: Dictionary) -> bool:
	for cell: Vector2i in value.cells:
		if _chunk_dirty(cell): return true
	return false


func _chunk_dirty(cell: Vector2i) -> bool:
	if _chunk_sources.get(cell, {}).size() > MAX_BUCKET: return true
	for id: int in _chunk_sources.get(cell, {}):
		if _sources.has(id) and _sources[id].dirty: return true
	return false


func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))


func _maintain_one(region: NavigationRegion3D) -> void:
	if not _events.is_empty():
		var id := 0
		for event_id: int in _events:
			id = event_id
			break
		var node: Node = _events[id].get_ref()
		_events.erase(id)
		if is_instance_valid(node) and _belongs_here(node, region): _register_shape(node)
		return
	if not _walk.is_empty():
		var entry: Dictionary = _walk.back()
		var node: Node = entry.node.get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree() or entry.child >= node.get_child_count():
			_walk.pop_back()
			return
		var child: Node = node.get_child(entry.child)
		entry.child += 1
		_register_shape(child)
		# Never descend into another navigation domain or dynamic actor body.
		if not child is NavigationRegion3D and not child is CharacterBody3D:
			_walk.append({"node": weakref(child), "child": 0})
		return
	if _source_ids.is_empty(): return
	_source_cursor %= _source_ids.size()
	var id: int = _source_ids[_source_cursor]
	_source_cursor += 1
	_audit_shape(id)


func _node_added(node: Node) -> void:
	if node is CollisionShape3D and _events.size() < MAX_SOURCES:
		_events[node.get_instance_id()] = weakref(node)


func _belongs_here(node: Node, region: NavigationRegion3D) -> bool:
	var parent := node.get_parent()
	for _depth in 64:
		if parent == region: return true
		if parent == null or parent is NavigationRegion3D or parent is CharacterBody3D: return false
		parent = parent.get_parent()
	return false


func _node_removed(node: Node) -> void:
	var id := node.get_instance_id()
	_events.erase(id)
	if _sources.has(id):
		_sources[id].dirty = true
		# Actual removal and affected chunk invalidation use the next budget slot.


func _register_shape(node: Node) -> void:
	if not node is CollisionShape3D or not node.get_parent() is StaticBody3D: return
	var id := node.get_instance_id()
	if _sources.has(id): return
	if _sources.size() >= MAX_SOURCES:
		_saturated = true
		return
	_sources[id] = {"node": weakref(node), "signature": [], "shape": null,
		"callback": Callable(), "geometry": {}, "dirty": true}
	_source_ids.append(id)
	_audit_shape(id)


func _shape_changed(id: int) -> void:
	if _sources.has(id): _sources[id].dirty = true


func _disconnect_shape(source: Dictionary) -> void:
	var shape: Shape3D = source.get("shape")
	var callback: Callable = source.get("callback", Callable())
	if shape != null and callback.is_valid() and shape.changed.is_connected(callback):
		shape.changed.disconnect(callback)


func _audit_shape(id: int) -> void:
	var source: Dictionary = _sources.get(id, {})
	if source.is_empty(): return
	_stats.audited += 1
	var node: CollisionShape3D = source.node.get_ref() as CollisionShape3D
	var region := _get_region()
	if node == null or not node.is_inside_tree() or region == null or not _belongs_here(node, region):
		_invalidate_geometry(source.geometry, id, false)
		_disconnect_shape(source)
		_sources.erase(id)
		_source_ids.erase(id)
		return
	var shape := node.shape
	var body := node.get_parent() as StaticBody3D
	var signature := [node.global_transform, node.disabled, body.collision_layer,
		shape.get_instance_id() if shape != null else 0]
	if not source.dirty and source.signature == signature: return
	_invalidate_geometry(source.geometry, id, false)
	if source.shape != shape:
		_disconnect_shape(source)
		source.shape = shape
		source.callback = _shape_changed.bind(id)
		if shape != null and not shape.changed.is_connected(source.callback): shape.changed.connect(source.callback)
	source.signature = signature
	source.dirty = false
	source.geometry = _shape_geometry(node, body)
	_invalidate_geometry(source.geometry, id, true)
	_revision += 1


func _shape_geometry(node: CollisionShape3D, body: StaticBody3D) -> Dictionary:
	if node.shape == null or node.disabled or (body.collision_layer & 1) == 0: return {}
	# Box geometry covers the existing map walls, cover and doors. Other shape
	# types retain their actual native debug-mesh bounds without claiming doors.
	var local_bounds: AABB
	if node.shape is BoxShape3D:
		local_bounds = AABB(-node.shape.size * 0.5, node.shape.size)
	else:
		local_bounds = node.shape.get_debug_mesh().get_aabb()
	var bounds: AABB = node.global_transform * local_bounds
	var faces: Array[Dictionary] = []
	if node.shape is BoxShape3D and body.has_method("get_candidates"):
		var half: Vector3 = node.shape.size * 0.5
		for axis in [0, 2]:
			var other: int = 2 if axis == 0 else 0
			for side in [-1.0, 1.0]:
				var ends: Array[Vector3] = []
				for direction in [-1.0, 1.0]:
					var point := Vector3(0.0, -half.y, 0.0)
					point[axis] = side * half[axis]
					point[other] = direction * half[other]
					ends.append(node.global_transform * point)
				faces.append({"axis": axis, "side": side, "ends": ends})
	return {"source_key": str(_get_region().get_path_to(node)), "bounds": bounds,
		"transform": node.global_transform, "shape_type": node.shape.get_class(),
		"cover_faces": faces, "collision_layer": body.collision_layer, "static_only": true}


func _invalidate_geometry(geometry: Dictionary, source_id: int, present: bool) -> void:
	if geometry.is_empty(): return
	var bounds: AABB = geometry.bounds
	var first := _cell(bounds.position - Vector3.ONE)
	var last := _cell(bounds.end + Vector3.ONE)
	var width := last.x - first.x + 1
	var count := width * (last.y - first.y + 1)
	if count > MAX_SHAPE_CELLS:
		# Rare region-wide shapes require topology invalidation, not a synchronous
		# scan of every template. The rebuild remains in the same shared queue.
		_mesh_dirty = true
		return
	for index in count:
		var cell := Vector2i(first.x + index % width, first.y + index / width)
		if not _chunk_revisions.has(cell) and _chunk_revisions.size() >= MAX_TEMPLATES * 4:
			_mesh_dirty = true
			_saturated = true
			continue
		_chunk_revisions[cell] = int(_chunk_revisions.get(cell, 0)) + 1
		var owners: Dictionary = _chunk_sources.get(cell, {})
		if present: owners[source_id] = true
		else: owners.erase(source_id)
		if owners.is_empty(): _chunk_sources.erase(cell)
		else: _chunk_sources[cell] = owners
