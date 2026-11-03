extends SceneTree

## Integration coverage: real region, facade/runtime, rules, actors, AI and camera rig.
## No gameplay process is disabled and no director/runtime clock is manually advanced.
const Region = preload("res://scripts/world/shooting_range.gd")
const Waves = preload("res://scripts/world/enemy_wave_controller.gd")
const Wave = preload("res://scripts/world/enemy_wave_definition.gd")
const Rule = preload("res://scripts/systems/scene_flow_rule.gd")
const Action = preload("res://scripts/systems/scene_flow_action.gd")
const Trigger = preload("res://scripts/systems/scene_event_trigger.gd")
const Pause = preload("res://scripts/systems/scene_pause_coordinator.gd")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CameraScene: PackedScene = preload("res://scenes/player/player_camera_rig.tscn")
const SquadScene: PackedScene = preload("res://scenes/world/squad.tscn")
const EnemyScene: PackedScene = preload("res://scenes/enemy/levels/lvl_1/melee.tscn")

class Events extends Node:
	signal reinforce
	signal arm_delay

## Negative control, opt-in only: reproduce the old pre-notification mouse snapshot
## without editing production code. All token and pause behavior remains production.
class LegacyMouseSnapshot extends "res://scripts/systems/scene_pause_coordinator.gd":
	func acquire(owner: Node, reason: StringName, visible_mouse: bool = false) -> int:
		var first_owner: bool = _tokens.is_empty()
		var before_notifications: Input.MouseMode = Input.mouse_mode
		var token: int = super.acquire(owner, reason, visible_mouse)
		if first_owner: _previous_mouse_mode = before_notifications
		return token

