extends SceneTree

const Runtime = preload("res://scripts/world/enemy_wave_runtime.gd")
const Wave = preload("res://scripts/world/enemy_wave_definition.gd")
const Trigger = preload("res://scripts/systems/scene_event_trigger.gd")
const Filter = preload("res://scripts/systems/scene_event_filter.gd")
const Subscription = preload("res://scripts/systems/scene_event_subscription.gd")
const EventNode = preload("res://scripts/systems/scene_event.gd")
const SquadScene = preload("res://scenes/world/squad.tscn")
const EnemyScene = preload("res://scenes/enemy/levels/lvl_1/melee.tscn")

# Independent facade: the production host can be integrated concurrently.
class Host extends Node3D:
	var auto_start_on_enter := false
	var spawn_retry_seconds := 0.05
	var runtime = Runtime.new(self)
	func capture_templates(region: Node3D) -> void: runtime.capture_templates(region)
	func start_encounter() -> void: runtime.start_encounter()
	func advance_from_region(delta: float) -> void: runtime.advance_from_region(delta)
	func reset_encounter() -> void: runtime.reset_encounter()
	func owns_runtime_enemy(enemy: Node) -> bool: return runtime.owns_runtime_enemy(enemy)
	func _exit_tree() -> void: runtime.release()

class FixtureRegion extends "res://scripts/world/shooting_range.gd":
	func _enter_tree() -> void:
		ammo_drops.bind(self)
		for child in get_children():
			if child is Host: _enemy_waves = child
		_enemy_waves.capture_templates(self)

class InvalidEvent extends Node:
	signal triggered(value: int)

