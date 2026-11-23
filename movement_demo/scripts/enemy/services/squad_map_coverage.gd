extends RefCounted

## One squad's persistent area ledger. Navigation supplies observer positions;
## floor/collision samples describe hiding space, including off-nav margins.
const Visual = preload("res://scripts/enemy/services/enemy_visual_observation.gd")
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Geometry = preload("res://scripts/systems/character_geometry.gd")
const CELL_SIZE := 1.5
const SAMPLE_AREA := CELL_SIZE * CELL_SIZE / 4.0
const REVISIT_SECONDS := 30.0
var cells: Dictionary = {}
var map_id := ""
var map_version := 0
var completed_rounds := 0
var _region_id := 0
var _navigation_version := -1
var _queue: Array[Vector3] = []
var _cursor := 0
var _audit := 0
var _missing_audit := 0
var _observers: Dictionary = {}
var _last_observation: Dictionary = {}
var _round_at := 0.0
var _now := 0.0
var _position_stamps: Dictionary = {}
var _round_unseen := false

func bind(ctx) -> void:
	if not is_instance_valid(ctx.navigation_region) or ctx.navigation_region.navigation_mesh == null: return
	var nav_version: int = ctx.tactical_map.navigation_revision() if ctx.tactical_map != null else 0
	if _region_id == ctx.navigation_region.get_instance_id() and _navigation_version == nav_version: return
	_region_id = ctx.navigation_region.get_instance_id()
	_navigation_version = nav_version
	map_version += 1
	map_id = str(ctx.navigation_region.get_path())
	cells.clear()
	_observers.clear()
	_last_observation.clear()
	_queue.clear()
	_position_stamps.clear()
	_cursor = 0
	_audit = 0
	_missing_audit = 0
	_round_unseen = false
	completed_rounds = 0
	_round_at = _now
	var floors := {}
	for local: Vector3 in ctx.navigation_region.navigation_mesh.get_vertices():
		var point: Vector3 = ctx.navigation_region.to_global(local)
		var floor_id := roundi(point.y)
		if not floors.has(floor_id): floors[floor_id] = AABB(point, Vector3.ZERO)
		floors[floor_id] = floors[floor_id].expand(point)
	for floor_id in floors:
		var bounds: AABB = floors[floor_id]
		for x in range(floori(bounds.position.x / CELL_SIZE), ceili(bounds.end.x / CELL_SIZE)):
			for z in range(floori(bounds.position.z / CELL_SIZE), ceili(bounds.end.z / CELL_SIZE)):
				_queue.append(Vector3((x + 0.5) * CELL_SIZE, bounds.position.y, (z + 0.5) * CELL_SIZE))
	_queue.sort_custom(func(a, b): return a.distance_squared_to(ctx.actor.global_position) < b.distance_squared_to(ctx.actor.global_position))

func advance(ctx, now: float, deadline: int) -> void:
	_now = now
	bind(ctx)
	for work in 4:
		if _cursor >= _queue.size() or Time.get_ticks_usec() >= deadline: break
		_build(ctx, _queue[_cursor])
		_cursor += 1
	# Local collision revisions invalidate only affected samples; reservations,
	# new evidence and failed travel never subtract from the area denominator.
	if not cells.is_empty():
		var keys := cells.keys()
		for work in 4:
			if Time.get_ticks_usec() >= deadline: break
			_audit %= keys.size()
			var cell: Dictionary = cells[keys[_audit]]
			_audit += 1
			var stamp := _stamp(ctx, cell.position)
			if stamp != cell.geometry_version:
				cell.geometry_version = stamp
				cell.failure = &"geometry_changed"
				cell.retry_at = 0.0
			for sample in cell.samples:
				if sample.get("eye", Vector3.INF).is_finite() and ctx.tactical_map != null:
					# Geometry changes trigger a real check of the recorded view.
					# Chunk overlap alone must not erase unrelated observations.
					if sample.get("visibility_revision", -1) != ctx.tactical_map.revision():
						sample.visibility_revision = ctx.tactical_map.revision()
						if not Visual.clear_from(ctx, sample.eye, sample.position):
							sample.previous_observed_at = sample.observed_at
							sample.observed_at = -INF
							sample.duration = 0.0
							sample.watched_until = 0.0
							sample.erase("eye")
				if sample.observed_at < _round_at: _round_unseen = true
			if _audit == keys.size():
				if ready() and not _round_unseen and now - _round_at > 2.0:
					completed_rounds += 1
					_round_at = now
				_round_unseen = false
	# Previously solid or missing patches may become inspectable after edits.
	if ready() and not _queue.is_empty() and Time.get_ticks_usec() < deadline:
		var point := _queue[_missing_audit % _queue.size()]
		_missing_audit += 1
		if _position_stamps.get(point, 0) != _stamp(ctx, point):
			var key := "%s:%s:%s" % [roundi(point.y), floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE)]
			if not cells.has(key): _build(ctx, point)
			_position_stamps[point] = _stamp(ctx, point)

