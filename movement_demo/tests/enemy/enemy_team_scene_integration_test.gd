extends SceneTree

const Binding = preload("res://scripts/enemy/config/team_cooperation_binding.gd")
const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	var paths := ["intel_only", "tactical", "coordinated"]
	for level in paths.size():
		var profile = load("res://resources/enemy/cooperation/%s.tres" % paths[level])
		check(profile.level == level and profile.overridden.has("level"), "Reusable profile %s retains its explicit level" % paths[level])
		var saved := "user://team_profile_%d.tres" % level
		var result := ResourceSaver.save(profile.duplicate(true), saved)
		var restored = ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(result == OK and restored != null and restored.level == level, "Profile %s survives save and reload" % paths[level])
	var legacy := Fixture.legacy_scene()
	check(legacy.get_node("Arena").team_cooperation_bindings.is_empty(), "Legacy fixtures explicitly retain their own personal training controls")
	legacy.free()
	# Load the actual explicit squad and every saved member, without legacy unwrapping.
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	var binding = arena.get_node("Squad")
	check(arena.team_cooperation_bindings.is_empty() and binding.profile.level == 2, "Saved arena uses a coordinated squad node as its only team configuration entry")
	var saved_profile = binding.profile
	binding.profile = saved_profile.duplicate(true)
	var saved_members: Array = Fixture.members(arena)
	check(not saved_members.is_empty(), "The saved arena supplies a real member with personal Training")
	# Older saved arenas have one member. Add only the second participant needed
	# by the independence assertion; never replace or rename a saved actor.
	if saved_members.size() == 1:
		var companion = load("res://scenes/enemy/enemy.tscn").instantiate()
		companion.position = saved_members[0].position + Vector3(0, 0, 2)
		binding.add_child(companion)
	root.add_child(scene)
	current_scene = scene
	var members: Array = Fixture.members(arena)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = Vector3(23, 0, 0)
	for frame in 45: await physics_frame
	check(members.size() == maxi(2, saved_members.size()) and saved_members.all(func(member): return members.has(member)), "Integration retains every saved member and has two real participants for personal isolation")
	var contexts: Array = members.map(func(member): return member.get_node("AI").context)
	check(contexts.all(func(context): return context.cooperation_level() == 2 and context.coordinated_cooperation_enabled()), "Normal AI ticks inherit the saved shared level for every member")
	check(members.all(func(member): return member.get_node("AI").is_physics_processing()), "Member AI remains active throughout the integration test")
	var selections: Array = contexts.map(func(context): return context.training.selected_tactics.duplicate())
	var personal_second: float = contexts[1].setting(&"tactics", &"fire_reaction_seconds", 0.0)
	contexts[0].training.set_setting(&"tactics", &"fire_reaction_seconds", personal_second + 0.25)
	check(contexts[0].training != contexts[1].training and is_equal_approx(contexts[1].setting(&"tactics", &"fire_reaction_seconds", 0.0), personal_second), "Editing one personal tactic leaves the other member's Training unchanged")
	var revision: int = arena.cooperation.team_configuration_revision(contexts[0])
	for level in [0, 1, 2]:
		binding.profile.level = level
		for frame in 45: await physics_frame
		check(contexts.all(func(context): return context.cooperation_level() == level) and arena.cooperation.team_configuration_revision(contexts[0]) > revision, "Normal region ticks switch the entire squad to level %d and advance its revision" % level)
		revision = arena.cooperation.team_configuration_revision(contexts[0])
		if level < 2:
			check(contexts.all(func(context): return context.coordination_assignment().is_empty() and context.coordination_support_state().is_empty()), "Level %d cannot retain a strong assignment or promised support" % level)
		if level == 0:
			check(contexts.all(func(context): return context.coordination_recommendation().is_empty() and not context.can_use_action(&"cooperate")), "Intel-only removes tactical offers despite preserved personal legacy switches")
	var unchanged := true
	for index in contexts.size(): unchanged = unchanged and contexts[index].training.selected_tactics == selections[index]
	check(unchanged and saved_profile.level == 2, "Hot switching never rewrites personal selections or the saved template")
	var resets: Dictionary = {}
	for member in members:
		resets[member.get_instance_id()] = 0
		member.reset_completed.connect(func(): resets[member.get_instance_id()] += 1)
	arena._reset_targets()
	check(resets.values().all(func(count): return count == 1), "Area reset invokes each nested member exactly once")
	check(arena.cooperation.coordination_debug_snapshot(&"_coordination_plans").is_empty() and arena.cooperation.coordination_debug_snapshot(&"_recommendations").is_empty(), "Area reset clears plans and advice before a new combat cycle")
	for frame in 15: await physics_frame
	check(contexts.all(func(context): return context.cooperation_level() == 2 and context.squad_node == binding), "Respawn retains the shared configuration and independent personal actors")
	check(members.all(func(member): return Binding.find_for_member(member).get("binding") == binding), "Editor membership lookup resolves the same runtime squad")
	# A bound squad can shrink to one member. Team-only nonempty reload previews
	# must not win personal Utility when there is nobody to provide an assignment.
	var solo = members[0]
	for member in members.slice(1): member.queue_free()
	await process_frame
	await physics_frame
	var solo_ai = solo.get_node("AI")
	solo_ai.set_physics_process(false)
	Fixture.configure_timing(solo)
	solo_ai.reset_actions()
	solo.ammo.magazine_rounds = 1
	check(arena.cooperation.registered_member_count() == 1 and solo_ai.context.cooperation_level() == 2 and solo_ai.actions.reload.collect_candidates(false).is_empty(), "A lone strong member has no unsupported proactive reload that can block personal search")
	solo.ammo.magazine_rounds = 0
	check(not solo_ai.actions.reload.collect_candidates(false).is_empty(), "The same isolated strong member still retains urgent empty-magazine reload")
	scene.queue_free()
	await scene.tree_exited
	await process_frame
	print("TEAM SCENE INTEGRATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
