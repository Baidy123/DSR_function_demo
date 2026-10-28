extends RefCounted

## 区域可选的波次组件。编辑时保留全部部署；运行时按各波条件生成，可同时存在多波。
const Subscription = preload("res://scripts/systems/scene_event_subscription.gd")
const EventNode = preload("res://scripts/systems/scene_event.gd")
const Wave = preload("res://scripts/world/enemy_wave_definition.gd")
const Squad = preload("res://scripts/world/squad_controller.gd")
const Actor = preload("res://scripts/enemy/enemy_actor.gd")
const SpawnCheck = preload("res://scripts/world/enemy_wave_spawn_check.gd")
const CorpseVisual = preload("res://scripts/enemy/enemy_corpse_visual.gd")
const SearchHints = preload("res://scripts/enemy/services/enemy_search_hints.gd")

## 信号中的波次编号从1开始，与检查器中的出场顺序一致。
signal wave_started(index: int)
signal wave_cleared(index: int)
signal encounter_completed
## Synchronous presentation barrier, before public notifications.
signal wave_committed(wave: Node, focus: Vector3)

enum State { WAITING, DELAY, BLOCKED, SPAWNING, ACTIVE, CLEARING, COMPLETED, ERROR }
const STATE_NAMES := ["等待入场", "波前等待", "等待刷新点", "正在生成", "本波战斗", "清理本波", "全部完成", "配置或运行错误"]

## Scene paths, tree access and authoring exports belong to the stable host.
var _host: Node3D
var _started := false
var _events_prepared := false
var _event_links: Array[Dictionary] = []
var _last_advance_frame := -1
var _released := false

var _region: Node3D
var _waves: Array[Dictionary] = []
var _captured := false
var _configuration_errors: PackedStringArray = []
var _configuration_advisories: PackedStringArray = []
var _state := State.WAITING
var _index := -1
var _remaining := 0.0
var _generation := 0
var _reason := ""
## 波次编号 -> 独立的小队、存活身份和清理状态；后出的波允许先清空。
var _runtime: Dictionary = {}
var _cleared: Dictionary = {}
var _spawned := 0
var _retiring: Array[Node] = []
var _owned: Dictionary = {}
var _alive: Dictionary = {}
## Exit notifications also run while an ancestor scene is being removed. Hold
## advancement until the deferred check can distinguish unload from member loss.
var _exiting_members: Dictionary = {}
var _corpse_root: Node3D
## Legacy read-only diagnostic view; each wave still owns its pending instances.
var _pending: Array[Dictionary]:
	get:
		var result: Array[Dictionary] = []
		for wave in _waves: result.append_array(wave.pending)
		return result

func _init(host: Node3D) -> void:
	_host = host

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
			"search_on_spawn": wave.search_on_spawn, "spawn_search_error_radius": wave.spawn_search_error_radius,
			"deployments": deployments, "member_count": wave.member_count,
			"definition": weakref(wave.definition), "start_mode": wave.start_mode,
			"triggers": wave.triggers, "event_node_start": wave.event_node_start, "combination": wave.combination,
			"state": &"waiting", "remaining": 0.0, "pending": [], "received": {},
			"reason": "", "focus": null, "ready_frame": -1})
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
		if count > 1: errors.append("一个战斗区域只放一个 SceneDirector；多个小队放在同一波内。")
	if not is_finite(_host.spawn_retry_seconds) or _host.spawn_retry_seconds <= 0.0:
		errors.append("重试间隔必须大于0秒。")
	for child in _host.get_children():
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
			"search_on_spawn": child.search_on_spawn, "spawn_search_error_radius": child.spawn_search_error_radius,
			"squads": squads, "member_count": member_count, "definition": child,
			"start_mode": child.start_mode, "triggers": config.triggers.duplicate(true), "event_node_start": config.event_node_start,
			"combination": child.trigger_combination})
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

