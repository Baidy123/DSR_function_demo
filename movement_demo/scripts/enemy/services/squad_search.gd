extends RefCounted

## Squad-owned search evidence and bounded area coverage. Hints are explicitly
## uncertain samples, never visual reports or permission to fire.
const Hints = preload("res://scripts/enemy/services/enemy_search_hints.gd")
const Geometry = preload("res://scripts/systems/character_geometry.gd")
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Coverage = preload("res://scripts/enemy/services/squad_map_coverage.gd")
const Routes = preload("res://scripts/enemy/services/squad_search_route.gd")
var coverage = Coverage.new()
var routes = Routes.new()
var _hints = Hints.new()
var center := Vector3.ZERO
var origin := Vector3.ZERO
var settings: Dictionary = {}
var hint: Dictionary = {}
var revision := 0
var hint_checks := 0
var started_at := 0.0
var _next_hint := 0.0
var _lost_hint := true
var _allow_hint := false

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
	_rebuild()

func _rebuild() -> void:
	revision += 1

func advance(contexts: Array, profiles: Dictionary, now: float) -> void:
	if contexts.is_empty(): return
	if _allow_hint and now >= _next_hint:
		_check_hint(contexts, profiles, now)

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

func sites(position: Vector3, now: float, member_id: int = 0) -> Array[Dictionary]:
	return routes.sites(coverage, position, center, float(settings.get("search_radius", 5.0)), now, member_id)

func reject(key: String, now: float) -> void:
	coverage.reject(key.trim_prefix("map:"), &"route_or_observation_blocked", now)

func snapshot(now: float = 0.0, detail: bool = false) -> Dictionary:
	var value: Dictionary = coverage.snapshot(now, detail)
	value.merge({"center": center, "last_seen": origin, "radius": settings.get("search_radius", 5.0),
		"revision": revision, "hint": hint.duplicate(true), "hint_checks": hint_checks}, true)
	return value
