extends SceneTree

class StateProbe extends Node:
	var flags := {&"door_open": true}
	var counts := {&"keycard": 2}

	func get_flag(key: StringName, fallback: bool = false) -> bool:
		return bool(flags.get(key, fallback))

	func get_item_count(key: StringName) -> int:
		return int(counts.get(key, 0))

class QuestProbe extends Node:
	var statuses := {&"escape": 3}

	func status_of(key: StringName) -> int:
		return int(statuses.get(key, 0))

class QueryTarget extends Node:
	var visible := true
	var enabled := true

	func is_ready_for_event(minimum: int) -> bool:
		return enabled and minimum == 2

	func text_query() -> String:
		return "not a bool"

class Host extends Node:
	var wave_states: Dictionary = {}

	func wave_status(wave: Node) -> StringName:
		return wave_states.get(wave, &"unknown")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Host.new()
	host.name = "Host"
	root.add_child(host)
	var state := StateProbe.new()
	state.name = "State"
	host.add_child(state)
	var quests := QuestProbe.new()
	quests.name = "Quests"
	host.add_child(quests)
	var wave := Node.new()
	wave.name = "Wave"
	host.add_child(wave)
	host.wave_states[wave] = &"cleared"
	var target := QueryTarget.new()
	target.name = "Target"
	target.add_to_group(&"event_targets")
	host.add_child(target)
	var definition := SceneEventDefinition.new()
	definition.event_id = &"conditions"
	var context := SceneActionContext.new().configure(host, host, definition, null, 1, -1)

	var flag := SceneFlagCondition.new()
	flag.state_path = ^"State"
	flag.flag = &"door_open"
	flag.expected = true
	check(flag.matches(context), "flag condition compares the exact bool value")
	flag.expected = false
	check(not flag.matches(context), "flag condition does not coerce the opposite value")

	var item := SceneItemCondition.new()
	item.state_path = ^"State"
	item.item_id = &"keycard"
	item.minimum_count = 2
	check(item.matches(context), "item condition accepts the configured minimum count")
	item.minimum_count = 3
	check(not item.matches(context), "item condition rejects a lower inventory count")

	var quest := SceneQuestCondition.new()
	quest.controller_path = ^"Quests"
	quest.quest_id = &"escape"
	quest.expected_status = 3
	check(quest.matches(context), "quest condition compares the authoritative status")

	var wave_condition := SceneWaveCondition.new()
	wave_condition.wave_path = ^"Wave"
	wave_condition.expected_status = &"cleared"
	check(wave_condition.matches(context), "wave condition queries the director without mutating the wave")

	var node_condition := SceneNodeCondition.new()
	node_condition.target_path = ^"Target"
	node_condition.query = SceneNodeCondition.Query.VISIBLE
	check(node_condition.matches(context), "node condition reads visibility")
	node_condition.query = SceneNodeCondition.Query.ENABLED
	check(node_condition.matches(context), "node condition reads enabled state")
	node_condition.query = SceneNodeCondition.Query.IN_GROUP
	node_condition.group = &"event_targets"
	check(node_condition.matches(context), "node condition reads group membership")
	node_condition.query = SceneNodeCondition.Query.EXISTS
	node_condition.expected = false
	check(not node_condition.matches(context), "node existence honors the expected value")

	var method := SceneMethodCondition.new()
	method.target_path = ^"Target"
	method.method = &"is_ready_for_event"
	method.arguments = [2]
	check(method.diagnostics(context).is_empty() and method.matches(context),
		"method condition validates and invokes a public bool query")
	method.method = &"text_query"
	method.arguments = []
	check(not method.diagnostics(context).is_empty() and not method.matches(context),
		"method condition rejects a non-bool query result")

	host.queue_free()
	await process_frame
	print("Scene event conditions: %d failures" % failures)
	quit(1 if failures else 0)


func check(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
