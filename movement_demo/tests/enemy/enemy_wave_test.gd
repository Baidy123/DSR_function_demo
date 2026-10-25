extends SceneTree

const Controller = preload("res://scripts/world/enemy_wave_controller.gd")
const Wave = preload("res://scripts/world/enemy_wave_definition.gd")
const Region = preload("res://scripts/world/shooting_range.gd")
const SquadScene = preload("res://scenes/world/squad.tscn")
const EnemyScene = preload("res://scenes/enemy/levels/lvl_1/melee.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if Engine.is_editor_hint():
		await _editor_roundtrip()
		print("ENEMY WAVES EDITOR: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	root.get_node("DebugSettings").enabled = false
	await _templates()
	await _runtime_waves()
	await _overlapping_waves()
	await _mixed_wave_conditions()
	await _safety_and_lifecycle()
	await _actual_levels()
	print("ENEMY WAVES: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _templates() -> void:
	var region = Node3D.new()
	region.set_script(Region)
	region.name = "TemplateRegion"
	region.position = Vector3(31, 0, 4)
	region.rotation.y = 0.7
	var controller = Controller.new()
	controller.name = "EnemyWaves"
	region.add_child(controller)
	var first = Wave.new()
	first.name = "First"
	controller.add_child(first)
	var second = Wave.new()
	second.name = "Second"
	second.position = Vector3(-3, 0, 1)
	controller.add_child(second)
	var external = SquadScene.instantiate()
	external.name = "Squad"
	region.add_child(external)
	first.existing_squads.assign([NodePath("../../Squad")])
	var nested = SquadScene.instantiate()
	second.add_child(nested)
	var template = EnemyScene.instantiate()
	template.max_health = 173.0
	template.position = Vector3(2, 0, -2)
	template.rotation.y = 0.9
	external.add_child(template)
	# 故意让关卡拥有手工新增成员；未经规范化直接 pack(Squad) 会漏掉它。
	template.owner = region
	var material := StandardMaterial3D.new()
	material.resource_local_to_scene = true
	material.albedo_color = Color.BLUE
	template.get_node("Body").material_override = material
	var weapon = template.weapon
	var training = template.get_node("Training").profile
	var profile = external.profile
	var transform_before: Transform3D = template.transform
	var later = EnemyScene.instantiate()
	nested.add_child(later)
	var entries := [0]
	template.tree_entered.connect(func(): entries[0] += 1)
	later.tree_entered.connect(func(): entries[0] += 1)
	root.add_child(region)
	check(entries[0] == 0 and not is_instance_valid(template) and not is_instance_valid(later), "捕获早于所有受管成员入树，原模板节点释放")
	check(region.enemies.is_empty() and get_nodes_in_group("shot_listener").is_empty() and get_nodes_in_group("combat_target").is_empty(), "未来波次无区域注册、近弹监听或战斗目标")
	check(controller.debug_snapshot().errors.is_empty() and controller.debug_snapshot().wave_count == 2, "原路径引用和直接子小队共用捕获流程")
	var copies: Array[Dictionary] = controller._instantiate_wave(0)
	check(copies.size() == 1 and copies[0].members.size() == 1, "保留关卡拥有的手工成员")
	var enemy = copies[0].members[0]
	check(enemy.max_health == 173.0 and enemy.transform == transform_before and enemy.get_child_count() == 12 and enemy.has_node("HealthBar"), "完整保留生命、部署朝向及包含血条的公共组件")
	check(enemy.weapon == weapon and enemy.get_node("Training").profile == training and copies[0].root.profile == profile, "普通武器、嵌套训练与小队 Profile 保持共享引用")
	check(enemy.get_node("Body").material_override != material and enemy.get_node("Body").material_override.albedo_color == Color.BLUE, "实例覆盖的 local_to_scene 资源独立且值保留")
	region.add_child(copies[0].root)
	check(region.get_node("Squad/" + str(enemy.name)) == enemy and enemy.global_transform.is_equal_approx(region.global_transform * transform_before), "运行副本恢复原节点路径及区域变换")
	check(region.enemies.has(enemy) and enemy.get_node("AI").is_in_group("shot_listener") and enemy.health == 173.0, "仅运行副本正常就绪并注册原 AI")
	enemy.receive_hit(20.0)
	copies[0].root.free()
	var again: Array[Dictionary] = controller._instantiate_wave(0)
	check(again[0].members[0].max_health == 173.0 and again[0].members[0].transform == transform_before, "再次生成仍使用未受伤未移动的部署快照")
	again[0].root.free()
	var next: Array[Dictionary] = controller._instantiate_wave(1)
	check(next[0].parent.get_ref() == second, "后续波保留直接子小队的原父节点")
	next[0].root.free()
	check(region.enemies.is_empty() and get_nodes_in_group("shot_listener").is_empty(), "销毁运行副本沿原流程注销")
	region.free()
	await process_frame
	check(not is_instance_valid(controller), "关卡卸载释放控制器及内存部署资源")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _fixture(with_waves: bool = true) -> Node3D:
	var region := Node3D.new()
	region.name = "WaveRegion"
	region.set_script(Region)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(24, 0.2, 24)
	floor_body.position.y = -0.1
	floor_body.add_child(floor_shape)
	region.add_child(floor_body)
	var navigation := NavigationRegion3D.new()
	navigation.name = "NavigationRegion3D"
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-11, 0, -11), Vector3(11, 0, -11), Vector3(11, 0, 11), Vector3(-11, 0, 11)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	region.add_child(navigation)
	var zone := Area3D.new()
	zone.name = "CombatZone"
	zone.collision_layer = 0
	var zone_shape := CollisionShape3D.new()
	zone_shape.name = "CollisionShape3D"
	zone_shape.shape = BoxShape3D.new()
	zone_shape.shape.size = Vector3(22, 4, 22)
	zone_shape.position.y = 1.0
	zone.add_child(zone_shape)
	region.add_child(zone)
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0, 5)
	region.add_child(player)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 15, 10)
	camera.rotation.x = -0.9
	region.add_child(camera)
	if with_waves:
		var controller = Controller.new()
		controller.name = "EnemyWaves"
		region.add_child(controller)
		for index in 2:
			var wave = Wave.new()
			wave.name = "Wave%d" % (index + 1)
			controller.add_child(wave)
			var squad = SquadScene.instantiate()
			wave.add_child(squad)
			_add_member(squad, "Enemy", Vector3(-2, 0, -3 if index == 0 else 3))
			_add_member(squad, "Enemy2", Vector3(2, 0, -3 if index == 0 else 3))
			if index == 0:
				var other = SquadScene.instantiate()
				other.name = "OtherSquad"
				wave.add_child(other)
				_add_member(other, "Enemy3", Vector3(0, 0, -6))
	return region

