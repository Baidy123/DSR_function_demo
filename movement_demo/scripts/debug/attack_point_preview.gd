extends Node3D

@onready var debug_settings = get_node("/root/DebugSettings")

const SHORT_REASONS := {"空间被占": "占位", "不可达": "无路", "射界受阻": "挡枪",
	"散布射界贴墙": "贴墙", "超射程": "超距", "无武器": "无枪", "完全遮挡": "全遮"}

# 只读的运行时调试显示，独立于AI的决策更新；关闭后不再执行候选查询。
var assessments: Array[Dictionary] = []
var _labels: Array[Label3D] = []
var _markers: MeshInstance3D
var _elapsed: float = 0.0
var _pending: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _cursor: int = 0
var _known_target: Vector3
@onready var selection = get_parent()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_markers = MeshInstance3D.new()
	add_child(_markers)
	debug_settings.changed.connect(_apply_debug_mode)
	_apply_debug_mode(debug_settings.enabled)


func _apply_debug_mode(enabled: bool) -> void:
	set_physics_process(enabled)
	if not enabled:
		clear()


func _physics_process(delta: float) -> void:
	var ai = selection.ai
	if not debug_settings.enabled or not selection.debug_attack_points or selection.enemy.is_dead or not ai.is_arena_active() or not ai.is_alerted or not ai.has_visual_memory:
		clear()
		return
	_elapsed -= delta
	if _pending.is_empty():
		if _elapsed > 0.0:
			return
		# 整轮使用同一份目击信息，避免玩家移动时混合不同方向的评估。
		_known_target = ai.last_seen_position + Vector3.UP * 0.8
		for region in get_tree().get_nodes_in_group("cover_region"):
			if ai.navigation_region.is_ancestor_of(region):
				for point in region.get_attack_candidates():
					_pending.append({"position": point, "cover": region})
		_cursor = 0
		_results.clear()
	# 调试查询分帧执行：每帧最多64点，并在约2.5毫秒后让出；完整后统一显示。
	var started := Time.get_ticks_usec()
	var end := mini(_cursor + 64, _pending.size())
	while _cursor < end:
		var candidate := _pending[_cursor]
		if not is_instance_valid(candidate.cover):
			clear()
			return
		_results.append(selection.assess_attack_point(candidate.position, candidate.cover, _known_target, _known_target))
		_cursor += 1
		if Time.get_ticks_usec() - started >= 2500:
			break
	if _cursor == _pending.size():
		if not _results.all(func(result): return is_instance_valid(result.cover)):
			clear()
			return
		assessments = _results.duplicate()
		_pending.clear()
		_results.clear()
		_draw_results()
		_elapsed = 0.25


func refresh() -> void:
	# 手动验证使用同步查询；日常运行通过上面的分帧流程刷新。
	_pending.clear()
	_results.clear()
	var ai = selection.ai
	if not debug_settings.enabled or not selection.debug_attack_points or selection.enemy.is_dead or not ai.is_arena_active() or not ai.is_alerted or not ai.has_visual_memory:
		clear()
		return
	# 身体中心高度与现有玩家瞄准点一致；失去视野后冻结在最后目击位置。
	var known_target: Vector3 = ai.last_seen_position + Vector3.UP * 0.8
	assessments = selection.get_attack_assessments(known_target, known_target)
	_draw_results()
	_elapsed = 0.25


func _draw_results() -> void:
	# 区域有大量样本：所有红绿标记合在一张网格中，每个掩体只显示一份汇总。
	var summaries := {}
	var mesh := ImmediateMesh.new()
	if not assessments.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for result in assessments:
		var region: StaticBody3D = result.cover
		if not summaries.has(region):
			summaries[region] = {"count": 0, "usable": 0, "reasons": {}}
		var summary: Dictionary = summaries[region]
		summary.count += 1
		summary.usable += int(result.usable)
		if not result.usable:
			summary.reasons[result.reason] = summary.reasons.get(result.reason, 0) + 1
		var color := Color.GREEN if result.usable else Color(1.0, 0.25, 0.2)
		for offset in [Vector3.RIGHT, Vector3.FORWARD]:
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(result.position + Vector3.UP * 0.08 - offset * 0.05)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(result.position + Vector3.UP * 0.08 + offset * 0.05)
	if not assessments.is_empty():
		mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_markers.mesh = mesh
	_markers.material_override = material
	_markers.visible = not assessments.is_empty()
	var regions := summaries.keys()
	while _labels.size() < regions.size():
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 28
		label.outline_size = 5
		label.pixel_size = 0.007
		add_child(label)
		_labels.append(label)
	for index in _labels.size():
		var label := _labels[index]
		label.visible = index < regions.size()
		if not label.visible:
			continue
		var region: StaticBody3D = regions[index]
		var summary: Dictionary = summaries[region]
		var collision: CollisionShape3D = region.get_node("CollisionShape3D")
		label.global_position = collision.to_global(Vector3.UP * collision.shape.size.y * 0.5) + Vector3.UP * 0.35
		label.modulate = Color.GREEN if summary.usable > 0 else Color.WHITE
		label.text = "%s\n可用 %d/%d" % [region.name, summary.usable, summary.count]
		var reasons: Array = summary.reasons.keys()
		reasons.sort_custom(func(a, b): return summary.reasons[a] > summary.reasons[b])
		for reason in reasons.slice(0, 2):
			label.text += "\n%s %d" % [SHORT_REASONS.get(reason, reason), summary.reasons[reason]]


func clear() -> void:
	assessments.clear()
	_pending.clear()
	_results.clear()
	_cursor = 0
	_elapsed = 0.0
	if is_instance_valid(_markers):
		_markers.hide()
	for label in _labels:
		label.hide()
