@tool
extends EditorPlugin

var weapon_inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	weapon_inspector = preload("res://addons/weapon_mode_inspector/weapon_inspector.gd").new()
	add_inspector_plugin(weapon_inspector)
	EditorInterface.get_inspector().property_edited.connect(_on_property_edited)


func _exit_tree() -> void:
	var inspector := EditorInterface.get_inspector()
	if inspector.property_edited.is_connected(_on_property_edited):
		inspector.property_edited.disconnect(_on_property_edited)
	remove_inspector_plugin(weapon_inspector)


func _on_property_edited(property: String) -> void:
	if property not in ["weapon", "primary_weapon", "secondary_weapon"]:
		return
	# 资源引用更换后，等本次编辑事件结束再刷新面板。
	_refresh_weapon.call_deferred()


func _refresh_weapon() -> void:
	var owner := EditorInterface.get_inspector().get_edited_object()
	if owner == null or owner.get_script() == null:
		return
	var script_path: String = owner.get_script().resource_path
	var weapons: Array = []
	if script_path == "res://scripts/enemy/enemy_actor.gd":
		weapons.append(owner.get("weapon"))
	elif script_path == "res://scripts/player/player_weapon_slots.gd":
		weapons.append(owner.get("primary_weapon"))
		weapons.append(owner.get("secondary_weapon"))
	for weapon in weapons:
		if weapon is Resource:
			weapon.notify_property_list_changed()