var checks: int = 0
var failures: int = 0
var region: Node3D
var host: Node3D
var reinforcement: Node3D
var player: CharacterBody3D
var source: Camera3D
var events: Events
var focus_marker: Marker3D
var old_enemy: CharacterBody3D
var ready_observations: Array[Dictionary] = []
var public_observations: Array[Dictionary] = []
var started_observations: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("DebugSettings").set("enabled", false)
	node_added.connect(_watch_added_node)
	var mouse_only: bool = OS.get_cmdline_user_args().has("--mouse-ownership-only")
	if not mouse_only:
		await _real_spawn_barrier_and_return()
		await _blocked_spawn()
		await _direct_wave_presentation()
		await _missing_target(false, true)
		await _missing_target(false)
		await _missing_target(true)
		await _death_cancels_presentation()
		await _region_exit_cancels_presentation()
	if DisplayServer.get_name() != "headless":
		if mouse_only and OS.get_cmdline_user_args().has("--legacy-mouse-snapshot"):
			var legacy: RefCounted = LegacyMouseSnapshot.new()
			legacy.set("_tree", weakref(self))
			set_meta(Pause.META, legacy)
			print("NEGATIVE CONTROL: snapshot mouse mode before pause notifications")
		await _mouse_capture_handoff(false)
		await _mouse_capture_handoff(true)
	elif mouse_only:
		_check("mouse ownership requires a real window/display backend", false)
	else:
		print("SKIP rendered mouse ownership: run without --headless and with -- --mouse-ownership-only")
	node_added.disconnect(_watch_added_node)
	_check("all integration fixtures release pause ownership", not paused and Pause.for_tree(self).snapshot().count == 0)
	print("SCENE REINFORCEMENT: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _fixture(blocked: bool = false, bind_target: bool = true, direct_wave: bool = false) -> void:
	ready_observations.clear()
	public_observations.clear()
	started_observations.clear()
	old_enemy = null
	region = Region.new()
	region.name = "ReinforcementRegion"
	# A translated region distinguishes a manually bound target's global_position from position.
	region.position = Vector3(13, 0, 17)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(24.0, 0.2, 24.0)
	floor_shape.shape = floor_box
	floor_body.position.y = -0.1
	floor_body.add_child(floor_shape)
	region.add_child(floor_body)
	var navigation: NavigationRegion3D = NavigationRegion3D.new()
	navigation.name = "NavigationRegion3D"
	var mesh: NavigationMesh = NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-11, 0, -11), Vector3(11, 0, -11), Vector3(11, 0, 11), Vector3(-11, 0, 11)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	region.add_child(navigation)
	var zone: Area3D = Area3D.new()
	zone.name = "CombatZone"
	zone.collision_layer = 0
	var zone_shape: CollisionShape3D = CollisionShape3D.new()
	zone_shape.name = "CollisionShape3D"
	var zone_box: BoxShape3D = BoxShape3D.new()
	zone_box.size = Vector3(22.0, 4.0, 22.0)
	zone_shape.shape = zone_box
	zone_shape.position.y = 1.0
	zone.add_child(zone_shape)
	region.add_child(zone)
	player = PlayerScene.instantiate() as CharacterBody3D
	player.name = "Player"
	player.position = Vector3(0, 0, 7)
	player.get_node("Health").set("debug_mode", false)
	# Isolated resource copy ensures a real magazine reload without relying on user gun tuning.
	var equipment: Node = player.get_node("Equipment")
	var weapon: WeaponData = (equipment.get("primary_weapon") as WeaponData).duplicate(true) as WeaponData
	weapon.fire_mode = WeaponData.FireMode.SEMI_AUTO
	weapon.magazine_capacity = 12
	weapon.reload_seconds = 3.0
	equipment.set("primary_weapon", weapon)
	equipment.set("starting_slot", 0)
	region.add_child(player)
	source = CameraScene.instantiate() as Camera3D
	source.name = "Camera3D"
	region.add_child(source)
	focus_marker = Marker3D.new()
	focus_marker.name = "CameraFocus"
	# Deliberately differs from the reinforcement center (5, 0, -4).
	focus_marker.position = Vector3(-3, 0, -7)
	region.add_child(focus_marker)
	events = Events.new()
	events.name = "Events"
	region.add_child(events)
	host = Waves.new()
	host.name = "EnemyWaves"
	host.set("guide_path", NodePath())
	host.set("result_view_path", NodePath())
	host.set("complete_when_all_waves_cleared", false)
	host.set("spawn_retry_seconds", 0.05)
	region.add_child(host)
	_add_wave("Old", Wave.StartMode.SEQUENCE, [Vector3(-6, 0, -4)])
	reinforcement = _add_wave("Reinforcement", Wave.StartMode.REQUEST, [Vector3(4, 0, -4), Vector3(6, 0, -4)])
	var delayed: Node3D = _add_wave("Delayed", Wave.StartMode.REQUEST, [Vector3(-7, 0, 5)])
	delayed.set("start_delay_seconds", 5.0)
	var request_rule: SceneFlowRule = _rule("reinforcement", &"reinforce")
	var request: SceneFlowAction = Action.new()
	request.kind = Action.Kind.REQUEST_WAVE
	request.target_path = ^"Reinforcement"
	request.present_spawn = true
	if bind_target: request.presentation_target_path = ^"../CameraFocus"
	request.move_seconds = 0.15
	request.hold_seconds = 0.5
	request.return_seconds = 0.15
	request_rule.actions.append(request)
	var delayed_rule: SceneFlowRule = _rule("delayed_wave", &"arm_delay")
	var delay_request: SceneFlowAction = Action.new()
	delay_request.kind = Action.Kind.REQUEST_WAVE
	delay_request.target_path = ^"Delayed"
	delayed_rule.actions.append(delay_request)
	var wait_rule: SceneFlowRule = _rule("ordinary_delay", &"arm_delay")
	var wait_action: SceneFlowAction = Action.new()
	wait_action.kind = Action.Kind.WAIT
	wait_action.seconds = 5.0
	wait_rule.actions.append(wait_action)
	var rules: Array[SceneFlowRule] = [delayed_rule, wait_rule, request_rule]
	if direct_wave:
		# Editor-facing Wave route: no SceneFlowRule or REQUEST_WAVE can arm this camera.
		rules.clear()
		reinforcement.set("start_mode", Wave.StartMode.EVENTS)
		var wave_trigger: SceneEventTrigger = Trigger.new()
		wave_trigger.source_path = ^"../../Events"
		wave_trigger.signal_name = &"reinforce"
		var wave_triggers: Array[SceneEventTrigger] = [wave_trigger]
		reinforcement.set("triggers", wave_triggers)
		reinforcement.set("show_spawn_presentation", true)
		if bind_target: reinforcement.set("presentation_target_path", ^"../../CameraFocus")
		reinforcement.set("presentation_move_seconds", 0.15)
		reinforcement.set("presentation_hold_seconds", 0.5)
		reinforcement.set("presentation_return_seconds", 0.15)
		reinforcement.set("presentation_size", 6.25)
	host.set("scene_rules", rules)
	reinforcement.connect("spawned", _on_public_spawned)
	host.connect("wave_started", _on_wave_started)
	if blocked:
		var blocker: CharacterBody3D = CharacterBody3D.new()
		blocker.name = "SpawnBlocker"
		blocker.position = Vector3(4.0, 0.875, -4.0)
		var shape: CollisionShape3D = CollisionShape3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.75
		shape.shape = capsule
		blocker.add_child(shape)
		region.add_child(blocker)
	root.add_child(region)
	current_scene = region
	_check("real facade captures templates before runtime enemies enter the tree", ready_observations.is_empty() and (region.get("enemies") as Array).is_empty())
	var old_ready: bool = await _await_wave(host.get_node("Old"), &"active")
	_check("real region entry spawns the initial wave", old_ready and bool(region.call("has_active_player")))
	old_enemy = host.get_node_or_null("Old/Squad/Enemy1") as CharacterBody3D
	await _steps(3)
	_check("real player rig and initialized director are available", source.is_current() and _director().call("debug_snapshot").state == &"running")
	_check("old enemy AI and cooperation were advancing before the request", old_enemy != null and _enemy_snapshot(old_enemy).evidence > 0.0 and _cooperation_time() > 0.0)


