@tool
extends Node3D

const State = preload("res://scripts/systems/presentation/presentation_state.gd")
## 只包含外观的 Node3D 场景。留空完全保留旧外观和玩法。
@export var model_scene: PackedScene:
	set(value):
		model_scene = value
		_schedule_rebuild()
## 相对于模型根的 AnimationPlayer 路径；无动画时可留空。
@export var animation_player_path: NodePath = ^"AnimationPlayer":
	set(value):
		animation_player_path = value
		_schedule_rebuild()
@export var animation_profile: PresentationAnimationProfile
## 相对于本节点，只指定旧 Mesh；禁止填写角色根、碰撞或交互节点。
@export var placeholder_paths: Array[NodePath] = []
## 玩家死亡时只允许本表现分支在暂停中播完，其他情况遵循世界暂停。
@export var death_during_pause: bool = false

var model: Node3D
var player: AnimationPlayer
var state = State.new()
var current_state: StringName = &"idle"
var _clip: StringName = &""
var _event: StringName = &""
var _time: float = 0.0
var _pivot: Node3D
var _fallbacks: Dictionary = {}
var _rebuild_queued: bool = false
var _death_started: bool = false
var _death_tween: Tween
var _rest_pose: Array[Dictionary] = []
var _rest_values: Array[Dictionary] = []


func _ready() -> void:
	rebuild_model()


func _schedule_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued: return
	_rebuild_queued = true
	rebuild_model.call_deferred()


func rebuild_model() -> void:
	_rebuild_queued = false
	reset_presentation()
	_restore_placeholders()
	player = null
	model = null
	_rest_pose.clear()
	_rest_values.clear()
	if is_instance_valid(_pivot):
		remove_child(_pivot)
		_pivot.queue_free()
	_pivot = null
	if model_scene == null: return
	var instance := model_scene.instantiate()
	if not instance is Node3D or _has_physics(instance):
		push_warning("Presentation: 模型必须是纯外观 Node3D，不能包含碰撞或导航节点。")
		instance.free()
		return
	_pivot = Node3D.new()
	_pivot.name = "_ModelPivot"
	# 内部节点不序列化；预览和运行实例均不修改源模型场景。
	add_child(_pivot, false, Node.INTERNAL_MODE_BACK)
	model = instance
	_pivot.add_child(model)
	_capture_pose(model)
	player = model.get_node_or_null(animation_player_path) as AnimationPlayer if not animation_player_path.is_empty() else null
	if player != null:
		player.stop()
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		# 每个模型独立持有动画库；循环由本后端管理，不改源资源或其他角色。
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
			for name in library.get_animation_list(): library.get_animation(name).loop_mode = Animation.LOOP_NONE
			player.remove_animation_library(library_name)
			player.add_animation_library(library_name, library)
		if not _validate_tracks():
			push_warning("Presentation: 动画包含方法轨道或模型之外的目标，已停用动画；请修正包装场景。")
			player = null
	_hide_placeholders()
	apply_state(state)


