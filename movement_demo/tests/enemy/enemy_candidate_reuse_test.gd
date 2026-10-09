extends SceneTree

var checks := 0
var failures := 0

class Ammo extends RefCounted:
	var magazine_rounds := 4
	var is_reloading := false

class Weapon extends RefCounted:
	var fire_range := 20.0
	var reload_seconds := 2.0

class Body extends Node3D:
	var ammo := Ammo.new()
	var weapon := Weapon.new()
	var firearms := true
	func can_use_firearms() -> bool: return firearms
	func get_shot_origin() -> Vector3: return global_position + Vector3.UP

class Melee extends RefCounted:
	var allowed := true
	func can_request(_visible: bool) -> bool: return allowed
	func is_active_for(_owner: StringName) -> bool: return false
	func weapon_settings() -> Dictionary: return {"windup": 0.2, "recovery": 0.3, "distance": 1.5}

class Fire extends RefCounted:
	func has_clear_firing_lane(_origin: Vector3, _direction: Vector3, _distance: float) -> bool: return true

class Spatial extends RefCounted:
	var points: Array = []
	func destinations(_owner) -> Array: return points.duplicate(true)
	func _ammo_wait(_context) -> float: return 0.15
	func _reload_seconds(_context) -> float: return 0.0
	func assess_route(_context, path: PackedVector3Array, threat: Vector3, _multiplier: float, _reload: float, _fire: bool, start: float = 0.0) -> Dictionary:
		return {"seconds": start + path[-1].length() * 0.25, "exposure": 0.2 + threat.length() * 0.05, "fire_seconds": 0.1}

class Context extends RefCounted:
	var actor
	var melee := Melee.new()
	var fire := Fire.new()
	var spatial := Spatial.new()
	var last_known_position := Vector3(2, 0, 0)
	var utility_horizon_seconds := 4.0
	var observed_velocity := Vector3(-1, 0, 0)
	func known_target_point(point: Vector3) -> Vector3: return point + Vector3.UP
	func _reload_exposure(point: Vector3, threat: Vector3) -> float: return 0.3 + point.distance_to(threat) * 0.02

class CountingTactics extends "res://scripts/enemy/actions/enemy_tactics.gd":
	var pushes := 0
	var assessments := 0
	var reject := Vector3.INF
	func is_enabled() -> bool: return true
	func assess_engagement_point(point: Vector3, _threat: Vector3) -> Dictionary:
		assessments += 1
		return {} if point == reject else {"position": point, "path": PackedVector3Array([actor.global_position, point])}
	func _free_melee_push_distance(_threat: Vector3, _direction: Vector3, distance: float) -> float:
		pushes += 1
		return distance * 0.7

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	var body := Body.new()
	root.add_child(body)
	var context := Context.new()
	context.actor = body
	var action := CountingTactics.new()
	action.setup(context)
	action.action_id = &"engage"
	var first := {"position": Vector3(1, 0, 0), "path": PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)])}
	var second := {"position": Vector3(1, 0, 0.0001), "path": PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0.0001)])}
	context.spatial.points = [first, second]
	action._running = true
	action.plan = {"plan": &"", "destination": first}
	var reference: Array[Dictionary] = [action._melee_option(), action._melee_option(first), action._melee_option(second), action._melee_option(first)]
	_check(action.pushes == 4, "independent melee options each perform their own push geometry query")
	action.pushes = 0
	var candidates: Array[Dictionary] = action.collect_candidates(true)
	_check(candidates.size() == 8 and candidates.filter(func(candidate): return candidate.plan == &"melee").size() == 4, "reuse retains every ranged and melee candidate including the repeated running destination")
	_check(action.pushes == 1, "one synchronous collection evaluates identical push geometry once")
	_check(action.assessments == 2, "exact duplicate positions reuse validation while a 0.1 mm different point stays independent")
	var melee: Array = candidates.filter(func(candidate): return candidate.plan == &"melee")
	_check(melee == reference, "batched melee destinations and outcomes equal independent fresh calculations")
	candidates[2].destination.position = Vector3(7, 0, 0)
	_check(candidates[6].destination.position == first.position, "duplicate candidates retain independent destination dictionaries")
	context.last_known_position = Vector3(2, 0, 2)
	context.observed_velocity = Vector3(-2, 0, 0)
	var expected: Dictionary = action._melee_option(second)
	action.pushes = 0
	action.assessments = 0
	var changed: Array[Dictionary] = action.collect_candidates(true)
	_check(action.pushes == 1 and action.assessments == 2 and changed[5] == expected and changed[5].outcome != melee[2].outcome, "next collection recomputes changed evidence and motion without carrying prior facts")
	action.reject = first.position
	action.assessments = 0
	var blocked: Array[Dictionary] = action.collect_candidates(true)
	_check(blocked.size() == 4 and action.assessments == 2, "a newly invalid point removes both of its duplicate options after fresh validation")
	context.melee.allowed = false
	action.pushes = 0
	var ranged: Array[Dictionary] = action.collect_candidates(true)
	_check(action.pushes == 0 and ranged.size() == 2, "unavailable melee performs no push query and preserves ranged options")
	context.melee.allowed = true
	body.firearms = false
	action.pushes = 0
	var unarmed: Array[Dictionary] = action.collect_candidates(true)
	_check(unarmed.size() == 1 and unarmed[0].plan == &"melee" and action.pushes == 1, "melee-only capability retains its independently valid stationary option")
	body.free()
	print("CANDIDATE REUSE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