class Source extends Node:
	signal pulse
	signal item(item_id: StringName, title: String, total: int)
	signal flag(flag_id: StringName, enabled: bool)
	signal body(body: Node)
	signal loose(value)
	signal four(a, b, c, d)
	signal five(a, b, c, d, e)
	signal six(a, b, c, d, e, f)
	signal seven(a, b, c, d, e, f, g)
	signal eight(a, b, c, d, e, f, g, h)
	signal nine(a, b, c, d, e, f, g, h, i)

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("DebugSettings").enabled = false
	await _subscriptions()
	_configuration_roundtrip()
	await _event_node_configuration()
	await _relay_prerequisites()
	await _independent_events()
	await _blocked_candidates()
	await _reset_and_sources()
	await _event_boundary_and_reentrancy()
	await _lifecycle_guards()
	await _dependencies()
	await _sequence_and_empty()
	print("ENEMY WAVE EVENTS: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _trigger(path: String, signal_id: StringName) -> Resource:
	var trigger := Trigger.new()
	trigger.source_path = NodePath(path)
	trigger.signal_name = signal_id
	return trigger

func _subscriptions() -> void:
	var source := Source.new()
	source.name = "Source"
	root.add_child(source)
	var owner := Node.new()
	source.add_child(owner)
	var subscriptions := Subscription.new()
	var counts := {"value": 0}
	var callback := func(): counts.value += 1
	for signal_id in [&"pulse", &"loose", &"flag", &"item", &"four", &"five", &"six", &"seven", &"eight"]:
		check(subscriptions.connect_trigger(owner, _trigger("..", signal_id), callback).is_empty(), "connect exact arity: %s" % signal_id)
	source.pulse.emit()
	source.loose.emit(1)
	source.flag.emit(&"door", true)
	source.item.emit(&"key", "Key", 1)
	source.four.emit(1, 2, 3, 4)
	source.five.emit(1, 2, 3, 4, 5)
	source.six.emit(1, 2, 3, 4, 5, 6)
	source.seven.emit(1, 2, 3, 4, 5, 6, 7)
	source.eight.emit(1, 2, 3, 4, 5, 6, 7, 8)
	check(counts.value == 9, "all 0..8 adapters call the zero-argument callback")
	check(not subscriptions.connect_trigger(owner, _trigger("..", &"nine"), callback).is_empty(), "unsupported arity diagnosed before connection")
	check(not subscriptions.connect_trigger(owner, _trigger("Missing", &"pulse"), callback).is_empty(), "missing source diagnosed")
	check(not subscriptions.connect_trigger(owner, _trigger("..", &"missing"), callback).is_empty(), "missing signal diagnosed")
	subscriptions.clear()
	var trigger := _trigger("..", &"item")
	var filter := Filter.new()
	filter.string_name_value = &"key"
	trigger.filters.append(filter)
	check(subscriptions.connect_trigger(owner, trigger, callback).is_empty(), "typed item filter accepted")
	source.item.emit(&"coin", "Coin", 1)
	source.item.emit(&"key", "Key", 1)
	check(counts.value == 10, "item ID filters unrelated pickups")
	filter.string_name_value = &"coin"
	source.item.emit(&"key", "Key", 1)
	check(counts.value == 11, "subscription owns frozen configuration, not shared mutable state")
	filter.value_type = Filter.ValueType.STRING
	check(not subscriptions.connect_trigger(owner, trigger, callback).is_empty(), "String and StringName mismatches rejected from metadata")
	filter.parameter_index = 3
	check(not subscriptions.connect_trigger(owner, trigger, callback).is_empty(), "out of range filter index rejected")
	subscriptions.clear()
	var node_filter := Filter.new()
	node_filter.operator = Filter.Operator.NODE_IN_GROUP
	var body_trigger := _trigger("..", &"body")
	body_trigger.filters.append(node_filter)
	check(subscriptions.connect_trigger(owner, body_trigger, callback).is_empty(), "Node group filter connects")
	source.body.emit(owner)
	owner.add_to_group("player")
	source.body.emit(owner)
	check(counts.value == 12, "body must belong to player group")
	subscriptions.clear()
	var typed := Filter.new()
	typed.value_type = Filter.ValueType.BOOL
	typed.parameter_index = 1
	var flag_trigger := _trigger("..", &"flag")
	flag_trigger.filters.append(typed)
	check(subscriptions.connect_trigger(owner, flag_trigger, callback).is_empty(), "boolean filter connects")
	source.flag.emit(&"door", false)
	source.flag.emit(&"door", true)
	check(counts.value == 13, "false does not satisfy true")
	var old_adapter: Callable = source.get_signal_connection_list(&"flag")[0].callable
	subscriptions.clear()
	old_adapter.call(&"door", true)
	source.flag.emit(&"door", true)
	check(counts.value == 13, "disconnected and retained old adapters cannot fire after clear")
	source.free()
	await process_frame

func _configuration_roundtrip() -> void:
	var container := Node3D.new()
	var first := Wave.new()
	first.name = "First"
	container.add_child(first)
	first.owner = container
	var second := Wave.new()
	second.name = "Second"
	second.start_mode = Wave.StartMode.EVENTS
	second.trigger_combination = Wave.TriggerCombination.ALL
	second.triggers.append(_trigger("../First", &"cleared"))
	var filter := Filter.new()
	filter.value_type = Filter.ValueType.INT
	filter.int_value = 7
	var extra := _trigger("../../Source", &"loose")
	extra.filters.append(filter)
	second.triggers.append(extra)
	second.event_nodes.assign([NodePath("../../SceneEvents/Entered")])
	container.add_child(second)
	second.owner = container
	var copied := second.duplicate()
	copied.name = "Copy"
	container.add_child(copied)
	copied.owner = container
	container.move_child(first, 2)
	var packed := PackedScene.new()
	check(packed.pack(container) == OK, "event resource configuration packs without altering user scenes")
	var reopened := packed.instantiate()
	var reopened_wave = reopened.get_node("Second")
	check(reopened_wave.start_mode == Wave.StartMode.EVENTS and reopened_wave.trigger_combination == Wave.TriggerCombination.ALL and reopened_wave.triggers[1].filters[0].int_value == 7, "packed scene restores typed nested event resource fields")
	check(reopened.get_node("Copy").get_node(reopened_wave.triggers[0].source_path) == reopened.get_node("First"), "copy and reorder keep explicit source node identity")
	check(reopened_wave.event_nodes == [NodePath("../../SceneEvents/Entered")] and reopened.get_node("Copy").event_nodes == reopened_wave.event_nodes, "event node paths survive scene packing and Wave duplication")
	container.free()
	reopened.free()

func _fixture(wave_count: int = 3) -> Node3D:
	var region := FixtureRegion.new()
	region.name = "EventRegion"
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(24, 0.2, 24)
	floor_body.position.y = -0.1
	floor_body.add_child(floor_shape)
	region.add_child(floor_body)
	var navigation := NavigationRegion3D.new()
	navigation.name = "NavigationRegion3D"
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-11, 0, -11), Vector3(11, 0, -11), Vector3(11, 0, 11), Vector3(-11, 0, 11)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	region.add_child(navigation)
	var zone := Area3D.new()
	zone.name = "CombatZone"
	zone.collision_layer = 0
	var zone_shape := CollisionShape3D.new()
	zone_shape.name = "CollisionShape3D"
	zone_shape.shape = BoxShape3D.new()
	zone_shape.shape.size = Vector3(22, 4, 22)
	zone_shape.position.y = 1.0
	zone.add_child(zone_shape)
	region.add_child(zone)
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0, 7)
	region.add_child(player)
	var host := Host.new()
	host.name = "EnemyWaves"
	region.add_child(host)
	for index in wave_count:
		var wave := Wave.new()
		wave.name = "Wave%d" % (index + 1)
		wave.start_mode = Wave.StartMode.EVENTS
		wave.search_on_spawn = false
		wave.triggers.append(_trigger("../../Source", &"pulse"))
		host.add_child(wave)
		var squad = SquadScene.instantiate()
		wave.add_child(squad)
		var enemy = EnemyScene.instantiate()
		enemy.name = "Enemy"
		enemy.position = Vector3(-6 + 6 * index, 0, -4)
		enemy.get_node("NavigationAgent3D").path_height_offset = 0.0
		enemy.get_node("Training").profile = enemy.get_node("Training").profile.duplicate(true)
		enemy.get_node("Training").profile.selected_tactics.clear()
		squad.add_child(enemy)
	var source := Source.new()
	source.name = "Source"
	region.add_child(source)
	return region

