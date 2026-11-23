@tool
extends SceneTree

const Property = preload("res://addons/weapon_mode_inspector/shotgun_pattern_property.gd")
const CoverageProperty = preload("res://addons/weapon_mode_inspector/shotgun_coverage_property.gd")
const Ballistics = preload("res://scripts/weapons/shotgun_ballistics.gd")
var checks := 0
var failed := 0

func _initialize() -> void:
	if "--preview-runtime" in OS.get_cmdline_user_args(): _run_preview_runtime.call_deferred()
	else: _run.call_deferred()

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
	for point in [Vector2.ZERO, Vector2(0.5, 0.5)]:
		_mouse(canvas, MOUSE_BUTTON_LEFT, true, canvas.point_to_pixel(point))
		_mouse(canvas, MOUSE_BUTTON_LEFT, false, canvas.point_to_pixel(point))
	check(pattern.points == PackedVector2Array([Vector2.ZERO, Vector2(0.5, 0.5)]), "Drawing after clearing creates reusable custom pellet positions")
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
		var copy_position: Vector2 = copy_property.canvas.point_to_pixel(Vector2(-0.5, 0.5))
		_mouse(copy_property.canvas, MOUSE_BUTTON_LEFT, true, copy_position)
		_mouse(copy_property.canvas, MOUSE_BUTTON_LEFT, false, copy_position)
		copy_property.save_button.pressed.emit()
		var saved_copy = ResourceLoader.load(copy.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(saved_copy.points == copy.points and saved_copy.points.size() == pattern.points.size() + 1 and pattern.points == reloaded.points and source.points == source_points, "Editing and saving the new copy preserves both original resources")
	else:
		check(false, "New copy still has the native drawing board")
	await _check_coverage(manager)
	EditorInterface.open_scene_from_path("res://scenes/presentation/shotgun_pattern_preview.tscn")
	EditorInterface.set_main_screen_editor("2D")
	for frame in 30: await process_frame
	var preview = EditorInterface.get_edited_scene_root()
	check(preview is Control and preview.size.x >= 1152 and preview.shots.size() == 3, "Preview scene draws its three panels in the editor without running F6")
	check(preview.get_child_count() >= 4 and preview.status != null and not preview.status.text.is_empty(), "Editor preview contains visible labels and controls")
	var saved_preview_angle: float = preview.preview_pattern_angle_degrees
	var saved_preview_distance: float = preview.preview_calibration_distance_m
	EditorInterface.edit_node(preview)
	for frame in 20: await process_frame
	for field in ["pattern_1", "pattern_2", "pattern_3", "preview_spread_mode", "preview_stable_jitter_degrees", "preview_unstable_jitter_degrees", "preview_pattern_angle_degrees"]:
		check(_find_property(EditorInterface.get_inspector(), preview, field) != null, "Preview exposes inspector input " + field)
	var jitter_property := _find_property(EditorInterface.get_inspector(), preview, "preview_unstable_jitter_degrees")
	var initial_jitter: float = preview.preview_unstable_jitter_degrees
	jitter_property.emit_changed("preview_unstable_jitter_degrees", 0.9)
	for frame in 3: await process_frame
	var scene_history = manager.get_history_undo_redo(manager.get_object_history_id(preview))
	check(is_equal_approx(preview.preview_unstable_jitter_degrees, 0.9) and scene_history.undo() and is_equal_approx(preview.preview_unstable_jitter_degrees, initial_jitter), "Preview parameters use native scene undo")
	check(scene_history.redo() and is_equal_approx(preview.preview_unstable_jitter_degrees, 0.9), "Preview parameters use native scene redo")
	var mode_property := _find_property(EditorInterface.get_inspector(), preview, "preview_spread_mode")
	var original_mode: int = preview.preview_spread_mode
	var new_mode := 1 - original_mode
	mode_property.emit_changed("preview_spread_mode", new_mode)
	for frame in 3: await process_frame
	check(mode_property.label == "预览偏移方式" and preview.preview_spread_mode == new_mode and preview._settings.spread_mode == new_mode, "Preview mode edits refresh the shared sampler")
	check(scene_history.undo() and preview.preview_spread_mode == original_mode, "Native scene undo restores preview mode")
	check(scene_history.redo() and preview.preview_spread_mode == new_mode, "Native scene redo restores preview mode")
	await _check_preview_calibration_controls(preview, manager, saved_preview_angle, saved_preview_distance)
	await _check_preview(preview)
	await _check_preview_calibration(preview)
	var packed := PackedScene.new()
	packed.pack(preview)
	check(packed.get_state().get_node_count() == 1, "Tool preview does not serialize generated UI into the user's scene")
	if DisplayServer.get_name() != "headless":
		EditorInterface.get_inspector().expand_all_folding()
		for frame in 20: await process_frame
		EditorInterface.get_inspector().ensure_control_visible(_find_property(EditorInterface.get_inspector(), preview, "preview_unstable_jitter_degrees"))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/shotgun_pattern_editor/editor_preview.png")
	EditorInterface.get_inspector().edit(null)
	bridge.free()
	print("SHOTGUN PATTERN EDITOR: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func _check_coverage(manager: EditorUndoRedoManager) -> void:
	var settings := ShotgunSettings.new()
	settings.pattern = ShotgunPattern.new()
	settings.pattern.points = PackedVector2Array([Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)])
	settings.stable_jitter_degrees = 0
	settings.unstable_jitter_degrees = 0.55
	var other := ShotgunSettings.new()
	other.pattern = settings.pattern
	var original_points := settings.pattern.points.duplicate()
	ResourceSaver.save(settings, "res://logs/shotgun_pattern_editor/coverage.tres", ResourceSaver.FLAG_CHANGE_PATH)
	settings.take_over_path("res://logs/shotgun_pattern_editor/coverage.tres")
	EditorInterface.edit_resource(settings)
	for frame in 20: await process_frame
	var control := _find_property(EditorInterface.get_inspector(), settings, "pattern_angle_degrees")
	check(control != null and control.get_script() == CoverageProperty, "Shotgun settings expose the distance and area editor")
	if control == null or control.get_script() != CoverageProperty: return
	check(settings.pattern_angle_degrees == 3 and settings.pattern_calibration_distance_m == 4 and absf(control.area.value - 0.1758) < 0.001, "Opening legacy settings preserves its angle and derives area at four meters")
	var old_gun = load("res://resources/weapons/test_shotgun.tres")
	check(old_gun.shotgun.pattern_calibration_distance_m == 4 and old_gun.shotgun.pattern_angle_degrees == 3, "Existing saved weapon loads without changing its original trajectory")
	control.area.value = 1.0
	check(_projected_extent(settings, 4).is_equal_approx(Vector2.ONE), "Area control changes real pellet directions to a one-meter square at four meters")
	check(settings.pattern.points == original_points and other.pattern_angle_degrees == 3 and settings.unstable_jitter_degrees == 0.55, "Calibration preserves shared pattern, other weapon and existing jitter")
	var angle_at_four := settings.pattern_angle_degrees
	control.distance.value = 8.0
	check(is_equal_approx(settings.get_pattern_coverage_area(), 1.0) and _projected_extent(settings, 8).is_equal_approx(Vector2.ONE) and _projected_extent(settings, 4).is_equal_approx(Vector2.ONE * 0.5), "Increasing distance keeps area fixed and tightens the actual trajectory")
	var history = manager.get_history_undo_redo(manager.get_object_history_id(settings))
	check(history.undo() and settings.pattern_calibration_distance_m == 4 and settings.pattern_angle_degrees == angle_at_four, "One native undo restores distance and angle together")
	check(history.redo() and settings.pattern_calibration_distance_m == 8 and is_equal_approx(settings.get_pattern_coverage_area(), 1), "Native redo restores the calibrated pair")
	var before_angle := settings.pattern_angle_degrees
	control.distance.value = 0.1
	check(settings.pattern_calibration_distance_m == 8 and settings.pattern_angle_degrees == before_angle and control.status.visible, "Out-of-range combination is rejected without partial writes")
	check(not settings.set_pattern_calibration(0, 1) and not settings.set_pattern_calibration(4, -1) and not settings.set_pattern_calibration(NAN, 1) and not settings.set_pattern_calibration(4, INF) and settings.pattern_angle_degrees == before_angle, "Calibration API rejects invalid inputs atomically")
	control._set_read_only(true)
	control.distance.value = 4
	control.area.value = 0.5
	check(settings.pattern_calibration_distance_m == 8 and settings.pattern_angle_degrees == before_angle and not control.distance.editable and not control.area.editable, "Read-only settings block both performance controls")
	control._set_read_only(false)
	control._update_property()
	control.area.value = 0
	check(settings.pattern_angle_degrees == 0 and _projected_extent(settings, 8).is_zero_approx(), "Zero area collapses only the fixed pattern")
	var max_area := pow(2.0 * 4.0 * tan(deg_to_rad(15.0)), 2)
	control._commit_calibration(4, max_area)
	check(is_equal_approx(settings.pattern_angle_degrees, 15), "Original maximum angle remains available")
	control._commit_calibration(4, max_area + 1)
	check(is_equal_approx(settings.pattern_angle_degrees, 15) and settings.pattern_calibration_distance_m == 4, "Exceeding maximum area keeps the saved calibration intact")
	control._commit_calibration(8, 1)
	var summary: String = control.details.text
	settings.pattern.points = PackedVector2Array([Vector2.ZERO, Vector2(0.5, 0.5)])
	settings.pattern.emit_changed()
	await create_timer(0.7).timeout
	check(control.details.text != summary and is_equal_approx(settings.get_pattern_coverage_area(), 1), "Editing pellet positions updates bounds without rescaling the calibration")
	settings.pattern.points.clear()
	settings.pattern.emit_changed()
	await create_timer(0.7).timeout
	check(control.details.text.contains("宽 0.000 × 高 0.000"), "Empty pattern retains the center-pellet fallback in coverage display")
	var previous_pattern := settings.pattern
	var replacement := ShotgunPattern.new()
	replacement.points = PackedVector2Array([Vector2(-0.5, 0), Vector2(0.5, 0)])
	_find_property(EditorInterface.get_inspector(), settings, "pattern").emit_changed("pattern", replacement)
	await create_timer(0.7).timeout
	check(settings.pattern == replacement and not control.details.text.contains("宽 0.000") and not previous_pattern.changed.is_connected(control._update_property), "Replacing the native Pattern reference updates bounds and disconnects the previous pattern")
	replacement.points.clear()
	replacement.emit_changed()
	await create_timer(0.7).timeout
	check(control.details.text.contains("宽 0.000 × 高 0.000"), "Replacement pattern edits update coverage without manually refreshing the inspector")
	ResourceSaver.save(settings, settings.resource_path)
	var saved = ResourceLoader.load(settings.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved.pattern_calibration_distance_m == 8 and is_equal_approx(saved.get_pattern_coverage_area(), 1) and saved.pattern_angle_degrees == settings.pattern_angle_degrees, "Saved calibration restores distance, area and angle consistently")
	if DisplayServer.get_name() != "headless":
		EditorInterface.get_inspector().expand_all_folding()
		for frame in 20: await process_frame
		EditorInterface.get_inspector().ensure_control_visible(control)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/shotgun_pattern_editor/coverage_editor.png")
	EditorInterface.get_inspector().edit(null)

func _projected_extent(settings: ShotgunSettings, distance_m: float) -> Vector2:
	return _offset_extent(Ballistics.sample_offsets(settings, 1, RandomNumberGenerator.new()), distance_m)

func _offset_extent(offsets: PackedVector2Array, distance_m: float) -> Vector2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for direction in Ballistics.directions(Vector3.FORWARD, offsets):
		var projected := Vector2(direction.x, direction.y) * distance_m / -direction.z
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	return maximum - minimum

func _check_preview_calibration_controls(preview, manager: EditorUndoRedoManager, saved_angle: float, saved_distance: float) -> void:
	var control := _find_property(EditorInterface.get_inspector(), preview, "preview_pattern_angle_degrees")
	check(control != null and control.get_script() == CoverageProperty, "Preview inspector exposes its own distance and area controls")
	if control == null or control.get_script() != CoverageProperty: return
	check(preview.preview_calibration_distance_m == saved_distance and preview.preview_pattern_angle_degrees == saved_angle, "Opening an existing preview preserves its saved independent calibration")
	# 用户场景可以已调过参数；验证操作在隔离实例准备的四米基准上进行。
	preview.set_pattern_calibration(4, ShotgunSettings.coverage_area_at(4, saved_angle))
	var angle_before_edit: float = preview.preview_pattern_angle_degrees
	control.area.value = 1
	var angle_at_four: float = preview.preview_pattern_angle_degrees
	check(preview.preview_calibration_distance_m == 4 and is_equal_approx(preview.get_pattern_coverage_area(), 1), "Preview area input keeps its calibration distance")
	control.distance.value = 8
	check(preview.preview_calibration_distance_m == 8 and is_equal_approx(preview.get_pattern_coverage_area(), 1) and preview.preview_pattern_angle_degrees < angle_at_four, "Preview distance input preserves area and tightens spread")
	var history = manager.get_history_undo_redo(manager.get_object_history_id(preview))
	check(history.undo() and preview.preview_calibration_distance_m == 4 and preview.preview_pattern_angle_degrees == angle_at_four, "Scene undo restores preview distance and angle as one operation")
	check(history.undo() and preview.preview_calibration_distance_m == 4 and preview.preview_pattern_angle_degrees == angle_before_edit, "Scene undo also restores the previous preview area")
	check(history.redo() and history.redo() and preview.preview_calibration_distance_m == 8 and is_equal_approx(preview.get_pattern_coverage_area(), 1), "Scene redo restores both independent calibration operations")
	control.distance.value = 0.1
	check(preview.preview_calibration_distance_m == 8 and control.status.visible, "Preview rejects an invalid calibration without changing saved values")
	control._set_read_only(true)
	control.area.value = 0
	check(is_equal_approx(preview.get_pattern_coverage_area(), 1) and not control.area.editable and not control.distance.editable, "Read-only preview blocks both calibration inputs")
	control._set_read_only(false)
	control._update_property()
	await process_frame

func _check_preview_calibration(preview) -> void:
	var pattern := ShotgunPattern.new()
	pattern.points = PackedVector2Array([Vector2(-1, -1), Vector2(1, 1)])
	ResourceSaver.save(pattern, "res://logs/shotgun_pattern_editor/calibration_pattern.tres", ResourceSaver.FLAG_CHANGE_PATH)
	pattern.take_over_path("res://logs/shotgun_pattern_editor/calibration_pattern.tres")
	preview.pattern_1 = pattern
	preview.pattern_2 = null
	preview.pattern_3 = pattern
	preview.preview_stable_jitter_degrees = 0
	preview.preview_unstable_jitter_degrees = 0
	preview.preview_initial_stability = 1
	preview.set_pattern_calibration(4, 1)
	for frame in 3: await process_frame
	check(_offset_extent(preview.shots[0], 4).is_equal_approx(Vector2.ONE), "Preview calibration changes sampled directions to one square meter at four meters")
	preview.set_pattern_calibration(8, preview.get_pattern_coverage_area())
	for frame in 3: await process_frame
	check(_offset_extent(preview.shots[0], 4).is_equal_approx(Vector2.ONE * 0.5), "Independent preview distance changes the actual fixed spread")
	var angle: float = preview.preview_pattern_angle_degrees
	check(not preview.set_pattern_calibration(0, 1) and not preview.set_pattern_calibration(4, INF) and preview.preview_calibration_distance_m == 8 and preview.preview_pattern_angle_degrees == angle, "Preview calibration API rejects invalid pairs atomically")
	var source_gun = load("res://resources/weapons/test_shotgun.tres")
	var original_range: float = source_gun.fire_range
	var original_angle: float = source_gun.shotgun.pattern_angle_degrees
	var original_distance: float = source_gun.shotgun.pattern_calibration_distance_m
	source_gun.fire_range = 1
	preview.preview_distance_m = 1000
	for frame in 3: await process_frame
	check(preview.distance_m == 1000 and preview._distance_spin.value == 1000 and _offset_extent(preview.shots[0], preview.distance_m).is_equal_approx(Vector2.ONE * 125), "Thousand-meter preview ignores the actual weapon firing range")
	preview._distance_spin.value = 2000
	check(preview.distance_m == 2000 and preview.preview_distance_m == 1000, "Runtime distance input accepts values above one thousand meters without saving them")
	preview.preview_distance_m = 2000
	for frame in 3: await process_frame
	var view_radius: float = preview.get_view_radius_m()
	var fits := true
	for offsets in preview.shots:
		for offset in offsets:
			var projected: Vector2 = preview._project(offset).abs()
			fits = fits and maxf(projected.x, projected.y) < view_radius
	check(view_radius > 1.8 and fits, "Far-distance panels use one expanded metric scale that contains every pellet")
	check(source_gun.shotgun.pattern_angle_degrees == original_angle and source_gun.shotgun.pattern_calibration_distance_m == original_distance and pattern.points == PackedVector2Array([Vector2(-1, -1), Vector2(1, 1)]), "Preview calibration leaves weapon settings and shared pattern points unchanged")
	source_gun.fire_range = original_range
	var packed := PackedScene.new()
	packed.pack(preview)
	ResourceSaver.save(packed, "res://logs/shotgun_pattern_editor/calibrated_preview.tscn")
	var restored = ResourceLoader.load("res://logs/shotgun_pattern_editor/calibrated_preview.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.add_child(restored)
	for frame in 3: await process_frame
	check(restored.preview_calibration_distance_m == 8 and is_equal_approx(restored.get_pattern_coverage_area(), 1) and restored.distance_m == 2000 and _offset_extent(restored.shots[0], 4).is_equal_approx(Vector2.ONE * 0.5), "Scene reload preserves independent calibration and unrestricted observation distance")
	restored.queue_free()
	await process_frame

func _check_preview(preview) -> void:
	var child_count: int = preview.get_child_count()
	var custom := ShotgunPattern.new()
	custom.display_name = "独立图样测试"
	custom.points = PackedVector2Array([Vector2.ZERO, Vector2(0.4, -0.2)])
	ResourceSaver.save(custom, "res://logs/shotgun_pattern_editor/custom.tres", ResourceSaver.FLAG_CHANGE_PATH)
	custom.take_over_path("res://logs/shotgun_pattern_editor/custom.tres")
	var slot_count := 0
	for field in preview.get_property_list():
		if field.usage & PROPERTY_USAGE_EDITOR and field.hint_string == "ShotgunPattern": slot_count += 1
	check(slot_count == 3, "Preview has exactly three typed pattern resource slots")
	preview.pattern_1 = custom
	preview.pattern_2 = null
	preview.pattern_3 = custom
	preview.preview_pattern_angle_degrees = 2
	preview.preview_stable_jitter_degrees = 0
	preview.preview_unstable_jitter_degrees = 1
	preview.preview_initial_stability = 0.5
	preview.preview_distance_m = 4
	for frame in 3: await process_frame
	check(preview.shots.size() == 3 and preview.shots[0].size() == 2 and preview.shots[1].is_empty() and preview.shots[2].size() == 2, "Replacing slots updates all three panels and preserves empty slots")
	var preview_connections := custom.changed.get_connections().filter(func(connection): return connection.callable == Callable(preview, "_queue_refresh"))
	check(preview_connections.size() == 1, "Duplicate slots share a single pattern-change connection")
	var expected := ShotgunSettings.new()
	expected.pattern = custom
	expected.pattern_angle_degrees = 2
	expected.stable_jitter_degrees = 0
	expected.unstable_jitter_degrees = 1
	for mode in [ShotgunSettings.SpreadMode.RANDOM, ShotgunSettings.SpreadMode.NO_INWARD]:
		preview.preview_spread_mode = mode
		expected.spread_mode = mode
		for stability_value in [0.0, 0.5, 1.0]:
			preview.stability = stability_value
			preview.rng.seed = 2468
			preview.fire()
			var rng := RandomNumberGenerator.new()
			rng.seed = 2468
			check(preview.shots[0] == Ballistics.sample_offsets(expected, stability_value, rng) and preview.shots[2] == Ballistics.sample_offsets(expected, stability_value, rng), "Independent preview uses real sampling: mode %d stability %.1f" % [mode, stability_value])
	check(preview.status.text.contains("不向圆心偏移"), "Preview status names the selected mode")
	var source_gun = load("res://resources/weapons/test_shotgun.tres")
	var source_angle: float = source_gun.shotgun.pattern_angle_degrees
	var source_jitter: float = source_gun.shotgun.stable_jitter_degrees
	var source_mode: int = source_gun.shotgun.spread_mode
	source_gun.shotgun.spread_mode = ShotgunSettings.SpreadMode.RANDOM
	source_gun.shotgun.pattern_angle_degrees = 14
	source_gun.shotgun.stable_jitter_degrees = 4
	preview.fire()
	check(preview.preview_spread_mode == ShotgunSettings.SpreadMode.NO_INWARD and preview.preview_pattern_angle_degrees == 2 and preview.shots[0][1].is_equal_approx(Vector2(0.8, -0.4)), "Changing the example weapon cannot affect preview configuration or samples")
	source_gun.shotgun.spread_mode = source_mode
	source_gun.shotgun.pattern_angle_degrees = source_angle
	source_gun.shotgun.stable_jitter_degrees = source_jitter
	custom.points.append(Vector2(-0.5, 0.6))
	custom.emit_changed()
	for frame in 3: await process_frame
	check(preview.shots[0].size() == 3 and preview.get_child_count() == child_count, "Pattern changes refresh samples without duplicating generated UI")
	# Save this deliberately edited test resource before checking scene round-trip.
	ResourceSaver.save(custom, custom.resource_path)
	var points_before := custom.points.duplicate()
	var packed := PackedScene.new()
	packed.pack(preview)
	ResourceSaver.save(packed, "res://logs/shotgun_pattern_editor/preview.tscn")
	var restored = ResourceLoader.load("res://logs/shotgun_pattern_editor/preview.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.add_child(restored)
	for frame in 3: await process_frame
	check(restored.get_patterns()[0].resource_path == custom.resource_path and restored.pattern_2 == null and restored.preview_unstable_jitter_degrees == 1 and restored.stability == 0.5 and restored.distance_m == 4, "Saved preview restores custom slots and independent parameters")
	check(restored.preview_spread_mode == ShotgunSettings.SpreadMode.NO_INWARD and restored._settings.spread_mode == ShotgunSettings.SpreadMode.NO_INWARD and source_gun.shotgun.spread_mode == source_mode, "Scene reload preserves preview mode without changing the weapon mode")
	check(restored.shots[0].size() == 3 and packed.get_state().get_node_count() == 1, "Restored scene rebuilds only transient UI and samples its saved pattern")
	restored.queue_free()
	await process_frame
	preview.pattern_1 = null
	preview.pattern_3 = null
	for frame in 3: await process_frame
	check(not custom.changed.is_connected(preview._queue_refresh) and preview.shots.all(func(points): return points.is_empty()), "Clearing slots disconnects unused resources and leaves three empty panels")
	check(custom.points == points_before and source_gun.shotgun.pattern_angle_degrees == source_angle and source_gun.shotgun.stable_jitter_degrees == source_jitter, "Preview sampling and slot changes leave weapon and pattern data untouched")
	preview.pattern_1 = custom
	for frame in 3: await process_frame

func _run_preview_runtime() -> void:
	DirAccess.make_dir_recursive_absolute("res://logs/shotgun_pattern_editor")
	var preview = load("res://scenes/presentation/shotgun_pattern_preview.tscn").instantiate()
	root.add_child(preview)
	var loaded_weapon := false
	for file in DirAccess.get_files_at("res://resources/weapons"):
		if file.ends_with(".tres"):
			loaded_weapon = loaded_weapon or ResourceLoader.has_cached("res://resources/weapons/" + file)
	check(not loaded_weapon, "Starting the standalone preview loads no weapon resource files")
	await _check_preview(preview)
	await _check_preview_calibration(preview)
	preview.queue_free()
	await process_frame
	print("SHOTGUN PREVIEW RUNTIME: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func _find_property(node: Node, object: Object, field: String = "points") -> EditorProperty:
	if node is EditorProperty and node.get_edited_object() == object and node.get_edited_property() == field: return node
	for child in node.get_children():
		var found := _find_property(child, object, field)
		if found != null: return found
	return null

func _mouse(canvas: Control, button: MouseButton, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	canvas._gui_input(event)