func _has_physics(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is NavigationRegion3D or node is NavigationObstacle3D:
		return true
	if node is AnimationTree:
		node.active = false # 首版由本后端独占 AnimationPlayer。
	if node is AnimationPlayer:
		node.autoplay = ""
		node.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for child in node.get_children():
		if _has_physics(child): return true
	return false


func _validate_tracks() -> bool:
	var track_root := player.get_node_or_null(player.root_node)
	if track_root == null: return false
	var isolated: Dictionary = {}
	for name in player.get_animation_list():
		var animation := player.get_animation(name)
		for index in animation.get_track_count():
			if animation.track_get_type(index) == Animation.TYPE_METHOD: return false
			var target := track_root.get_node_or_null(NodePath(animation.track_get_path(index).get_concatenated_names()))
			if target == null or (target != model and not model.is_ancestor_of(target)): return false
			if animation.track_get_type(index) == Animation.TYPE_VALUE:
				var track_path := animation.track_get_path(index)
				var property := NodePath(track_path.get_concatenated_subnames())
				# 材质等嵌套资源若被动画写入，只复制该被写资源，避免实例之间串色。
				if track_path.get_subname_count() > 1:
					var first := String(track_path.get_subname(0))
					var resource = target.get(first)
					var key := str(target.get_instance_id(), ":", first)
					if resource is Resource and not isolated.has(key):
						target.set(first, resource.duplicate(true))
						isolated[key] = true
				_rest_values.append({"node": weakref(target), "property": property, "value": target.get_indexed(property)})
	return true


func _hide_placeholders() -> void:
	# 编辑器不改原场景 Mesh 的 visible，防止预览状态被保存到旧外观。
	if Engine.is_editor_hint(): return
	for path in placeholder_paths:
		var mesh := get_node_or_null(path) as MeshInstance3D
		if mesh == null: continue
		if not _fallbacks.has(path): _fallbacks[path] = mesh.visible
		mesh.hide()


func _restore_placeholders() -> void:
	for path in _fallbacks:
		var mesh := get_node_or_null(path) as MeshInstance3D
		if mesh != null: mesh.visible = _fallbacks[path]
	_fallbacks.clear()


func has_model() -> bool:
	return is_instance_valid(model)


func _capture_pose(node: Node) -> void:
	if node is Node3D: _rest_pose.append({"node": weakref(node), "transform": node.transform})
	if node is Skeleton3D:
		for index in node.get_bone_count():
			_rest_pose.append({"node": weakref(node), "bone": index, "pose": node.get_bone_pose(index)})
	for child in node.get_children(): _capture_pose(child)


func _restore_pose() -> void:
	for entry in _rest_values:
		var node = entry.node.get_ref()
		if is_instance_valid(node): node.set_indexed(entry.property, entry.value)
	for entry in _rest_pose:
		var node = entry.node.get_ref()
		if not is_instance_valid(node): continue
		if entry.has("bone"): node.set_bone_pose(entry.bone, entry.pose)
		else: node.transform = entry.transform


func apply_state(value) -> void:
	state = value
	_update_posture_fallback()
	if state.dead and not _death_started and has_model():
		_death_started = true
		_event = &""
		if death_during_pause: process_mode = Node.PROCESS_MODE_ALWAYS
		if _resolve(&"dead").is_empty():
			_death_tween = create_tween().set_parallel(true)
			_death_tween.tween_property(_pivot, "rotation:x", PI / 2.0, 0.3)
			_death_tween.tween_property(_pivot, "position:y", 0.35, 0.3)
	if state.dead or state.in_dialogue or state.reloading or state.melee_active or state.vaulting: _event = &""
	_select_animation()


func _update_posture_fallback() -> void:
	if not has_model() or Engine.is_editor_hint(): return
	var missing := false
	if not state.dead:
		if state.vaulting: missing = _resolve(&"vault").is_empty()
		elif state.crouch_amount > 0.01: missing = _resolve(&"crouch").is_empty()
	model.visible = not missing
	if missing: _restore_placeholders()
	else: _hide_placeholders()


func play_event(event_id: StringName) -> void:
	if not has_model() or state.dead or state.in_dialogue or state.reloading or state.melee_active or state.vaulting: return
	if _resolve(event_id).is_empty(): return
	_event = event_id
	_clip = &"" # 每一次实际发射都可以重新开始一次性动作。
	_select_animation()


func _resolve(key: StringName) -> StringName:
	if player == null or animation_profile == null: return &""
	var name := animation_profile.clip(key)
	if not name.is_empty() and player.has_animation(name): return name
	if key == &"sprint": return _resolve(&"move")
	if key == &"crouch_move": return _resolve(&"crouch")
	if key in [&"move", &"aim", &"dialogue", &"reload", &"melee"]: return _resolve(&"idle")
	return &""


func _select_animation() -> void:
	current_state = _event if not _event.is_empty() else state.base_state()
	var next := _resolve(current_state)
	if next != _clip:
		_clip = next
		_time = 0.0
		if player != null:
			if next.is_empty(): player.stop()
			else:
				player.play(next, animation_profile.blend_seconds)
				player.seek(0.0, true)
				player.advance(0.0)
	if current_state == &"reload" and player != null and animation_profile != null and _clip == animation_profile.reload and not _clip.is_empty():
		_time = clampf(state.reload_progress, 0.0, 1.0) * player.get_animation(_clip).length
		player.seek(_time, true)
	if current_state == &"melee" and player != null and animation_profile != null and _clip == animation_profile.melee and not _clip.is_empty():
		_time = clampf(state.melee_progress, 0.0, 1.0) * player.get_animation(_clip).length
		player.seek(_time, true)
	if current_state == &"vault" and player != null and not _clip.is_empty():
		_time = clampf(state.vault_progress, 0.0, 1.0) * player.get_animation(_clip).length
		player.seek(_time, true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or player == null or _clip.is_empty(): return
	if get_tree().paused and not (state.dead and death_during_pause): return
	if current_state == &"reload" and animation_profile != null and _clip == animation_profile.reload: return
	if current_state == &"melee" and animation_profile != null and _clip == animation_profile.melee: return
	if current_state == &"vault": return
	var animation := player.get_animation(_clip)
	var length := maxf(0.001, animation.length)
	var rate := 1.0
	if current_state in [&"move", &"sprint"] and animation_profile != null:
		var reference := animation_profile.sprint_reference_speed if current_state == &"sprint" and _clip == animation_profile.sprint else animation_profile.move_reference_speed
		rate = clampf(state.local_velocity.length() / maxf(0.1, reference), animation_profile.minimum_rate, maxf(animation_profile.minimum_rate, animation_profile.maximum_rate))
	var step := delta * rate
	# 自己约束循环与结束，避免共享动画资源的 loop_mode 被各实例改写。
	player.advance(minf(step, maxf(0.0, length - _time)))
	_time += step
	if _time < length: return
	if current_state == &"dead":
		_time = length
		player.seek(length, true)
	elif not _event.is_empty():
		_event = &""
		_select_animation()
	else:
		_time = fmod(_time, length)
		player.play(_clip)
		player.seek(_time, true)


func reset_presentation() -> void:
	if _death_tween != null and _death_tween.is_valid(): _death_tween.kill()
	if is_instance_valid(_pivot): _pivot.transform = Transform3D.IDENTITY
	if player != null:
		player.stop()
		if player.has_animation(&"RESET"):
			player.play(&"RESET")
			player.advance(0.0)
			player.stop()
	_restore_pose()
	state = State.new()
	_event = &""
	_clip = &""
	_time = 0.0
	_death_started = false
	process_mode = Node.PROCESS_MODE_INHERIT
	if has_model(): _hide_placeholders()
	_update_posture_fallback()
	_select_animation()
