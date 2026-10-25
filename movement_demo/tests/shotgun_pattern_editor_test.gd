@tool
extends SceneTree

const Property = preload("res://addons/weapon_mode_inspector/shotgun_pattern_property.gd")
var checks := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	await create_timer(3).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
	var source = load("res://resources/weapons/patterns/balanced.tres")
	var source_points: PackedVector2Array = source.points.duplicate()
	var pattern: ShotgunPattern = source.duplicate(true)
	pattern.points = PackedVector2Array([Vector2.ZERO])
	DirAccess.make_dir_recursive_absolute("res://logs/shotgun_pattern_editor")
	ResourceSaver.save(pattern, "res://logs/shotgun_pattern_editor/edited.tres", ResourceSaver.FLAG_CHANGE_PATH)
	pattern.take_over_path("res://logs/shotgun_pattern_editor/edited.tres")
	EditorInterface.edit_resource(pattern)
	for frame in 30: await process_frame
	var property: EditorProperty = _find_property(EditorInterface.get_inspector(), pattern)
	check(property != null and property.get_script() == Property, "Pattern resource has the native inspector drawing board")
	if property == null or property.get_script() != Property:
		quit(1)
		return
	var canvas = property.canvas
	check(canvas.size.x > 100 and canvas.size.y >= 260, "Board has a visible usable area in the inspector")
	_mouse(canvas, MOUSE_BUTTON_LEFT, true, canvas.point_to_pixel(Vector2(0.5, 0.5)))
	_mouse(canvas, MOUSE_BUTTON_LEFT, false, canvas.point_to_pixel(Vector2(0.5, 0.5)))
	check(pattern.points.size() == 2 and pattern.points[1].is_equal_approx(Vector2(0.5, 0.5)), "Clicking upper-right creates the correct positive X/Y pellet offset")
	var before := pattern.points.duplicate()
	_mouse(canvas, MOUSE_BUTTON_LEFT, true, canvas.point_to_pixel(Vector2.ZERO))
	var motion := InputEventMouseMotion.new()
	motion.position = canvas.point_to_pixel(Vector2(-0.5, -0.25))
	canvas._gui_input(motion)
	property._update_property()
	check(pattern.points == before and canvas.points[0].is_equal_approx(Vector2(-0.5, -0.25)), "Drag previews without committing; inspector polling does not cancel it")
	_mouse(canvas, MOUSE_BUTTON_LEFT, false, motion.position)
	check(pattern.points[0].is_equal_approx(Vector2(-0.5, -0.25)), "Releasing commits the dragged pellet position")
	var bridge := EditorPlugin.new()
	var manager = bridge.get_undo_redo()
	var history = manager.get_history_undo_redo(manager.get_object_history_id(pattern))
	check(history.undo() and pattern.points == before, "Native undo restores the complete gesture")
	check(history.redo() and pattern.points[0].is_equal_approx(Vector2(-0.5, -0.25)), "Native redo restores the dragged pattern")
	property._update_property()
	_mouse(canvas, MOUSE_BUTTON_RIGHT, true, canvas.point_to_pixel(Vector2(0.5, 0.5)))
	check(pattern.points.size() == 1, "Right click removes one pellet")
	property.clear_button.pressed.emit()
	check(pattern.points.is_empty() and property.counter.text.contains("回退"), "Clear exposes the existing empty-pattern fallback explicitly")
	property.presets.item_selected.emit(2)
	check(pattern.points == load("res://resources/weapons/patterns/horizontal.tres").points, "Loading a preset copies its actual pellet positions")
	property._set_read_only(true)
	before = pattern.points.duplicate()
	_mouse(canvas, MOUSE_BUTTON_LEFT, true, canvas.point_to_pixel(Vector2(0, 0.8)))
	check(pattern.points == before and property.clear_button.disabled and property.save_button.disabled, "Read-only resources cannot be changed or overwritten by the board")
	property._set_read_only(false)
	property.save_button.pressed.emit()
	var reloaded = ResourceLoader.load(pattern.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded.points == pattern.points and property.status.text.contains("已保存"), "Save button persists the board into a real reusable pattern resource")
	check(source.points == source_points, "Editing a copy leaves the original preset unchanged")
	var settings := ShotgunSettings.new()
	settings.pattern = reloaded
	settings.stable_jitter_degrees = 0
	var offsets := preload("res://scripts/weapons/shotgun_ballistics.gd").sample_offsets(settings, 1, RandomNumberGenerator.new())
	check(offsets.size() == pattern.points.size() and offsets[1].is_equal_approx(pattern.points[1] * settings.pattern_angle_degrees), "Saved board points feed the real pellet sampler")
	property.copy_button.pressed.emit()
	check(property.copy_dialog.visible, "Save copy opens a reusable resource file chooser")
	property.copy_dialog.hide()
	property.copy_dialog.file_selected.emit("res://logs/shotgun_pattern_editor/copy.tres")
	for frame in 30: await process_frame
	var copy = EditorInterface.get_inspector().get_edited_object()
	check(copy is ShotgunPattern and copy != pattern and copy.resource_path == "res://logs/shotgun_pattern_editor/copy.tres" and copy.points == pattern.points, "Save copy switches the inspector to an independent saved pattern")
	var copy_property := _find_property(EditorInterface.get_inspector(), copy)
	if copy_property != null and copy_property.get_script() == Property:
		copy_property.presets.item_selected.emit(1)
		copy_property.save_button.pressed.emit()
		var saved_copy = ResourceLoader.load(copy.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(saved_copy.points == source_points and pattern.points == reloaded.points and source.points == source_points, "Editing and saving the new copy preserves both original resources")
	else:
		check(false, "New copy still has the native drawing board")
	EditorInterface.open_scene_from_path("res://scenes/presentation/shotgun_pattern_preview.tscn")
	EditorInterface.set_main_screen_editor("2D")
	for frame in 30: await process_frame
	var preview = EditorInterface.get_edited_scene_root()
	check(preview is Control and preview.size.x >= 1152 and preview.shots.size() == 3, "Preview scene draws its three panels in the editor without running F6")
	check(preview.get_child_count() >= 4 and preview.status != null and not preview.status.text.is_empty(), "Editor preview contains visible labels and controls")
	var packed := PackedScene.new()
	packed.pack(preview)
	check(packed.get_state().get_node_count() == 1, "Tool preview does not serialize generated UI into the user's scene")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/shotgun_pattern_editor/editor_preview.png")
	EditorInterface.get_inspector().edit(null)
	bridge.free()
	print("SHOTGUN PATTERN EDITOR: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func _find_property(node: Node, resource: Resource) -> EditorProperty:
	if node is EditorProperty and node.get_edited_object() == resource and node.get_edited_property() == "points": return node
	for child in node.get_children():
		var found := _find_property(child, resource)
		if found != null: return found
	return null

func _mouse(canvas: Control, button: MouseButton, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	canvas._gui_input(event)
