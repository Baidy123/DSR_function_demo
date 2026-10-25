@tool
extends Node3D

## 区域可选的波次组件。编辑时保留全部部署；运行时按各波条件生成，可同时存在多波。
const Wave = preload("res://scripts/world/enemy_wave_definition.gd")
const Squad = preload("res://scripts/world/squad_controller.gd")
const Actor = preload("res://scripts/enemy/enemy_actor.gd")
const SpawnCheck = preload("res://scripts/world/enemy_wave_spawn_check.gd")
const CorpseVisual = preload("res://scripts/enemy/enemy_corpse_visual.gd")

## 信号中的波次编号从1开始，与检查器中的出场顺序一致。
signal wave_started(index: int)
signal wave_cleared(index: int)
signal encounter_completed

enum State { WAITING, DELAY, BLOCKED, SPAWNING, ACTIVE, CLEARING, COMPLETED, ERROR }
const STATE_NAMES := ["等待入场", "波前等待", "等待刷新点", "正在生成", "本波战斗", "清理本波", "全部完成", "配置或运行错误"]

## 开启后玩家进入所属 CombatZone 自动开始；关闭后由 start_encounter() 启动。
@export var auto_start_on_enter: bool = true
@export_group("高级设置")
## 刷新点被占用时的重试间隔，单位秒；必须大于0。只等待原位置，不挪动部署或强刷。
@export_range(0.05, 5.0, 0.05, "or_greater", "suffix:s") var spawn_retry_seconds: float = 0.25

var _region: Node3D
var _waves: Array[Dictionary] = []
var _captured := false
var _configuration_errors: PackedStringArray = []
var _state := State.WAITING
var _index := -1
var _remaining := 0.0
var _generation := 0
var _reason := ""
var _pending: Array[Dictionary] = []
## 波次编号 -> 独立的小队、存活身份和清理状态；后出的波允许先清空。
var _runtime: Dictionary = {}
var _cleared: Dictionary = {}
var _spawned := 0
var _retiring: Array[Node] = []
var _owned: Dictionary = {}
var _alive: Dictionary = {}
var _corpse_root: Node3D

func _ready() -> void:
	if Engine.is_editor_hint(): child_order_changed.connect(_refresh_editor_warnings)

func _refresh_editor_warnings() -> void:
	if not is_inside_tree() or EditorInterface.get_edited_scene_root() == null: return
	update_configuration_warnings()
	for child in get_children():
		if child is Wave: child.update_configuration_warnings()

func capture_templates(region: Node3D) -> void:
	if Engine.is_editor_hint() or _captured: return
	_captured = true
	_region = region
	var configuration := _collect_configuration(region)
	_configuration_errors = configuration.errors
	# 错误层级也不能绕过波次直接入树参战；先给配置诊断，再隔离这些无效部署。
	for invalid in configuration.invalid_roots:
		if is_instance_valid(invalid) and invalid.get_parent() != null:
			invalid.get_parent().remove_child(invalid)
			invalid.free()
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
		_waves.append({"name": wave.name, "delay": wave.delay, "wait_for_previous_clear": wave.wait_for_previous_clear,
			"deployments": deployments, "member_count": wave.member_count})
	if not _configuration_errors.is_empty(): _fail("; ".join(_configuration_errors))

func _collect_configuration(region: Node) -> Dictionary:
	var errors: PackedStringArray = []
	var waves: Array[Dictionary] = []
	var invalid_roots: Array[Node] = []
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
			invalid_roots.append(child)
			continue
		var config: Dictionary = child.deployment_configuration()
		for deployment in child.get_children():
			if not deployment is Squad: invalid_roots.append(deployment)
		for error in config.errors: errors.append("%s：%s" % [child.name, error])
		var squads: Array[Node3D] = []
		var member_count := 0
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
			member_count += members.size()
			if members.is_empty(): errors.append("%s：小队内还没有敌人。" % squad.name)
			squads.append(squad)
		waves.append({"name": child.name, "delay": child.start_delay_seconds, "wait_for_previous_clear": child.wait_for_previous_clear,
			"squads": squads, "member_count": member_count})
	if waves.is_empty(): errors.append("请添加 enemy_wave.tscn；波次按场景树从上到下排列。")
	return {"waves": waves, "errors": errors, "invalid_roots": invalid_roots}

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

func start_encounter() -> void:
	if not _captured or _state != State.WAITING or not _configuration_errors.is_empty(): return
	_generation += 1
	_begin_wave(0)

