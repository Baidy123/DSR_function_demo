extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 等待编辑器启动完成，避免恢复场景覆盖本测试正在检查的对象。
	await create_timer(3.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
	var weapon := WeaponData.new()
	_check_layout(weapon)
	weapon.magazine_capacity = 27
	EditorInterface.edit_resource(weapon)
	for frame in 30: await process_frame
	EditorInterface.get_inspector().expand_all_folding()
	for frame in 10: await process_frame
	var ranged := _properties(EditorInterface.get_inspector(), weapon)
	for field in ["hit_accuracy_loss", "suppression_accuracy_loss", "hit_speed_loss", "melee_accuracy_loss"]:
		var found := false
		for prop in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
			if prop.get_edited_object() != weapon or prop.get_edited_property() != field: continue
			var spins := _descendants(prop, "SpinBox")
			found = spins.size() == 1 and spins[0].suffix == "%" and not spins[0].tooltip_text.is_empty()
		check(found, "攻击效果在真实检查器显示百分比及解释：" + field)
	check(ranged.has("fire_mode") and not ranged.has("weapon_type") and ranged.has("magazine_capacity") and ranged.has("melee_range"), "原Fire Mode和枪械近战参数可见，没有额外Weapon Type")
	var bridge := EditorPlugin.new()
	var manager = bridge.get_undo_redo()
	_select_mode(weapon, WeaponData.FireMode.MELEE)
	for frame in 30: await process_frame
	var melee := _properties(EditorInterface.get_inspector(), weapon)
	check(melee.has("fire_mode") and melee.has("melee_damage") and melee.has("melee_range"), "选近战后Fire Mode仍可修改且近战参数可见")
	check(not melee.has("magazine_capacity") and not melee.has("shot_accuracy_penalty") and not melee.has("shot_spread_penalty_degrees"), "近战隐藏弹匣及两种远程准度参数")
	var history = manager.get_history_undo_redo(manager.get_object_history_id(weapon))
	check(history.undo(), "原生编辑器撤销Fire Mode切换")
	for frame in 30: await process_frame
	var restored := _properties(EditorInterface.get_inspector(), weapon)
	check(restored.has("magazine_capacity") and weapon.fire_mode == WeaponData.FireMode.SEMI_AUTO and weapon.magazine_capacity == 27, "撤销回单发恢复字段且保留原数值")
	check(history.redo(), "原生编辑器重做Fire Mode切换")
	for frame in 30: await process_frame
	check(not _properties(EditorInterface.get_inspector(), weapon).has("magazine_capacity") and weapon.magazine_capacity == 27, "重做为近战重新隐藏字段且不清零")
	# 已打开的资源热更新后，旧实例可能漏发 setter 通知。模拟此现场，要求
	# 控件在操作完成后自行刷新；不能只靠新建资源的 setter 使测试通过。
	_select_mode(weapon, WeaponData.FireMode.AUTOMATIC, true)
	for frame in 30: await process_frame
	check(_properties(EditorInterface.get_inspector(), weapon).has("magazine_capacity"), "缺少资源即时通知时，下拉框切回枪械仍恢复字段")
	_select_mode(weapon, WeaponData.FireMode.MELEE, true)
	for frame in 30: await process_frame
	check(not _properties(EditorInterface.get_inspector(), weapon).has("magazine_capacity"), "缺少资源即时通知时，下拉框选择近战仍隐藏字段")
	weapon.set_block_signals(true)
	var undone: bool = history.undo()
	weapon.set_block_signals(false)
	for frame in 30: await process_frame
	# 原生检查器轮询按实际时间推进；无渲染的30帧可能先于下一次刷新。
	# 仍要求真正撤销并恢复字段，只为异步UI刷新提供最多一秒的条件等待。
	var refresh_deadline := Time.get_ticks_msec() + 1000
	while undone and weapon.fire_mode != WeaponData.FireMode.MELEE and not _properties(EditorInterface.get_inspector(), weapon).has("magazine_capacity") and Time.get_ticks_msec() < refresh_deadline:
		await process_frame
	var capacity_visible: bool = _properties(EditorInterface.get_inspector(), weapon).has("magazine_capacity")
	check(undone and weapon.fire_mode != WeaponData.FireMode.MELEE and capacity_visible, "缺少资源即时通知时，撤销也恢复远程字段")
	weapon.set_block_signals(true)
	var redone: bool = history.redo()
	weapon.set_block_signals(false)
	for frame in 30: await process_frame
	check(redone and weapon.fire_mode == WeaponData.FireMode.MELEE and not _properties(EditorInterface.get_inspector(), weapon).has("magazine_capacity") and weapon.magazine_capacity == 27, "缺少资源即时通知时，重做重新隐藏并保留数值")
	await _convergence_checks(manager)
	await _player_recovery_controls(manager)
	# 使用实际敌人节点的内嵌资源 Inspector，并通过资源选择器展开。
	EditorInterface.open_scene_from_path("res://scenes/enemy/enemy.tscn")
	await create_timer(1.0).timeout
	var actor = EditorInterface.get_edited_scene_root()
	var nested := WeaponData.new()
	nested.magazine_capacity = 31
	nested.convergence_seconds = 3.0
	actor.set("weapon", nested)
	EditorInterface.inspect_object(actor)
	for frame in 30: await process_frame
	EditorInterface.get_inspector().expand_all_folding()
	for prop in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
		if prop.get_edited_object() == actor and prop.get_edited_property() == "weapon":
			for picker in _descendants(prop, "EditorResourcePicker"):
				picker.resource_selected.emit(nested, false)
	for frame in 30: await process_frame
	var nested_before := _properties(EditorInterface.get_inspector(), nested)
	check(nested_before.has("fire_mode") and nested_before.has("magazine_capacity"), "敌人 Weapon 内嵌面板的真实下拉框可操作")
	_select_mode(nested, WeaponData.FireMode.MELEE, true)
	for frame in 30: await process_frame
	var nested_melee := _properties(EditorInterface.get_inspector(), nested)
	check(nested_melee.has("melee_damage") and nested_melee.has("fire_mode") and not nested_melee.has("magazine_capacity") and not nested_melee.has("damage") and not nested_melee.has("fire_range"), "敌人内嵌面板缺少即时通知时隐藏弹匣、子弹伤害、射程")
	_select_mode(nested, WeaponData.FireMode.SEMI_AUTO, true)
	for frame in 30: await process_frame
	var nested_restored := _properties(EditorInterface.get_inspector(), nested)
	check(nested_restored.has("damage") and nested_restored.has("magazine_capacity") and nested.magazine_capacity == 31 and nested_restored.has("initial_accuracy") and not nested_restored.has("min_spread_angle_degrees"), "内嵌面板切回单发恢复数值，并保持敌人的概率模式过滤")
	var enemy_recovery := _spin(nested, "stabilize_seconds")
	check(enemy_recovery != null and enemy_recovery.editable, "敌人仍可编辑自己的恢复速度，不受玩家正数收敛时间误锁")
	EditorInterface.get_inspector().edit(null)
	bridge.free()
	for frame in 5: await process_frame
	print("Weapon fire mode inspector: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _select_mode(weapon: WeaponData, mode: int, suppress_notification: bool = false) -> void:
	_select_enum(weapon, "fire_mode", mode, suppress_notification)


func _check_layout(weapon: WeaponData) -> void:
	var groups: Array[String] = []
	var locations := {}
	var group := ""
	var subgroup := ""
	var in_weapon_script := false
	for property in weapon.get_property_list():
		if property.usage & PROPERTY_USAGE_CATEGORY:
			in_weapon_script = property.hint_string == weapon.get_script().resource_path
			continue
		if not in_weapon_script: continue
		if property.usage & PROPERTY_USAGE_GROUP:
			group = property.name
			subgroup = ""
			groups.append(group)
		elif property.usage & PROPERTY_USAGE_SUBGROUP:
			subgroup = property.name
		elif property.usage & PROPERTY_USAGE_EDITOR:
			locations[property.name] = [group, subgroup]
	check(groups == ["基本信息", "射击与弹药", "瞄准与散布", "命中效果", "近战", "外观与声音"], "原资源按确认的六组显示")
	check(locations.convergence_model == locations.spread_recovery_degrees_per_second and locations.convergence_seconds == locations.stabilize_seconds and locations.spread_recovery_delay == locations.convergence_seconds, "恢复公式、时间、旧速度与恢复等待归在同一处")
	check(locations.min_spread_angle_degrees[0] == "瞄准与散布" and locations.initial_accuracy[0] == "瞄准与散布" and locations.headshot_enabled[0] == "命中效果" and locations.visual_model[0] == locations.shot_noise[0], "散布、爆头、表现参数分别归入对应大组")


func _spin(object: Object, path: String) -> SpinBox:
	for prop in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
		if prop.get_edited_object() != object or prop.get_edited_property() != path: continue
		var spins := _descendants(prop, "SpinBox")
		if not spins.is_empty(): return spins[0]
	return null


func _player_recovery_controls(manager: EditorUndoRedoManager) -> void:
	EditorInterface.open_scene_from_path("res://scenes/player/player.tscn")
	await create_timer(1.0).timeout
	var slots = EditorInterface.get_edited_scene_root().get_node("Equipment")
	var weapon := WeaponData.new()
	weapon.spread_recovery_degrees_per_second = 7
	weapon.convergence_model = WeaponData.ConvergenceModel.QUADRATIC
	slots.set("primary_weapon", weapon)
	slots.set("secondary_weapon", null)
	EditorInterface.inspect_object(slots)
	for frame in 30: await process_frame
	EditorInterface.get_inspector().expand_all_folding()
	for prop in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
		if prop.get_edited_object() == slots and prop.get_edited_property() == "primary_weapon":
			for picker in _descendants(prop, "EditorResourcePicker"): picker.resource_selected.emit(weapon, false)
	for frame in 30: await process_frame
	EditorInterface.get_inspector().expand_all_folding()
	var legacy := _spin(weapon, "spread_recovery_degrees_per_second")
	var seconds := _spin(weapon, "convergence_seconds")
	check(legacy != null and legacy.editable and seconds != null, "玩家内嵌资源：二次＋时间0时旧速度仍可编辑")
	if seconds == null: return
	seconds.value = 3
	for frame in 30: await process_frame
	legacy = _spin(weapon, "spread_recovery_degrees_per_second")
	check(legacy != null and not legacy.editable and legacy.tooltip_text.contains("当前玩家"), "玩家新时间大于0时旧速度置灰并显示生效说明")
	if legacy != null: legacy.value = 9
	check(weapon.spread_recovery_degrees_per_second == 7, "禁用的输入不会把旧速度写回资源")
	var history := manager.get_history_undo_redo(manager.get_object_history_id(weapon))
	var undone := history.undo()
	for frame in 30: await process_frame
	legacy = _spin(weapon, "spread_recovery_degrees_per_second")
	check(undone and weapon.convergence_seconds == 0 and legacy != null and legacy.editable and weapon.spread_recovery_degrees_per_second == 7, "撤销到时间0会解锁旧速度并保留原数值")
	var redone := history.redo()
	for frame in 30: await process_frame
	legacy = _spin(weapon, "spread_recovery_degrees_per_second")
	check(redone and weapon.convergence_seconds == 3 and legacy != null and not legacy.editable, "重做正数时间会重新禁用旧速度")
	_select_mode(weapon, WeaponData.FireMode.SHOTGUN)
	for frame in 30: await process_frame
	for prop in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
		if prop.get_edited_object() == weapon and prop.get_edited_property() == "shotgun":
			for picker in _descendants(prop, "EditorResourcePicker"): picker.resource_selected.emit(weapon.shotgun, false)
	for frame in 30: await process_frame
	EditorInterface.get_inspector().expand_all_folding()
	var settle := _spin(weapon.shotgun, "settle_seconds")
	check(settle != null and not settle.editable, "玩家霰弹内嵌配置的原恢复用时也按所属武器禁用")
	EditorInterface.edit_resource(weapon.shotgun)
	for frame in 30: await process_frame
	settle = _spin(weapon.shotgun, "settle_seconds")
	check(settle != null and settle.editable and settle.tooltip_text.contains("独立打开"), "独立霰弹资源不猜测父武器，保留编辑并解释生效条件")
	weapon.fire_mode = WeaponData.FireMode.SEMI_AUTO
	EditorInterface.edit_resource(weapon)
	for frame in 30: await process_frame
	legacy = _spin(weapon, "spread_recovery_degrees_per_second")
	check(legacy != null and legacy.editable and legacy.tooltip_text.contains("敌人仍使用"), "独立共享武器仍可调敌人旧速度，同时明确玩家未使用")


func _convergence_checks(manager: EditorUndoRedoManager) -> void:
	var weapon := WeaponData.new()
	EditorInterface.edit_resource(weapon)
	for frame in 30: await process_frame
	EditorInterface.get_inspector().expand_all_folding()
	for frame in 10: await process_frame
	var fields := _properties(EditorInterface.get_inspector(), weapon)
	check(fields.has("convergence_model") and fields.has("convergence_seconds") and not fields.has("convergence_exponent_k"), "线性显示收敛公式与时间，隐藏指数强度")
	_select_enum(weapon, "convergence_model", WeaponData.ConvergenceModel.EXPONENTIAL)
	for frame in 30: await process_frame
	check(weapon.convergence_model == 2 and _properties(EditorInterface.get_inspector(), weapon).has("convergence_exponent_k"), "真实公式下拉框写入指数并显示强度")
	var history := manager.get_history_undo_redo(manager.get_object_history_id(weapon))
	var undone := history.undo()
	for frame in 30: await process_frame
	check(undone and weapon.convergence_model == 0 and not _properties(EditorInterface.get_inspector(), weapon).has("convergence_exponent_k"), "撤销公式后字段按线性刷新")
	var redone := history.redo()
	for frame in 30: await process_frame
	check(redone and weapon.convergence_model == 2 and _properties(EditorInterface.get_inspector(), weapon).has("convergence_exponent_k"), "重做公式后恢复指数强度")
	var edited := false
	for prop in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
		if prop.get_edited_object() != weapon or prop.get_edited_property() != "convergence_seconds": continue
		for spin in _descendants(prop, "SpinBox"):
			edited = spin.suffix == "s" and not spin.tooltip_text.is_empty()
			spin.value = 2.75
	for frame in 10: await process_frame
	check(edited and weapon.convergence_seconds == 2.75, "真实秒数控件有单位／兼容说明且写回资源")
	undone = history.undo()
	for frame in 10: await process_frame
	check(undone and weapon.convergence_seconds == 0, "收敛时间可原生撤销")
	redone = history.redo()
	for frame in 10: await process_frame
	check(redone and weapon.convergence_seconds == 2.75, "收敛时间可原生重做")
	var path := "user://convergence-inspector-test.tres"
	var saved := ResourceSaver.save(weapon, path)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as WeaponData
	check(saved == OK and loaded.convergence_model == 2 and loaded.convergence_seconds == 2.75, "检查器操作后的公式与时间保存重载一致")
	DirAccess.remove_absolute(path)
	_select_mode(weapon, WeaponData.FireMode.SHOTGUN)
	for frame in 30: await process_frame
	fields = _properties(EditorInterface.get_inspector(), weapon)
	check(fields.has("convergence_model") and fields.has("convergence_seconds"), "霰弹保留玩家收敛入口")
	_select_mode(weapon, WeaponData.FireMode.MELEE)
	for frame in 30: await process_frame
	fields = _properties(EditorInterface.get_inspector(), weapon)
	check(not fields.has("convergence_model") and not fields.has("convergence_seconds") and not fields.has("convergence_exponent_k"), "近战隐藏全部瞄准收敛字段")


func _select_enum(weapon: WeaponData, path: String, mode: int, suppress_notification: bool = false) -> void:
	for prop in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
		if prop.get_edited_object() != weapon or prop.get_edited_property() != path: continue
		for option in _descendants(prop, "OptionButton"):
			var index: int = option.get_item_index(mode)
			option.select(index)
			weapon.set_block_signals(suppress_notification)
			option.item_selected.emit(index)
			weapon.set_block_signals(false)
			return
	check(false, "未找到原生下拉框：" + path)


func _descendants(node: Node, type: String) -> Array:
	var result := []
	for child in node.get_children(true):
		if child.is_class(type): result.append(child)
		result.append_array(_descendants(child, type))
	return result


func _properties(node: Node, weapon: WeaponData) -> Dictionary:
	var result := {}
	if node is EditorProperty and node.get_edited_object() == weapon:
		result[node.get_edited_property()] = true
	for child in node.get_children(true):
		result.merge(_properties(child, weapon))
	return result


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