func _add_wave(label: String, mode: int, positions: Array[Vector3]) -> Node3D:
	var wave: Node3D = Wave.new()
	wave.name = label
	wave.set("start_mode", mode)
	wave.set("search_on_spawn", false)
	host.add_child(wave)
	var squad: Node3D = SquadScene.instantiate() as Node3D
	squad.name = "Squad"
	var profile: Resource = (squad.get("profile") as Resource).duplicate(true)
	profile.set("level", 1)
	squad.set("profile", profile)
	wave.add_child(squad)
	for index in positions.size():
		var enemy: CharacterBody3D = EnemyScene.instantiate() as CharacterBody3D
		enemy.name = "Enemy%d" % (index + 1)
		enemy.position = positions[index]
		enemy.get_node("NavigationAgent3D").set("path_height_offset", 0.0)
		squad.add_child(enemy)
	return wave


func _rule(label: String, event: StringName) -> SceneFlowRule:
	var rule: SceneFlowRule = Rule.new()
	rule.label = label
	rule.scope = Rule.Scope.REGION
	var trigger: SceneEventTrigger = Trigger.new()
	trigger.source_path = ^"../Events"
	trigger.signal_name = event
	rule.triggers.append(trigger)
	return rule


func _watch_added_node(node: Node) -> void:
	if not is_instance_valid(reinforcement) or not node is CharacterBody3D: return
	if node.get_parent() == null or node.get_parent().get_parent() != reinforcement: return
	node.ready.connect(_on_reinforcement_ready.bind(node), CONNECT_ONE_SHOT)


func _on_reinforcement_ready(enemy: CharacterBody3D) -> void:
	# Public body operations seed active timers before the production spawn barrier.
	enemy.call("apply_hit_slowdown", 0.25, 2.0)
	enemy.set("melee_cooldown", 2.0)
	ready_observations.append({"paused": paused, "source_current": source.is_current(),
		"body": _enemy_snapshot(enemy), "cooperation": _cooperation_time(),
		"physics_frame": Engine.get_physics_frames()})