func _add_member(squad: Node, label: String, at: Vector3) -> Node3D:
	var enemy = EnemyScene.instantiate()
	enemy.name = label
	enemy.position = at
	enemy.rotation.y = PI
	# 本夹具导航面为Y=0；原烘焙关卡的高度补偿不能用于这个合成地面。
	enemy.get_node("NavigationAgent3D").path_height_offset = 0.0
	# 夹具使用原兵种基础动作，不依赖用户在本地勾选的额外战术。
	enemy.get_node("Training").profile = enemy.get_node("Training").profile.duplicate(true)
	enemy.get_node("Training").profile.selected_tactics.clear()
	squad.add_child(enemy)
	return enemy

func _settle(frames: int = 5) -> void:
	for frame in frames: await physics_frame
	await process_frame

func _await_state(controller: Node, expected: String, frames: int = 90) -> bool:
	for frame in frames:
		if controller.debug_snapshot().state == expected: return true
		if controller.debug_snapshot().state == "ERROR":
			print("Wave diagnosis: ", controller.debug_snapshot())
			return false
		await _settle(1)
	return controller.debug_snapshot().state == expected

func _runtime_waves() -> void:
	var region = _fixture()
	var controller = region.get_node("EnemyWaves")
	controller.get_node("Wave2").start_delay_seconds = 0.15
	var events := {"started": [], "cleared": [], "completed": 0, "hits": 0}
	controller.wave_started.connect(func(index): events.started.append(index))
	controller.wave_cleared.connect(func(index): events.cleared.append(index))
	controller.encounter_completed.connect(func(): events.completed += 1)
	root.add_child(region)
	current_scene = region
	var player = region.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	player.get_node("Health").hit_received.connect(func(_damage): events.hits += 1)
	check(await _await_state(controller, "ACTIVE"), "真实区域入场自动生成首波")
	if controller.debug_snapshot().state != "ACTIVE":
		region.queue_free()
		await _settle()
		return
	check(region.enemies.size() == 3 and controller.debug_snapshot().alive == 3 and region.get_node("EnemyWaves/Wave2").get_child_count() == 0, "同波两个小队全部计数，下一波尚无运行实例")
	var health_bar = region.enemies[0].get_node("HealthBar")
	var health_before: float = region.enemies[0].health
	region.enemies[0].receive_hit(health_before * 0.25)
	check(is_equal_approx(health_bar.ratio, 0.75) and health_bar.visible, "真实受伤更新无数字血条，正常游戏可见")
	var original_positions := {}
	for enemy in region.enemies: original_positions[enemy.get_instance_id()] = enemy.global_position
	for frame in 480:
		if events.hits > 0: break
		await physics_frame
	var moved := false
	for enemy in region.enemies:
		moved = moved or enemy.global_position.distance_to(original_positions[enemy.get_instance_id()]) > 0.5
		if events.hits == 0:
			var ai = enemy.get_node("AI")
			print("Combat diagnostic: ", enemy.name, " at=", enemy.global_position, " active=", ai.is_arena_active(), " visible=", ai.perception.can_see_player(), " action=", ai.utility_current, " melee=", enemy.melee_count, " weapon=", enemy.weapon)
	check(moved and events.hits > 0, "新生敌人通过原 AI 自主移动并真实命中玩家")
	player.global_position = Vector3(-2, 0, 3)
	await _settle()
	var first_members: Array = region.enemies.duplicate()
	first_members[0].receive_hit(10000.0)
	first_members[0].died.emit()
	await _settle()
	check(controller.debug_snapshot().alive == 2 and events.started == [1], "真实死亡按身份去重，剩余成员未死不推进")
	first_members[1].receive_hit(10000.0)
	var execution_result: StringName = first_members[2].receive_headshot_hit(1.0, player.global_position, {}, {"execution": true})
	check(execution_result == &"killed" and first_members[2].is_dead, "最后一人经爆头秒杀入口死亡，接续原波次与尸体流程")
	check(await _await_state(controller, "BLOCKED"), "同帧全灭后第二波遇到真实玩家占位而等待")
	check(events.cleared == [1] and events.completed == 0 and controller.debug_snapshot().pending == 2 and region.enemies.is_empty(), "旧波完成注销，受阻整波保留两名待生成成员")
	check(is_instance_valid(controller._corpse_root) and controller._corpse_root.get_child_count() == 3 and _only_corpse_visuals(controller._corpse_root), "首波只留下三具静态尸体，没有AI、血条或碰撞")
	var last_body = controller._corpse_root.get_child(2).get_child(0)
	var falling_angle: float = last_body.rotation.x
	check(falling_angle >= 0.0 and falling_angle < PI * 0.5 - 0.01, "最后一人回收后接续倒地中间姿态，不瞬间躺平")
	await _settle(35)
	check(is_equal_approx(last_body.rotation.x, PI * 0.5) and is_equal_approx(last_body.position.y, 0.35), "轻量尸体完成剩余倒地过程并停在原终点")
	check(events.started == [1] and region.enemies.is_empty(), "持续占位不跳波、不部分生成、不强刷")
	var remaining: float = controller.debug_snapshot().remaining_seconds
	player.is_in_dialogue = true
	await _settle(20)
	check(is_equal_approx(remaining, controller.debug_snapshot().remaining_seconds), "对话冻结剩余重试时间")
	player.is_in_dialogue = false
	paused = true
	await _settle(5)
	check(is_equal_approx(remaining, controller.debug_snapshot().remaining_seconds), "暂停冻结波次时钟")
	paused = false
	player.global_position = Vector3(0, 0, 7)
	check(await _await_state(controller, "ACTIVE"), "玩家让开后第二波恢复生成")
	check(events.started == [1, 2] and region.enemies.size() == 2 and region.enemies[0].initial_transform.origin == Vector3(-2, 0, 3), "仅生成一次且保留人工部署点")
	var second_members: Array = region.enemies.duplicate()
	for enemy in second_members: enemy.receive_hit(10000.0)
	check(await _await_state(controller, "COMPLETED"), "最后一波清空完成")
	controller.start_encounter()
	await _settle(20)
	check(events.cleared == [1, 2] and events.completed == 1 and region.enemies.is_empty(), "完成信号一次，重复启动不自动循环")
	check(controller._corpse_root.get_child_count() == 5, "最终完成保留两波全部尸体")
	player.global_position = Vector3(30, 0, 0)
	await _settle()
	check(controller.debug_snapshot().state == "WAITING", "最后玩家离场恢复等待首波")
	check(controller._corpse_root == null, "离场重开清理本轮尸体")
	player.global_position = Vector3(0, 0, 5)
	check(await _await_state(controller, "ACTIVE") and controller.debug_snapshot().wave == 1, "重新入场从完整首波重新生成")
	var reset_events := [0]
	for enemy in region.enemies: enemy.reset_completed.connect(func(): reset_events[0] += 1)
	# 真实离场信号中 queue_free 尚未完成时，区域也不能对旧波 reset_target。
	player.global_position = Vector3(30, 0, 0)
	await _settle()
	check(region.enemies.is_empty() and reset_events[0] == 0, "离场清理不复活旧波成员")
	region.queue_free()
	await _settle()
	check(get_nodes_in_group("shot_listener").is_empty(), "卸载关卡清除全部近弹监听和运行实例")