## Call after every scene sibling is ready; capture deliberately does no binding.
func prepare_events() -> void:
	if _released or not _captured or _events_prepared: return
	_events_prepared = true
	if not _configuration_errors.is_empty(): return
	for index in _waves.size():
		var wave: Dictionary = _waves[index]
		if wave.start_mode != Wave.StartMode.EVENTS: continue
		var definition: Node = wave.definition.get_ref()
		for trigger_index in wave.triggers.size():
			if trigger_index >= wave.event_node_start and is_instance_valid(definition):
				var node_diagnostic: String = definition.event_node_diagnostic(wave.triggers[trigger_index].source_path)
				if not node_diagnostic.is_empty():
					_configuration_errors.append("%s: %s" % [wave.name, node_diagnostic])
					continue
			var subscription := Subscription.new()
			var diagnostic := subscription.connect_trigger(definition, wave.triggers[trigger_index], _on_trigger.bind(index, trigger_index, _generation))
			if not diagnostic.is_empty():
				_configuration_errors.append("%s: %s" % [wave.name, diagnostic])
			else:
				_event_links.append({"subscription": subscription, "wave": index, "trigger": trigger_index})
	_configuration_errors.append_array(_prerequisite_errors())
	_configuration_advisories = _prerequisite_errors([], true)
	if not _configuration_errors.is_empty(): _fail("; ".join(_configuration_errors))

func _prerequisite_errors(definitions: Array[Dictionary] = [], follow_relay_bindings: bool = false) -> PackedStringArray:
	# Least fixed point of possible entries. ANY with an external entry can unlock
	# a cycle; ALL still requires every dependency. No guessed dynamic dependencies.
	# SceneEvent.trigger() is an explicit external entry even with a bound source.
	# Following its bindings is an advisory-only automatic-entry analysis, never a
	# hard prerequisite: SceneEvent currently has no pure-forwarding declaration.
	var waves := _waves if definitions.is_empty() else definitions
	var possible: Dictionary = {}
	var relayed_waves: Dictionary = {}
	var dependencies: Array[Array] = []
	for index in waves.size():
		var wave: Dictionary = waves[index]
		var entries: Array[int] = []
		if wave.start_mode == Wave.StartMode.REQUEST or (wave.start_mode == Wave.StartMode.SEQUENCE and index == 0):
			possible[index] = true
		elif wave.start_mode == Wave.StartMode.SEQUENCE:
			entries.append(index - 1)
		else:
			var definition: Node = wave.definition.get_ref()
			if not is_instance_valid(definition):
				dependencies.append(entries)
				continue
			for trigger in wave.triggers:
				if trigger == null: continue
				var source := definition.get_node_or_null(trigger.source_path)
				var signal_name: StringName = trigger.signal_name
				var visited: Dictionary = {}
				var relay_cycle := false
				while follow_relay_bindings and source is EventNode and signal_name == &"triggered" and not source.source_path.is_empty():
					relayed_waves[index] = true
					if visited.has(source):
						relay_cycle = true
						break
					visited[source] = true
					signal_name = source.signal_name
					source = source.get_node_or_null(source.source_path)
				var dependency := -1
				for candidate in waves.size():
					if waves[candidate].definition.get_ref() == source:
						dependency = candidate
						break
				if relay_cycle: entries.append(index)
				else: entries.append(dependency if dependency >= 0 and signal_name in [&"spawned", &"cleared"] else -1)
		dependencies.append(entries)
	for iteration in waves.size():
		var changed := false
		for index in waves.size():
			if possible.has(index): continue
			var wave: Dictionary = waves[index]
			var all_required: bool = wave.start_mode == Wave.StartMode.SEQUENCE or wave.combination == Wave.TriggerCombination.ALL
			var satisfied := all_required and not dependencies[index].is_empty()
			for dependency in dependencies[index]:
				var available: bool = dependency < 0 or possible.has(dependency)
				satisfied = (satisfied and available) if all_required else (satisfied or available)
			if satisfied:
				possible[index] = true
				changed = true
		if not changed: break
	var errors: PackedStringArray = []
	for index in waves.size():
		if not possible.has(index):
			if not follow_relay_bindings:
				errors.append("%s: required wave prerequisites have no entry (self-spawn/self-clear or required dependency cycle)." % waves[index].name)
			elif relayed_waves.has(index):
				errors.append("%s：事件节点绑定的自动来源形成波次依赖环，不能自行启动；仍可显式调用 SceneEvent.trigger()，或配置独立入口。" % waves[index].name)
	return errors

