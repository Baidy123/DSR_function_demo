@tool
extends EditorProperty

const MODE_LABELS := ["自动锁定", "鼠标瞄准"]

var _owner: Object
var _shotgun_panel := false
var _fields: Array[Dictionary]
var _history: EditorUndoRedoManager
var _controls: Array[Dictionary] = [{}, {}]


func configure(owner: Object, tracking: Object, fields: Array[Dictionary], history: EditorUndoRedoManager) -> void:
	_owner = owner
	_shotgun_panel = tracking is ShotgunSettings
	_fields = fields
	_history = history
	draw_label = false
	var tabs := TabContainer.new()
	tabs.name = "AimModeTabs"
	add_child(tabs)
	set_bottom_editor(tabs)
	for mode in MODE_LABELS.size():
		var page := VBoxContainer.new()
		tabs.add_child(page)
		tabs.set_tab_title(mode, MODE_LABELS[mode])
		for field in _fields:
			_add_field(page, mode, field)
	tabs.tab_changed.connect(func(_mode: int): _update_property())
	_update_property()


func _ready() -> void:
	_history.history_changed.connect(_update_property)
	_history.version_changed.connect(_update_property)
	var owner_history := _history.get_history_undo_redo(_history.get_object_history_id(_owner))
	if owner_history != null:
		owner_history.version_changed.connect(_update_property)


func _add_field(page: VBoxContainer, mode: int, field: Dictionary) -> void:
	var path: String = field.name
	var row := HBoxContainer.new()
	row.name = path
	page.add_child(row)
	var caption := Label.new()
	caption.text = field.label
	caption.tooltip_text = field.help
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var input: Control
	if field.hint == PROPERTY_HINT_ENUM:
		var option := OptionButton.new()
		for entry in String(field.hint_string).split(","):
			var parts := entry.rsplit(":", true, 1)
			option.add_item(parts[0], int(parts[1]) if parts.size() == 2 else option.item_count)
		option.item_selected.connect(func(index: int): _edit(mode, field, option.get_item_id(index)))
		input = option
	else:
		var spin := SpinBox.new()
		var scale_factor := configure_spin(spin, field.hint_string, field.percentage)
		spin.value_changed.connect(func(value: float): _edit(mode, field, value / scale_factor))
		input = spin
	input.name = "Value"
	input.tooltip_text = field.help
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	add_focusable(input.get_line_edit() if input is SpinBox else input)
	_controls[mode][path] = input


func _tracking_source() -> Object:
	return _owner.get_shotgun_settings() if _shotgun_panel else _owner


func _read(mode: int, path: String) -> Variant:
	if mode == 0:
		return _tracking_source().get(path)
	if _owner is WeaponData:
		return _owner.mouse_aim_accuracy.get(path) if _owner.mouse_aim_accuracy != null else _tracking_source().get(path)
	return _owner.get("mouse_" + path)


func _update_property() -> void:
	if not is_instance_valid(_owner): return
	for mode in MODE_LABELS.size():
		for field in _fields:
			var path: String = field.name
			var value = _read(mode, path)
			var input: Control = _controls[mode][path]
			if input is OptionButton:
				input.select(input.get_item_index(int(value)))
				input.disabled = read_only
			else:
				input.set_value_no_signal(float(value) * (100.0 if field.percentage else 1.0))
				input.editable = not read_only and (path != "convergence_exponent_k"
					or _read(mode, "convergence_model") == WeaponData.ConvergenceModel.EXPONENTIAL)


func _set_read_only(_value: bool) -> void:
	_update_property()


func _edit(mode: int, field: Dictionary, value: Variant) -> void:
	var path: String = field.name
	if read_only or not is_instance_valid(_owner) or _read(mode, path) == value:
		return
	var target := _tracking_source()
	var property := path
	if mode == 1 and _owner is WeaponData:
		var profile: Resource = _owner.mouse_aim_accuracy
		if profile == null:
			profile = _create_profile(_owner)
			profile.set(path, value)
			target = _owner
			property = "mouse_aim_accuracy"
			value = profile
		else:
			target = profile
	elif mode == 1:
		property = "mouse_" + path
	elif _shotgun_panel and _owner.shotgun == null:
		target.set(path, value)
		value = target
		target = _owner
		property = "shotgun"
	var context := _owner
	if target is Resource and not target.is_built_in() and not target.resource_path.is_empty():
		context = target
	_history.create_action("调整%s · %s" % [MODE_LABELS[mode], field.label], UndoRedo.MERGE_DISABLE, context)
	_history.add_do_property(target, property, value)
	_history.add_undo_property(target, property, target.get(property))
	if target is Resource:
		_history.add_do_method(target, &"emit_changed")
		_history.add_undo_method(target, &"emit_changed")
	_history.commit_action()
	_update_property()


func _create_profile(weapon: WeaponData) -> Resource:
	var profile := WeaponData.MouseAimAccuracy.new()
	var shotgun := weapon.get_shotgun_settings()
	for field in profile.get_property_list():
		if not field.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var value = weapon.get(field.name)
		if value == null:
			value = shotgun.get(field.name)
		if value != null:
			profile.set(field.name, value)
	return profile


static func configure_spin(spin: SpinBox, range_hint: String, percentage: bool) -> float:
	var parts := range_hint.split(",")
	var factor := 100.0 if percentage else 1.0
	spin.min_value = float(parts[0]) * factor
	spin.max_value = float(parts[1]) * factor
	spin.step = float(parts[2]) * factor
	spin.allow_greater = parts.has("or_greater")
	spin.allow_lesser = parts.has("or_less")
	if percentage:
		spin.suffix = "%"
	else:
		for part in parts:
			if part.begins_with("suffix:"):
				spin.suffix = part.trim_prefix("suffix:")
	return factor
