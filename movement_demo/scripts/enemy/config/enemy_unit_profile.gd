@tool
extends Resource
class_name EnemyUnitProfile

@export var unit_id: StringName
@export var display_name: String
## 能力标识可扩展，不以近战/远程枚举作为唯一兵种身份。
@export var capabilities: Array[StringName] = [&"locomotion"]
@export_group("默认行为")
@export var default_behaviors: Array[EnemyActionDefinition] = []
@export_group("战术动作")
@export var tactical_actions: Array[EnemyActionDefinition] = []

func definition(id: StringName) -> EnemyActionDefinition:
	for item in default_behaviors + tactical_actions:
		if item != null and item.action_id == id:
			return item
	return null

func supports(requirements: Array) -> bool:
	return requirements.all(func(capability): return capabilities.has(capability))

func fingerprint() -> int:
	var data: Array = [unit_id, capabilities]
	for list in [default_behaviors, tactical_actions]:
		data.append(list.size())
		for entry in list:
			data.append([entry.action_id, entry.category, entry.implementation, entry.includes, entry.required_capabilities, entry.parameters] if entry != null else null)
	return hash(data)
