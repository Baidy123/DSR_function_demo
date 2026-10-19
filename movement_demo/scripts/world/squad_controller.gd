@tool
extends Node3D

## Scene container and sole owner of this squad's configuration and runtime.
## The area's active clock calls advance_from_area; no independent AI loop.
const Settings = preload("res://scripts/enemy/config/cooperation_settings.gd")
const Coordination = preload("res://scripts/enemy/services/squad_coordination.gd")
@export var profile: Settings = Settings.new():
	set(value):
		profile = value
		update_configuration_warnings()
@export var faction_id: StringName = &"enemy"
@export var communication_group: StringName = &""
var coordinator = Coordination.new()
var team_id := 0
var _area_service: WeakRef
var _last_frame := -1

func squad_configuration() -> Dictionary:
	return {"level": int(profile.level) if profile != null else 0,
		"values": profile.values() if profile != null else {},
		"overridden": profile.overridden.duplicate() if profile != null else PackedStringArray(),
		"diagnostic": "小队缺少团队意识配置，团队战术安排已停用。" if profile == null else ""}

func fingerprint() -> int:
	return hash([faction_id, communication_group, profile.get_instance_id() if profile != null else 0, profile.fingerprint() if profile != null else 0])

func _enter_tree() -> void:
	if not Engine.is_editor_hint(): _register_area.call_deferred()

func _register_area() -> void:
	if Engine.is_editor_hint(): return
	if not is_inside_tree(): return
	var area := get_parent()
	while area != null and not area.has_method("enemy_environment"): area = area.get_parent()
	if area != null:
		var environment: Dictionary = area.enemy_environment()
		if environment.get("cooperation") != null: environment.cooperation.register_squad(self)

func attach_to_area(board, identity: int) -> void:
	var previous = _area_service.get_ref() if _area_service != null else null
	if previous != null and previous != board: previous.unregister_squad(self)
	_area_service = weakref(board)
	team_id = identity
	coordinator.bind_environment(board)
	_last_frame = -1

func advance_from_area(frame: int) -> void:
	if frame == _last_frame: return
	_last_frame = frame
	coordinator.advance()

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	var board = _area_service.get_ref() if _area_service != null else null
	if board != null: board.unregister_squad(self)
	_area_service = null
	team_id = 0

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if profile == null: warnings.append("请设置团队意识 Profile；缺失时仅保留个人行为与合法共享情报。")
	if profile != null and not profile.resource_path.is_empty():
		warnings.append("当前使用外部团队意识模板；编辑模板会影响所有引用它的小队，运行计划仍独立。")
	return warnings
