extends SceneTree

const Region = preload("res://scripts/world/shooting_range.gd")
const DirectorScene: PackedScene = preload("res://scenes/world/scene_director.tscn")
const Wave = preload("res://scripts/world/enemy_wave_definition.gd")
const Rule = preload("res://scripts/systems/scene_flow_rule.gd")
const Action = preload("res://scripts/systems/scene_flow_action.gd")
const Trigger = preload("res://scripts/systems/scene_event_trigger.gd")
const Pauses = preload("res://scripts/systems/scene_pause_coordinator.gd")
const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const CameraScene: PackedScene = preload("res://scenes/player/player_camera_rig.tscn")
const SquadScene: PackedScene = preload("res://scenes/world/squad.tscn")
const EnemyScene: PackedScene = preload("res://scenes/enemy/levels/lvl_1/melee.tscn")
const ShotScene: PackedScene = preload("res://scenes/cinematic/cinematic_shot_3d.tscn")

class CaptureHost extends Node3D:
	func capture_templates(_region: Node3D) -> void:
		pass

class PlayerSource extends Node3D:
	var is_in_dialogue := false
	var is_facing_npc := false
	var is_dead := false

	func set_dialogue_active(value: bool) -> void:
		is_in_dialogue = value

	func face_npc(_point: Vector3) -> void:
		pass

class HealthSource extends Node:
	signal died

