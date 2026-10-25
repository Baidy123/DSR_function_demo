extends SceneTree

var checks := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	for level in 3: await _case(level)
	print("HEADSHOT STAGGER RUNTIME: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func _case(level: int) -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	var squad = arena.get_node("Squad")
	squad.profile = squad.profile.duplicate(true)
	squad.profile.level = level
	var actors: Array = arena.find_children("*", "CharacterBody3D", true, false).filter(func(body): return body.has_node("AI"))
	for actor in actors:
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres")
		actor.get_node("Training").profile = EnemyTrainingProfile.new()
		var training = actor.get_node("Training").profile
		training.tactics.headshot_protection = true
		training.tactics.fire_reaction_seconds = 0.1
		training.tactics.burst_shot_count = 10
		training.tactics.burst_pause_seconds = 0.1
		actor.max_health = 10000
		actor.weapon = WeaponData.new()
		actor.weapon.damage = 1
		actor.weapon.aim_range = 30
		actor.weapon.fire_range = 50
		actor.weapon.shot_noise = null
		actor.weapon.magazine_capacity = 100
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3(1, 0, 2))
	var starts := [Vector3(-2, 0, -3), Vector3(1, 0, -3), Vector3(4, 0, -3)]
	for index in actors.size():
		actors[index].global_position = arena.to_global(starts[index % starts.size()])
		actors[index].look_at(player.global_position)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 40
	arena.add_child(camera)
	camera.global_position = arena.to_global(Vector3(1, 25, 12))
	camera.look_at(arena.to_global(Vector3(1, 0, 0)))
	camera.make_current()
	var actor = actors[0]
	var ai = actor.get_node("AI")
	for frame in 600:
		await physics_frame
		if actor.shot_count > 0 and actors.slice(1).any(func(other): return other.shot_count > 0): break
	check(actor.shot_count > 0 and ai.context.is_arena_active(), "Level %d: real AI perceives the player and fires before interruption" % level)
	var source_training = actor.get_node("Training").profile
	source_training.tactics.headshot_protection = false
	for frame in 3: await physics_frame
	check(actor.is_headshot_protected() == (level > 0), "Level %d: protection follows personal live or team frozen training rules" % level)
	source_training.tactics.headshot_protection = true
	for frame in 3: await physics_frame
	var gun := WeaponData.new()
	gun.damage = 10
	gun.aim_range = 50
	gun.fire_range = 50
	gun.min_spread_angle_degrees = 0
	gun.max_spread_angle_degrees = 0
	gun.headshot_chance = 1
	gun.headshot_stagger_seconds = 2
	gun.shot_noise = null
	var combat = player.get_node("Combat")
	combat.equip_weapon(gun)
	combat.is_aiming = true
	combat.accuracy = 1
	combat.locked_target = actor
	var health: float = actor.health
	var action_before = ai.current_action
	var assignment_before: Dictionary = ai.context.coordination_assignment().duplicate(true)
	combat.shoot()
	check(combat.last_shot_collider == actor and actor.health == health - 30 and actor.is_staggered(), "Level %d: actual player ray causes protected damage and stagger" % level)
	check(ai.current_action == action_before and ai.context.coordination_assignment() == assignment_before, "Level %d: headshot preserves the current AI action and coordinator assignment" % level)
	var start: Vector3 = actor.global_position
	var evidence_before: float = ai.context.evidence_elapsed_seconds
	var others_before: int = _shots(actors.slice(1))
	var still := true
	var zero_accuracy := true
	var ticks := 0
	while actor.is_staggered() and ticks < 240:
		await physics_frame
		ticks += 1
		if not actor.is_staggered(): break
		still = still and Vector2(actor.global_position.x - start.x, actor.global_position.z - start.z).length() < 0.02
		zero_accuracy = zero_accuracy and actor.get_center_probability() == 0
	check(still and zero_accuracy and ticks > 30 and not actor.is_staggered() and ai.context.evidence_elapsed_seconds > evidence_before, "Level %d: AI keeps updating while only body movement and accuracy are restricted" % level)
	check(_shots(actors.slice(1)) > others_before, "Level %d: teammates continue actual firing during this member's stagger" % level)
	var shots_after_expiry: int = actor.shot_count
	for frame in 600:
		await physics_frame
		if actor.shot_count > shots_after_expiry: break
	if actor.shot_count <= shots_after_expiry:
		print("Recovery diagnostic: level=", level, " action=", ai.utility_current, " task=", ai.context.coordination_assignment(), " probability=", actor.get_center_probability(), " position=", actor.global_position, " visible=", ai.context.sees_player)
		var point: Vector3 = ai.context.perception.visible_aim_position(true)
		print("Fire diagnostic: can_fire=", actor.can_fire(), " request=", ai.context.fire.request, " lane=", ai.context.fire.has_clear_firing_lane(actor.get_shot_origin(), actor.aim_direction, actor.get_shot_origin().distance_to(point)), " ally_safe=", ai.context.cooperation_line_safe(actor.get_shot_origin(), point), " rounds=", actor.ammo.magazine_rounds, " decision=", ai.context.fire.fire_decision.selected_action, " paused=", ai.context.fire.fire_pause_remaining)
	check(actor.shot_count > shots_after_expiry and ai.current_action != null, "Level %d: original planner continues valid execution and actual firing after expiry" % level)
	actor.apply_stagger(1)
	player.is_in_dialogue = true
	for frame in 3: await physics_frame
	check(not actor.is_staggered(), "Level %d: dialogue clears reaction state through original lifecycle" % level)
	player.is_in_dialogue = false
	scene.queue_free()
	for frame in 4: await physics_frame

func _shots(actors: Array) -> int:
	var count := 0
	for actor in actors: count += actor.shot_count
	return count
