extends RefCounted

## Squad-owned search evidence and bounded area coverage. Hints are explicitly
## uncertain samples, never visual reports or permission to fire.
const Hints = preload("res://scripts/enemy/services/enemy_search_hints.gd")
const Geometry = preload("res://scripts/systems/character_geometry.gd")
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
var _hints = Hints.new()
var center := Vector3.ZERO
var origin := Vector3.ZERO
var settings: Dictionary = {}
var cells: Dictionary = {}
var hint: Dictionary = {}
var revision := 0
var round := 0
var hint_checks := 0
var started_at := 0.0
var _next_hint := 0.0
var _lost_hint := true
var _allow_hint := false
var _cursor := 0
var _extent := 0
var _spacing := 1.5
var _next_round := 0.0
var _excluded: Dictionary = {}

func begin(objective: Dictionary, profiles: Dictionary, now: float) -> void:
	settings = {}
	for profile in profiles.values():
		var action = Contract.executor(profile, &"search")
		if not action.is_empty():
			settings = profile.actions[action].parameters.duplicate(true)
			break
	origin = objective.position
	center = origin
	started_at = now
	_next_hint = now
	_lost_hint = true
	_allow_hint = objective.get("source") != &"noise" and objective.get("target_id", 0) != 0
	hint.clear()
	hint_checks = 0
	round = 0
	_rebuild()

func _rebuild() -> void:
	revision += 1
	cells.clear()
	_excluded.clear()
	_cursor = 0
	_spacing = maxf(1.25, float(settings.get("search_coverage_radius", 2.0)) * 0.75)
	_extent = ceili(float(settings.get("search_radius", 5.0)) / _spacing)
	_next_round = 0.0

func advance(contexts: Array, profiles: Dictionary, now: float) -> void:
	if contexts.is_empty(): return
	if _allow_hint and now >= _next_hint:
		_check_hint(contexts, profiles, now)
	var ctx = contexts[0]
	var total = (_extent * 2 + 1) * (_extent * 2 + 1)
	var deadline = Time.get_ticks_usec() + 500
	for work in 8:
		if _cursor >= total or Time.get_ticks_usec() >= deadline: break
		var width = _extent * 2 + 1
		var offset = Vector3(float(_cursor / width - _extent), 0, float(_cursor % width - _extent)) * _spacing
		_cursor += 1
		var radius = float(settings.get("search_radius", 5.0))
		if offset.length() > radius: continue
		var raw = center + offset
		var point = NavigationServer3D.region_get_closest_point(ctx.navigation_region.get_rid(), raw)
		point.y = ctx.actor.global_position.y
		if Contract.horizontal(raw, point) > float(settings.get("search_nav_snap_tolerance", 0.65)) or Contract.horizontal(center, point) > radius: continue
		if not Geometry.can_occupy(ctx.actor, point, ctx.actor.get_body_height(), ctx.coordination_motion_state().radius, true): continue
		var key = "area:%s:%s" % [roundi(point.x * 10.0), roundi(point.z * 10.0)]
		cells[key] = {"position": point, "look_position": point, "site_key": key, "sync_key": "area:%s" % revision, "observed": false}
	if _cursor >= total and cells.values().all(func(cell): return cell.observed):
		if _next_round == 0.0: _next_round = now + maxf(0.5, float(settings.get("search_pause_seconds", 0.5)))
		if now >= _next_round:
			round += 1
			_rebuild()

func _check_hint(contexts: Array, profiles: Dictionary, now: float) -> void:
	_next_hint = now + maxf(0.25, float(settings.get("search_hint_interval_seconds", 1.5)))
	var lost = _lost_hint
	_lost_hint = false
	# One draw per squad opportunity, using an eligible trained member's frozen
	# settings. Adding members does not multiply the probability or refresh age.
	for ctx in contexts:
		var profile: Dictionary = profiles.get(ctx.actor.get_instance_id(), {})
		var action = Contract.executor(profile, &"search")
		if action.is_empty(): continue
		var p: Dictionary = profile.actions[action].parameters
		if not p.get("tracking_cheat_enabled", true): continue
		var chance: float = p.get("lost_target_hint_chance", 0.5) if lost else p.get("search_hint_chance", 0.35)
		if chance <= 0.0: continue
		if not is_instance_valid(ctx.player) or not ctx.is_arena_active(): return
		var position: Vector3 = ctx.player.global_position
		if Contract.horizontal(ctx.actor.global_position, position) > float(p.get("tracking_cheat_max_distance", 12.0)): continue
		if not lost:
			chance = _hints.chance(chance, int(p.get("search_hint_decay_mode", 4)), now - started_at,
				Contract.horizontal(origin, position), float(p.get("search_hint_min_multiplier", 0.05)),
				float(p.get("search_hint_linear_decay_seconds", 8.0)), float(p.get("search_hint_half_life_seconds", 4.0)),
				float(p.get("search_hint_distance_falloff", 6.0)), _custom_decay)
		hint_checks += 1
		if randf() > chance: return
		var error = float(p.get("tracking_hint_error_radius", 1.25))
		for attempt in int(p.get("tracking_hint_position_attempts", 4)):
			var raw = _hints.sample(position, error)
			var point = NavigationServer3D.region_get_closest_point(ctx.navigation_region.get_rid(), raw)
			point.y = ctx.actor.global_position.y
			if Contract.horizontal(point, raw) > maxf(1.5, error + 0.75): continue
			if not Geometry.can_occupy(ctx.actor, point, ctx.actor.get_body_height(), ctx.coordination_motion_state().radius, true): continue
			if hint.is_empty() or Contract.horizontal(point, center) > maxf(1.5, error * 2.0):
				hint = {"position": point, "captured_at": now, "uncertainty": error, "source": &"hint"}
				center = point
				_rebuild()
			return
		return

func _custom_decay(_elapsed: float, _distance: float) -> float:
	return 1.0

func sites(position: Vector3, now: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in cells.values():
		if cell.observed or float(_excluded.get(cell.site_key, 0.0)) > now: continue
		result.append(cell.duplicate(true))
	result.sort_custom(func(a, b): return Contract.horizontal(position, a.position) + Contract.horizontal(center, a.position) * 0.25 < Contract.horizontal(position, b.position) + Contract.horizontal(center, b.position) * 0.25)
	return result.slice(0, 24)

func mark(ctx, now: float) -> void:
	var radius = float(settings.get("search_coverage_radius", 2.0))
	for cell in cells.values():
		if not cell.observed and Contract.horizontal(ctx.actor.global_position, cell.position) <= radius and ctx.perception.can_observe_position(cell.position):
			cell.observed = true
			cell.observed_at = now

func reject(key: String, now: float) -> void:
	_excluded[key] = now + 4.0

func snapshot() -> Dictionary:
	return {"center": center, "last_seen": origin, "radius": settings.get("search_radius", 5.0),
		"cells": cells.size(), "observed": cells.values().filter(func(cell): return cell.observed).size(),
		"round": round, "revision": revision, "hint": hint.duplicate(true), "hint_checks": hint_checks}
