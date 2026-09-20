extends Node3D

const SHORT_REASONS := {"空间被占": "占位", "不可达": "无路", "射界受阻": "挡枪",
	"无遮挡": "无掩", "超射程": "超距", "无武器": "无枪", "完全遮挡": "全遮"}

# 只读的运行时调试显示，独立于AI的决策更新；关闭后不再执行候选查询。
var assessments: Array[Dictionary] = []
var _labels: Array[Label3D] = []
var _elapsed: float = 0.0
@onready var selection = get_parent()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	set_physics_process(OS.is_debug_build())


func _physics_process(delta: float) -> void:
	var ai = selection.ai
	if not selection.debug_attack_points or selection.enemy.is_dead or not ai.is_arena_active() or not ai.is_alerted or not ai.has_visual_memory:
		clear()
		return
	_elapsed -= delta
	if _elapsed <= 0.0:
		refresh()
		_elapsed = 0.25


func refresh() -> void:
	var ai = selection.ai
	if not OS.is_debug_build() or not selection.debug_attack_points or selection.enemy.is_dead or not ai.is_arena_active() or not ai.is_alerted or not ai.has_visual_memory:
		clear()
		return
	# 身体中心高度与现有玩家瞄准点一致；失去视野后冻结在最后目击位置。
	var known_target: Vector3 = ai.last_seen_position + Vector3.UP * 0.8
	assessments = selection.get_attack_assessments(known_target, known_target)
	while _labels.size() < assessments.size():
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 32
		label.outline_size = 5
		label.pixel_size = 0.009
		add_child(label)
		_labels.append(label)
	for index in _labels.size():
		var label := _labels[index]
		label.visible = index < assessments.size()
		if not label.visible:
			continue
		var result := assessments[index]
		label.global_position = result.position + Vector3.UP * 0.18
		label.modulate = Color.GREEN if result.usable else Color(1.0, 0.25, 0.2)
		label.text = "◇ %s" % SHORT_REASONS.get(result.reason, result.reason)
		if result.usable:
			label.text += "\n%d/9" % roundi(result.protection * 9.0)


func clear() -> void:
	assessments.clear()
	_elapsed = 0.0
	for label in _labels:
		label.hide()
