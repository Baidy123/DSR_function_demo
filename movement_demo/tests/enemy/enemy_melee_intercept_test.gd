extends SceneTree

## Real mixed-squad decisions. Only equipment/training and player movement are
## fixture inputs; never inject observations, candidates, commands or selection.
const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const Prediction = preload("res://scripts/enemy/services/enemy_melee_interception.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	seed(20261024)
	_run.call_deferred()

func _run() -> void:
	var level := 2
	var trained := not OS.get_cmdline_user_args().has("--untrained")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): level = int(arg.trim_prefix("--level="))
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	var squad = arena.get_node("Squad")
	squad.profile = squad.profile.duplicate(true)
	squad.profile.level = level
	var actors := Fixture.members(arena)
	var hits := {}
	for index in actors.size():
		var actor = actors[index]
		var melee := index > 0
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/%s.tres" % ("melee" if melee else "ranged"))
		actor.weapon = load("res://resources/weapons/enemy_test_%s.tres" % ("melee" if melee else "pistol")).duplicate(true)
		actor.weapon.fire_mode = 2 if melee else 0
		var training = load("res://resources/enemy/training/arena.tres").duplicate(true)
		training.selected_tactics.clear()
		if melee and trained: training.selected_tactics.append(&"melee_intercept")
		training.search.tracking_cheat_enabled = false
		actor.get_node("Training").profile = training
		hits[actor.name] = 0
		actor.melee_struck.connect(func(target, _weapon, _direction):
			if target != null: hits[actor.name] += 1)
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3(1, 0, -2))
	var starts := [Vector3(-1.5, 0, -3.5), Vector3(-0.5, 0, -3), Vector3(4.5, 0, -3)]
	for index in actors.size():
		actors[index].global_position = arena.to_global(starts[index])
		actors[index].look_at(player.global_position)
	var active := 0
	var max_lead := -INF
	var running := false
	var simultaneous_fire := false
	var previous_shots := 0
	var clearance := INF
	var owners_valid := true
	var finite_plans := true
	var last_predictions := {}
	var old_forward_reused := false
	var late_intercepts := 0
	var costs: Array[int] = []
	for frame in 420:
		if frame < 220: player.global_position.z += 2.0 / 60.0
		elif frame >= 260 and frame < 370: player.global_position.z -= 2.0 / 60.0
		await physics_frame
		if frame == 30:
			check(actors.all(func(actor): return actor.is_on_floor() and actor.get_node("AI").context.has_visual_memory), "Fixture acquires real sight on the map")
			check(actors.slice(1).all(func(actor): return actor.get_node("AI").actions.has(&"melee_intercept") == trained), "Training alone controls interception assembly")
			check(actors.all(func(actor): return not actor.get_node("AI").actions.has(&"melee_rush")), "Interception does not grant short rush")
		var cost: int = arena.cooperation.last_advance_usec
		var intercepting := false
		for index in actors.size():
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var ctx = ai.context
			for value in ai.frame_costs.values(): cost += int(value)
			owners_valid = owners_valid and ctx.commanded() == (level > 0)
			var task: Dictionary = ctx.coordination_assignment() if level > 0 else ai.utility_current
			if task.get("action", task.get("id")) == &"melee_intercept":
				active += 1
				intercepting = true
				if frame < 220: max_lead = maxf(max_lead, actor.global_position.z - player.global_position.z)
				running = running or actor.get_local_movement_velocity().length() > actor.move_speed * 1.5
				var prediction: Dictionary = task.interception
				var old: Dictionary = last_predictions.get(actor.name, {})
				if old.get("captured_at", -INF) == prediction.captured_at:
					finite_plans = finite_plans and old.until == prediction.until and old.position == prediction.position
				last_predictions[actor.name] = prediction.duplicate(true)
				if frame >= 300 and frame < 370: old_forward_reused = old_forward_reused or prediction.velocity.z > 0.0
				if frame >= 415: late_intercepts += 1
			for other in actors.slice(index + 1): clearance = minf(clearance, actor.global_position.distance_to(other.global_position))
		if actors[0].shot_count > previous_shots: simultaneous_fire = simultaneous_fire or intercepting
		previous_shots = actors[0].shot_count
		if frame >= 30: costs.append(cost)
	check(owners_valid, "Level zero uses personal Utility; levels one/two use commands")
	check((active > 0) == trained, "Only trained members independently choose interception")
	if trained:
		check(running and max_lead > 0.0, "Actual running body reaches ahead of the moving player")
		check(simultaneous_fire, "Ranged member actually fires while melee intercepts")
		check(finite_plans, "Continuing predictions retain their original post and deadline")
	check(not old_forward_reused and late_intercepts == 0, "Reversal and stopping release obsolete interception")
	check(actors.slice(1).all(func(actor): return hits[actor.name] > 0), "Every melee member actually hits after moving")
	check(clearance >= 0.64, "Interception preserves real ally body clearance")
	check(actors[0].shot_count > 0, "Mixed ranged member retains effective fire")
	costs.sort()
	# Same strict diagnostic as the existing intel-only runtime test. Behavior
	# and budget results are separate; a known baseline failure is not a pass.
	if OS.get_cmdline_user_args().has("--budget"):
		check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "AI cumulative P99 <16ms / maximum <50ms")
	print("INTERCEPT METRICS level=", level, " trained=", trained, " active=", active, " lead=", max_lead, " hits=", hits, " shots=", actors[0].shot_count, " clearance=", clearance, " p99_usec=", costs[int(costs.size() * 0.99)], " peak_usec=", costs[-1])
	_evidence_contract()
	scene.queue_free()
	await physics_frame
	print("MELEE INTERCEPT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

## A deliberately observation-only context: the validation boundary has no
## player body to query. This is a unit contract, separate from runtime above.
class EvidenceContext:
	extends RefCounted
	var evidence_elapsed_seconds := 0.0
	var memory_generation := 0
	var evidence := {"source": &"visual", "position": Vector3.ZERO, "velocity": Vector3(0, 0, 2), "captured_at": 0.0}
	func cooperation_target_evidence() -> Dictionary: return evidence
	func cooperation_target_id() -> int: return 1

func _evidence_contract() -> void:
	var ctx := EvidenceContext.new()
	var prediction := {"generation": 0, "target_id": 1, "until": 2.0, "position": Vector3(1, 0, 3), "velocity": Vector3(0, 0, 2), "forecast": PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 4)])}
	var original := ctx.evidence.duplicate(true)
	check(Prediction.valid(ctx, prediction, 0.6), "Observation-only validation needs no hidden body")
	ctx.evidence_elapsed_seconds = 0.5
	check(Prediction.valid(ctx, prediction, 0.6) and ctx.evidence == original, "Brief loss preserves finite hypothesis without renewing evidence")
	ctx.evidence_elapsed_seconds = 0.61
	check(not Prediction.valid(ctx, prediction, 0.6), "Stale observation expires")
	ctx.evidence_elapsed_seconds = 0.0
	ctx.evidence.source = &"noise"
	check(not Prediction.valid(ctx, prediction, 0.6), "Noise cannot invent visual movement")
	ctx.evidence.source = &"shared_visual"
	check(Prediction.valid(ctx, prediction, 0.6), "Legal shared sight can support interception")
	ctx.evidence.velocity = Vector3(0, 0, -2)
	check(not Prediction.valid(ctx, prediction, 0.6), "Observed reversal invalidates old prediction")
	ctx.evidence.velocity = Vector3.ZERO
	check(not Prediction.valid(ctx, prediction, 0.6), "Observed stop invalidates old prediction")
	ctx.evidence = original
	ctx.memory_generation += 1
	check(not Prediction.valid(ctx, prediction, 0.6), "Reset invalidates a prediction from the previous battle")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)
