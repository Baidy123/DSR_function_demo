@tool
extends Node3D

## Scene lifetime adapter. Area owns the clock; this node owns one coordinator.
const Settings = preload("res://scripts/enemy/config/cooperation_settings.gd")
const Coordinator = preload("res://scripts/enemy/services/squad_coordination.gd")
## 配合配置资源：拖入预设 .tres，或从资源菜单新建 EnemyCooperationSettings。
## 展开资源后用 Level 选择等级；Script 字段是节点脚本，不是预设入口。
@export var profile: EnemyCooperationSettings = Settings.new():
	set(value):
		profile = value
		update_configuration_warnings()
@export var faction_id: StringName = &"enemy"
@export var communication_group: StringName = &""
var coordinator = Coordinator.new()
var team_id = 0
var _area: WeakRef
var _advanced_frame = -1

func squad_configuration() -> Dictionary:
	return {"level": profile.level if profile != null else 0,
		"values": profile.values() if profile != null else {},
		"overridden": profile.overridden.duplicate() if profile != null else PackedStringArray(),
		"diagnostic": "缺少团队意识配置，使用个人行为和合法情报共享。" if profile == null else ""}

func fingerprint() -> int:
	return hash([faction_id, communication_group, profile.fingerprint() if profile != null else 0])

func _ready() -> void:
	if not Engine.is_editor_hint(): _connect_area.call_deferred()

func _connect_area() -> void:
	if not is_inside_tree(): return
	var ancestor = get_parent()
	while ancestor != null:
		if ancestor.has_method("enemy_environment"):
			var services: Dictionary = ancestor.enemy_environment()
			if services.get("cooperation") != null: services.cooperation.register_squad(self)
			return
		ancestor = ancestor.get_parent()

func attach_to_area(board, identity: int) -> void:
	var old = _area.get_ref() if _area != null else null
	if old != null and old != board: old.unregister_squad(self)
	_area = weakref(board)
	team_id = identity
	_advanced_frame = -1
	coordinator.bind_environment(board)

func advance_from_area(frame: int) -> void:
	if frame == _advanced_frame or _area == null: return
	_advanced_frame = frame
	coordinator.advance()

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	var board = _area.get_ref() if _area != null else null
	if board != null: board.unregister_squad(self)
	else: coordinator.reset()
	_area = null
	team_id = 0
	_advanced_frame = -1

func _get_configuration_warnings() -> PackedStringArray:
	if profile == null: return PackedStringArray(["请设置团队意识配置；缺失时使用个人 Utility。"])
	return PackedStringArray()