func _on_trigger(index: int, trigger_index: int, generation: int) -> void:
	if _released or generation != _generation or index >= _waves.size() or _state in [State.ERROR, State.COMPLETED]: return
	var wave: Dictionary = _waves[index]
	if wave.state != &"waiting": return
	wave.received[trigger_index] = true
	if wave.combination == Wave.TriggerCombination.ANY or wave.received.size() == wave.triggers.size():
		_mark_ready(index)

func _mark_ready(index: int) -> void:
	var wave: Dictionary = _waves[index]
	if wave.state != &"waiting": return
	wave.state = &"ready"
	wave.ready_frame = Engine.get_physics_frames()

func request_wave(wave: Node) -> bool:
	var index := _wave_index(wave)
	if index < 0 or _released or _state == State.ERROR or _state == State.COMPLETED: return false
	if _waves[index].state == &"waiting": _mark_ready(index)
	return true

func wave_status(wave: Node) -> StringName:
	var index := _wave_index(wave)
	if index < 0: return &"unknown"
	return &"error" if _state == State.ERROR else _waves[index].state

func wave_focus(wave: Node) -> Variant:
	var index := _wave_index(wave)
	return _waves[index].focus if index >= 0 else null

func _wave_index(wave: Node) -> int:
	if not is_instance_valid(wave): return -1
	for index in _waves.size():
		if _waves[index].definition.get_ref() == wave: return index
	return -1

func start_encounter() -> void:
	if _released or not _captured or _started or not _configuration_errors.is_empty(): return
	# Listening begins at prepare_events; starting must not invalidate earlier facts.
	_started = true
	if not _waves.is_empty() and _waves[0].start_mode == Wave.StartMode.SEQUENCE:
		_begin_wave(0)
	_refresh_summary()

func _begin_wave(index: int) -> void:
	var wave: Dictionary = _waves[index]
	wave.state = &"delay"
	wave.remaining = wave.delay
	wave.reason = ""
	_index = index

func advance_from_region(delta: float) -> void:
	if not _can_advance() or not _events_prepared: return
	var frame := Engine.get_physics_frames()
	if frame == _last_advance_frame: return
	_last_advance_frame = frame
	_collect_retired()
	if not _started or _state in [State.COMPLETED, State.ERROR]: return
	if _spawned == 0 and not _retiring.is_empty(): return
	for link in _event_links:
		var waiting: Dictionary = _waves[link.wave]
		if waiting.state != &"waiting" or waiting.received.has(link.trigger): continue
		var diagnostics: PackedStringArray = link.subscription.diagnostics()
		if not diagnostics.is_empty():
			_fail("%s: %s" % [waiting.name, "; ".join(diagnostics)])
			return
	if not _clear_finished_waves(): return
	# No deployments is valid director-only mode, never an automatic victory.
	if not _waves.is_empty() and _spawned == _waves.size() and _runtime.is_empty():
		_state = State.COMPLETED
		_clear_subscriptions()
		encounter_completed.emit()
		return
	# Advance every independent clock, even when an earlier candidate commits.
	var candidates: Array[int] = []
	for index in _waves.size():
		var wave: Dictionary = _waves[index]
		if wave.state == &"ready" and wave.ready_frame < frame: _begin_wave(index)
		if wave.state not in [&"delay", &"blocked"] or wave.ready_frame == frame: continue
		wave.remaining = maxf(0.0, wave.remaining - maxf(delta, 0.0))
		if wave.remaining == 0.0: candidates.append(index)
	for index in candidates:
		var wave: Dictionary = _waves[index]
		_index = index
		if wave.pending.is_empty(): wave.pending = _instantiate_wave(index)
		if wave.pending.is_empty():
			_fail("Unable to create the complete wave deployment.")
			return
		var deployments: Array[Dictionary] = []
		deployments.assign(wave.pending)
		var result := SpawnCheck.inspect(_region, deployments)
		if result.kind == "ready":
			# Keep second geometry check adjacent to commit, without signals/await.
			result = SpawnCheck.inspect(_region, deployments)
		if result.kind == "error":
			_fail(result.reason)
			return
		if result.kind == "wait":
			wave.state = &"blocked"
			wave.reason = result.reason
			wave.remaining = _host.spawn_retry_seconds
			continue
		_commit_wave()
		break
	_refresh_summary()