func _only_corpse_visuals(node: Node) -> bool:
	if not node is Node3D or node.get_script() != null or node is CollisionObject3D or node is CollisionShape3D: return false
	for child in node.get_children():
		if not _only_corpse_visuals(child): return false
	return true

func _await_wave(controller: Node, index: int, frames: int = 90) -> bool:
	for frame in frames:
		if controller.debug_snapshot().active_waves.has(index): return true
		if controller.debug_snapshot().state == "ERROR": return false
		await _settle(1)
	return controller.debug_snapshot().active_waves.has(index)

func _overlapping_waves() -> void:
	var region = _fixture()
	var controller = region.get_node("EnemyWaves")
	controller.get_node("Wave2").wait_for_previous_clear = false
	controller.get_node("Wave2").start_delay_seconds = 0.4
	var events := {"started": [], "cleared": [], "completed": 0}
	controller.wave_started.connect(func(index):
		events.started.append(index)
		# 此用例验证调度；固定真实敌人位置，避免 AI 行走偶然占据下一波刷新点。
		for enemy in region.enemies: enemy.set_physics_process(false))
	controller.wave_cleared.connect(func(index): events.cleared.append(index))
	controller.encounter_completed.connect(func(): events.completed += 1)
	root.add_child(region)
	current_scene = region
	var player = region.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	check(await _await_wave(controller, 1) and controller.debug_snapshot().state == "DELAY", "定时模式从上一波实际出场开始计时")
	await _settle(6)
	check(events.started == [1] and controller.debug_snapshot().alive == 3 and controller.debug_snapshot().remaining_seconds > 0.0, "定时未到不提前生成，首波存活不阻止倒计时")
	var remaining: float = controller.debug_snapshot().remaining_seconds
	player.is_in_dialogue = true
	await _settle(25)
	check(is_equal_approx(remaining, controller.debug_snapshot().remaining_seconds) and events.started == [1], "对话冻结多波加入倒计时")
	player.is_in_dialogue = false
	paused = true
	await _settle(5)
	check(is_equal_approx(remaining, controller.debug_snapshot().remaining_seconds), "暂停冻结多波加入倒计时")
	paused = false
	check(await _await_wave(controller, 2) and controller.debug_snapshot().alive == 5 and controller.debug_snapshot().active_waves == [1, 2], "时间到后两波共五名敌人同时存在并各自计数")
	for enemy in controller.get_node("Wave2/Squad").get_children(): enemy.receive_hit(10000.0)
	await _settle(5)
	check(events.cleared == [2] and events.completed == 0 and controller.debug_snapshot().alive == 3, "第二波先全灭只清理第二波，首波仍存活不能完成战斗")
	for enemy in region.enemies.duplicate(): enemy.receive_hit(10000.0)
	check(await _await_state(controller, "COMPLETED") and events.cleared == [2, 1] and events.completed == 1, "允许乱序清波，所有波次全灭后只完成一次")
	controller.reset_encounter()
	controller.start_encounter()
	await _await_wave(controller, 1)
	controller.reset_encounter()
	await _settle(35)
	check(controller.debug_snapshot().state == "WAITING" and region.enemies.is_empty() and events.started == [1, 2, 1], "倒计时期间复位取消尚未加入的波次")
	controller.start_encounter()
	await _await_wave(controller, 2)
	var resets := [0]
	for enemy in region.enemies: enemy.reset_completed.connect(func(): resets[0] += 1)
	player.global_position = Vector3(30, 0, 0)
	await _settle()
	check(controller.debug_snapshot().state == "WAITING" and region.enemies.is_empty() and resets[0] == 0, "多波同时存在时离场统一回收，不复活任何旧成员")
	region.queue_free()
	await _settle()
	check(get_nodes_in_group("shot_listener").is_empty(), "重叠波次卸载后没有遗留监听")