func _on_public_spawned() -> void:
	var camera: Camera3D = root.get_camera_3d()
	var ground: Vector3 = player.get_global_transform_interpolated().origin
	ground.y = float(player.call("get_camera_ground_height"))
	public_observations.append({"paused": paused, "camera": camera,
		"camera_origin": camera.global_position if camera != null else Vector3.ZERO,
		"ground": ground, "target": focus_marker.global_position if is_instance_valid(focus_marker) else null,
		"presenting": camera != null and camera.has_method("is_presenting") and bool(camera.call("is_presenting")),
		"ready_count": ready_observations.size(), "state": _state_snapshot(),
		"physics_frame": Engine.get_physics_frames(), "pause": _director().call("debug_snapshot").pause})


func _on_wave_started(index: int) -> void:
	if index == 2:
		started_observations.append({"paused": paused, "camera": root.get_camera_3d(), "count": public_observations.size()})


func _real_spawn_barrier_and_return() -> void:
	await _fixture()
	events.arm_delay.emit()
	await _steps(5)
	_check("ordinary flow wait and independent wave delay are active", _ordinary_remaining() > 0.0 and _wave_remaining("Delayed") > 0.0)
	player.call("apply_hit_slowdown", 0.25, 2.0)
	player.call("try_consume_stamina", 20.0)
	old_enemy.call("apply_hit_slowdown", 0.25, 2.0)
	old_enemy.set("melee_cooldown", 2.0)
	var combat: Node = player.get_node("Combat")
	var ammo: RefCounted = combat.get("ammo")
	ammo.set("magazine_rounds", 1)
	ammo.set("infinite_reserve", true)
	_check("real player reload starts before reinforcement", bool(combat.call("request_reload")))
	Input.action_press("move_right")
	var before_moving: Vector3 = player.global_position
	await _steps(30)
	_check("player is actually moving before the presentation barrier", player.global_position.distance_to(before_moving) > 0.1 and player.velocity.length() > 0.0)
	events.reinforce.emit()
	_check("trigger callback does not show an empty location or pause gameplay", not paused and source.is_current() and ready_observations.is_empty())
	if not await _await_presentation():
		await _cleanup()
		return
	_check_spawn_order()
	var at_commit: Dictionary = public_observations[0].state
	var camera: Camera3D = public_observations[0].camera
	var camera_start: Vector3 = camera.global_position
	await _steps(12)
	var during: Dictionary = _state_snapshot()
	_check("presentation remains active while its own camera moves", paused and bool(camera.call("is_presenting")) and camera.global_position.distance_to(camera_start) > 0.01)
	_check_manual_focus(camera)
	_check("player movement stamina reload and hit duration freeze from the commit", during.player == at_commit.player)
	_check("old enemy body and real AI clocks freeze from the commit", during.old == at_commit.old)
	_check("new enemies cannot run their first AI or body tick behind the presentation", during.new == at_commit.new and _new_evidence_is_zero(during.new))
	_check("same-step and subsequent region cooperation are frozen", during.cooperation == at_commit.cooperation and at_commit.cooperation == ready_observations.back().cooperation and during.squad_frames == at_commit.squad_frames)
	_check("independent wave and ordinary scene delays stay frozen", during.wave_remaining == at_commit.wave_remaining and during.flow_remaining == at_commit.flow_remaining)
	var finished: Array[Dictionary] = []
	camera.connect("presentation_finished", func(id: int, result: StringName) -> void:
		finished.append({"id": id, "result": result, "source_current": source.is_current(),
			"aligned": camera.global_transform.is_equal_approx(source.global_transform) and is_equal_approx(camera.size, source.size)})
	)
	await _await_presentation_end()
	_check("completion returns an aligned view to the real player rig", finished.size() == 1 and finished[0].result == &"completed" and finished[0].source_current and finished[0].aligned and source.is_current())
	_check("completion releases only its presentation pause", not paused and _director().call("debug_snapshot").pause.count == 0)
	await _steps(4)
	var resumed: Dictionary = _state_snapshot()
	_check("real gameplay and both delay clocks resume after return", resumed.player.position != at_commit.player.position and resumed.player.reload > at_commit.player.reload and resumed.old.evidence > at_commit.old.evidence and resumed.cooperation > at_commit.cooperation and resumed.wave_remaining < at_commit.wave_remaining and resumed.flow_remaining < at_commit.flow_remaining)
	_check("new members begin AI only after camera return", not _new_evidence_is_zero(resumed.new) and (region.get("enemies") as Array).size() == 3)
	await _cleanup()