func _begin_wave(index: int) -> void:
	_index = index
	_remaining = _waves[index].delay
	_reason = ""
	_state = State.DELAY

func advance_from_region(delta: float) -> void:
	if not _can_advance(): return
	_collect_retired()
	if _state in [State.WAITING, State.COMPLETED, State.ERROR]: return
	# 复位后的新轮次必须等旧轮次全部退树；正常清波不暂停其他波的计时。
	if _spawned == 0 and not _retiring.is_empty(): return
	if not _clear_finished_waves(): return
	if _spawned == _waves.size() and _runtime.is_empty():
		_state = State.COMPLETED
		encounter_completed.emit()
		return
	if _state == State.ACTIVE or _state == State.CLEARING:
		if _index + 1 < _waves.size() and (not _waves[_index + 1].wait_for_previous_clear or _cleared.has(_index)):
			_begin_wave(_index + 1)
		elif _runtime.has(_index) and _runtime[_index].retiring:
			_state = State.CLEARING
		else:
			_state = State.ACTIVE
		return
	if _state != State.DELAY and _state != State.BLOCKED: return
	_remaining = maxf(0.0, _remaining - maxf(delta, 0.0))
	if _remaining > 0.0: return
	if _pending.is_empty(): _pending = _instantiate_wave(_index)
	if _pending.is_empty():
		_fail("本波无法创建完整小队，请检查部署配置。")
		return
	var result := SpawnCheck.inspect(_region, _pending)
	if result.kind == "ready":
		# 最后一次检查紧挨提交，期间不 await、发信号或让出物理帧。
		result = SpawnCheck.inspect(_region, _pending)
	if result.kind == "error":
		_fail(result.reason)
	elif result.kind == "wait":
		_state = State.BLOCKED
		_reason = result.reason
		_remaining = spawn_retry_seconds
	else:
		_commit_wave()

func _clear_finished_waves() -> bool:
	var generation := _generation
	for index in _runtime.keys():
		var wave: Dictionary = _runtime[index]
		if not wave.alive.is_empty(): continue
		if not wave.retiring:
			wave.retiring = true
			_preserve_corpses(wave.deployments)
			_retire_deployments(wave.deployments)
			continue
		var exited := true
		for deployment in wave.deployments:
			if is_instance_valid(deployment.root): exited = false
		if not exited: continue
		_runtime.erase(index)
		_cleared[index] = true
		wave_cleared.emit(index + 1)
		if generation != _generation or _state == State.ERROR or not _can_advance(): return false
	return true

func _can_advance() -> bool:
	return is_inside_tree() and is_instance_valid(_region) and _region.is_inside_tree() and not _region.is_queued_for_deletion() and not get_tree().paused and _region.has_active_player()

func _commit_wave() -> void:
	if not _can_advance(): return
	_state = State.SPAWNING
	_reason = ""
	var generation := _generation
	var deployments := _pending
	_pending = []
	var wave := {"deployments": deployments, "alive": {}, "retiring": false}
	_runtime[_index] = wave
	# 所有身份和订阅先就位，任一成员在 ready 中死亡也不能提前清波。
	for deployment in deployments:
		for enemy in deployment.members:
			var id: int = enemy.get_instance_id()
			var death := _on_member_died.bind(id, generation)
			var leaving := _on_member_exiting.bind(id, generation)
			_owned[id] = {"ref": weakref(enemy), "death": death, "leaving": leaving, "wave": _index}
			_alive[id] = true
			wave.alive[id] = true
			enemy.died.connect(death)
			enemy.tree_exiting.connect(leaving)
	for deployment in deployments:
		if generation != _generation: return
		var parent: Node = deployment.parent.get_ref()
		if not is_instance_valid(parent) or not parent.is_inside_tree():
			_fail("生成过程中部署父节点离场；已取消整波。")
			_retire_runtime()
			return
		parent.add_child(deployment.root)
		if generation != _generation: return
		if _state == State.ERROR or not is_instance_valid(deployment.root) or not deployment.root.is_inside_tree():
			_fail("生成过程中成员离场；已取消整波。")
			_retire_runtime()
			return
		parent.move_child(deployment.root, mini(deployment.order, parent.get_child_count() - 1))
	_spawned = _index + 1
	_state = State.ACTIVE
	wave_started.emit(_index + 1)
	if generation != _generation or _state != State.ACTIVE: return
	if _index + 1 < _waves.size() and not _waves[_index + 1].wait_for_previous_clear:
		_begin_wave(_index + 1)

