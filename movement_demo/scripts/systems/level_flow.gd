extends CanvasLayer

## 五关共用：清场后只开放返回酒馆，下一关由 A 在酒馆中解锁。

const LEVELS: Array[String] = [
	"res://scenes/world/levels/lvl_1.tscn",
	"res://scenes/world/levels/lvl_2.tscn",
	"res://scenes/world/levels/lvl_3.tscn",
	"res://scenes/world/levels/lvl_4.tscn",
	"res://scenes/world/levels/lvl_5.tscn",
]

@export_range(1, 5) var level_number: int = 1
@export_node_path("Interactable") var return_portal_path: NodePath

@onready var _health = get_parent().get_node("Player/Health")
@onready var _return_portal = get_node_or_null(return_portal_path) as Interactable

var _completion_pending := false


func _ready() -> void:
	$Progress.text = "第 %d 关 / 5" % level_number
	get_parent().get_node("EnemyWaves").encounter_completed.connect(_on_encounter_completed)


func _on_encounter_completed() -> void:
	if _completion_pending or (_return_portal != null and _return_portal.visible):
		return
	_completion_pending = true
	_show_completion.call_deferred()


func _show_completion() -> void:
	_completion_pending = false
	if _health.is_dead:
		return
	if _return_portal == null:
		push_error("第%d关完成但未配置返回酒馆传送门" % level_number)
		return
	_return_portal.visible = true
	_return_portal.enabled = true
	_return_portal.monitoring = true