func _mixed_wave_conditions() -> void:
	var region = _fixture()
	var controller = region.get_node("EnemyWaves")
	controller.get_node("Wave1").start_delay_seconds = 0.15
	controller.get_node("Wave1").wait_for_previous_clear = false
	controller.get_node("Wave2").wait_for_previous_clear = false
	var third = Wave.new()
	third.name = "Wave3"
	third.start_delay_seconds = 0.2
	controller.add_child(third)
	var squad = SquadScene.instantiate()
	third.add_child(squad)
	_add_member(squad, "Enemy", Vector3(6, 0, -5))
	var started: Array = []
	controller.wave_started.connect(func(index):
		started.append(index)
		for enemy in region.enemies: enemy.set_physics_process(false))
	root.add_child(region)
	current_scene = region
	var player = region.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	await _settle(3)
	check(started.is_empty(), "首波无上一波时仍遵守本轮开始后的等待秒数")
	# 首波不占用后续刷新点，玩家占位会让0秒的第二波等待而非强刷。
	player.global_position = Vector3(-2, 0, 3)
	check(await _await_state(controller, "BLOCKED") and started == [1] and controller.debug_snapshot().alive == 3, "定时0秒允许尽快加入，但仍服从原位置的真实占位检查")
	await _settle(20)
	check(started == [1], "后续波不会越过尚未实际出场的受阻波次")
	player.global_position = Vector3(0, 0, 7)
	check(await _await_wave(controller, 2), "刷新点让开后定时波完整加入")
	await _settle(20)
	check(started == [1, 2], "等待全灭的第三波不会从第二波出场时提前计时")
	for enemy in controller.get_node("Wave2/Squad").get_children(): enemy.receive_hit(10000.0)
	await _settle(5)
	check(started == [1, 2] and controller.debug_snapshot().state == "DELAY" and controller.debug_snapshot().remaining_seconds > 0.0, "上一波全灭后才开始第三波的等待秒数")
	check(await _await_wave(controller, 3) and controller.debug_snapshot().active_waves == [1, 3], "等待上一波仅指相邻第二波，允许更早的首波仍存活")
	region.queue_free()
	await _settle()
	check(get_nodes_in_group("shot_listener").is_empty(), "混合条件战斗中卸载清理所有存活波次")