func _stamp(ctx, position: Vector3) -> int:
	return ctx.tactical_map.observation_revision(position) if ctx.tactical_map != null else 0

func _build(ctx, center: Vector3) -> void:
	_position_stamps[center] = _stamp(ctx, center)
	var samples: Array[Dictionary] = []
	var excluded := Geometry.exclusions(ctx.actor, true)
	for offset in [Vector2(-0.25, -0.25), Vector2(-0.25, 0.25), Vector2(0.25, -0.25), Vector2(0.25, 0.25)]:
		var raw: Vector3 = center + Vector3(offset.x, 0, offset.y) * CELL_SIZE
		var query := PhysicsRayQueryParameters3D.create(raw + Vector3.UP * 0.4, raw - Vector3.UP * 0.6, 1, excluded)
		var ground: Dictionary = ctx.actor.get_world_3d().direct_space_state.intersect_ray(query)
		if ground.is_empty() or ground.normal.y < 0.8: continue
		var point: Vector3 = ground.position
		# Exclude solid wall interiors, never inaccessible free space. This tiny
		# static-only capsule is a hiding-space probe, not the actual player body.
		if not Geometry.can_occupy(ctx.actor, point + Vector3.UP * 0.02, 0.65, 0.12, true): continue
		samples.append({"position": point, "duration": 0.0, "observed_at": -INF,
			"observer": 0, "watched_until": 0.0, "source": &"", "task_id": 0})
	if samples.is_empty(): return
	var key := "%s:%s:%s" % [roundi(center.y), floori(center.x / CELL_SIZE), floori(center.z / CELL_SIZE)]
	var point: Vector3 = NavigationServer3D.region_get_closest_point(ctx.navigation_region.get_rid(), center)
	point.y = samples[0].position.y
	var reachable := Contract.horizontal(point, center) <= CELL_SIZE
	cells[key] = {"key": key, "map_id": map_id, "floor": roundi(center.y), "position": center,
		"area": samples.size() * SAMPLE_AREA, "samples": samples, "observer_position": point,
		"geometry_version": _stamp(ctx, center), "reachable": reachable, "observable": false,
		"failure": &"" if reachable else &"no_navigation_post", "retry_at": 0.0, "responsibility": 0}

func ready() -> bool:
	return not map_id.is_empty() and _cursor >= _queue.size()

func release(id: int) -> void:
	_observers.erase(id)
	_last_observation.erase(id)
	for cell in cells.values():
		if cell.responsibility == id: cell.responsibility = 0
		for sample in cell.samples:
			if sample.observer == id: sample.watched_until = 0.0