func _blocked_spawn() -> void:
	await _fixture(true)
	events.reinforce.emit()
	_check("occupied request enters the runtime's real blocked state", await _await_wave(reinforcement, &"blocked"))
	var before: float = _cooperation_time()
	await _steps(12)
	_check("blocked deployment never creates an empty presentation", not paused and source.is_current() and ready_observations.is_empty() and public_observations.is_empty() and _director().call("debug_snapshot").presentation == 0)
	_check("blocked retry leaves existing gameplay active", _cooperation_time() > before and (region.get("enemies") as Array).size() == 1)
	focus_marker.position = Vector3(-4, 0, -8)
	region.get_node("SpawnBlocker").queue_free()
	if await _await_presentation():
		_check_spawn_order()
		_check("clearing occupancy commits the complete original deployment once", public_observations.size() == 1 and (region.get("enemies") as Array).size() == 3 and host.call("wave_focus", reinforcement).is_equal_approx(region.to_global(Vector3(5, 0, -4))))
		await _steps(12)
		_check_manual_focus(root.get_camera_3d())
		_director().call("skip_presentation")
		_check("skipping presentation keeps the committed reinforcement alive", not paused and source.is_current() and host.call("wave_status", reinforcement) == &"active" and (region.get("enemies") as Array).size() == 3)
	await _cleanup()


func _direct_wave_presentation() -> void:
	await _fixture(true, true, true)
	_check("editor Wave route has no scene rules or global presentation fallback", _director().call("debug_snapshot").flows.rules.is_empty() and not bool(host.get("present_spawned_waves")))
	events.reinforce.emit()
	_check("direct Wave trigger respects real occupied spawn space", await _await_wave(reinforcement, &"blocked"))
	await _steps(4)
	_check("direct Wave presentation waits for successful deployment", not paused and source.is_current() and public_observations.is_empty())
	focus_marker.position = Vector3(-5, 0, -6)
	region.get_node("SpawnBlocker").queue_free()
	if not await _await_presentation():
		await _cleanup()
		return
	_check_spawn_order()
	var camera: Camera3D = public_observations[0].camera
	var original_size: float = source.size
	var committed: Dictionary = public_observations[0].state
	await _steps(12)
	_check_manual_focus(camera)
	_check("Wave-authored move and hold durations reach its configured size", paused and bool(camera.call("is_presenting")) and is_equal_approx(camera.size, 6.25) and is_equal_approx(source.size, original_size))
	var during: Dictionary = _state_snapshot()
	_check("direct Wave camera freezes real actors and area cooperation", during.player == committed.player and during.old == committed.old and during.new == committed.new and during.cooperation == committed.cooperation)
	await _await_presentation_end()
	_check("Wave-authored return duration restores source and releases the barrier", source.is_current() and not paused and not bool(camera.call("is_presenting")) and is_equal_approx(camera.size, source.size) and _director().call("debug_snapshot").pause.count == 0)
	_check("direct Wave is committed once and never creates a Flow execution", public_observations.size() == 1 and host.call("wave_status", reinforcement) == &"active" and _director().call("debug_snapshot").flows.rules.is_empty())
	await _cleanup()


