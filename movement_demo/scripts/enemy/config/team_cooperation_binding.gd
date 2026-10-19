@tool
extends Resource
class_name EnemyTeamCooperationBinding

## A squad owns only team awareness. Unit and personal Training remain separate.
const Settings = preload("res://scripts/enemy/config/cooperation_settings.gd")
const LEVEL_NAMES := ["仅视野共享", "战术配合", "强配合"]

@export var faction_id: StringName = &"enemy":
	set(value):
		faction_id = value
		emit_changed()
@export var communication_group: StringName = &"":
	set(value):
		communication_group = value
		emit_changed()
@export var profile: Settings = Settings.new():
	set(value):
		profile = value
		emit_changed()

func squad_key() -> String:
	return JSON.stringify([String(faction_id), String(communication_group)])

func fingerprint() -> int:
	return hash([faction_id, communication_group, profile.fingerprint() if profile != null else 0])

## Editor lookup does not instantiate a runtime board or borrow another member.
static func find_for_member(member: Node) -> Dictionary:
	if member == null or member.get("faction_id") == null or member.get("communication_group") == null: return {}
	var squad := squad_for_member(member)
	if squad != null:
		var settings: Dictionary = squad.squad_configuration()
		return {"binding": squad, "squad": squad, "squad_key": String(squad.name),
			"level": settings.level, "diagnostic": settings.diagnostic}
	var area := member.get_parent()
	while area != null:
		var bindings = area.get("team_cooperation_bindings")
		if bindings is Array:
			var matches: Array = []
			for binding in bindings:
				if binding is EnemyTeamCooperationBinding and binding.faction_id == member.faction_id and binding.communication_group == member.communication_group:
					matches.append(binding)
			if matches.is_empty(): return {}
			var binding: EnemyTeamCooperationBinding = matches[0]
			var diagnostic := "同一小队存在重复绑定，战术安排已停用。" if matches.size() > 1 else ("小队缺少团队意识配置。" if binding.profile == null else "")
			return {"binding": binding, "area": area, "squad_key": binding.squad_key(), "diagnostic": diagnostic,
				"level": int(binding.profile.level) if diagnostic.is_empty() else Settings.Level.INTEL_ONLY}
		area = area.get_parent()
	return {}

## Scene identity is the nearest explicit squad inside this area, independent
## of faction, radio group, node name and shared configuration resource.
static func squad_for_member(member: Node) -> Node:
	var current := member.get_parent() if member != null else null
	while current != null:
		if current.has_method("enemy_environment"): return null
		if current.has_method("squad_configuration"): return current
		current = current.get_parent()
	return null

static func effective_faction(member: Node) -> StringName:
	var squad := squad_for_member(member)
	return squad.faction_id if squad != null else member.faction_id

static func effective_communication_group(member: Node) -> StringName:
	var squad := squad_for_member(member)
	return squad.communication_group if squad != null else member.communication_group