func _safety_and_lifecycle() -> void:
	# 重叠、墙内、空波及重复引用均保持错误，不能偷偷跳过或宣布完成。
	for problem in ["overlap", "wall", "empty", "duplicate", "loose_enemy"]:
		var region = _fixture()
		var controller = region.get_node("EnemyWaves")
		var first = controller.get_node("Wave1")
		if problem == "overlap": first.get_node("Squad/Enemy2").position = first.get_node("Squad/Enemy").position
		if problem == "wall":
			var wall := StaticBody3D.new()
			wall.name = "BlockedSpawn"
			wall.position = Vector3(-2, 0.9, -3)
			var shape := CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			shape.shape.size = Vector3(1, 1.8, 1)
			wall.add_child(shape)
			region.add_child(wall)
		if problem == "empty":
			for child in first.get_children(): child.free()
		if problem == "duplicate": controller.get_node("Wave2").existing_squads.assign([NodePath("../Wave1/Squad")])
		if problem == "loose_enemy": first.get_node("Squad/Enemy").reparent(first, false)
		root.add_child(region)
		region.get_node("Player").set_physics_process(false)
		check(await _await_state(controller, "ERROR") and region.enemies.is_empty() and not controller.debug_snapshot().reason.is_empty(), "错误配置 %s 有诊断且不会部分生成或清波" % problem)
		region.queue_free()
		await _settle()
	var manual = _fixture()
	var controller = manual.get_node("EnemyWaves")
	controller.auto_start_on_enter = false
	root.add_child(manual)
	var player = manual.get_node("Player")
	player.set_physics_process(false)
	await _settle()
	check(controller.debug_snapshot().state == "WAITING" and manual.enemies.is_empty(), "关闭自动开始时入场不生成")
	controller.start_encounter()
	controller.start_encounter()
	check(await _await_state(controller, "ACTIVE") and manual.enemies.size() == 3, "手动开始及重复调用只生成完整首波一次")
	manual.enemies[0].queue_free()
	check(await _await_state(controller, "ERROR") and controller.debug_snapshot().wave == 1, "活敌人意外移除停止推进，不能视作死亡")
	controller.reset_encounter()
	controller.start_encounter()
	check(await _await_state(controller, "ACTIVE") and manual.enemies.size() == 3, "复位后等待旧实例退树再生成，不重复注册")
	# 死亡已经发生、尚未切波时离场；不能让旧死亡回调推进下一轮。
	for enemy in manual.enemies.duplicate(): enemy.receive_hit(10000.0)
	player.global_position = Vector3(30, 0, 0)
	await _settle()
	check(controller.debug_snapshot().state == "WAITING" and manual.enemies.is_empty(), "清波与离场相邻时取消旧轮推进")
	manual.queue_free()
	await _settle()
	# 没有组件的原区域仍原地复活，而且只复位一次。
	var plain = _fixture(false)
	var squad = SquadScene.instantiate()
	plain.add_child(squad)
	var enemy = _add_member(squad, "OrdinaryEnemy", Vector3(0, 0, -3))
	root.add_child(plain)
	plain.get_node("Player").set_physics_process(false)
	enemy.get_node("AI").set_physics_process(false)
	await _settle()
	var resets := [0]
	enemy.reset_completed.connect(func(): resets[0] += 1)
	enemy.receive_hit(10000.0)
	plain.get_node("Player").global_position = Vector3(30, 0, 0)
	await _settle()
	check(resets[0] == 1 and not enemy.is_dead and enemy.health == enemy.max_health, "无波次区域沿用原复位一次的行为")
	plain.queue_free()
	await _settle()