func _mount(region: Node3D) -> void:
	root.add_child(region)
	region.get_node("Player").set_physics_process(false)
	region.get_node("Player/Health").debug_invincible = true
	var runtime = region._enemy_waves.runtime
	runtime.wave_started.connect(func(_index):
		for enemy in region.enemies:
			enemy.set_physics_process(false)
			enemy.get_node("AI").set_physics_process(false)
	)
	runtime.prepare_events()
	await _settle()

func _settle(frames: int = 4) -> void:
	for frame in frames: await physics_frame
	await process_frame

func _await_status(runtime: RefCounted, wave: Node, status: StringName, frames: int = 60) -> bool:
	for frame in frames:
		if runtime.wave_status(wave) == status: return true
		if runtime.debug_snapshot().state == "ERROR":
			print("DIAGNOSTIC ", runtime.debug_snapshot())
			return false
		await _settle(1)
	return runtime.wave_status(wave) == status

func _independent_events() -> void:
	var region := _fixture()
	var host = region.get_node("EnemyWaves")
	var first = host.get_node("Wave1")
	var second = host.get_node("Wave2")
	var third = host.get_node("Wave3")
	first.start_mode = Wave.StartMode.REQUEST
	second.trigger_combination = Wave.TriggerCombination.ALL
	second.triggers.append(_trigger("../../Source", &"flag"))
	second.start_delay_seconds = 0.06
	await _mount(region)
	var runtime = host.runtime
	var source = region.get_node("Source")
	var notifications: Array[String] = []
	var frames: Array[int] = []
	runtime.wave_committed.connect(func(_wave, _focus):
		notifications.append("committed")
		paused = true
	)
	third.spawned.connect(func(): notifications.append("spawned"))
	runtime.wave_started.connect(func(index):
		frames.append(Engine.get_physics_frames())
		if index == 3: notifications.append("started_paused" if paused else "started_unpaused")
	)
	source.pulse.emit()
	source.pulse.emit()
	check(runtime.wave_status(third) == &"ready" and runtime.wave_status(second) == &"waiting", "prestart events latch independently, ALL requires every input")
	check(region.enemies.is_empty(), "event callback cannot spawn or bypass encounter start")
	runtime.start_encounter()
	check(await _await_status(runtime, third, &"active"), "later event wave starts while earlier request wave remains waiting")
	check(notifications == ["committed", "spawned", "started_paused"], "commit barrier precedes stable and public notifications")
	check(runtime.wave_focus(third) is Vector3 and runtime.wave_focus(first) == null, "focus reports only committed deployment")
	source.flag.emit(&"open", true)
	await _settle()
	check(runtime.wave_status(second) == &"ready", "events received during presentation pause are retained")
	paused = false
	check(await _await_status(runtime, second, &"active"), "ALL latches across frames and starts after unpause")
	paused = false
	check(runtime.request_wave(first) and runtime.request_wave(first), "explicit wave requests are idempotent")
	check(await _await_status(runtime, first, &"active"), "requested first wave starts independently")
	paused = false
	check(frames.size() == 3 and frames[0] != frames[1] and frames[1] != frames[2], "at most one successful wave commit in each physics step")
	for enemy in region.enemies.duplicate(): enemy.receive_hit(10000.0)
	await _settle(8)
	check(runtime.debug_snapshot().state == "COMPLETED", "only all spawned and cleared waves complete the encounter")
	check(runtime.wave_status(third) == &"cleared" and is_instance_valid(host.get_node("Wave3")), "Wave definition survives runtime teardown")
	region.queue_free()
	await _settle()