func _on_member_died(id: int, generation: int) -> void:
	if generation != _generation or not _alive.has(id): return
	var enemy = _owned[id].ref.get_ref()
	if is_instance_valid(enemy) and enemy.is_dead:
		_alive.erase(id)
		_runtime[_owned[id].wave].alive.erase(id)

func _on_member_exiting(id: int, generation: int) -> void:
	if generation == _generation and _alive.has(id) and not _region.is_queued_for_deletion():
		_fail("本波仍存活的敌人被移除；停止推进，不计为击杀。")

func reset_encounter() -> void:
	_generation += 1
	_retire_runtime()
	_free_pending()
	_clear_corpses()
	_index = -1
	_spawned = 0
	_cleared.clear()
	_remaining = 0.0
	_reason = "; ".join(_configuration_errors)
	_state = State.WAITING if _configuration_errors.is_empty() else State.ERROR

func _retire_runtime() -> void:
	for wave in _runtime.values(): _retire_deployments(wave.deployments)
	_runtime.clear()
	_alive.clear()

func _preserve_corpses(deployments: Array[Dictionary]) -> void:
	if not is_instance_valid(_corpse_root):
		_corpse_root = Node3D.new()
		_corpse_root.name = "Corpses"
		add_child(_corpse_root, false, Node.INTERNAL_MODE_BACK)
	for deployment in deployments:
		for enemy in deployment.members:
			if is_instance_valid(enemy) and enemy.is_inside_tree() and enemy.is_dead:
				CorpseVisual.create(enemy, _corpse_root)

func _clear_corpses() -> void:
	if is_instance_valid(_corpse_root): _corpse_root.queue_free()
	_corpse_root = null

func _retire_deployments(deployments: Array[Dictionary]) -> void:
	for deployment in deployments:
		for enemy in deployment.members:
			if not is_instance_valid(enemy): continue
			var entry: Dictionary = _owned.get(enemy.get_instance_id(), {})
			if entry.is_empty(): continue
			if enemy.died.is_connected(entry.death): enemy.died.disconnect(entry.death)
			if enemy.tree_exiting.is_connected(entry.leaving): enemy.tree_exiting.disconnect(entry.leaving)
			_alive.erase(enemy.get_instance_id())
		var instance: Node = deployment.root
		if not is_instance_valid(instance) or instance.is_queued_for_deletion(): continue
		_retiring.append(instance)
		instance.queue_free()

func _collect_retired() -> void:
	_retiring = _retiring.filter(func(node): return is_instance_valid(node))
	for id in _owned.keys():
		if not is_instance_valid(_owned[id].ref.get_ref()): _owned.erase(id)

func owns_runtime_enemy(enemy: Node) -> bool:
	return is_instance_valid(enemy) and _owned.has(enemy.get_instance_id())

func _free_pending() -> void:
	for deployment in _pending:
		if is_instance_valid(deployment.root): deployment.root.free()
	_pending.clear()

func _fail(reason: String) -> void:
	if _state != State.ERROR or _reason != reason: push_warning("EnemyWaves：" + reason)
	_state = State.ERROR
	_reason = reason

func debug_snapshot() -> Dictionary:
	var pending_count := 0
	for deployment in _pending: pending_count += deployment.members.size()
	if _state == State.DELAY or _state == State.BLOCKED: pending_count = _waves[_index].member_count
	var active_waves: Array[int] = []
	for index in _runtime:
		if not _runtime[index].alive.is_empty(): active_waves.append(index + 1)
	return {"captured": _captured, "wave_count": _waves.size(), "errors": _configuration_errors.duplicate(),
		"state": State.keys()[_state], "status": STATE_NAMES[_state], "wave": _index + 1,
		"alive": _alive.size(), "active_waves": active_waves, "pending": pending_count, "remaining_seconds": _remaining, "reason": _reason}

func _get_configuration_warnings() -> PackedStringArray:
	var region := _nearest_region(self)
	var errors: PackedStringArray = _collect_configuration(region).errors
	if region == null or region != get_parent(): errors.append("请把 EnemyWaves 直接放在战斗区域根节点下。")
	return errors

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		if child_order_changed.is_connected(_refresh_editor_warnings):
			child_order_changed.disconnect(_refresh_editor_warnings)
		return
	_generation += 1
	_retire_runtime()
	_free_pending()
	_waves.clear()
