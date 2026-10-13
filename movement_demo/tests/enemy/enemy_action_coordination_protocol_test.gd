extends "res://tests/enemy/enemy_geometry_batch_test.gd"

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	var actor = preload("res://tests/enemy/enemy_fire_fixture.gd").primary_enemy(arena)
	for child in arena.get_children():
		if child != actor and child.has_node("AI"): child.free()
	root.add_child(scene)
	current_scene = scene
	root.get_node("DebugSettings").enabled = false
	Fixture.configure_timing(actor)
	var ai = actor.get_node("AI")
	var context = ai.context
	ai.set_physics_process(false)
	actor.set_physics_process(false)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.health.debug_invincible = true
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(24, 0, -3.25)
	actor.look_at(player.global_position)
	var layers := {}
	for body in get_nodes_in_group("cover_region"):
		layers[body] = body.collision_layer
		body.collision_layer = 0
	for frame in 6: await physics_frame
	context.update_evidence(0.0, context.perception.can_see_player())
	check(context.sees_player and context.melee.can_request(true), "Fixture supplies real sight, body permission and weapon melee reach")
	_default_contract(context)
	_reload_contract(ai, actor)
	_melee_contract(ai, actor, player)
	for body in layers: body.collision_layer = layers[body]
	player.global_position = Vector3(20, 0, -2)
	actor.look_at(player.global_position)
	for frame in 3: await physics_frame
	context.is_alerted = true
	context.has_visual_memory = true
	context.last_known_position = player.global_position
	context.last_seen_position = player.global_position
	context.noise_search_origin = Vector3.INF
	_cover_contract(ai, actor, player)
	await _melee_owner_contract(ai, actor, player)
	print("ACTION COORDINATION PROTOCOL: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await scene.tree_exited
	quit(1 if failures else 0)

func _default_contract(context) -> void:
	var action := preload("res://scripts/enemy/actions/enemy_action.gd").new()
	action.setup(context)
	action.action_id = &"engage"
	var candidate: Dictionary = action.option({}, 0.0, 0.0)
	candidate.urgent = true
	check(action.coordination_offers(true).is_empty() and not action.assignment_escape(candidate, true), "Default actions offer no tactical role and urgent labels grant no escape")
	var idle: Dictionary = action.execution_contract(true)
	check(not idle.valid and idle.segment_boundary and idle.remaining_seconds == 0.0 and idle.progress == 0.0 and not idle.ready_for_phase, "Default idle contract promises neither an occupied segment nor phase readiness")
	action.begin(candidate, true)
	var active: Dictionary = action.execution_contract(true)
	check(active.valid and active.segment_boundary and active.remaining_seconds == 0.0 and not active.ready_for_phase, "A valid ordinary action remains at a segment boundary instead of locking every decision")
	action.cancel()
	check(not action.execution_contract(true).valid, "Cancellation immediately clears default execution validity")

func _reload_contract(ai, actor) -> void:
	var action = ai.actions[&"reload"]
	var candidate: Dictionary = action.option({}, 0.0, 0.0, 0.0, &"here")
	candidate.urgent = true
	actor.ammo.magazine_rounds = 1
	check(not action.assignment_escape(candidate, true), "A partially filled magazine cannot invent emergency reload from an urgent label")
	actor.ammo.magazine_rounds = 0
	check(action.assignment_escape(candidate, true), "A truly empty usable firearm can choose its legal personal reload")
	check(actor.request_reload() and action.assignment_escape(candidate, true), "A real empty-magazine reload remains executable while its body reload is running")
	actor.cancel_reload()
	var unreachable: Dictionary = candidate.duplicate(true)
	unreachable.destination = {"position": Vector3(1000, 0, 1000)}
	check(not action.assignment_escape(unreachable, true), "Empty ammunition cannot authorize an unreachable reload destination")
	actor.ammo.magazine_rounds = actor.weapon.magazine_capacity

func _melee_contract(ai, actor, player) -> void:
	var action = ai.actions[&"engage"]
	var candidate: Dictionary = action.option({}, 0.0, 0.0, 0.0, &"melee")
	check(action.assignment_escape(candidate, true), "Ranged defensive melee uses real current weapon and target reach")
	var ordinary: Dictionary = action.option({}, 0.0, 0.0)
	ordinary.urgent = true
	check(not action.assignment_escape(ordinary, true) and not action.assignment_escape(candidate, false), "Ordinary firing and loss of personal sight cannot masquerade as melee defense")
	var nearby: Vector3 = player.global_position
	player.global_position += Vector3(0, 0, -5)
	check(not action.assignment_escape(candidate, true), "A target outside actual melee range cannot release a tactical assignment")
	player.global_position = nearby
	# The real controller only executes the currently selected action's intent.
	# Establish that authorization through the production begin transaction.
	ai._start_utility_option(candidate, true)
	ai.context.melee.update(0.0, true, {"owner": &"engage"})
	check(actor.melee_active and not action.assignment_escape(candidate, true), "An already occupied melee body cannot request a second defensive strike")
	ai._cancel_utility_execution(&"finished")

func _cover_candidate(context, action) -> Dictionary:
	for destination: Dictionary in context.spatial.cover_points():
		var candidate: Dictionary = action.option(destination, 0.0, 0.0)
		if action.validate(candidate, true): return candidate
	return {}

func _cover_contract(ai, actor, player) -> void:
	var context = ai.context
	var action = ai.actions[&"cover"]
	var candidate := _cover_candidate(context, action)
	check(not candidate.is_empty(), "Cover fixture contains a genuinely reachable and concealing destination")
	if candidate.is_empty(): return
	candidate.urgent = true
	context.recent_damage_pressure = 0.0
	context.nearby_shot_pressure = 0.0
	actor.health = actor.max_health * 0.5
	check(not action.assignment_escape(candidate, true), "Low health and an urgent label alone do not create a current defensive incident")
	actor.receive_hit(1.0, player.global_position)
	candidate = _cover_candidate(context, action)
	check(context.recent_damage_pressure > 0.0 and not candidate.is_empty() and action.assignment_escape(candidate, true), "A real damage event allows the currently validated ordinary hiding choice")
	if candidate.is_empty(): return
	var peek: Dictionary = candidate.duplicate(true)
	peek.mode = &"peek"
	var advance: Dictionary = candidate.duplicate(true)
	advance.plan = &"advance"
	var wait: Dictionary = candidate.duplicate(true)
	wait.destination = {}
	check(not action.assignment_escape(peek, true) and not action.assignment_escape(advance, true) and not action.assignment_escape(wait, true), "Peeking, offensive cover advance and empty waiting destinations are not hiding escapes")
	var unreachable: Dictionary = candidate.duplicate(true)
	unreachable.destination.hide = Vector3(1000, 0, 1000)
	check(not action.assignment_escape(unreachable, true), "Real damage does not override current cover geometry and path validation")
	context.recent_damage_pressure = 0.0
	context.nearby_shot_pressure = 0.15
	check(action.assignment_escape(candidate, true), "An existing real near-shot pressure fact permits the same validated hide")
	var retreat = ai.actions[&"covering_retreat"]
	var retreat_choice: Dictionary = candidate.duplicate(true)
	retreat_choice.id = retreat.action_id
	retreat_choice.mode = &"covering_retreat"
	check(retreat.assignment_escape(retreat_choice, true), "Pressure allows an armed visible covering retreat along its legal cover path")
	actor.ammo.magazine_rounds = 0
	check(not retreat.assignment_escape(retreat_choice, true), "An empty firearm cannot promise a covering-retreat execution")
	actor.ammo.magazine_rounds = actor.weapon.magazine_capacity
	check(not retreat.assignment_escape(retreat_choice, false), "Covering retreat cannot use a visible firing mode without personal sight")
	context.nearby_shot_pressure = 0.0

func _melee_owner_contract(ai, actor, player) -> void:
	actor.reset_target()
	ai.unit_type.profile = preload("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile.selected_tactics.assign([&"melee_rush"])
	actor.equip_weapon(preload("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(24, 0, -3.25)
	actor.look_at(player.global_position)
	for body in get_nodes_in_group("cover_region"): body.collision_layer = 0
	for frame in 6: await physics_frame
	ai.context.update_evidence(0.0, ai.context.perception.can_see_player())
	var melee = ai.actions[&"melee_engage"]
	var candidate: Dictionary = melee.option({}, 0.0, 0.0)
	check(ai.context.melee.can_request(true) and melee.assignment_escape(candidate, true), "The real melee unit's approach action may defend itself when its next tick can actually strike")
	var rush = ai.actions[&"melee_rush"]
	var rush_choice: Dictionary = rush.option({}, 0.0, 0.0, 0.0, &"burst")
	rush_choice.urgent = true
	check(not rush.assignment_escape(rush_choice, true), "Movement-only rush never inherits the approach action's defensive strike exception")