func _missing_target(remove_while_blocked: bool, direct_wave: bool = false) -> void:
	await _fixture(remove_while_blocked, remove_while_blocked, direct_wave)
	events.reinforce.emit()
	if remove_while_blocked:
		_check("target-loss fixture arms its request before occupancy clears", await _await_wave(reinforcement, &"blocked"))
		focus_marker.queue_free()
		await _steps(2)
		region.get_node("SpawnBlocker").queue_free()
	_check("missing camera target does not cancel real enemy generation", await _await_wave(reinforcement, &"active"))
	var label: String = "lost" if remove_while_blocked else "unbound"
	if direct_wave: label += " Wave"
	_check("%s manual target skips presentation without falling back to enemy center" % label, public_observations.size() == 1 and not public_observations[0].paused and not public_observations[0].presenting and source.is_current() and not paused and _director().call("debug_snapshot").presentation == 0)
	_check("%s manual target reports a diagnostic while deployment stays committed" % label, not String(_director().call("debug_snapshot").last_error).is_empty() and (region.get("enemies") as Array).size() == 3)
	await _cleanup()


func _check_manual_focus(camera: Camera3D) -> void:
	var observed: Dictionary = public_observations[0]
	var expected: Vector3 = observed.camera_origin + observed.target - observed.ground
	_check("camera holds at the explicitly bound marker sampled at commit", observed.target == focus_marker.global_position and camera.global_position.distance_to(expected) < 0.001)
	var inferred_center: Vector3 = host.call("wave_focus", reinforcement)
	var forbidden: Vector3 = observed.camera_origin + inferred_center - observed.ground
	_check("camera destination is not the computed enemy center", camera.global_position.distance_to(forbidden) > 1.0)


func _death_cancels_presentation() -> void:
	await _fixture()
	events.reinforce.emit()
	if not await _await_presentation():
		await _cleanup()
		return
	var camera: Camera3D = root.get_camera_3d()
	player.call("receive_hit", 100000.0)
	var snapshot: Dictionary = _director().call("debug_snapshot")
	_check("real player death cancels the camera and retains terminal pause", bool(player.call("is_dead")) and paused and snapshot.state == &"dead" and snapshot.presentation == 0 and snapshot.pause.reasons == [&"death"] and source.is_current() and not bool(camera.call("is_presenting")))
	var frozen: Dictionary = _state_snapshot()
	await _steps(10)
	var after: Dictionary = _state_snapshot()
	_check("death does not leave a transient gameplay resume after camera cancellation", after.old == frozen.old and after.new == frozen.new and after.cooperation == frozen.cooperation and paused)
	_check("reinforcement stays committed exactly once after death", public_observations.size() == 1 and host.call("wave_status", reinforcement) == &"active")
	await _cleanup()


func _region_exit_cancels_presentation() -> void:
	await _fixture()
	events.reinforce.emit()
	if not await _await_presentation():
		await _cleanup()
		return
	var camera: Camera3D = root.get_camera_3d()
	# Walking is intentionally frozen; model an external departure through the real
	# Area3D signal route while paused, after teleporting the actor outside its volume.
	player.position = Vector3(30, 0, 30)
	player.reset_physics_interpolation()
	var zone: Area3D = region.get_node("CombatZone") as Area3D
	zone.body_exited.emit(player)
	_check("region exit cancels its camera and immediately restores player view", not paused and source.is_current() and not bool(camera.call("is_presenting")) and _director().call("debug_snapshot").presentation == 0)
	await _steps(5)
	_check("real region reset retires all wave actors and clears pending requests", (region.get("enemies") as Array).is_empty() and host.call("wave_status", reinforcement) == &"waiting" and not bool(region.call("has_active_player")))
	_check("region-scoped presentation rule resets without stale completion", _director().call("debug_snapshot").pause.count == 0 and _rule_state("reinforcement").events == 0 and not _rule_state("reinforcement").fired and public_observations.size() == 1)
	player.position = Vector3(0, 0, 7)
	player.reset_physics_interpolation()
	_check("re-entering starts the ordinary first wave again", await _await_wave(host.get_node("Old"), &"active"))
	await _steps(4)
	_check("old event does not replay reinforcement or presentation on re-entry", host.call("wave_status", reinforcement) == &"waiting" and source.is_current() and not paused and public_observations.size() == 1)
	await _cleanup()