func _arm_sequence_follower(index: int, cleared: bool) -> void:
	if index + 1 >= _waves.size(): return
	var next: Dictionary = _waves[index + 1]
	if next.start_mode != Wave.StartMode.SEQUENCE or next.state != &"waiting": return
	if bool(next.wait_for_previous_clear) != cleared: return
	_begin_wave(index + 1)
	next.ready_frame = Engine.get_physics_frames()

func _clear_finished_waves() -> bool:
	var generation := _generation
	for index in _runtime.keys():
		var wave: Dictionary = _runtime[index]
		if not wave.alive.is_empty(): continue
		if not wave.retiring:
			wave.retiring = true
			_waves[index].state = &"clearing"
			_preserve_corpses(wave.deployments)
			_retire_deployments(wave.deployments)
			continue
		var exited := true
		for deployment in wave.deployments:
			if is_instance_valid(deployment.root): exited = false
		if not exited: continue
		_runtime.erase(index)
		_cleared[index] = true
		_waves[index].state = &"cleared"
		_arm_sequence_follower(index, true)
		var definition: Node = _waves[index].definition.get_ref()
		if is_instance_valid(definition): definition.cleared.emit()
		if generation != _generation or _released: return false
		wave_cleared.emit(index + 1)
		if generation != _generation or _state == State.ERROR or not _can_advance(): return false
	return true

func _can_advance() -> bool:
	return not _released and _exiting_members.is_empty() and is_instance_valid(_host) and _host.is_inside_tree() and not _host.is_queued_for_deletion() and is_instance_valid(_region) and _region.is_inside_tree() and not _region.is_queued_for_deletion() and not _host.get_tree().paused and _region.has_active_player()

func _commit_wave() -> void:
	if not _can_advance(): return
	# 冻结一次成功提交时的情报；占位重试及未入树部署不读取隐藏玩家位置。
	var search_hint := _spawn_search_hint()
	_state = State.SPAWNING
	_reason = ""
	var generation := _generation
	var index := _index
	var definition_state: Dictionary = _waves[index]
	definition_state.state = &"spawning"
	var deployments: Array[Dictionary] = []
	deployments.assign(definition_state.pending)
	definition_state.pending = []
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
	# 成员 ready 已完成，初始化重置不会抹掉提示；整波仍未执行第一轮 AI。
	if not search_hint.is_empty():
		for deployment in deployments:
			for enemy in deployment.members:
				if is_instance_valid(enemy) and not enemy.is_dead:
					enemy.get_node("AI").receive_spawn_search_hint(search_hint)
	_spawned += 1
	definition_state.state = &"active"
	definition_state.reason = ""
	var center := Vector3.ZERO
	var count := 0
	for deployment in deployments:
		for enemy in deployment.members:
			if is_instance_valid(enemy) and enemy.is_inside_tree():
				center += enemy.global_position
				count += 1
	definition_state.focus = center / maxf(1.0, count)
	_state = State.ACTIVE
	var definition: Node = definition_state.definition.get_ref()
	wave_committed.emit(definition, definition_state.focus)
	if generation != _generation or _released or _state == State.ERROR: return
	if is_instance_valid(definition): definition.spawned.emit()
	if generation != _generation or _released or _state == State.ERROR: return
	wave_started.emit(index + 1)
	if generation != _generation or _released or _state == State.ERROR: return
	_arm_sequence_follower(index, false)

