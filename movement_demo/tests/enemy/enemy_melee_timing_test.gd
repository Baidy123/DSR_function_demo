extends SceneTree

## Explicit legal execution contracts. Autonomous choice remains covered by the
## unchanged enemy_melee_approach_test, not by selecting a melee owner here.
const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
const FIRE := {"owner": &"engage", "mode": &"visible"}
var checks := 0
var failures := 0
var scene
var actor
var player
var ai
var context
var hits := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _parallel_waits(1, 0.9, 1.0, "burst pause")
	await _parallel_waits(3, 1.0, 1.0, "mechanical cooldown")
	await _parallel_waits(3, 1.0, 2.0, "AI interval")
	await _fresh_reaction_and_steady()
	await _cancelled_reload(false)
	await _cancelled_reload(true)
	await _covering_quota_transition()
	await _dispose()
	print("MELEE TIMING CONTRACT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _dispose() -> void:
	if not is_instance_valid(scene): return
	scene.queue_free()
	await scene.tree_exited
	await process_frame
	scene = null

func _fixture() -> void:
	await _dispose()
	scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	actor = arena.get_node("Enemy")
	for child in arena.get_children():
		if child != actor and child.has_node("AI"): child.free()
	root.add_child(scene)
	current_scene = scene
	for region in get_nodes_in_group("cover_region"):
		region.collision_layer = 0
		region.remove_from_group("cover_region")
	Fixture.configure_timing(actor)
	ai = actor.get_node("AI")
	ai.training.profile.selected_tactics.assign([&"cooperate"])
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	ai.training.profile.set_setting(&"tactics", &"fire_reaction_seconds", 0.2)
	ai.refresh_configuration(true)
	ai.set_physics_process(false)
	actor.set_physics_process(false)
	actor.aim_turn_speed_degrees = 3600.0
	actor.debug_shooting = false
	actor.weapon.melee_windup_seconds = 0.15
	actor.weapon.melee_recovery_seconds = 0.25
	actor.weapon.melee_knockback_distance = 0.0
	actor.weapon.melee_slow_seconds = 0.0
	actor.global_position = Vector3(24, 0, -2)
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = Vector3(24, 0, -3.25)
	player.velocity = Vector3.ZERO
	actor.look_at(player.global_position)
	context = ai.context
	context.utility_current = {"id": &"engage", "plan": &"melee"}
	hits = 0
	actor.melee_struck.connect(func(target, _settings, _direction):
		if target == player: hits += 1)
	for frame in 6: await physics_frame
	context.update_evidence(0.0, context.perception.can_see_player())
	_check(context.sees_player and context.player == player and context.melee.can_request(true), "Fixture has actual sight, the current player, and legal melee reach")

func _step(intent: Dictionary = {}, melee: bool = false) -> void:
	await physics_frame
	context.update_evidence(STEP, context.perception.can_see_player())
	if melee: context.melee.update(STEP, context.sees_player, {"owner": &"engage"})
	context.fire.update(STEP, context.sees_player, false, intent)
	actor._physics_process(STEP)

func _until_shot(intent: Dictionary = FIRE, maximum: int = 240) -> float:
	var before: int = actor.shot_count
	for frame in maximum:
		await _step(intent)
		if actor.shot_count > before: return (frame + 1) * STEP
	return INF

func _melee_cycle() -> float:
	var shots: int = actor.shot_count
	context.melee.update(0.0, context.sees_player, {"owner": &"engage"})
	_check(actor.melee_active and context.melee.phase == context.melee.Phase.WINDUP, "Legal melee intent actually starts the body windup")
	var frames := 0
	while actor.melee_active and frames < 90:
		await _step({}, true)
		frames += 1
	_check(not actor.melee_active and hits == 1 and actor.shot_count == shots, "Actual melee hits once, completes recovery, and never fires concurrently")
	return frames * STEP

func _parallel_waits(quota: int, pause: float, multiplier: float, label: String) -> void:
	await _fixture()
	ai.training.profile.set_setting(&"tactics", &"burst_shot_count", quota)
	ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", pause)
	ai.training.profile.set_setting(&"tactics", &"shot_interval_multiplier", multiplier)
	_check(is_finite(await _until_shot()) and actor.shot_count == 1, label + ": the initial shot creates real timer state")
	var fire = context.fire
	var old_pause: float = fire.fire_pause_remaining
	var old_interval: float = fire.fire_interval_remaining
	var old_mechanical: float = actor.shot_cooldown
	var forecast: float = ai.actions[&"engage"]._melee_facts().ready
	var occupied: float = await _melee_cycle()
	_check(is_equal_approx(fire.fire_pause_remaining, maxf(0.0, old_pause - occupied)) and is_equal_approx(fire.fire_interval_remaining, maxf(0.0, old_interval - occupied)) and is_equal_approx(actor.shot_cooldown, maxf(0.0, old_mechanical - occupied)), label + ": existing waits decay during actual melee instead of starting afterward")
	_check(is_zero_approx(fire.fire_reaction_elapsed) and not actor.has_aim, label + ": no-fire melee resets reaction and clears aim")
	var resumed: float = await _until_shot()
	var measured: float = occupied + resumed
	_check(is_finite(resumed) and absf(forecast - measured) <= STEP * 2.1, label + ": predicted unavailable time matches first real resumed shot")
	print("MELEE TIMER ", label, " forecast=", forecast, " actual=", measured, " occupied=", occupied)

func _fresh_reaction_and_steady() -> void:
	await _fixture()
	actor.weapon.shot_interval = 0.05
	_check(is_finite(await _until_shot()), "Reaction contract starts after an actual reacted shot")
	var forecast: float = ai.actions[&"engage"]._melee_facts().ready
	var occupied: float = await _melee_cycle()
	var resumed: float = await _until_shot()
	_check(resumed >= context.fire.fire_reaction_seconds - STEP * 0.1 and absf(forecast - occupied - resumed) <= STEP * 2.1, "Previously completed reaction is paid again after the no-fire melee stage")

	await _fixture()
	ai.training.profile.set_setting(&"tactics", &"ranged_min_distance", 0.1)
	actor.weapon.initial_accuracy = 0.5
	actor.weapon.accuracy_recovery_delay = 3.0
	actor.equip_weapon(actor.weapon)
	actor.apply_aim_penalty(0.01)
	for frame in 28: await _step(FIRE)
	var fire = context.fire
	_check(actor.shot_count == 0 and fire.fire_decision.wait_seconds > 0.2, "Low-accuracy real fire evaluation has accumulated steady wait without firing")
	var before := _timing_snapshot()
	var reset_wait: float = fire.estimated_reset_steady_wait()
	forecast = ai.actions[&"engage"]._melee_facts().ready
	_check(before == _timing_snapshot() and reset_wait > 0.6, "Reset steady prediction is read-only and ignores previously accumulated wait")
	occupied = await _melee_cycle()
	_check(is_zero_approx(fire.fire_decision.wait_seconds) and is_zero_approx(fire.fire_decision.last_recovery_rate), "Real no-fire melee clears both steady wait and measured recovery")
	resumed = await _until_shot()
	_check(is_finite(resumed) and resumed > context.fire.fire_reaction_seconds + 0.5 and absf(forecast - occupied - resumed) <= STEP * 2.1, "Actual post-melee shot rebuilds reaction and steady pressure from zero")

	# High old aim accuracy is also lost by clear_aim; this helper must not grant it
	# to a future no-fire stage. Only a read-only forecast is asserted here.
	actor.weapon_stability = 1.0
	before = _timing_snapshot()
	_check(fire.estimated_reset_steady_wait() > 0.6 and before == _timing_snapshot(), "Old high accuracy cannot erase the predicted reset steady wait")

func _cancelled_reload(empty: bool) -> void:
	await _fixture()
	var label := "empty magazine" if empty else "partial magazine"
	actor.weapon.reload_seconds = 1.0
	actor.weapon.accuracy_recovery_delay = 0.0
	actor.weapon.stabilize_seconds = 0.1
	actor.ammo.magazine_rounds = 0 if empty else 3
	_check(actor.request_reload(), label + ": a real reload begins")
	for frame in 24: await _step()
	_check(actor.ammo.is_reloading and is_equal_approx(actor.ammo.reload_progress, 0.4), label + ": real partial reload progress exists before melee")
	var prediction: float = ai.actions[&"engage"]._melee_facts().ready
	# Reload accuracy is genuinely zero here, so ready also includes a conservative
	# steady estimate. Isolate reload cost from that independent accuracy cost.
	actor.weapon.reload_seconds = 2.0
	var longer_reload_prediction: float = ai.actions[&"engage"]._melee_facts().ready
	actor.weapon.reload_seconds = 1.0
	_check(is_equal_approx(longer_reload_prediction - prediction, 1.0 if empty else 0.0), label + ": only an empty magazine prices the full future reload duration")
	var occupied: float = await _melee_cycle()
	_check(not actor.ammo.is_reloading and is_zero_approx(actor.ammo.reload_progress) and is_zero_approx(actor.ammo.reload_checkpoint), label + ": melee cancels rather than suspends old reload progress")
	if not empty:
		var resumed: float = await _until_shot()
		_check(is_finite(resumed) and resumed < actor.weapon.reload_seconds and actor.ammo.magazine_rounds == 2, "Retained rounds actually fire without finishing or restarting the cancelled reload")
	else:
		for frame in 18: await _step(FIRE)
		_check(actor.shot_count == 0 and actor.ammo.magazine_rounds == 0, "An empty magazine cannot fire after melee merely because old reload progress existed")
		# The real reload action submits no fire intent while it reloads.
		_check(actor.request_reload() and is_zero_approx(actor.ammo.reload_progress), "Empty-magazine recovery starts a new reload from zero")
		for frame in 59: await _step()
		_check(actor.ammo.is_reloading and actor.ammo.magazine_rounds == 0 and actor.shot_count == 0, "A restarted empty reload remains unavailable just before its full duration")
		await _step()
		_check(not actor.ammo.is_reloading and actor.ammo.magazine_rounds == actor.weapon.magazine_capacity and is_zero_approx(context.fire.fire_reaction_elapsed), "Full fresh reload refills the magazine without pre-paying fire reaction")
		var resumed: float = await _until_shot()
		_check(is_finite(resumed) and resumed >= context.fire.fire_reaction_seconds - STEP * 0.1, "Real fire resumes only after the fresh reload and renewed reaction")
		_check(prediction >= occupied + actor.weapon.reload_seconds + context.fire.fire_reaction_seconds - STEP, "Empty-magazine prediction includes a full future reload and fresh reaction")

func _covering_quota_transition() -> void:
	await _fixture()
	ai.training.profile.set_setting(&"tactics", &"support_burst_shot_count", 8)
	ai.training.profile.set_setting(&"tactics", &"burst_shot_count", 3)
	ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", 1.0)
	actor.weapon.shot_interval = 0.1
	var partner = load("res://scenes/enemy/enemy.tscn").instantiate()
	scene.get_node("Arena").add_child(partner)
	Fixture.configure_timing(partner)
	var partner_ai = partner.get_node("AI")
	partner_ai.training.profile.selected_tactics.assign([&"cooperate"])
	partner_ai.refresh_configuration(true)
	partner_ai.set_physics_process(false)
	partner.set_physics_process(false)
	partner.global_position = actor.global_position + Vector3(2.0, 0, 0)
	partner.look_at(player.global_position)
	partner.weapon.reload_seconds = 5.0
	partner.ammo.magazine_rounds = 1
	for frame in 6: await physics_frame
	var other = partner_ai.context
	other.update_evidence(0.0, other.perception.can_see_player())
	_check(partner.request_reload(), "Covering transition has an actual teammate reload request")
	var support := {"owner": &"engage", "mode": &"visible", "support_intent": true}
	for frame in 120:
		other.update_evidence(STEP, other.perception.can_see_player())
		other.fire.update(STEP, other.sees_player, false, {})
		other.cooperation_publish_execution({})
		await _step(support)
		if actor.shot_count >= 4: break
	var fire = context.fire
	_check(actor.shot_count == 4 and fire.fire_burst_shots == 4 and is_zero_approx(fire.fire_pause_remaining) and fire.burst_limit(true) > fire.burst_limit(false), "Real supporting fire exceeds the ordinary quota without inventing a prior pause")
	var before := _timing_snapshot()
	var predicted: float = fire.pause_after_no_fire_seconds()
	var facts: Dictionary = ai.actions[&"engage"]._melee_facts()
	_check(is_equal_approx(predicted, 1.0) and facts.ready >= predicted and before == _timing_snapshot(), "No-fire prediction includes the impending quota downgrade pause without mutating it")
	context.melee.update(0.0, true, {"owner": &"engage"})
	fire.update(0.0, true, false, {})
	_check(actor.melee_active and fire.fire_burst_shots == 0 and is_equal_approx(fire.fire_pause_remaining, predicted), "Actual switch to no-fire melee finishes the long burst and starts its ordinary pause")

	await _fixture()
	_check(is_finite(await _until_shot()) and context.fire.fire_burst_shots == 1, "Below-quota counter comes from one actual shot")
	_check(is_zero_approx(context.fire.pause_after_no_fire_seconds()), "Below-quota forecast does not invent a new pause")
	context.melee.update(0.0, true, {"owner": &"engage"})
	context.fire.update(0.0, true, false, {})
	_check(actor.melee_active and context.fire.fire_burst_shots == 1 and is_zero_approx(context.fire.fire_pause_remaining), "Actual below-quota melee preserves the count without starting a pause")

func _timing_snapshot() -> Array:
	var fire = context.fire
	return [fire.fire_reaction_elapsed, fire.fire_pause_remaining, fire.fire_interval_remaining, fire.fire_burst_shots,
		fire.fire_decision.wait_seconds, fire.fire_decision.last_recovery_rate, fire.fire_decision.selected_action,
		actor.weapon_stability, actor.shot_cooldown, actor.shot_count, actor.ammo.magazine_rounds,
		actor.ammo.is_reloading, actor.ammo.reload_progress, actor.has_aim, actor.aim_direction]

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
