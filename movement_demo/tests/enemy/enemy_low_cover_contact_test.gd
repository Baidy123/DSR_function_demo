extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func settle() -> void:
	for frame in 8: await physics_frame

func _run() -> void:
	seed(2110)
	var scene = Fixture.single_member_scene()
	root.add_child(scene)
	current_scene = scene
	var enemy = Fixture.primary_enemy(scene)
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	enemy.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	Fixture.configure_timing(enemy)
	# Exercise the base search/attack loop without optional combat tactics.
	ai.training.profile.selected_tactics.clear()
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	ai.training.profile.set_setting(&"perception", &"close_cover_intelligence_enabled", false)
	ai.refresh_configuration(true)
	var search = ai.actions[&"search"]
	search.tracking_cheat_enabled = true
	search.lost_target_hint_chance = 1.0
	search.search_hint_chance = 1.0
	var environment = scene.get_node("Arena/NavigationRegion3D/Environment")
	var cover = environment.get_node_or_null("LowCover")
	if cover == null:
		for candidate in environment.get_children():
			if candidate.scene_file_path == "res://scenes/world/low_cover.tscn":
				cover = candidate
				break
	check(cover != null, "saved arena contains a real low-cover instance")
	if cover == null:
		scene.queue_free()
		quit(1)
		return
	var center: Vector3 = cover.global_position
	center.y = 0.0
	var front: Vector3 = cover.global_basis.z.normalized()
	var along: Vector3 = cover.global_basis.x.normalized()
	var start: Vector3 = center + front * 2.0
	var known: Vector3 = center - front * 0.66
	enemy.global_position = start
	player.global_position = known
	enemy.look_at(known)
	player.request_crouch(true)
	player._update_posture(0.3)
	await settle()
	for frame in 120:
		if ai.context.environment_ready(): break
		await physics_frame
	check(ai.context.environment_ready(), "real arena navigation is ready")
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	check(not ai.context.has_visual_memory and search._low_cover_focus.is_empty(), "an undiscovered crouching player remains hidden")
	player.request_crouch(false)
	player._update_posture(0.3)
	await settle()
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	check(ai.context.sees_player and ai.has_visual_memory, "standing player establishes actual visual contact")
	player.request_crouch(true)
	player._update_posture(0.3)
	await settle()
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	check(not ai.context.sees_player and search._has_low_cover_focus(), "crouching behind the witnessed wall retains cover contact without sight")
	var captured: float = ai.context.suppression_evidence.captured_at
	player.global_position += along * 0.3
	await settle()
	search.begin({"destination": {}}, false)
	var maintained := true
	for frame in 300:
		ai.context.update_evidence(0.1, ai.perception.can_see_player())
		search.tick(0.1, false)
		maintained = maintained and search._has_low_cover_focus() and search.investigation_phase != ai.State.SEARCH and search.coverage.sample_count == 0
	check(maintained and ai.utility_unseen_seconds > 20.0, "route failures and expired ordinary clue timers never start area search")
	check(search._low_cover_focus.get("position") == known and ai.last_seen_position == known and ai.last_known_position == known, "even 100 percent search hints cannot track hidden movement during cover contact")
	check(not ai.context.sees_player and ai.context.suppression_basis().is_empty() and ai.context.suppression_evidence.captured_at == captured, "persistent contact does not renew sight or suppression authority")
	search.cancel(&"switch")
	search.begin({"destination": {}}, false)
	check(search._has_low_cover_focus(), "ordinary action switches retain the frozen cover")
	var timer: float = search.track_timer
	search.on_event(&"damage", {"amount": 1.0})
	check(search._has_low_cover_focus() and search.track_timer == timer, "damage permits self preservation without renewing or forgetting the cover")
	# A real clear view of the now-empty remembered position releases the focus.
	player.global_position = known - front * 6.0
	enemy.global_position = known - front * 2.0
	enemy.look_at(known)
	await settle()
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	check(not ai.context.sees_player and ai.perception.can_observe_position(known), "empty-hideout fixture is truly observable without seeing the player")
	search.step(0.1)
	check(search._low_cover_focus.is_empty() and search.investigation_phase == ai.State.SEARCH, "actual inspection of the empty location permits area search")
	# Re-establish the encounter, then let the original Utility and body run.
	enemy.reset_target()
	ai.set_physics_process(false)
	enemy.set_physics_process(false)
	enemy.global_position = start
	player.global_position = known
	player.request_crouch(false)
	player._update_posture(0.3)
	enemy.look_at(known)
	await settle()
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	player.request_crouch(true)
	player._update_posture(0.3)
	await settle()
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	search.tracking_cheat_enabled = false
	var shots: int = enemy.shot_count
	var reacquired := false
	var stayed_focused := true
	var travelled := 0.0
	var previous: Vector3 = enemy.global_position
	var old_scale := Engine.time_scale
	Engine.time_scale = 4.0
	enemy.set_physics_process(true)
	for frame in 900:
		await physics_frame
		ai._physics_process(enemy.get_physics_process_delta_time())
		travelled += enemy.global_position.distance_to(previous)
		previous = enemy.global_position
		reacquired = reacquired or ai.context.sees_player
		if not reacquired: stayed_focused = stayed_focused and search.investigation_phase != ai.State.SEARCH
		if reacquired and enemy.shot_count > shots: break
	Engine.time_scale = old_scale
	check(stayed_focused and travelled > 1.0 and reacquired, "normal Utility physically approaches the cover and reacquires the crouching player")
	check(enemy.shot_count > shots and search._low_cover_focus.is_empty(), "real reacquisition resumes firearm execution and clears the old cover focus")
	# New evidence and reset retain their normal authority.
	enemy.set_physics_process(false)
	search._capture_low_cover_focus(known, cover)
	search.on_event(&"noise", {"position": known + Vector3.RIGHT * 4.0})
	check(search._low_cover_focus.is_empty(), "a different actual sound clue supersedes the old cover")
	search._capture_low_cover_focus(known, cover)
	enemy.reset_target()
	check(search._low_cover_focus.is_empty() and not ai.has_visual_memory, "real reset clears both contact and action progress")
	search._capture_low_cover_focus(known, cover)
	ai.context.reset_memory()
	check(not search._has_low_cover_focus(), "memory generation changes invalidate retained action evidence")
	search.reset()
	search._capture_low_cover_focus(known, cover)
	var wall_shape: CollisionShape3D = cover.get_node("CollisionShape3D")
	wall_shape.disabled = true
	check(not search._has_low_cover_focus(), "disabled cover geometry cannot retain a stale hideout")
	wall_shape.disabled = false
	search.reset()
	# A second actor receives real sight from the far side of the wall, while
	# remaining personally blind. No event or shared report is injected here.
	var receiver = load("res://scenes/enemy/enemy.tscn").instantiate()
	receiver.weapon = WeaponData.new()
	scene.get_node("Arena").add_child(receiver)
	Fixture.configure_timing(receiver)
	var receiver_ai = receiver.get_node("AI")
	receiver_ai.set_physics_process(false)
	receiver.set_physics_process(false)
	receiver_ai.training.profile.set_setting(&"perception", &"close_cover_intelligence_enabled", false)
	receiver_ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	receiver.global_position = start
	receiver.look_at(known)
	enemy.global_position = known + Vector3.FORWARD * 2.0
	enemy.look_at(known)
	player.global_position = known
	await settle()
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	receiver_ai.context.update_evidence(0.1, receiver_ai.perception.can_see_player())
	var receiver_search = receiver_ai.actions[&"search"]
	check(ai.context.sees_player and not receiver_ai.context.sees_player and not receiver_ai.has_visual_memory and receiver_search._has_low_cover_focus(), "actual teammate sight creates frozen low-cover contact without personal visibility")
	var report: Dictionary = receiver_ai.context.fresh_shared_contact()
	receiver_ai.context.evidence_elapsed_seconds += 25.0
	receiver_search.begin({"destination": {}}, false)
	check(not report.is_empty() and receiver_ai.context.fresh_shared_contact().is_empty() and receiver_search._has_low_cover_focus(), "expiry of precise shared sight does not erase an unchecked known cover")
	receiver_ai.context._cooperation_identity = []
	check(not receiver_search._has_low_cover_focus(), "a changed communication identity invalidates contact derived only from teammates")
	print("LOW COVER CONTACT: %d/%d passed; travelled=%s" % [checks - failures, checks, travelled])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