func _actual_levels() -> void:
	for number in range(1, 6):
		var level = load("res://scenes/world/levels/lvl_%d.tscn" % number).instantiate()
		check(level.get_script() == Region and level.has_node("CombatZone/CollisionShape3D") and level.has_node("NavigationRegion3D"), "第%d关继续共用原区域接口" % number)
		level.free()
	var level = load("res://scenes/world/levels/lvl_1.tscn").instantiate()
	var controller = level.get_node("EnemyWaves")
	var count: int = level.get_node("Squad").get_child_count()
	var second_count: int = controller.get_node("Wave2/Squad").get_child_count()
	var poses := {}
	for child in level.get_node("Squad").get_children(): poses[child.name] = child.transform
	root.add_child(level)
	current_scene = level
	var player = level.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	var hits := [0]
	player.get_node("Health").hit_received.connect(func(_damage): hits[0] += 1)
	check(await _await_state(controller, "ACTIVE") and level.enemies.size() == count, "保存的第一关实际生成用户原小队")
	if controller.debug_snapshot().state != "ACTIVE":
		level.queue_free()
		await _settle()
		return
	var all_preserved := true
	for enemy in level.enemies: all_preserved = all_preserved and enemy.initial_transform.is_equal_approx(poses[enemy.name])
	check(all_preserved and level.has_node("Squad/Enemy"), "第一关原节点路径、位置与朝向完整保留")
	# 进入上侧开阔通道建立真实接敌；不把随机巡逻能否在10秒内遇到南侧玩家当成波次门槛。
	# 只移动测试实例的玩家，不改保存部署、敌人训练、AI观察或任务。
	player.global_position = level.to_global(Vector3(-5.5, 0, -2.05))
	var before := {}
	for enemy in level.enemies: before[enemy.get_instance_id()] = enemy.global_position
	for frame in 600:
		if hits[0] > 0: break
		await physics_frame
	var moved := false
	for enemy in level.enemies:
		moved = moved or enemy.global_position.distance_to(before[enemy.get_instance_id()]) > 0.5
		if hits[0] == 0:
			print("Level combat diagnostic: ", enemy.name, " at=", enemy.global_position, " player=", player.global_position, " speed=", enemy.move_speed, " melee=", enemy.melee_count, " action=", enemy.get_node("AI").utility_current.get("id"))
	check(moved and hits[0] > 0, "第一关保存的导航与训练下原 AI 自主移动并实际命中")
	for enemy in level.enemies.duplicate(): enemy.receive_hit(10000.0)
	for frame in 90:
		await _settle(1)
		if controller.debug_snapshot().wave == 2 and controller.debug_snapshot().state == "ACTIVE": break
	check(controller.debug_snapshot().wave == 2 and controller.debug_snapshot().alive == second_count, "第一关第二波按当前保存的成员数出场")
	for enemy in level.enemies.duplicate(): enemy.receive_hit(10000.0)
	check(await _await_state(controller, "COMPLETED"), "第一关两波完整结束")
	# 只改另一张地图的内存实例，旋转/平移整个区域后沿同一流程部署。
	var other = load("res://scenes/world/levels/lvl_2.tscn").instantiate()
	# 跨区用例由第一关同一个玩家移动过去；用户可独立给第二关配置试玩玩家／相机。
	for path in ["Player", "Camera3D", "EnemyWaves"]:
		var standalone = other.get_node_or_null(path)
		if standalone != null: standalone.free()
	for authored_member in other.get_node("Squad").get_children(): authored_member.free()
	other.position = Vector3(60, 0, 0)
	other.rotation.y = PI * 0.5
	var waves = load("res://scenes/world/enemy_waves.tscn").instantiate()
	other.add_child(waves)
	var other_wave = load("res://scenes/world/enemy_wave.tscn").instantiate()
	other_wave.name = "Wave1"
	waves.add_child(other_wave)
	other_wave.existing_squads.assign([NodePath("../../Squad")])
	var member = _add_member(other.get_node("Squad"), "Enemy", Vector3(-9, 0, -6))
	var local_pose: Transform3D = member.transform
	root.add_child(other)
	await _settle()
	check(waves.debug_snapshot().state == "WAITING" and other.enemies.is_empty(), "另一地图未入场保持树外部署，不被第一关推进")
	player.global_position = other.to_global(Vector3(-9, 0, -2))
	check(await _await_state(waves, "ACTIVE"), "另一地图使用同一组件入场生成")
	if not other.enemies.is_empty():
		var spawned = other.enemies[0]
		check(spawned.initial_transform.is_equal_approx(local_pose) and spawned.get_node("AI").context.navigation_region == other.get_node("NavigationRegion3D"), "旋转平移后的部署与导航归属正确")
	check(controller.debug_snapshot().state == "WAITING" and level.enemies.is_empty(), "跨区移动仅复位离开的第一关")
	other.queue_free()
	level.queue_free()
	await _settle()

