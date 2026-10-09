extends SceneTree

const Spatial = preload("res://scripts/enemy/services/enemy_spatial_evaluator.gd")
const Action = preload("res://scripts/enemy/actions/enemy_action.gd")
var checks := 0
var failures := 0

class TestAmmo extends RefCounted:
	var is_reloading := false

class TestActor extends CharacterBody3D:
	var ammo := TestAmmo.new()
	var weapon := Resource.new()
	func get_posture_body_height(crouched: bool) -> float: return 1.0 if crouched else 1.75

class TestRoutes extends RefCounted:
	var resets := 0
	func has_pending() -> bool: return false
	func reset() -> void: resets += 1

class TestContext extends Node:
	var actor
	var agent
	var navigation_region
	var routes := TestRoutes.new()
	var sees_player := true
	var begins := 0
	var ends := 0
	func _known_reload_threat() -> Vector3: return Vector3(5, 0, 0)
	func begin_geometry_evaluation() -> void: begins += 1
	func end_geometry_evaluation() -> void: ends += 1

class TestAction extends "res://scripts/enemy/actions/enemy_action.gd":
	var revision := 0
	var builds := 0
	var evaluated := 0
	var points: Array = []
	var enabled := true
	func is_enabled() -> bool: return enabled
	func evaluation_revision() -> int: return revision
	func evaluation_priority_count() -> int: return 2
	func evaluation_points() -> Array:
		builds += 1
		return points.duplicate()
	func evaluate_point(point: Variant) -> Dictionary:
		evaluated += 1
		return {"destination": {"position": point}, "cost": absf(point.x)}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	var actor := TestActor.new()
	actor.collision_layer = 0
	actor.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = CapsuleShape3D.new()
	actor.add_child(collision)
	var agent := NavigationAgent3D.new()
	actor.add_child(agent)
	root.add_child(actor)
	var context := TestContext.new()
	root.add_child(context)
	context.actor = actor
	context.agent = agent
	context.navigation_region = actor
	var spatial := Spatial.new()
	spatial.context = context
	var dormant := TestAction.new()
	dormant.action_id = &"dormant"
	var unchanged := TestAction.new()
	unchanged.action_id = &"unchanged"
	unchanged.points = [Vector3(2, 0, 0), Vector3(3, 0, 0)]
	spatial.register(dormant)
	spatial.register(unchanged)
	# A newly attached NavigationAgent changes the map iteration after the first
	# physics signal. Let that genuine global invalidation settle before testing
	# a purely local revision; otherwise rebuilding both queues is correct.
	var iteration := -1
	for warmup in 6:
		await physics_frame
		var current_iteration: int = NavigationServer3D.map_get_iteration_id(agent.get_navigation_map())
		if warmup >= 2 and current_iteration == iteration: break
		iteration = current_iteration
	spatial.advance_evaluation()
	_check(Action.new().evaluation_revision() == 0, "existing actions have a stable default revision")
	_check(dormant.builds == 1 and unchanged.builds == 1 and spatial.assessments(dormant).is_empty(), "the initial empty action queue is recorded without inventing candidates")
	var old_job: Dictionary = spatial.jobs.filter(func(job): return job.channel == &"unchanged")[0]
	old_job.cache.append({"destination": {"position": Vector3(99, 0, 0)}, "cost": -100.0,
		"assessment": {"marker": true}, "time": Time.get_ticks_msec()})
	var old_passes: int = old_job.completed_passes
	dormant.points = [Vector3(1, 0, 0)]
	dormant.revision += 1
	await physics_frame
	spatial.advance_evaluation()
	_check(dormant.builds == 2 and not spatial.assessments(dormant).is_empty(), "new non-geometric information wakes an empty stationary queue")
	_check(unchanged.builds == 1 and old_job.completed_passes >= old_passes and old_job.cache.any(func(entry): return entry.assessment.get("marker", false)), "local revision preserves unrelated queues, progress and cache")
	var before: int = spatial.total_evaluated_count
	spatial.advance_evaluation()
	_check(spatial.total_evaluated_count == before and dormant.builds == 2, "same-frame reads still cannot repeat scanning or rebuilding")
	await physics_frame
	spatial.advance_evaluation()
	_check(dormant.builds == 2 and unchanged.builds == 1, "stable revisions continue the old rotating scan without rebuilding")
	dormant.points.clear()
	dormant.revision += 1
	await physics_frame
	spatial.advance_evaluation()
	_check(spatial.assessments(dormant).is_empty() and unchanged.builds == 1, "local withdrawal clears only that action's stale candidates")
	dormant.points = [Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)]
	dormant.revision += 1
	await physics_frame
	spatial.advance_evaluation()
	var local_job: Dictionary = spatial.jobs.filter(func(job): return job.channel == &"dormant")[0]
	# Simulate a revision while an initial priority slice is partially consumed.
	local_job.priority = 1
	local_job.priority_cursor = 2
	dormant.points = [Vector3(4, 0, 0)]
	dormant.revision += 1
	await physics_frame
	spatial.advance_evaluation()
	_check(local_job.priority == 0 and local_job.points.size() == 1 and not spatial.assessments(dormant).is_empty(), "a shrinking queue cannot retain an out-of-range priority index")
	_check(spatial.last_evaluated_count <= 24 and spatial.EVALUATION_POINTS_PER_FRAME == 24 and spatial.EVALUATION_BUDGET_USEC == 2000 and spatial.CACHED_DESTINATIONS == 6, "local invalidation retains the original point, time and cache budgets")
	var builds_before: int = unchanged.builds
	actor.position.x += 0.6
	await physics_frame
	spatial.advance_evaluation()
	_check(unchanged.builds == builds_before + 1, "the original actor-movement invalidation still rebuilds every affected queue")
	_check(context.begins == context.ends, "every scan keeps its geometry evaluation batch balanced")
	spatial.reset_evaluation()
	_check(spatial.cached_candidate_count() == 0 and spatial.total_evaluated_count == 0, "reset still clears all previous evaluation progress")
	actor.free()
	context.free()
	print("SPATIAL REVISION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
