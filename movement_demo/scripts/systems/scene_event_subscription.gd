extends RefCounted

## Exact-arity adapters support source signals with 0..8 arguments. Callbacks
## receive no arguments. Connections and filter snapshots belong to this instance.
const Trigger = preload("res://scripts/systems/scene_event_trigger.gd")
const MAX_ARGUMENTS := 8
var _connections: Array[Dictionary] = []
var _generation := 0

func connect_trigger(owner: Node, trigger: Resource, callback: Callable) -> String:
	if not is_instance_valid(owner): return "Event owner is missing."
	if not trigger is Trigger: return "Expected a SceneEventTrigger resource."
	if not callback.is_valid(): return "Event callback is invalid."
	if trigger.source_path.is_empty(): return "Event source_path is empty."
	var source := owner.get_node_or_null(trigger.source_path)
	if not is_instance_valid(source): return "Event source not found: %s." % trigger.source_path
	if trigger.signal_name.is_empty() or not source.has_signal(trigger.signal_name):
		return "Source %s has no signal '%s'." % [trigger.source_path, trigger.signal_name]
	var arguments: Array = []
	var found := false
	for metadata in source.get_signal_list():
		if metadata.name == trigger.signal_name:
			arguments = metadata.args
			found = true
			break
	if not found: return "Signal metadata is unavailable: %s." % trigger.signal_name
	if arguments.size() > MAX_ARGUMENTS:
		return "Signal %s has %d arguments; supported arity is 0..8." % [trigger.signal_name, arguments.size()]
	var filters: Array[Resource] = []
	for filter in trigger.filters:
		if filter == null: return "Event filter is null."
		var diagnostic: String = filter.validate(arguments)
		if not diagnostic.is_empty(): return "%s.%s: %s" % [trigger.source_path, trigger.signal_name, diagnostic]
		filters.append(filter.duplicate(true))
	var entry := {"source": weakref(source), "owner": weakref(owner), "signal": trigger.signal_name,
		"path": trigger.source_path, "filters": filters, "callback": callback, "arity": arguments.size()}
	var adapter := Callable(self, "_receive_%d" % arguments.size()).bind(entry, _generation)
	var error := source.connect(trigger.signal_name, adapter)
	if error != OK: return "Cannot connect %s.%s (%d)." % [trigger.source_path, trigger.signal_name, error]
	_connections.append({"entry": entry, "adapter": adapter})
	return ""

func clear() -> void:
	_generation += 1
	for connection in _connections:
		var source: Node = connection.entry.source.get_ref()
		if is_instance_valid(source) and source.is_connected(connection.entry.signal, connection.adapter):
			source.disconnect(connection.entry.signal, connection.adapter)
	_connections.clear()

func diagnostics() -> PackedStringArray:
	var result: PackedStringArray = []
	for connection in _connections:
		var source: Node = connection.entry.source.get_ref()
		if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion():
			result.append("Event source disappeared before completion: %s.%s." % [connection.entry.path, connection.entry.signal])
		elif source.has_method("scene_event_diagnostics"):
			result.append_array(source.scene_event_diagnostics())
	return result

func _dispatch(arguments: Array, entry: Dictionary, generation: int) -> void:
	if generation != _generation or not is_instance_valid(entry.owner.get_ref()) or not entry.callback.is_valid(): return
	var source: Node = entry.source.get_ref()
	var owner: Node = entry.owner.get_ref()
	if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion(): return
	if not owner.is_inside_tree() or owner.is_queued_for_deletion(): return
	if arguments.size() != entry.arity: return
	for filter in entry.filters:
		if not filter.matches(arguments): return
	entry.callback.call()

func _receive_0(entry: Dictionary, generation: int) -> void:
	_dispatch([], entry, generation)

func _receive_1(a: Variant, entry: Dictionary, generation: int) -> void:
	_dispatch([a], entry, generation)

func _receive_2(a: Variant, b: Variant, entry: Dictionary, generation: int) -> void:
	_dispatch([a, b], entry, generation)

func _receive_3(a: Variant, b: Variant, c: Variant, entry: Dictionary, generation: int) -> void:
	_dispatch([a, b, c], entry, generation)

func _receive_4(a: Variant, b: Variant, c: Variant, d: Variant, entry: Dictionary, generation: int) -> void:
	_dispatch([a, b, c, d], entry, generation)

func _receive_5(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, entry: Dictionary, generation: int) -> void:
	_dispatch([a, b, c, d, e], entry, generation)

func _receive_6(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, f: Variant, entry: Dictionary, generation: int) -> void:
	_dispatch([a, b, c, d, e, f], entry, generation)

func _receive_7(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, f: Variant, g: Variant, entry: Dictionary, generation: int) -> void:
	_dispatch([a, b, c, d, e, f, g], entry, generation)

func _receive_8(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, f: Variant, g: Variant, h: Variant, entry: Dictionary, generation: int) -> void:
	_dispatch([a, b, c, d, e, f, g, h], entry, generation)