func _spawn_search_hint() -> Dictionary:
	if _index == 0 or not _waves[_index].search_on_spawn: return {}
	var player: Node3D
	for candidate in _region.players_inside:
		if is_instance_valid(candidate) and candidate.is_inside_tree() and not candidate.is_dead() and not candidate.is_in_dialogue:
			player = candidate
			break
	if player == null:
		push_warning("SceneDirector：%s 出生搜索未找到本区域有效玩家，使用原出生行为。" % _waves[_index].name)
		return {}
	var captured_position := player.global_position
	var radius: float = _waves[_index].spawn_search_error_radius
	var navigation := _region.get_node("NavigationRegion3D") as NavigationRegion3D
	var hints := SearchHints.new()
	for attempt in 4:
		var raw := hints.sample(captured_position, radius)
		var point := NavigationServer3D.region_get_closest_point(navigation.get_rid(), raw)
		if not point.is_finite(): continue
		if Vector2(point.x - raw.x, point.z - raw.z).length() > 0.65: continue
		if Vector2(point.x - captured_position.x, point.z - captured_position.z).length() > radius + 0.001: continue
		return {"id": _region.cooperation.allocate_coordination_id(), "source": &"wave_spawn",
			"target_id": player.get_instance_id(), "position": point, "uncertainty": radius,
			"captured_at": _region.cooperation.elapsed}
	push_warning("SceneDirector：%s 出生搜索未取得本区合法误差点，使用原出生行为。" % _waves[_index].name)
	return {}

func _on_member_died(id: int, generation: int) -> void:
	if generation != _generation or not _alive.has(id): return
	var enemy = _owned[id].ref.get_ref()
	if is_instance_valid(enemy) and enemy.is_dead:
		_alive.erase(id)
		_runtime[_owned[id].wave].alive.erase(id)

func _on_member_exiting(id: int, generation: int) -> void:
	if _released or generation != _generation or not _alive.has(id): return
	if not is_instance_valid(_region) or _region.is_queued_for_deletion(): return
	_exiting_members[id] = generation
	_verify_member_exit.call_deferred(id, generation)

func _verify_member_exit(id: int, generation: int) -> void:
	if _released or generation != _generation: return
	_exiting_members.erase(id)
	if not _alive.has(id): return
	# Descendants exit before their host. Normal scene replacement can therefore
	# have an unqueued, still-in-tree host during the original signal callback.
	if not is_instance_valid(_host) or not _host.is_inside_tree() or _host.is_queued_for_deletion(): return
	if not is_instance_valid(_region) or not _region.is_inside_tree() or _region.is_queued_for_deletion(): return
	_fail("本波仍存活的敌人被移除；停止推进，不计为击杀。")

func reset_encounter() -> void:
	if _released: return
	var reconnect_events := _events_prepared
	_generation += 1
	_exiting_members.clear()
	_clear_subscriptions()
	_events_prepared = false
	_started = false
	_retire_runtime()
	_free_pending()
	_clear_corpses()
	_index = -1
	_spawned = 0
	_cleared.clear()
	_remaining = 0.0
	_reason = "; ".join(_configuration_errors)
	_state = State.WAITING if _configuration_errors.is_empty() else State.ERROR
	for wave in _waves:
		wave.state = &"waiting"
		wave.remaining = 0.0
		wave.received.clear()
		wave.reason = ""
		wave.focus = null
		wave.ready_frame = -1
	if reconnect_events: prepare_events()

func _retire_runtime() -> void:
	for wave in _runtime.values(): _retire_deployments(wave.deployments)
	_runtime.clear()
	_alive.clear()

func _preserve_corpses(deployments: Array[Dictionary]) -> void:
	if not is_instance_valid(_corpse_root):
		_corpse_root = Node3D.new()
		_corpse_root.name = "Corpses"
		_host.add_child(_corpse_root, false, Node.INTERNAL_MODE_BACK)
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
	for wave in _waves:
		for deployment in wave.pending:
			if is_instance_valid(deployment.root): deployment.root.free()
		wave.pending.clear()

func _fail(reason: String) -> void:
	if _state != State.ERROR or _reason != reason: push_warning("SceneDirector：" + reason)
	_state = State.ERROR
	_reason = reason
	_clear_subscriptions()

