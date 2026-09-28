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
	if property not in ["aim_mode", "weapon", "primary_weapon", "secondary_weapon"]:
		return
	# 当前事件结束后再重建资源面板；撤销/重做模式选择也会触发该信号。
	_refresh_weapon.call_deferred()


func _refresh_weapon() -> void:
	var combat = EditorInterface.get_inspector().get_edited_object()
	if combat == null or combat.get_script() == null:
		return
	var script_path: String = combat.get_script().resource_path
	var weapons: Array = []
	if script_path == "res://scripts/enemy/enemy_actor.gd":
		weapons.append(combat.get("weapon"))
	elif script_path in ["res://scripts/player/player_combat_v3.gd", "res://scripts/player/player_weapon_slots.gd"]:
		var slots = combat if script_path == "res://scripts/player/player_weapon_slots.gd" else combat.get_node_or_null("../WeaponSlots")
		if slots != null:
			weapons.append(slots.get("primary_weapon"))
			weapons.append(slots.get("secondary_weapon"))
	for weapon in weapons:
		if weapon is Resource:
			weapon.notify_property_list_changed()