class Events extends Node:
	signal reinforce

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("DebugSettings").set("enabled", false)
	await _test_wave_contract()
	await _test_action_contract()
	await _test_shot_waits_for_real_commit()
	await _test_cinematic_priority_over_legacy()
	await _test_blocked_and_failed_deployments_have_no_shot()
	await _test_busy_shot_does_not_roll_back_deployment()
	await _test_legacy_presentation_remains_compatible()
	await _test_flow_action_waits_for_shot()
	await _test_flow_action_busy_failure()
	_check(not paused and Pauses.for_tree(self).snapshot().count == 0,
		"all cinematic Wave/action fixtures release pause ownership")
	print("CINEMATIC WAVE TRIGGER: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _test_wave_contract() -> void:
	var wave: Node3D = Wave.new()
	wave.name = "Wave"
	var cinematic_property: Dictionary = {}
	var cinematic_group_index := -1
	var cinematic_property_index := -1
	var fields: Array[Dictionary] = wave.get_property_list()
	for index in fields.size():
		var field: Dictionary = fields[index]
		if field.name == &"出场镜头" and int(field.usage) & PROPERTY_USAGE_GROUP:
			cinematic_group_index = index
		if field.name == &"cinematic_shot_path":
			cinematic_property = field
			cinematic_property_index = index
	_check(not cinematic_property.is_empty()
			and cinematic_group_index >= 0
			and cinematic_property_index > cinematic_group_index
			and int(cinematic_property.usage) & PROPERTY_USAGE_EDITOR,
		"Wave exports cinematic_shot_path in the 出场镜头 group")
	_check("Node" in String(cinematic_property.get("hint_string", "")),
		"Wave cinematic_shot_path uses the Node picker metadata")

	var scene := Node3D.new()
	scene.name = "WarningFixture"
	root.add_child(scene)
	var host := CaptureHost.new()
	host.name = "SceneDirector"
	scene.add_child(host)
	host.add_child(wave)
	var shots := Node3D.new()
	shots.name = "CinematicShots"
	scene.add_child(shots)
	var shot: Node3D = ShotScene.instantiate()
	shot.name = "WaveShot"
	shots.add_child(shot)
	var marker := Marker3D.new()
	marker.name = "Marker"
	scene.add_child(marker)
	if not cinematic_property.is_empty():
		wave.set("cinematic_shot_path", ^"../../CinematicShots/WaveShot")
	var valid_warnings: PackedStringArray = wave.call("_get_configuration_warnings")
	_check(not _warnings_mention(valid_warnings, "CinematicShot3D"),
		"a valid Wave cinematic target has no type warning")
	if not cinematic_property.is_empty():
		wave.set("cinematic_shot_path", ^"../../Marker")
	var invalid_warnings: PackedStringArray = wave.call("_get_configuration_warnings")
	_check(_warnings_mention(invalid_warnings, "CinematicShot3D"),
		"a non-CinematicShot3D Wave target warns in the inspector")
	scene.free()
	await process_frame


func _test_action_contract() -> void:
	var kind: int = int(Action.Kind.get("PLAY_CINEMATIC_SHOT", -1))
	_check(Action.Kind.RUN_SCRIPT == 10 and kind == 11,
		"PLAY_CINEMATIC_SHOT is appended after all existing action values")
	var action: SceneFlowAction = Action.new()
	action.kind = kind
	var visible: Array[StringName] = []
	for field in [&"target_path", &"seconds", &"present_spawn", &"presentation_target_path",
			&"move_seconds", &"hold_seconds", &"return_seconds", &"camera_size",
			&"guide_pauses_world", &"scene_path", &"method", &"arguments",
			&"completed_trigger", &"cancel_method"]:
		if _editor_visible(action, field): visible.append(field)
	_check(visible == [&"target_path"],
		"PLAY_CINEMATIC_SHOT exposes only target_path among action-specific fields")


func _test_shot_waits_for_real_commit() -> void:
	var f := await _wave_fixture()
	f.wave.set("cinematic_shot_path", ^"../../CinematicShots/WaveShot")
	var before: Dictionary = f.controller.get_snapshot()
	var spawned_observations: Array[Dictionary] = []
	f.wave.spawned.connect(func() -> void:
		spawned_observations.append(f.controller.get_snapshot().duplicate())
	)
	_check(f.host.request_wave(f.wave), "the real Wave request is accepted")
	_check(before.phase == &"idle" and f.controller.get_snapshot().phase == &"idle",
		"Shot does not start before a real deployment")
	var started: bool = await _await_controller_started(f)
	_check(started, "Shot starts only after wave_committed")
	_check(spawned_observations.size() == 1
			and spawned_observations[0].phase != &"idle",
		"the Shot barrier exists before the public spawned notification")
	_check(spawned_observations.size() == 1
			and f.host.call("wave_status", f.wave) == &"active"
			and _deployed_enemies(f).size() > 0,
		"the accepted Shot follows a complete real deployment")
	await _await_controller_idle(f)
	await _dispose_wave_fixture(f)


func _test_cinematic_priority_over_legacy() -> void:
	var f := await _wave_fixture()
	f.wave.set("cinematic_shot_path", ^"../../CinematicShots/WaveShot")
	f.wave.set("show_spawn_presentation", true)
	f.wave.set("presentation_target_path", ^"../../CameraPoints/LegacyFocus")
	f.wave.set("presentation_hold_seconds", 5.0)
	_check(f.host.request_wave(f.wave), "priority fixture requests its Wave")
	_check(await _await_controller_started(f),
		"the new Shot path takes priority over legacy presentation fields")
	_check(f.director.call("debug_snapshot").presentation == 0,
		"legacy presentation does not start alongside the new Shot")
	await _await_controller_idle(f)
	_check(f.director.call("debug_snapshot").presentation == 0
			and f.region.get_node_or_null("PresentationCamera") == null,
		"the legacy presentation never plays after the new Shot completes")
	await _dispose_wave_fixture(f)


func _test_blocked_and_failed_deployments_have_no_shot() -> void:
	var f := await _wave_fixture(Vector3(4.0, 0.875, -4.0))
	f.wave.set("cinematic_shot_path", ^"../../CinematicShots/WaveShot")
	var spawned_count := [0]
	f.wave.spawned.connect(func() -> void: spawned_count[0] += 1)
	_check(f.host.request_wave(f.wave), "blocked Wave fixture requests real deployment")
	_check(await _await_wave_status(f, &"blocked"),
		"occupied spawn space enters the real blocked state")
	await _steps(4)
	_check(f.controller.get_snapshot().phase == &"idle"
			and not paused and spawned_count[0] == 0,
		"blocked deployment creates no Shot, pause, or public spawn")
	f.region.get_node("SpawnBlocker").queue_free()
	_check(await _await_controller_started(f),
		"retry starts the Shot only after deployment actually commits")
	await _await_controller_idle(f)
	await _dispose_wave_fixture(f)

	var failed := await _wave_fixture_without_squad()
	failed.wave.set("cinematic_shot_path", ^"../../CinematicShots/WaveShot")
	var failed_request: bool = failed.host.request_wave(failed.wave)
	await _steps(8)
	_check(not failed_request
			and failed.controller.get_snapshot().phase == &"idle"
			and not paused,
		"failed deployment reports no shot request and acquires no pause")
	await _dispose_wave_fixture(failed)


func _test_busy_shot_does_not_roll_back_deployment() -> void:
	var f := await _wave_fixture()
	f.blocker_shot.set("pause_world", false)
	f.blocker_shot.set("enter_seconds", 5.0)
	f.blocker_shot.set("hold_seconds", 5.0)
	f.blocker_shot.set("return_seconds", 5.0)
	var first: Dictionary = f.controller.play_shot(f.blocker_shot)
	_check(first.accepted, "busy fixture owns the single camera Shot slot")
	f.wave.set("cinematic_shot_path", ^"../../CinematicShots/WaveShot")
	var spawned_count := [0]
	f.wave.spawned.connect(func() -> void: spawned_count[0] += 1)
	_check(f.host.request_wave(f.wave), "busy fixture requests its real Wave")
	_check(await _await_wave_status(f, &"active"),
		"a busy cinematic slot still allows the Wave to deploy")
	await _steps(3)
	_check(f.controller.get_snapshot().request_id == first.request_id
			and f.controller.get_snapshot().shot == f.blocker_shot,
		"busy Shot rejection preserves the existing camera request")
	_check(spawned_count[0] == 1
			and f.host.call("wave_status", f.wave) == &"active"
			and not _deployed_enemies(f).is_empty() and not paused,
		"busy Shot skips only the camera and never rolls back deployed enemies")
	f.controller.cancel_shot(&"test_cleanup")
	await _steps(2)
	_check(f.host.call("wave_status", f.wave) == &"active"
			and not _deployed_enemies(f).is_empty(),
		"players remain deployed after the pre-existing Shot is cancelled")
	await _dispose_wave_fixture(f)


func _test_legacy_presentation_remains_compatible() -> void:
	var f := await _wave_fixture()
	f.wave.set("show_spawn_presentation", true)
	f.wave.set("presentation_target_path", ^"../../CameraPoints/LegacyFocus")
	f.wave.set("presentation_move_seconds", 0.05)
	f.wave.set("presentation_hold_seconds", 0.1)
	f.wave.set("presentation_return_seconds", 0.05)
	_check(f.host.request_wave(f.wave), "legacy Wave fixture requests real deployment")
	var started := false
	for _frame in 180:
		if int(f.director.call("debug_snapshot").presentation) != 0:
			started = true
			break
		await _steps(1)
	_check(started and f.controller.get_snapshot().phase == &"idle" and paused,
		"existing Wave presentation fields still start after a real deployment")
	f.director.call("skip_presentation")
	await _steps(2)
	_check(not paused and f.source.is_current()
			and f.host.call("wave_status", f.wave) == &"active",
		"legacy presentation cancellation preserves the deployed Wave")
	await _dispose_wave_fixture(f)


func _test_flow_action_waits_for_shot() -> void:
	var f := await _flow_fixture(true)
	f.events.reinforce.emit()
	_check(await _await_controller_started(f),
		"PLAY_CINEMATIC_SHOT starts the target Shot through SceneFlowRunner")
	_check(_rule_state(f, "cinematic").action == 0,
		"the flow does not advance while its Shot request is running")
	var completed := false
	for _frame in 240:
		if f.controller.get_snapshot().phase == &"idle" \
				and _rule_state(f, "cinematic").action == 1:
			completed = true
			break
		await _steps(1)
	_check(completed and f.source.is_current() and not paused,
		"the flow continues only after the Shot request completes")
	await _dispose_flow_fixture(f)


func _test_flow_action_busy_failure() -> void:
	var f := await _flow_fixture(true)
	f.blocker_shot.set("pause_world", false)
	f.blocker_shot.set("enter_seconds", 5.0)
	f.blocker_shot.set("hold_seconds", 5.0)
	f.blocker_shot.set("return_seconds", 5.0)
	var first: Dictionary = f.controller.play_shot(f.blocker_shot)
	f.events.reinforce.emit()
	await _steps(8)
	var flow_errors: PackedStringArray = f.director.call("debug_snapshot").flows.errors
	_check(first.accepted and _strings_mention(flow_errors, "busy"),
		"a busy PLAY_CINEMATIC_SHOT uses the action failure path")
	_check(f.controller.get_snapshot().request_id == first.request_id
			and f.controller.get_snapshot().shot == f.blocker_shot,
		"a failed branch Shot request cannot displace the active Shot")
	f.controller.cancel_shot(&"test_cleanup")
	await _dispose_flow_fixture(f)


func _wave_fixture(blocker_position: Variant = null) -> Dictionary:
	var region: Node3D = Region.new()
	region.name = "CinematicWaveRegion"
	region.position = Vector3(11.0, 0.0, 7.0)
	_add_region_environment(region)
	var player: CharacterBody3D = PlayerScene.instantiate() as CharacterBody3D
	player.name = "Player"
	player.position = Vector3(0.0, 0.0, 7.0)
	player.get_node("Health").set("debug_mode", false)
	region.add_child(player)
	var source: Camera3D = CameraScene.instantiate() as Camera3D
	source.name = "Camera3D"
	region.add_child(source)
	var events := Events.new()
	events.name = "Events"
	region.add_child(events)
	var marker_root := Node3D.new()
	marker_root.name = "CameraPoints"
	region.add_child(marker_root)
	var legacy_focus := Marker3D.new()
	legacy_focus.name = "LegacyFocus"
	legacy_focus.position = Vector3(-4.0, 0.0, -5.0)
	marker_root.add_child(legacy_focus)
	var shots := Node3D.new()
	shots.name = "CinematicShots"
	region.add_child(shots)
	var wave_shot: Camera3D = ShotScene.instantiate() as Camera3D
	wave_shot.name = "WaveShot"
	wave_shot.position = Vector3(8.0, 5.0, -4.0)
	wave_shot.rotation_degrees = Vector3(-48.0, 25.0, 0.0)
	wave_shot.set("enter_seconds", 0.08)
	wave_shot.set("hold_seconds", 0.12)
	wave_shot.set("return_seconds", 0.08)
	shots.add_child(wave_shot)
	var blocker_shot: Camera3D = ShotScene.instantiate() as Camera3D
	blocker_shot.name = "BlockerShot"
	blocker_shot.position = Vector3(-6.0, 5.0, 3.0)
	blocker_shot.rotation_degrees = Vector3(-45.0, -20.0, 0.0)
	shots.add_child(blocker_shot)
	var host: Node3D = DirectorScene.instantiate() as Node3D
	host.name = "SceneDirector"
	host.set("guide_path", NodePath())
	host.set("result_view_path", NodePath())
	host.set("complete_when_all_waves_cleared", false)
	host.set("spawn_retry_seconds", 0.05)
	host.set("scene_rules", [])
	region.add_child(host)
	var wave: Node3D = _add_real_wave(host, "Reinforcement", [Vector3(4.0, 0.0, -4.0), Vector3(6.0, 0.0, -4.0)])
	if blocker_position != null:
		var blocker := CharacterBody3D.new()
		blocker.name = "SpawnBlocker"
		blocker.position = blocker_position
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.75
		shape.shape = capsule
		blocker.add_child(shape)
		region.add_child(blocker)
	root.add_child(region)
	current_scene = region
	await _steps(4)
	source.make_current()
	var host_director: Node = host.get("director")
	return {
		"region": region,
		"host": host,
		"director": host_director,
		"controller": host.get_node("CinematicCameraController"),
		"wave": wave,
		"wave_shot": wave_shot,
		"blocker_shot": blocker_shot,
		"player": player,
		"source": source,
	}


func _wave_fixture_without_squad() -> Dictionary:
	var region: Node3D = Region.new()
	region.name = "FailedCinematicWaveRegion"
	_add_region_environment(region)
	var player: CharacterBody3D = PlayerScene.instantiate() as CharacterBody3D
	player.name = "Player"
	player.position = Vector3(0.0, 0.0, 7.0)
	player.get_node("Health").set("debug_mode", false)
	region.add_child(player)
	var source: Camera3D = CameraScene.instantiate() as Camera3D
	source.name = "Camera3D"
	region.add_child(source)
	var events := Events.new()
	events.name = "Events"
	region.add_child(events)
	var shots := Node3D.new()
	shots.name = "CinematicShots"
	region.add_child(shots)
	var shot: Camera3D = ShotScene.instantiate() as Camera3D
	shot.name = "WaveShot"
	shots.add_child(shot)
	var host: Node3D = DirectorScene.instantiate() as Node3D
	host.name = "SceneDirector"
	host.set("guide_path", NodePath())
	host.set("result_view_path", NodePath())
	host.set("complete_when_all_waves_cleared", false)
	host.set("scene_rules", [])
	region.add_child(host)
	var wave: Node3D = Wave.new()
	wave.name = "Failed"
	wave.set("start_mode", Wave.StartMode.REQUEST)
	host.add_child(wave)
	root.add_child(region)
	current_scene = region
	await _steps(4)
	source.make_current()
	return {
		"region": region,
		"host": host,
		"director": host.get("director"),
		"controller": host.get_node("CinematicCameraController"),
		"wave": wave,
		"source": source,
	}


func _flow_fixture(triggered: bool) -> Dictionary:
	var scene := Node3D.new()
	scene.name = "CinematicFlowFixture"
	root.add_child(scene)
	var source: Camera3D = Camera3D.new()
	source.name = "PlayerCamera"
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.size = 12.0
	source.position = Vector3(0.0, 8.0, 6.0)
	source.rotation_degrees.x = -55.0
	scene.add_child(source)
	var player := PlayerSource.new()
	player.name = "Player"
	scene.add_child(player)
	var health := HealthSource.new()
	health.name = "Health"
	player.add_child(health)
	var events := Events.new()
	events.name = "Events"
	scene.add_child(events)
	var shots := Node3D.new()
	shots.name = "CinematicShots"
	scene.add_child(shots)
	var action_shot: Camera3D = ShotScene.instantiate() as Camera3D
	action_shot.name = "ActionShot"
	action_shot.position = Vector3(8.0, 5.0, -4.0)
	action_shot.rotation_degrees = Vector3(-48.0, 25.0, 0.0)
	action_shot.set("enter_seconds", 0.08)
	action_shot.set("hold_seconds", 0.12)
	action_shot.set("return_seconds", 0.08)
	shots.add_child(action_shot)
	var blocker_shot: Camera3D = ShotScene.instantiate() as Camera3D
	blocker_shot.name = "BlockerShot"
	shots.add_child(blocker_shot)
	var action: SceneFlowAction = Action.new()
	action.kind = int(Action.Kind.get("PLAY_CINEMATIC_SHOT", -1))
	action.target_path = ^"../CinematicShots/ActionShot"
	var rule: SceneFlowRule = Rule.new()
	rule.label = "cinematic"
	rule.scope = Rule.Scope.REGION
	rule.actions.append(action)
	if triggered:
		var trigger: SceneEventTrigger = Trigger.new()
		trigger.source_path = ^"../Events"
		trigger.signal_name = &"reinforce"
		rule.triggers.append(trigger)
	var rules: Array[SceneFlowRule] = [rule]
	var host: Node3D = DirectorScene.instantiate() as Node3D
	host.name = "SceneDirector"
	host.set("guide_path", NodePath())
	host.set("result_view_path", NodePath())
	host.set("scene_rules", rules)
	scene.add_child(host)
	await _steps(3)
	source.make_current()
	return {
		"scene": scene,
		"host": host,
		"director": host.get("director"),
		"controller": host.get_node("CinematicCameraController"),
		"action_shot": action_shot,
		"blocker_shot": blocker_shot,
		"events": events,
		"source": source,
	}


func _add_region_environment(region: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(24.0, 0.2, 24.0)
	floor_shape.shape = floor_box
	floor_body.position.y = -0.1
	floor_body.add_child(floor_shape)
	region.add_child(floor_body)
	var navigation := NavigationRegion3D.new()
	navigation.name = "NavigationRegion3D"
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([
		Vector3(-11, 0, -11), Vector3(11, 0, -11),
		Vector3(11, 0, 11), Vector3(-11, 0, 11),
	])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	region.add_child(navigation)
	var zone := Area3D.new()
	zone.name = "CombatZone"
	zone.collision_layer = 0
	var zone_shape := CollisionShape3D.new()
	zone_shape.name = "CollisionShape3D"
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(22.0, 4.0, 22.0)
	zone_shape.shape = zone_box
	zone_shape.position.y = 1.0
	zone.add_child(zone_shape)
	region.add_child(zone)


func _add_real_wave(host: Node3D, label: String, positions: Array[Vector3]) -> Node3D:
	var wave: Node3D = Wave.new()
	wave.name = label
	wave.set("start_mode", Wave.StartMode.REQUEST)
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


func _deployed_enemies(f: Dictionary) -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	var squad: Node = f.wave.get_node_or_null("Squad")
	if squad == null: return result
	for child in squad.get_children():
		if child is CharacterBody3D: result.append(child)
	return result


func _rule_state(f: Dictionary, label: String) -> Dictionary:
	var snapshot: Dictionary = f.director.call("debug_snapshot")
	for rule: Dictionary in snapshot.flows.rules:
		if rule.label == label: return rule
	return {}


func _await_controller_started(f: Dictionary) -> bool:
	for _frame in 180:
		if f.controller.get_snapshot().phase != &"idle": return true
		await _steps(1)
	print("DIAGNOSTIC ", f.host.call("debug_snapshot"))
	return false


func _await_controller_idle(f: Dictionary) -> bool:
	for _frame in 240:
		if f.controller.get_snapshot().phase == &"idle": return true
		await _steps(1)
	return false


func _await_wave_status(f: Dictionary, status: StringName) -> bool:
	for _frame in 180:
		if f.host.call("wave_status", f.wave) == status: return true
		await _steps(1)
	print("DIAGNOSTIC ", f.host.call("debug_snapshot"))
	return false


func _steps(count: int) -> void:
	for _frame in count:
		await physics_frame
	await process_frame


func _dispose_wave_fixture(f: Dictionary) -> void:
	if f.controller.get_snapshot().phase != &"idle":
		f.controller.cancel_shot(&"test_cleanup")
	f.region.queue_free()
	await _steps(4)
	_check(not paused and Pauses.for_tree(self).snapshot().count == 0,
		"cinematic Wave fixture releases pause ownership")


func _dispose_flow_fixture(f: Dictionary) -> void:
	if f.controller.get_snapshot().phase != &"idle":
		f.controller.cancel_shot(&"test_cleanup")
	f.scene.queue_free()
	await _steps(3)
	_check(not paused and Pauses.for_tree(self).snapshot().count == 0,
		"cinematic action fixture releases pause ownership")


func _editor_visible(action: SceneFlowAction, field: StringName) -> bool:
	var property := {"name": field, "usage": PROPERTY_USAGE_DEFAULT}
	action._validate_property(property)
	return bool(int(property.usage) & PROPERTY_USAGE_EDITOR)


func _warnings_mention(warnings: PackedStringArray, text: String) -> bool:
	for warning in warnings:
		if text in warning: return true
	return false


func _strings_mention(values: PackedStringArray, text: String) -> bool:
	for value in values:
		if text in value: return true
	return false


func _check(passed: bool, label: String) -> void:
	checks += 1
	if not passed: failures += 1
	print(("PASS " if passed else "FAIL ") + label)