func observe(ctx, token: Dictionary, now: float, duration: float, deadline: int) -> void:
	var id: int = ctx.actor.get_instance_id()
	if now <= float(_last_observation.get(id, -INF)): return
	_last_observation[id] = now
	if ctx.actor.is_dead or ctx.actor.is_vaulting() or ctx.actor.melee_active: return
	var work: Dictionary = _observers.get(id, {})
	if work.is_empty() or now >= work.until or Contract.horizontal(work.position, ctx.actor.global_position) > 1.0:
		var nearby: Array = []
		var position: Vector3 = ctx.actor.global_position
		var distance_squared: float = ctx.perception.sight_distance * ctx.perception.sight_distance
		for key in cells:
			var cell: Dictionary = cells[key]
			var offset: Vector3 = cell.position - position
			if absf(offset.y) > 1.0: continue
			if offset.x * offset.x + offset.z * offset.z <= distance_squared: nearby.append(key)
		# Round-robin inspection checks every nearby sample; repeatedly sorting
		# the same scan adds cost and gives no additional observation evidence.
		work = {"keys": nearby, "cursor": int(work.get("cursor", 0)), "until": now + 0.5, "position": position}
		_observers[id] = work
	if work.keys.is_empty(): return
	# Credit only time actually checked; skipped frames cannot manufacture dwell.
	var dt := minf(duration, 0.1)
	for count in mini(24, work.keys.size() * 4):
		if Time.get_ticks_usec() >= deadline: break
		work.cursor %= work.keys.size() * 4
		var key: String = work.keys[work.cursor / 4]
		var index: int = work.cursor % 4
		work.cursor += 1
		if not cells.has(key): continue
		var cell: Dictionary = cells[key]
		if index >= cell.samples.size() or cell.geometry_version != _stamp(ctx, cell.position): continue
		var sample: Dictionary = cell.samples[index]
		if not Visual.visible(ctx, sample.position): continue
		credit(key, sample.position, id, token.get("task_id", 0), now, dt, ctx)

## Called only after the coordinator/service checked this exact sample. A
## second observer/report in the same area tick cannot duplicate elapsed time.
func credit(key: String, point: Vector3, member: int, task_id: int, now: float, delta: float, ctx) -> void:
	if not cells.has(key): return
	var cell: Dictionary = cells[key]
	for sample in cell.samples:
		if sample.position.distance_squared_to(point) > 0.001: continue
		if float(sample.get("credited_at", -INF)) >= now: return
		cell.observable = true
		if now - float(sample.get("credited_at", -INF)) > REVISIT_SECONDS: sample.duration = 0.0
		sample.credited_at = now
		sample.duration += minf(delta, 0.1)
		sample.observer = member
		sample.source = &"personal_visual"
		sample.task_id = task_id
		sample.eye = ctx.actor.get_eye_position()
		if ctx.tactical_map != null: sample.visibility_revision = ctx.tactical_map.revision()
		sample.watched_until = now + 0.25
		if sample.duration >= 0.25: sample.observed_at = now
		return

func state(cell: Dictionary, now: float) -> StringName:
	var seen := 0
	var fresh := 0
	for sample in cell.samples:
		if sample.observed_at > -INF: seen += 1
		if now - float(sample.observed_at) <= REVISIT_SECONDS: fresh += 1
	if fresh == cell.samples.size(): return &"recent"
	if seen == cell.samples.size(): return &"revisit"
	return &"partial" if seen > 0 else &"unknown"

func unfinished(key: String, now: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	for sample in cells.get(key, {}).get("samples", []):
		if now - float(sample.observed_at) > REVISIT_SECONDS: result.append(sample.position)
	return result

func reject(key: String, reason: StringName, now: float) -> void:
	if not cells.has(key): return
	cells[key].failure = reason
	cells[key].retry_at = now + 4.0

func reserve(tasks: Dictionary) -> void:
	for cell in cells.values(): cell.responsibility = 0
	for id in tasks:
		var key: String = tasks[id].get("coverage_key", "")
		if cells.has(key): cells[key].responsibility = id

func snapshot(now: float, detail: bool = false) -> Dictionary:
	var area := 0.0
	var covered := 0.0
	var recent := 0.0
	var observed := 0
	var display: Array[Dictionary] = []
	for cell in cells.values():
		area += cell.area
		var status := state(cell, now)
		if status in [&"recent", &"revisit"]: observed += 1
		for sample in cell.samples:
			if sample.observed_at > -INF: covered += SAMPLE_AREA
			if now - float(sample.observed_at) <= REVISIT_SECONDS: recent += SAMPLE_AREA
		if detail: display.append({"key": cell.key, "position": cell.position, "state": status,
			"failure": cell.failure, "reachable": cell.reachable, "observable": cell.observable,
			"responsibility": cell.responsibility, "samples": cell.samples.duplicate(true)})
	return {"map_id": map_id, "map_version": map_version, "ready": ready(), "cells": cells.size(),
		"observed": observed, "area": area, "observed_area": covered, "recent_area": recent,
		"round": completed_rounds, "cell_size": CELL_SIZE, "display": display}
