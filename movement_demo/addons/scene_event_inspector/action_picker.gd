@tool
extends MenuButton

signal action_selected(action: SceneAction)

const CATEGORY_NAMES: Array[String] = [
	"流程", "战斗", "演出", "角色/NPC", "世界", "状态", "场景切换", "高级",
]
const CATEGORY_ICONS: Array[StringName] = [
	&"Time", &"AnimationTrackList", &"Camera3D", &"CharacterBody3D",
	&"Node3D", &"Resource", &"PackedScene", &"Tools",
]

const ENTRIES: Array[Dictionary] = [
	{"id": &"wait", "category": 0, "name": "等待", "script": preload("res://scripts/systems/scene_events/actions/flow/wait_action.gd")},
	{"id": &"wait_signal", "category": 0, "name": "等待信号", "script": preload("res://scripts/systems/scene_events/actions/flow/wait_signal_action.gd")},
	{"id": &"complete_scene", "category": 0, "name": "完成场景", "script": preload("res://scripts/systems/scene_events/actions/flow/complete_scene_action.gd")},
	{"id": &"spawn_wave", "category": 1, "name": "生成波次", "script": preload("res://scripts/systems/scene_events/actions/combat/spawn_wave_action.gd")},
	{"id": &"wait_wave_cleared", "category": 1, "name": "等待清场", "script": preload("res://scripts/systems/scene_events/actions/combat/wait_wave_cleared_action.gd")},
	{"id": &"camera", "category": 2, "name": "镜头调度", "script": preload("res://scripts/systems/scene_events/actions/presentation/camera_action.gd")},
	{"id": &"dialogue", "category": 2, "name": "触发对话", "script": preload("res://scripts/systems/scene_events/actions/presentation/dialogue_action.gd")},
	{"id": &"play_audio", "category": 2, "name": "播放音频", "script": preload("res://scripts/systems/scene_events/actions/presentation/play_audio_action.gd")},
	{"id": &"move_actor", "category": 3, "name": "移动角色", "script": preload("res://scripts/systems/scene_events/actions/actor/move_actor_action.gd")},
	{"id": &"seat_actor", "category": 3, "name": "入座/离席", "script": preload("res://scripts/systems/scene_events/actions/actor/seat_actor_action.gd")},
	{"id": &"set_actor_visible", "category": 3, "name": "显示/隐藏角色", "script": preload("res://scripts/systems/scene_events/actions/actor/set_actor_visible_action.gd")},
	{"id": &"set_door", "category": 4, "name": "开关门", "script": preload("res://scripts/systems/scene_events/actions/world/set_door_action.gd")},
	{"id": &"call_interaction", "category": 4, "name": "调用交互", "script": preload("res://scripts/systems/scene_events/actions/world/call_interaction_action.gd")},
	{"id": &"set_flag", "category": 5, "name": "设置旗标", "script": preload("res://scripts/systems/scene_events/actions/state/set_flag_action.gd")},
	{"id": &"give_equipment", "category": 5, "name": "发放装备", "script": preload("res://scripts/systems/scene_events/actions/state/give_equipment_action.gd")},
	{"id": &"update_quest", "category": 5, "name": "更新任务", "script": preload("res://scripts/systems/scene_events/actions/state/update_quest_action.gd")},
	{"id": &"change_scene", "category": 6, "name": "切换场景", "script": preload("res://scripts/systems/scene_events/actions/transition/change_scene_action.gd")},
	{"id": &"restart_scene", "category": 6, "name": "重开场景", "script": preload("res://scripts/systems/scene_events/actions/transition/restart_scene_action.gd")},
	{"id": &"run_provider", "category": 7, "name": "调用动作提供者", "script": preload("res://scripts/systems/scene_events/actions/advanced/run_provider_action.gd")},
]


static func category_names() -> PackedStringArray:
	return PackedStringArray(CATEGORY_NAMES)


static func registry() -> Array[Dictionary]:
	var result: Array[Dictionary] = ENTRIES.duplicate(true)
	for entry in result:
		entry["icon"] = CATEGORY_ICONS[entry.category]
	return result


static func create_action(id: StringName) -> SceneAction:
	for entry in ENTRIES:
		if entry.id == id:
			return entry.script.new() as SceneAction
	return null


static func entry_for_action(action: SceneAction) -> Dictionary:
	if action == null:
		return {}
	for entry in ENTRIES:
		if action.get_script() == entry.script:
			return entry
	return {}


func _ready() -> void:
	text = "添加动作"
	_build_menu()


func _build_menu() -> void:
	var popup := get_popup()
	popup.clear()
	for child in popup.get_children():
		popup.remove_child(child)
		child.queue_free()
	for category_index in CATEGORY_NAMES.size():
		var submenu := PopupMenu.new()
		submenu.name = "Category%d" % category_index
		popup.add_child(submenu)
		popup.add_submenu_node_item(CATEGORY_NAMES[category_index], submenu, category_index)
		submenu.id_pressed.connect(_on_entry_pressed)
		for entry_index in ENTRIES.size():
			var entry := ENTRIES[entry_index]
			if entry.category == category_index:
				submenu.add_item(entry.name, entry_index)
				var theme := EditorInterface.get_editor_theme()
				var icon_name: StringName = CATEGORY_ICONS[category_index]
				if theme != null and theme.has_icon(icon_name, &"EditorIcons"):
					submenu.set_item_icon(submenu.item_count - 1,
						theme.get_icon(icon_name, &"EditorIcons"))


func _on_entry_pressed(entry_index: int) -> void:
	if entry_index < 0 or entry_index >= ENTRIES.size():
		return
	action_selected.emit(create_action(ENTRIES[entry_index].id))
