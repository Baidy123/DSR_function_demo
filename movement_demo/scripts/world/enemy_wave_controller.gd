@tool
extends Node3D

## 区域可选的波次组件。编辑时保留全部部署；运行时只让当前波进入场景树。
const Wave = preload("res://scripts/world/enemy_wave_definition.gd")
const Squad = preload("res://scripts/world/squad_controller.gd")
const Actor = preload("res://scripts/enemy/enemy_actor.gd")

## 开启后玩家进入所属 CombatZone 自动开始；关闭后由 start_encounter() 启动。
@export var auto_start_on_enter: bool = true
@export_group("高级设置")
## 刷新点被占用时的重试间隔，单位秒；必须大于0。只等待原位置，不挪动部署或强刷。
@export_range(0.05, 5.0, 0.05, "or_greater", "suffix:s") var spawn_retry_seconds: float = 0.25

var _region: Node3D
var _waves: Array[Dictionary] = []
var _captured := false
var _configuration_errors: PackedStringArray = []

func capture_templates(region: Node3D) -> void:
	if Engine.is_editor_hint() or _captured: return
	_captured = true
	_region = region
	var configuration := _collect_configuration(region)
	_configuration_errors = configuration.errors
	# 先解析所有 NodePath，再移除任何小队，避免引用受遍历顺序影响。
	for wave in configuration.waves:
		var deployments: Array[Dictionary] = []
		for squad in wave.squads:
			if not is_instance_valid(squad) or squad.get_parent() == null: continue
			var parent: Node = squad.get_parent()
			var label: StringName = squad.name
			var order: int = squad.get_index()
			parent.remove_child(squad)
			# duplicate() 会共享实例覆盖中的 local_to_scene 资源。先建立完整、规范化所有权的
			# 树外快照，再由 PackedScene 实例化来执行引擎的资源本地化；绝不保存到用户场景。
			var snapshot: Node = squad.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
			_normalize_snapshot(snapshot, snapshot)
			var packed := PackedScene.new()
			var error := packed.pack(snapshot)
			if error != OK: _configuration_errors.append("无法保存小队部署：%s（%s）" % [label, error])
			else:
				deployments.append({"scene": packed, "parent": weakref(parent), "name": label, "order": order})
			snapshot.free()
			squad.free()
		_waves.append({"name": wave.name, "delay": wave.delay, "deployments": deployments})
	if not _configuration_errors.is_empty(): push_warning("EnemyWaves：" + "; ".join(_configuration_errors))

func _collect_configuration(region: Node) -> Dictionary:
	var errors: PackedStringArray = []
	var waves: Array[Dictionary] = []
	var claimed: Dictionary = {}
	if region != null:
		var count := 0
		for child in region.get_children():
			if child.has_method("capture_templates"): count += 1
		if count > 1: errors.append("一个战斗区域只放一个 EnemyWaves；多个小队放在同一波内。")
	if not is_finite(spawn_retry_seconds) or spawn_retry_seconds <= 0.0:
		errors.append("重试间隔必须大于0秒。")
	for child in get_children():
		if not child is Wave:
			errors.append("%s：控制器下面请放 enemy_wave.tscn 波次节点。" % child.name)
			continue
		var config: Dictionary = child.deployment_configuration()
		for error in config.errors: errors.append("%s：%s" % [child.name, error])
		var squads: Array[Node3D] = []
		for squad in config.squads:
			if _nearest_region(squad) != region:
				errors.append("%s：小队必须属于本区域。" % squad.name)
				continue
			if claimed.has(squad):
				errors.append("%s：同一小队不能属于多个波次。" % squad.name)
				continue
			claimed[squad] = true
			var members: Array[Node] = []
			_collect_members(squad, members, errors)
			if members.is_empty(): errors.append("%s：小队内还没有敌人。" % squad.name)
			squads.append(squad)
		waves.append({"name": child.name, "delay": child.start_delay_seconds, "squads": squads})
	if waves.is_empty(): errors.append("请添加 enemy_wave.tscn；波次按场景树从上到下排列。")
	return {"waves": waves, "errors": errors}

func _collect_members(node: Node, members: Array[Node], errors: PackedStringArray) -> void:
	for child in node.get_children():
		if child is Actor:
			members.append(child)
		elif child is Squad or child.has_method("enemy_environment"):
			errors.append("%s：小队内不能嵌套另一个小队或战斗区域。" % child.name)
		else:
			_collect_members(child, members, errors)

func _nearest_region(node: Node) -> Node:
	var ancestor := node.get_parent()
	while ancestor != null and not ancestor.has_method("enemy_environment"): ancestor = ancestor.get_parent()
	return ancestor

func _normalize_snapshot(node: Node, snapshot: Node) -> void:
	node.scene_file_path = ""
	if node != snapshot: node.owner = snapshot
	for child in node.get_children(): _normalize_snapshot(child, snapshot)

func _instantiate_wave(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _configuration_errors.is_empty() or index < 0 or index >= _waves.size(): return result
	for deployment in _waves[index].deployments:
		var instance: Node3D = deployment.scene.instantiate()
		instance.name = deployment.name
		var members: Array[Node] = []
		var errors: PackedStringArray = []
		_collect_members(instance, members, errors)
		result.append({"root": instance, "parent": deployment.parent, "order": deployment.order, "members": members})
	return result

func debug_snapshot() -> Dictionary:
	return {"captured": _captured, "wave_count": _waves.size(), "errors": _configuration_errors.duplicate()}

func _get_configuration_warnings() -> PackedStringArray:
	var region := _nearest_region(self)
	var errors: PackedStringArray = _collect_configuration(region).errors
	if region == null or region != get_parent(): errors.append("请把 EnemyWaves 直接放在战斗区域根节点下。")
	return errors

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): _waves.clear()