func _check_spawn_order() -> void:
	var before_pause: bool = ready_observations.size() == 2
	for observation: Dictionary in ready_observations:
		before_pause = before_pause and not observation.paused and observation.source_current and observation.body.evidence == 0.0
	_check("both real enemy ready callbacks precede freeze and camera switch", before_pause)
	var observed: Dictionary = public_observations[0]
	_check("public spawned observes a complete ready deployment behind the camera barrier", observed.ready_count == 2 and observed.paused and observed.presenting and observed.pause.reasons == [&"presentation"] and observed.state.new.size() == 2 and _new_evidence_is_zero(observed.state.new))
	var unchanged_since_ready: bool = ready_observations.size() == observed.state.new.size()
	for index in mini(ready_observations.size(), observed.state.new.size()):
		unchanged_since_ready = unchanged_since_ready and ready_observations[index].physics_frame == observed.physics_frame and ready_observations[index].body == observed.state.new[index]
	_check("whole-wave ready and public spawn share one physics step without a body tick", unchanged_since_ready)
	_check("facade wave_started follows spawned within the same paused handoff", started_observations.size() == 1 and started_observations[0].count == 1 and started_observations[0].paused and started_observations[0].camera == observed.camera)
	_check("presentation is a sibling of the original rig and preserves its follow target", observed.camera.get_parent() == source.get_parent() and not observed.camera.has_node("PhantomCamera3D") and source.get_node("PhantomCamera3D").get("follow_target") == source.get_node("CameraGroundAnchor"))