func _blocked_candidates() -> void:
	var region := _fixture(2)
	var host = region.get_node("EnemyWaves")
	var first = host.get_node("Wave1")
	var second = host.get_node("Wave2")
	var blocker := CharacterBody3D.new()
	blocker.position = Vector3(-6, 0.9, -4)
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.height = 1.75
	shape.shape.radius = 0.4
	blocker.add_child(shape)
	region.add_child(blocker)
	await _mount(region)
	var runtime = host.runtime
	region.get_node("Source").pulse.emit()
	runtime.start_encounter()
	check(await _await_status(runtime, second, &"active") and runtime.wave_status(first) == &"blocked", "occupied earlier spawn does not block independent later wave")
	check(runtime._pending.size() == 1 and runtime.debug_snapshot().alive == 1, "blocked wave remains outside tree with compatibility pending view")
	blocker.position = Vector3(8, 0.9, 8)
	check(await _await_status(runtime, first, &"active"), "blocked wave retries original position after it clears")
	region.queue_free()
	await _settle()

func _reset_and_sources() -> void:
	var region := _fixture(1)
	var host = region.get_node("EnemyWaves")
	var wave = host.get_node("Wave1")
	wave.start_delay_seconds = 0.1
	await _mount(region)
	var runtime = host.runtime
	var source = region.get_node("Source")
	# Retain the old subscription like an in-flight callback owner would; the
	# generation guard must still reject it even while that owner remains alive.
	var old_subscription: RefCounted = runtime._event_links[0].subscription
	var old_adapter: Callable = source.get_signal_connection_list(&"pulse")[0].callable
	source.pulse.emit()
	runtime.start_encounter()
	await _settle(2)
	runtime.reset_encounter()
	runtime.start_encounter()
	old_adapter.call()
	check(is_instance_valid(old_subscription), "in-flight old subscription can remain alive without advancing reset state")
	await _settle(10)
	check(runtime.wave_status(wave) == &"waiting" and region.enemies.is_empty(), "reset clears prestart facts, delay and stale generation callback")
	source.pulse.emit()
	check(await _await_status(runtime, wave, &"active"), "reset reconnects a fresh subscription generation")
	runtime.reset_encounter()
	runtime.start_encounter()
	source.queue_free()
	await _settle()
	check(runtime.debug_snapshot().state == "ERROR" and "disappeared" in runtime.debug_snapshot().reason, "required source loss gives an explicit diagnostic")
	region.queue_free()
	await _settle()

func _dependencies() -> void:
	for mode in ["self", "self_spawn", "cycle", "any_entry", "all_entry", "node_any_entry", "node_all_entry"]:
		var region := _fixture(2)
		var host = region.get_node("EnemyWaves")
		var first = host.get_node("Wave1")
		var second = host.get_node("Wave2")
		first.triggers.assign([_trigger("." if mode.begins_with("self") else "../Wave2", &"spawned" if mode == "self_spawn" else &"cleared")])
		second.triggers.assign([_trigger("../Wave1", &"cleared")])
		if mode.begins_with("node_"):
			var event := EventNode.new()
			event.name = "EntryEvent"
			region.add_child(event)
			first.event_nodes.assign([NodePath("../../EntryEvent")])
		elif mode.ends_with("entry"):
			first.triggers.append(_trigger("../../Source", &"pulse"))
		if mode in ["all_entry", "node_all_entry"]: first.trigger_combination = Wave.TriggerCombination.ALL
		var valid_entry: bool = mode in ["any_entry", "node_any_entry"]
		var warnings: PackedStringArray = host.runtime.configuration_warnings(region)
		check(warnings.is_empty() == valid_entry, "authoring warnings use the same prerequisite rules: %s" % mode)
		await _mount(region)
		var runtime = host.runtime
		check((runtime.debug_snapshot().state != "ERROR") == valid_entry, "provable prerequisite validation: %s" % mode)
		if valid_entry:
			runtime.start_encounter()
			if mode == "node_any_entry": region.get_node("EntryEvent").trigger()
			else: region.get_node("Source").pulse.emit()
			check(await _await_status(runtime, first, &"active"), "ANY external entry can break a dependency cycle")
			for enemy in region.enemies.duplicate(): enemy.receive_hit(10000.0)
			check(await _await_status(runtime, second, &"active"), "stable Wave.cleared unlocks explicit dependency")
		region.queue_free()
		await _settle()

