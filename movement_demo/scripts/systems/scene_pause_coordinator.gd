extends RefCounted

## One owner ledger per SceneTree; release never clears another owner's pause.
const META := &"scene_pause_coordinator"
var _tree: WeakRef
var _tokens: Dictionary = {}
var _owners: Dictionary = {}
var _next_id := 0
var _previous_pause := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE

static func for_tree(tree: SceneTree):
	if tree.has_meta(META): return tree.get_meta(META)
	var coordinator = load("res://scripts/systems/scene_pause_coordinator.gd").new()
	coordinator._tree = weakref(tree)
	tree.set_meta(META, coordinator)
	return coordinator

func acquire(owner: Node, reason: StringName, visible_mouse: bool = false) -> int:
	var tree: SceneTree = _tree.get_ref()
	if tree == null or not is_instance_valid(owner): return 0
	var first_owner := _tokens.is_empty()
	if first_owner:
		_previous_pause = tree.paused
	_next_id += 1
	var id := _next_id
	var owner_id := owner.get_instance_id()
	if not _owners.has(owner_id):
		var cleanup := _release_owner.bind(owner_id)
		_owners[owner_id] = {"owner": weakref(owner), "cleanup": cleanup}
		owner.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)
	_tokens[id] = {"owner_id": owner_id, "reason": reason, "mouse": visible_mouse}
	tree.paused = true
	# Pause notifications release the combat component's temporary mouse capture.
	# Save that settled mode, not a stale capture belonging to a now-paused action.
	if first_owner: _previous_mouse_mode = Input.mouse_mode
	if visible_mouse: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return id

func release(id: int) -> void:
	if not _tokens.has(id): return
	var entry: Dictionary = _tokens[id]
	_tokens.erase(id)
	var owner_id: int = entry.owner_id
	if not _has_owner_token(owner_id) and _owners.has(owner_id):
		var ownership: Dictionary = _owners[owner_id]
		_owners.erase(owner_id)
		var owner = ownership.owner.get_ref()
		if is_instance_valid(owner) and owner.tree_exiting.is_connected(ownership.cleanup):
			owner.tree_exiting.disconnect(ownership.cleanup)
	var tree: SceneTree = _tree.get_ref()
	if tree == null: return
	if _tokens.is_empty():
		tree.paused = _previous_pause
		Input.mouse_mode = _previous_mouse_mode
	elif not _has_mouse_owner():
		Input.mouse_mode = _previous_mouse_mode

func _release_owner(owner_id: int) -> void:
	# One connection per node, irrespective of how many reasons it owns. Snapshot
	# the ids because release() removes tokens and disconnects the final owner.
	for id in _tokens.keys():
		if _tokens[id].owner_id == owner_id: release(id)

func _has_owner_token(owner_id: int) -> bool:
	for entry in _tokens.values():
		if entry.owner_id == owner_id: return true
	return false

func can_advance_presentation(token: int) -> bool:
	return _tokens.has(token) and _tokens.size() == 1 and not _previous_pause

func _has_mouse_owner() -> bool:
	for entry in _tokens.values():
		if entry.mouse: return true
	return false

func snapshot() -> Dictionary:
	var reasons: Array[StringName] = []
	for entry in _tokens.values(): reasons.append(entry.reason)
	return {"count": _tokens.size(), "reasons": reasons, "external_pause": _previous_pause}
