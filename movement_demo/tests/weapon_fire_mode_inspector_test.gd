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
	weapon.magazine_capacity = 27
	EditorInterface.edit_resource(weapon)
	for frame in 30: await process_frame
	EditorInterface.get_inspector().expand_all_folding()
	for frame in 10: await process_frame
	var ranged := _properties(EditorInterface.get_inspector(), weapon)
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
	check(undone and weapon.fire_mode != WeaponData.FireMode.MELEE and _properties(EditorInterface.get_inspector(), weapon).has("magazine_capacity"), "缺少资源即时通知时，撤销也恢复远程字段")
	weapon.set_block_signals(true)
	var redone: bool = history.redo()
	weapon.set_block_signals(false)
	for frame in 30: await process_frame
	check(redone and weapon.fire_mode == WeaponData.FireMode.MELEE and not _properties(EditorInterface.get_inspector(), weapon).has("magazine_capacity") and weapon.magazine_capacity == 27, "缺少资源即时通知时，重做重新隐藏并保留数值")
	# 使用实际敌人节点的内嵌资源 Inspector，并通过资源选择器展开。
	EditorInterface.open_scene_from_path("res://scenes/enemy/enemy.tscn")
	await create_timer(1.0).timeout
	var actor = EditorInterface.get_edited_scene_root()
	var nested := WeaponData.new()
	nested.magazine_capacity = 31
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
	EditorInterface.get_inspector().edit(null)
	bridge.free()
	for frame in 5: await process_frame
	print("Weapon fire mode inspector: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _select_mode(weapon: WeaponData, mode: int, suppress_notification: bool = false) -> void:
	for prop in _descendants(EditorInterface.get_inspector(), "EditorProperty"):
		if prop.get_edited_object() != weapon or prop.get_edited_property() != "fire_mode": continue
		for option in _descendants(prop, "OptionButton"):
			var index: int = option.get_item_index(mode)
			option.select(index)
			weapon.set_block_signals(suppress_notification)
			option.item_selected.emit(index)
			weapon.set_block_signals(false)
			return
	check(false, "未找到Fire Mode原生下拉框")


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