func _event_node_configuration() -> void:
	var region := _fixture(2)
	var host = region.get_node("EnemyWaves")
	host.name = "SceneDirector"
	var first = host.get_node("Wave1")
	var second = host.get_node("Wave2")
	var events := Node.new()
	events.name = "SceneEvents"
	region.add_child(events)
	var manual := EventNode.new()
	manual.name = "Manual"
	events.add_child(manual)
	var filtered := EventNode.new()
	filtered.name = "FlagEnabled"
	filtered.source_path = NodePath("../../Source")
	filtered.signal_name = &"flag"
	var filter := Filter.new()
	filter.parameter_index = 1
	filter.value_type = Filter.ValueType.BOOL
	filtered.filters.append(filter)
	events.add_child(filtered)
	first.triggers.clear()
	first.event_nodes.assign([NodePath("../../SceneEvents/Manual")])
	second.event_nodes.assign([NodePath("../../SceneEvents/FlagEnabled")])
	second.trigger_combination = Wave.TriggerCombination.ALL
	check(first.deployment_configuration().errors.is_empty() and first.triggers.is_empty(), "EVENTS accepts event_nodes without legacy trigger resources")
	var merged: Array = second.configured_triggers()
	check(merged.size() == 2 and merged[0] == second.triggers[0] and merged[1].signal_name == &"triggered" and second.triggers.size() == 1, "event nodes compile after legacy triggers without modifying configured resources")
	check(host.runtime.configuration_warnings(region).is_empty(), "renamed SceneDirector validates Wave-relative event node paths")
	var fields: Array[Dictionary] = first.get_property_list()
	check(fields.any(func(field): return field.name == &"event_nodes" and field.type == TYPE_ARRAY and "Node" in field.hint_string), "event_nodes exports a typed NodePath array with node-picker metadata")
	await _mount(region)
	var runtime = host.runtime
	var source = region.get_node("Source")
	source.pulse.emit()
	source.flag.emit(&"open", false)
	manual.trigger()
	check(runtime.wave_status(first) == &"ready" and runtime.wave_status(second) == &"waiting", "event node callbacks latch before encounter and still respect source filters")
	runtime.start_encounter()
	check(await _await_status(runtime, first, &"active"), "manual SceneEvent triggers wave under renamed SceneDirector root")
	source.flag.emit(&"open", true)
	check(await _await_status(runtime, second, &"active"), "ALL combines a legacy event with the actual SceneEvent filtered output")
	region.queue_free()
	await _settle()
	for problem in ["missing", "empty", "signal", "arity"]:
		var invalid_region := _fixture(1)
		var invalid_host = invalid_region.get_node("EnemyWaves")
		var wave = invalid_host.get_node("Wave1")
		wave.triggers.clear()
		var path := NodePath("../../Missing")
		if problem == "empty": path = NodePath()
		elif problem == "signal": path = NodePath("../../Source")
		elif problem == "arity":
			var invalid := InvalidEvent.new()
			invalid.name = "InvalidEvent"
			invalid_region.add_child(invalid)
			path = NodePath("../../InvalidEvent")
		wave.event_nodes.assign([path])
		check(not wave._get_configuration_warnings().is_empty() and not invalid_host.runtime.configuration_warnings(invalid_region).is_empty(), "Wave and director authoring diagnostics agree: event node %s" % problem)
		await _mount(invalid_region)
		check(invalid_host.runtime.debug_snapshot().state == "ERROR" and invalid_region.enemies.is_empty(), "runtime rejects invalid event node before any spawn: %s" % problem)
		invalid_region.queue_free()
		await _settle()

