extends SceneTree

const Binding = preload("res://scripts/enemy/config/team_cooperation_binding.gd")
const Library = preload("res://scripts/enemy/enemy_action_library.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	for child in arena.get_children():
		if child.has_node("AI"): child.free()
	var alpha := Binding.new()
	alpha.communication_group = &"alpha"
	var beta := Binding.new()
	beta.communication_group = &"beta"
	beta.profile = alpha.profile
	arena.team_cooperation_bindings.assign([alpha, beta])
	var actors: Array = []
	for index in 3:
		var actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		actor.communication_group = &"alpha" if index < 2 else &"beta"
		actor.position = Vector3(-4 + index * 4, 0, -3)
		actor.get_node("Training").profile = EnemyTrainingProfile.new()
		actor.get_node("Training").profile.selected_tactics.assign([&"cooperate", &"suppression"] if index == 0 else [&"melee_rush"])
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres" if index == 0 else "res://resources/enemy/units/melee.tres").duplicate(true)
		arena.add_child(actor)
		actors.append(actor)
	root.add_child(scene)
	current_scene = scene
	arena.set_physics_process(false)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	var contexts: Array = []
	for actor in actors:
		actor.set_physics_process(false)
		actor.get_node("AI").set_physics_process(false)
		actor.get_node("AI").refresh_configuration(true)
		contexts.append(actor.get_node("AI").context)
	for frame in 4: await physics_frame
	var board = arena.cooperation
	check(contexts.all(func(c): return c.cooperation_level() == 0 and not c.can_use_action(&"cooperate")), "New binding is intel only despite a personal legacy cooperate selection")
	check(contexts[0].can_use_action(&"suppression") and contexts[1].can_use_action(&"melee_rush") and not contexts[1].can_use_action(&"suppression"), "Individual unit capabilities and personal tactics remain independent")
	check(contexts[0].training != contexts[1].training and board._team_settings.size() == 2, "One shared awareness snapshot per squad, separate personal Training per actor")
	check(board.can_cooperate(actors[0].get_instance_id(), actors[1].get_instance_id()) and not board.can_cooperate(actors[0].get_instance_id(), actors[2].get_instance_id()), "Reusing a template does not combine different squads")
	var selected: Array = contexts.map(func(c): return c.training.selected_tactics.duplicate())
	alpha.profile.level = 1
	alpha.profile.flank_distance = 6.0
	arena.enemy_environment()
	for actor in actors: actor.get_node("AI").refresh_configuration()
	check(contexts.all(func(c): return c.cooperation_level() == 1 and c.can_use_action(&"cooperate") and c.coordination_assignment().is_empty()), "Squad provides tactical awareness to different unit types without strong assignments")
	contexts[0].training.set_setting(&"cooperation", &"flank_distance", 2.0)
	check(contexts[0].setting(&"cooperation", &"flank_distance", 0) == 6.0 and actors[0].get_node("AI").actions.cooperate._setting(&"flank_distance", 0) == 6.0, "Context and action read shared settings ahead of legacy personal cooperation values")
	contexts[0].training.set_setting(&"tactics", &"fire_reaction_seconds", 3.25)
	check(contexts[0].setting(&"tactics", &"fire_reaction_seconds", 0) == 3.25, "Non-cooperation settings retain personal override precedence")
	var before: int = board.team_configuration_revision(contexts[0])
	var old_abilities: Dictionary = contexts[0].team_cooperation_abilities()
	old_abilities.level = 0
	check(contexts[0].cooperation_level() == 1, "Published ability values cannot mutate the shared snapshot")
	alpha.profile.level = 2
	arena.enemy_environment()
	for actor in actors: actor.get_node("AI").refresh_configuration()
	check(board.team_configuration_revision(contexts[0]) > before and contexts.all(func(c): return c.coordinated_cooperation_enabled()), "Hot level change reaches the whole squad and advances its configuration revision")
	check(contexts[0].training.selected_tactics == selected[0] and contexts[1].training.selected_tactics == selected[1], "Shared permission never rewrites any personal selection")
	check(not Library.resolve(contexts[0].unit, contexts[0].training, {"level": 0}).definitions.has(&"cooperate") and Library.resolve(contexts[0].unit, contexts[0].training).definitions.has(&"cooperate"), "Pure resolver retains unbound legacy compatibility")
	var saved := "user://team_binding_test.tres"
	check(ResourceSaver.save(alpha, saved) == OK, "Squad binding saves as a normal resource")
	var restored = ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.communication_group == &"alpha" and restored.profile.level == 2 and restored.profile.flank_distance == 6.0, "Reload restores shared level and parameter overrides")
	var duplicate := Binding.new()
	duplicate.communication_group = &"alpha"
	arena.team_cooperation_bindings.append(duplicate)
	arena.enemy_environment()
	for actor in actors: actor.get_node("AI").refresh_configuration()
	check(contexts[0].cooperation_level() == 0 and not contexts[1].can_use_action(&"cooperate") and contexts[2].cooperation_level() == 2, "Duplicate binding disables only the affected squad's tactical permissions")
	check(board.team_configuration_diagnostics().size() == 1 and board.can_share_intel(actors[0].get_instance_id(), actors[1].get_instance_id()), "Duplicate diagnosis preserves basic allied intel")
	arena.team_cooperation_bindings.clear()
	arena.enemy_environment()
	for actor in actors: actor.get_node("AI").refresh_configuration()
	check(contexts[0].cooperation_level() == 2 and contexts[1].cooperation_level() == 0, "Removing bindings returns to the preserved legacy individual configuration")
	scene.queue_free()
	await scene.tree_exited
	await process_frame
	print("TEAM TRAINING BINDING: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
