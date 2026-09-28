extends RefCounted

## 纯配置解析；既不创建运行对象，也不访问场景。检查器与游戏使用同一结果。
static func resolve(unit: EnemyUnitProfile, training: EnemyTrainingProfile) -> Dictionary:
	var result := {"definitions": {}, "included_by": {}, "errors": []}
	if unit == null:
		return result
	var catalog: Dictionary = {}
	var duplicate: Dictionary = {}
	for category in [EnemyActionDefinition.Category.DEFAULT, EnemyActionDefinition.Category.TACTICAL]:
		var entries = unit.default_behaviors if category == EnemyActionDefinition.Category.DEFAULT else unit.tactical_actions
		for definition in entries:
			if definition == null:
				continue
			var id: StringName = definition.action_id
			if catalog.has(id):
				duplicate[id] = true
				result.errors.append("重复动作 ID：" + String(id))
			if id.is_empty() or definition.category != category or not valid_implementation(definition.implementation):
				result.errors.append("无效动作或分类错误：" + String(id))
				continue
			catalog[id] = definition
	for id in duplicate:
		catalog.erase(id)
	for definition in unit.default_behaviors:
		if definition != null and catalog.has(definition.action_id) and unit.supports(definition.required_capabilities):
			result.definitions[definition.action_id] = definition
	for id in training.selected_tactics if training != null else []:
		if not catalog.has(id) or catalog[id].category != EnemyActionDefinition.Category.TACTICAL:
			continue # 保留旧兵种选择，但不参与当前装配。
		var closure: Dictionary = {}
		var error := _expand(id, catalog, unit, [], closure)
		if not error.is_empty():
			result.errors.append(error)
			continue
		for included in closure:
			result.definitions[included] = closure[included]
			if included != id:
				if not result.included_by.has(included):
					result.included_by[included] = []
				result.included_by[included].append(id)
	return result

static func _expand(id: StringName, catalog: Dictionary, unit: EnemyUnitProfile, visiting: Array, closure: Dictionary) -> String:
	if visiting.has(id):
		return "动作包含关系成环：" + String(id)
	if not catalog.has(id):
		return "兵种缺少关联动作：" + String(id)
	var definition: EnemyActionDefinition = catalog[id]
	if not unit.supports(definition.required_capabilities):
		return "兵种缺少动作所需能力：" + String(id)
	var next := visiting.duplicate()
	next.append(id)
	for included in definition.includes:
		var error := _expand(included, catalog, unit, next, closure)
		if not error.is_empty():
			return error
	closure[id] = definition
	return ""

static func instantiate(definition: EnemyActionDefinition, context):
	var implementation: Script = definition.implementation
	if not valid_implementation(implementation):
		push_error("动作未实现统一协议：" + String(definition.action_id))
		return null
	var action = implementation.new()
	action.action_id = definition.action_id
	action.config_section = definition.config_section
	action.definition = definition
	action.setup(context)
	return action

static func valid_implementation(implementation: Script) -> bool:
	var parent := implementation
	var base: Script = preload("res://scripts/enemy/actions/enemy_action.gd")
	while parent != null and parent != base:
		parent = parent.get_base_script()
	return parent != null