func _event_boundary_and_reentrancy() -> void:
	var region := _fixture(2)
	var host = region.get_node("EnemyWaves")
	var first = host.get_node("Wave1")
	var second = host.get_node("Wave2")
	second.triggers.assign([_trigger("../Wave1", &"spawned")])
	region.get_node("Source").pulse.emit()
	region.get_node("Player").position.x = 30
	await _mount(region)
	var runtime = host.runtime
	runtime.start_encounter()
	await _settle()

	check(runtime.wave_status(first) == &"waiting", "signals before subscription are not invented as historical events")
	region.get_node("Source").pulse.emit()
	await _settle()
	check(runtime.wave_status(first) == &"ready" and region.enemies.is_empty(), "pre-entry facts cannot bypass original region eligibility")
	var spawned_frames: Array[int] = []
	runtime.wave_started.connect(func(_index): spawned_frames.append(Engine.get_physics_frames()))
	region.get_node("Player").position.x = 0
	check(await _await_status(runtime, second, &"active"), "entering the region releases retained event and stable spawned chain")
	check(spawned_frames.size() == 2 and spawned_frames[0] < spawned_frames[1], "zero-delay spawned event chain is deferred to another physics step")
	runtime.reset_encounter()
	runtime.start_encounter()
	var public_signals := [0]
	runtime.wave_started.connect(func(_index): public_signals[0] += 1)
	var reset_at_commit := func(_wave, _focus): runtime.reset_encounter()
	runtime.wave_committed.connect(reset_at_commit, CONNECT_ONE_SHOT)
	region.get_node("Source").pulse.emit()
	await _settle(10)
	check(public_signals[0] == 0 and runtime.wave_status(first) == &"waiting" and region.enemies.is_empty(), "synchronous reset at commit cancels stale public notifications and spawned members")
	region.queue_free()
	await _settle()

func _relay_prerequisites() -> void:
	# SceneEvent's trigger() remains a legal external entry when a source is bound.
	# Automatic-only cycles are actionable advisories, not fatal configuration
	# errors. Direct Wave self-spawn/self-clear remains provably invalid above.
	for mode in ["self_spawn", "self_clear", "cross_clear", "chain_spawn", "any_entry"]:
		var region := _fixture(2 if mode == "cross_clear" else 1)
		var host = region.get_node("EnemyWaves")
		var wave = host.get_node("Wave1")
		wave.triggers.clear()
		wave.event_nodes.assign([NodePath("../../Relay")])
		var relay := EventNode.new()
		relay.name = "Relay"
		relay.source_path = NodePath("../EnemyWaves/Wave2" if mode == "cross_clear" else "../EnemyWaves/Wave1")
		relay.signal_name = &"cleared" if mode.ends_with("clear") else &"spawned"
		region.add_child(relay)
		if mode == "cross_clear":
			host.get_node("Wave2").triggers.assign([_trigger("../Wave1", &"cleared")])
		if mode == "chain_spawn":
			var intermediary := EventNode.new()
			intermediary.name = "Intermediary"
			intermediary.source_path = NodePath("../EnemyWaves/Wave1")
			intermediary.signal_name = &"spawned"
			region.add_child(intermediary)
			relay.source_path = NodePath("../Intermediary")
			relay.signal_name = &"triggered"
		if mode == "any_entry": wave.triggers.append(_trigger("../../Source", &"pulse"))
		var warnings: PackedStringArray = host.runtime.configuration_warnings(region)
		check(warnings.is_empty() == (mode == "any_entry"), "relay automatic-entry diagnostic respects ANY and explicit source chains: %s" % mode)
		await _mount(region)
		var runtime = host.runtime
		check(runtime.debug_snapshot().errors.is_empty() and runtime.debug_snapshot().advisories == warnings, "editor and runtime agree on nonfatal manual-entry diagnostics: %s" % mode)
		runtime.start_encounter()
		await _settle()
		check(runtime.wave_status(wave) == &"waiting" and region.enemies.is_empty(), "bound cyclic relay does not invent an event: %s" % mode)
		if mode == "any_entry": region.get_node("Source").pulse.emit()
		else: relay.trigger()
		check(await _await_status(runtime, wave, &"active"), "explicit manual or independent entry can unlock relay configuration: %s" % mode)
		if mode == "cross_clear":
			for enemy in region.enemies.duplicate(): enemy.receive_hit(10000.0)
			check(await _await_status(runtime, host.get_node("Wave2"), &"active"), "manual relay entry also unlocks the later direct Wave prerequisite")
		region.queue_free()
		await _settle()

