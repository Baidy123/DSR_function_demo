@tool
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await create_timer(3.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
	var gun := WeaponData.new()
	gun.damage = 17
	EditorInterface.edit_resource(gun)
	for frame in 20: await process_frame
	check(_fields(gun).has("damage") and not _fields(gun).has("shotgun"), "Legacy weapon inspector stays unchanged")
	var option: OptionButton
	for property in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
		if property.get_edited_object() == gun and property.get_edited_property() == "fire_mode":
			option = _descendants(property, "OptionButton")[0]
	check(option != null and option.item_count == 4 and option.get_item_text(3) == "霰弹" and option.get_item_id(3) == 3, "Fire Mode appends exactly one option named 霰弹")
	option.select(3)
	option.item_selected.emit(3)
	for frame in 20: await process_frame
	var fields := _fields(gun)
	check(gun.fire_mode == WeaponData.FireMode.SHOTGUN and gun.shotgun != null and gun.shotgun.get_pattern_points().size() == 9, "Choosing 霰弹 initializes a usable nine-pellet configuration")
	check(fields.has("shotgun") and fields.has("magazine_capacity") and fields.has("fire_mode"), "Shotgun mode keeps common controls and exposes its settings")
	check(not fields.has("damage") and not fields.has("initial_accuracy") and not fields.has("min_spread_angle_degrees"), "Shotgun mode hides unused single-projectile parameters")
	gun.shotgun.pellet_damage = 11
	var saved_settings = gun.shotgun
	EditorInterface.edit_resource(gun.shotgun)
	for frame in 20: await process_frame
	fields = _fields(gun.shotgun)
	check(fields.has("pattern") and fields.has("pellet_damage") and fields.has("stable_jitter_degrees") and fields.has("starting_stability"), "Expanded settings expose pattern, pellet damage and stability")
	gun.fire_mode = WeaponData.FireMode.SEMI_AUTO
	EditorInterface.edit_resource(gun)
	for frame in 20: await process_frame
	check(_fields(gun).has("damage") and not _fields(gun).has("shotgun") and gun.damage == 17, "Switching back restores original parameters without overwriting them")
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	check(gun.shotgun == saved_settings and gun.shotgun.pellet_damage == 11, "Returning to shotgun preserves its settings")
	var bridge := EditorPlugin.new()
	var manager = bridge.get_undo_redo()
	var history = manager.get_history_undo_redo(manager.get_object_history_id(gun))
	check(history.undo() and gun.fire_mode == WeaponData.FireMode.SEMI_AUTO, "Native inspector undo restores original Fire Mode")
	check(history.redo() and gun.fire_mode == WeaponData.FireMode.SHOTGUN, "Native inspector redo restores shotgun mode")
	EditorInterface.get_inspector().edit(null)
	bridge.free()
	for frame in 5: await process_frame
	print("SHOTGUN INSPECTOR: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _fields(gun: Resource) -> Array:
	var fields := []
	for property in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
		if property.get_edited_object() == gun: fields.append(property.get_edited_property())
	return fields

func _descendants(node: Node, type: String) -> Array:
	var result := []
	for child in node.get_children(true):
		if child.is_class(type): result.append(child)
		result.append_array(_descendants(child, type))
	return result

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