func _editor_roundtrip() -> void:
	# 只在独立编辑器验证副本运行；不保存用户打开的场景。
	await create_timer(3.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
	EditorInterface.open_scene_from_path("res://scenes/world/levels/lvl_1.tscn")
	for frame in 30: await process_frame
	var level := EditorInterface.get_edited_scene_root()
	var controller = level.get_node("EnemyWaves")
	check(level.has_node("Squad/Enemy") and controller.has_node("Wave2/Squad/Enemy") and not controller.debug_snapshot().captured, "编辑场景保留全部波次可见部署，不执行运行捕获")
	check(controller._get_configuration_warnings().is_empty(), "实际第一关编辑配置没有波次警告")
	EditorInterface.get_inspector().edit(controller)
	for frame in 20: await process_frame
	var fields := _inspector_fields(EditorInterface.get_inspector(), controller)
	check(fields.has("auto_start_on_enter") and fields.has("spawn_retry_seconds"), "原生检查器显示启动及高级重试参数")
	var wave = controller.get_node("Wave2")
	EditorInterface.get_inspector().edit(wave)
	for frame in 20: await process_frame
	fields = _inspector_fields(EditorInterface.get_inspector(), wave)
	check(fields.has("wait_for_previous_clear") and fields.has("start_delay_seconds") and fields.has("existing_squads"), "波次检查器显示全灭开关、等待秒数与可选已有小队引用")
	wave.wait_for_previous_clear = false
	wave.start_delay_seconds = 0.7
	var enemy = wave.get_node("Squad/Enemy")
	enemy.position += Vector3(0.4, 0, 0)
	enemy.rotation.y = 0.6
	var expected_pose: Transform3D = enemy.transform
	var copy = wave.duplicate()
	copy.name = "CopiedWave"
	controller.add_child(copy)
	_set_editor_owner(copy, level)
	controller.move_child(copy, 0)
	var output := "res://logs/enemy_waves_editor_roundtrip.tscn"
	EditorInterface.save_scene_as(output, false)
	var saved := ResourceLoader.load(output, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(saved != null, "通过原生场景保存写入独立副本")
	if saved != null:
		var reopened = saved.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		var waves = reopened.get_node("EnemyWaves")
		print("Saved wave order: ", waves.get_children().map(func(node): return str(node.name)))
		check(waves.get_child_count() == 3 and waves.get_child(0).name == "CopiedWave", "保存重开保留复制出的波次与树顺序")
		check(waves.get_node("Wave2/Squad/Enemy").transform.is_equal_approx(expected_pose) and is_equal_approx(waves.get_node("Wave2").start_delay_seconds, 0.7), "保存重开保留移动、朝向和等待参数")
		check(not waves.get_node("Wave2").wait_for_previous_clear and not waves.get_node("CopiedWave").wait_for_previous_clear and waves.get_node("Wave1").wait_for_previous_clear, "保存、复制和重开保留定时加入选项，原有波次默认等全灭")
		check(waves.get_node("Wave1").existing_squads == [NodePath("../../Squad")] and reopened.has_node("Squad/Enemy"), "保存重开保留兼容引用及原小队路径")
		reopened.free()
	EditorInterface.get_inspector().edit(null)
	for frame in 5: await process_frame

func _inspector_fields(node: Node, target: Object) -> PackedStringArray:
	var fields: PackedStringArray = []
	if node is EditorProperty and node.get_edited_object() == target: fields.append(node.get_edited_property())
	for child in node.get_children(): fields.append_array(_inspector_fields(child, target))
	return fields

func _set_editor_owner(node: Node, owner_root: Node) -> void:
	node.owner = owner_root
	for child in node.get_children():
		if child.owner == null: _set_editor_owner(child, owner_root)