func _sequence_and_empty() -> void:
	var region := _fixture(2)
	var host = region.get_node("EnemyWaves")
	var first = host.get_node("Wave1")
	var second = host.get_node("Wave2")
	first.start_mode = Wave.StartMode.SEQUENCE
	second.start_mode = Wave.StartMode.SEQUENCE
	second.start_delay_seconds = 0.1
	await _mount(region)
	var runtime = host.runtime
	runtime.start_encounter()
	check(await _await_status(runtime, first, &"active") and runtime.wave_status(second) == &"waiting", "default sequence still waits for adjacent previous clear")
	for enemy in region.enemies.duplicate(): enemy.receive_hit(10000.0)
	check(await _await_status(runtime, first, &"cleared") and runtime.wave_status(second) == &"delay", "sequential delay begins only after previous deployment exits")
	check(await _await_status(runtime, second, &"active"), "old sequential delay and spawn remain functional")
	region.queue_free()
	await _settle()
	var empty := _fixture(0)
	await _mount(empty)
	var empty_runtime = empty.get_node("EnemyWaves").runtime
	var completed := [0]
	empty_runtime.encounter_completed.connect(func(): completed[0] += 1)
	empty_runtime.start_encounter()
	await _settle()
	check(empty_runtime.debug_snapshot().errors.is_empty() and completed[0] == 0, "director-only empty controller is valid and does not auto-complete")
	empty.queue_free()
	await _settle()

func _lifecycle_guards() -> void:
	var source := Source.new()
	source.name = "PersistentEventSource"
	root.add_child(source)
	var region := _fixture(1)
	var host = region.get_node("EnemyWaves")
	var wave = host.get_node("Wave1")
	wave.triggers.assign([_trigger(str(source.get_path()), &"pulse")])
	var runtime = host.runtime
	# Capturing is deliberately earlier than ready; a reset in that interval must
	# preserve the explicit all-siblings-ready subscription boundary.
	runtime.capture_templates(region)
	runtime.reset_encounter()
	check(not runtime.debug_snapshot().events_prepared and source.get_signal_connection_list(&"pulse").is_empty(), "early reset cannot prepare subscriptions before the scene is ready")
	await _mount(region)
	var completions := [0]
	runtime.encounter_completed.connect(func(): completions[0] += 1)
	runtime.start_encounter()
	source.pulse.emit()
	check(await _await_status(runtime, wave, &"active"), "explicit prepare after an early reset establishes working subscriptions")
	for enemy in region.enemies.duplicate(): enemy.receive_hit(10000.0)
	await _settle(8)
	check(runtime.debug_snapshot().state == "COMPLETED" and source.get_signal_connection_list(&"pulse").is_empty(), "completed encounter disconnects persistent external event sources")
	runtime.start_encounter()
	source.pulse.emit()
	check(not runtime.request_wave(wave) and runtime.wave_status(wave) == &"cleared" and completions[0] == 1, "completed state and once-only completion survive repeated events and requests")
	runtime.reset_encounter()
	check(source.get_signal_connection_list(&"pulse").size() == 1 and runtime.wave_status(wave) == &"waiting", "reset after completion reconnects exactly one fresh subscription")
	runtime.start_encounter()
	source.pulse.emit()
	check(await _await_status(runtime, wave, &"active"), "new encounter runs after completed-state cleanup")
	var reference: WeakRef = weakref(runtime)
	# Scene replacement removes the old root before freeing it; it need not be
	# queue_free'd when a live descendant sends tree_exiting.
	root.remove_child(region)
	region.free()
	await _settle()
	check(runtime.debug_snapshot().released and runtime._owned.is_empty() and runtime._pending.is_empty() and runtime._retiring.is_empty(), "normal scene removal releases ownership, pending deployments and retirement references")
	check(source.get_signal_connection_list(&"pulse").is_empty(), "unload disconnects sources that outlive the scene")
	runtime = null
	await process_frame
	check(not is_instance_valid(reference.get_ref()), "released runtime has no remaining reference cycle")
	source.free()