func _mouse_capture_handoff(death: bool) -> void:
	await _fixture()
	var combat: Node = player.get_node("Combat")
	# The production Combat permission queries this group and actual Area overlap.
	region.get_node("CombatZone").add_to_group("combat_zone")
	combat.set("mouse_target_assist_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_aim_button(true)
	await _steps(3)
	var captured: bool = Input.is_action_pressed("aim") and bool(combat.get("is_aiming")) and bool(combat.get("_owns_switch_mouse_capture")) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_check("real right-button aim acquires temporary combat mouse capture", captured)
	if not captured:
		_aim_button(false)
		await _cleanup()
		return
	events.reinforce.emit()
	if not await _await_presentation():
		_aim_button(false)
		await _cleanup()
		return
	_check("presentation pause notification releases actual combat capture", paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not bool(combat.get("_owns_switch_mouse_capture")))
	_check("presentation hides the combat reticle while its gameplay clock is paused", not player.get_node("Combat/HUD/Reticle").is_visible_in_tree())
	_aim_button(false)
	await _steps(3)
	_check("real right-button release is recorded while the world is paused", paused and not Input.is_action_pressed("aim") and not bool(combat.get("_owns_switch_mouse_capture")))
	if death:
		player.call("receive_hit", 100000.0)
		_check("death cancellation keeps visible mouse with no combat capture", paused and source.is_current() and _director().call("debug_snapshot").state == &"dead" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not bool(combat.get("_owns_switch_mouse_capture")))
		await _cleanup()
		_check("releasing death ownership never restores the old aim capture", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not Input.is_action_pressed("aim"))
	else:
		await _await_presentation_end()
		_check("camera return restores visible mouse after aim was released during pause", not paused and source.is_current() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not bool(combat.get("_owns_switch_mouse_capture")))
		await _steps(3)
		_check("resumed combat leaves no capture or aiming state after the release", not Input.is_action_pressed("aim") and not bool(combat.get("is_aiming")) and not bool(combat.get("_owns_switch_mouse_capture")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
		await _cleanup()
	# Keep a failing negative control from contaminating the next isolated fixture.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _aim_button(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
	event.pressed = pressed
	event.position = root.get_visible_rect().size * 0.5
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _state_snapshot() -> Dictionary:
	var combat: Node = player.get_node("Combat")
	var ammo: RefCounted = combat.get("ammo")
	var player_state: Dictionary = {"position": player.global_position, "velocity": player.velocity,
		"stamina": player.get("stamina"), "stamina_timer": player.get("stamina_recovery_timer"),
		"reload": ammo.get("reload_progress"), "magazine": ammo.get("magazine_rounds"),
		"hit_time": player.get("_hit_slow_remaining")}
	var newborn: Array[Dictionary] = []
	var new_squad: Node = reinforcement.get_node_or_null("Squad")
	if new_squad != null:
		for child: Node in new_squad.get_children():
			if child is CharacterBody3D: newborn.append(_enemy_snapshot(child))
	var old_squad: Node = host.get_node_or_null("Old/Squad")
	return {"player": player_state, "old": _enemy_snapshot(old_enemy) if is_instance_valid(old_enemy) else {}, "new": newborn,
		"cooperation": _cooperation_time(), "wave_remaining": _wave_remaining("Delayed"), "flow_remaining": _ordinary_remaining(),
		"squad_frames": [old_squad.get("_advanced_frame") if old_squad != null else -1, new_squad.get("_advanced_frame") if new_squad != null else -1]}


func _enemy_snapshot(enemy: CharacterBody3D) -> Dictionary:
	var ai: Node = enemy.get_node("AI")
	var context: RefCounted = ai.get("context")
	return {"position": enemy.global_position, "velocity": enemy.velocity, "evidence": context.get("evidence_elapsed_seconds"),
		"decisions": ai.get("command_decision_count"), "utility": ai.get("utility_decision_count"),
		"hit_time": enemy.get("_hit_slow_remaining"), "cooldown": enemy.get("melee_cooldown"),
		"melee": enemy.get("melee_count"), "shots": enemy.get("shot_count")}


func _new_evidence_is_zero(members: Array) -> bool:
	if members.is_empty(): return false
	for member: Dictionary in members:
		if member.evidence != 0.0 or member.decisions != 0 or member.utility != 0: return false
	return true


func _cooperation_time() -> float:
	var cooperation: RefCounted = region.get("cooperation")
	return float(cooperation.get("elapsed"))


func _director() -> Node:
	return host.get("director") as Node


func _wave_remaining(label: String) -> float:
	var snapshot: Dictionary = host.call("debug_snapshot")
	for wave: Dictionary in snapshot.waves:
		if wave.name == label: return float(wave.remaining_seconds)
	return -1.0


func _rule_state(label: String) -> Dictionary:
	var snapshot: Dictionary = _director().call("debug_snapshot")
	for rule: Dictionary in snapshot.flows.rules:
		if rule.label == label: return rule
	return {}


func _ordinary_remaining() -> float:
	return float(_rule_state("ordinary_delay").get("remaining", 0.0))


func _await_wave(wave: Node, status: StringName) -> bool:
	for frame in 120:
		if host.call("wave_status", wave) == status: return true
		await _steps(1)
	print("DIAGNOSTIC ", host.call("debug_snapshot"))
	return false


func _await_presentation() -> bool:
	for frame in 120:
		if not public_observations.is_empty():
			_check("scene rule reaches real spawn and presentation", true)
			return true
		await _steps(1)
	_check("scene rule reaches real spawn and presentation", false)
	print("DIAGNOSTIC ", host.call("debug_snapshot"))
	return false


func _await_presentation_end() -> void:
	for frame in 120:
		if _director().call("debug_snapshot").presentation == 0: return
		await _steps(1)
	_check("presentation completes within its configured duration", false)


func _steps(count: int) -> void:
	for frame in count: await physics_frame
	await process_frame


func _cleanup() -> void:
	Input.action_release("move_right")
	region.queue_free()
	await _steps(4)
	_check("fixture teardown leaves no pause token or stuck tree", not paused and Pause.for_tree(self).snapshot().count == 0)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failures += 1
	print(("PASS " if passed else "FAIL ") + label)