func _refresh_summary() -> void:
	if _released or _state in [State.ERROR, State.COMPLETED]: return
	_state = State.ACTIVE if _started else State.WAITING
	_remaining = 0.0
	_reason = ""
	for index in _waves.size():
		var wave: Dictionary = _waves[index]
		if wave.state in [&"delay", &"blocked"]:
			_state = State.DELAY if wave.state == &"delay" else State.BLOCKED
			_index = index
			_remaining = wave.remaining
			_reason = wave.reason
			return
	if _runtime.is_empty():
		_state = State.WAITING
		if _started and not _waves.is_empty(): _reason = "Waiting for events or wave requests."
	elif not _runtime.values().any(func(wave): return not wave.alive.is_empty()):
		_state = State.CLEARING

func debug_snapshot() -> Dictionary:
	var pending_count := 0
	var details: Array[Dictionary] = []
	for index in _waves.size():
		var wave: Dictionary = _waves[index]
		if wave.state in [&"ready", &"delay", &"blocked"]: pending_count += wave.member_count
		var missing: PackedStringArray = []
		if wave.state == &"waiting" and wave.start_mode == Wave.StartMode.EVENTS:
			for trigger_index in wave.triggers.size():
				if wave.received.has(trigger_index): continue
				var trigger = wave.triggers[trigger_index]
				if trigger != null: missing.append("%s.%s" % [trigger.source_path, trigger.signal_name])
		details.append({"index": index + 1, "name": wave.name, "state": wave.state,
			"remaining_seconds": wave.remaining, "reason": wave.reason, "missing_events": missing})
	var active_waves: Array[int] = []
	for index in _runtime:
		if not _runtime[index].alive.is_empty(): active_waves.append(index + 1)
	return {"captured": _captured, "wave_count": _waves.size(), "errors": _configuration_errors.duplicate(), "advisories": _configuration_advisories.duplicate(),
		"state": State.keys()[_state], "status": STATE_NAMES[_state], "wave": _index + 1,
		"alive": _alive.size(), "active_waves": active_waves, "pending": pending_count,
		"remaining_seconds": _remaining, "reason": _reason, "waves": details, "events_prepared": _events_prepared, "released": _released}

func configuration_warnings(region: Node) -> PackedStringArray:
	if _captured:
		var captured_warnings := _configuration_errors.duplicate()
		captured_warnings.append_array(_configuration_advisories)
		return captured_warnings
	var configuration := _collect_configuration(region)
	var errors: PackedStringArray = configuration.errors
	var definitions: Array[Dictionary] = []
	for wave in configuration.waves:
		var definition: Node = wave.definition
		var entry: Dictionary = wave.duplicate()
		entry.definition = weakref(definition)
		definitions.append(entry)
		if wave.start_mode != Wave.StartMode.EVENTS: continue
		for trigger_index in wave.triggers.size():
			var trigger = wave.triggers[trigger_index]
			if trigger_index >= wave.event_node_start:
				var node_diagnostic: String = definition.event_node_diagnostic(trigger.source_path)
				if not node_diagnostic.is_empty():
					errors.append("%s: %s" % [wave.name, node_diagnostic])
					continue
			var subscription := Subscription.new()
			var diagnostic := subscription.connect_trigger(definition, trigger, func(): pass)
			subscription.clear()
			if not diagnostic.is_empty(): errors.append("%s: %s" % [wave.name, diagnostic])
	if not definitions.is_empty():
		errors.append_array(_prerequisite_errors(definitions))
		errors.append_array(_prerequisite_errors(definitions, true))
	if region == null or region != _host.get_parent(): errors.append("SceneDirector must be a direct child of its combat region.")
	return errors

func _clear_subscriptions() -> void:
	for link in _event_links: link.subscription.clear()
	_event_links.clear()

func release() -> void:
	if _released: return
	_released = true
	_generation += 1
	_clear_subscriptions()
	_retire_runtime()
	_free_pending()
	_clear_corpses()
	_waves.clear()
	_owned.clear()
	_retiring.clear()
	_cleared.clear()
	_exiting_members.clear()
	_started = false
	_events_prepared = false
	_state = State.WAITING
	_index = -1
	_spawned = 0
	_remaining = 0.0
	_reason = ""
	_region = null
	_host = null
