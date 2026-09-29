extends SceneTree

const EnemyScene = preload("res://scenes/enemy/enemy.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func settle() -> void:
	for frame in range(8): await physics_frame

func add_enemy(parent: Node3D, at: Vector3, label: String):
	var enemy = EnemyScene.instantiate()
	enemy.name = label
	enemy.position = at
	enemy.get_node("AI").set_physics_process(false)
	parent.add_child(enemy)
	enemy.get_node("AI").cover_selection.debug_attack_points = false
	return enemy

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	root.get_node("DebugSettings").enabled = false
	var arena = scene.get_node("Arena")
	var original = arena.get_node("Enemy")
	original.get_node("AI").set_physics_process(false)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	var container := Node3D.new()
	container.name = "Enemies"
	arena.add_child(container)
	var first = add_enemy(container, Vector3(0, 0, -2), "First")
	var second = add_enemy(arena, Vector3(2, 0, -2), "Second")
	var ai = first.get_node("AI")
	var other_ai = second.get_node("AI")
	check(ai.context.arena == arena and ai.navigation_region == arena.get_node("NavigationRegion3D"), "容器内敌人自动绑定最近竞技场及导航")
	check(arena.enemies.size() == 3, "拖入实例自动注册且不重复登记")
	check(ai.training.profile != other_ai.training.profile and ai.unit_type.profile != other_ai.unit_type.profile, "实例兵种与训练运行快照互不共享")
	check(ai.actions[&"search"].coverage != other_ai.actions[&"search"].coverage, "每个敌人独立保存搜索覆盖进度")
	player.global_position = Vector3(-30, 0, 0)
	await settle()
	var pause: float = ai.patrol_pause_timer
	ai._physics_process(1.0)
	ai.notice_shot(first.get_shot_origin(), first.get_shot_origin() + Vector3.RIGHT)
	first.receive_hit(1.0, player.global_position)
	check(not ai.is_arena_active() and not ai.is_alerted and ai.patrol_pause_timer == pause and first.position == Vector3(0, 0, -2), "区域外待命，近弹和受击不启动巡逻调查")
	player.global_position = arena.to_global(Vector3(1, 0, 2))
	await settle()
	check(ai.is_arena_active() and other_ai.is_arena_active(), "玩家入场激活同区域两个拖入实例")
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(first)
	first.face_direction(player.global_position - first.global_position, 10.0)
	var shots: int = first.shot_count
	for frame in range(120):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	check(first.shot_count > shots, "容器内敌人通过完整AI循环实际开火")
	var other_arena = load("res://scenes/arena.tscn").instantiate()
	other_arena.name = "OtherArena"
	other_arena.position = Vector3(80, 0, 0)
	other_arena.get_node("Enemy/AI").set_physics_process(false)
	scene.add_child(other_arena)
	var foreign = other_arena.get_node("Enemy")
	check(not foreign.get_node("AI").context.environment_ready(), "共享导航地图已同步时仍等待新区域自身同步")
	foreign.health = 37.0
	var resets := {"first": 0, "second": 0}
	first.reset_completed.connect(func(): resets.first += 1)
	second.reset_completed.connect(func(): resets.second += 1)
	first.health = 20.0
	second.health = 30.0
	first.ammo.magazine_rounds = 0
	first.request_reload()
	player.global_position = Vector3(-30, 0, 0)
	await settle()
	check(resets.first == 1 and resets.second == 1, "离场对直接子节点和容器内实例各复位一次")
	check(first.health == first.max_health and second.health == second.max_health and first.transform == first.initial_transform and not first.ammo.is_reloading, "离场恢复出生位置生命弹药并清理行动")
	check(foreign.health == 37.0, "本区域离场不刷新其他竞技场")
	player.global_position = arena.to_global(Vector3(1, 0, 2))
	await settle()
	check(ai.is_arena_active(), "重新进入可再次激活")
	var navigation = arena.get_node("NavigationRegion3D")
	navigation.enabled = false
	ai._physics_process(0.1)
	check(not ai.is_arena_active() and ai.current_action == null and ai.context.fire.request.is_empty(), "导航停用立即清理运行与开火请求")
	navigation.enabled = true
	await settle()
	check(ai.is_arena_active(), "导航恢复后正常运行")
	arena.remove_child(navigation)
	ai._physics_process(0.1)
	check(not ai.is_arena_active(), "导航离树安全待命")
	arena.add_child(navigation)
	ai._physics_process(0.1)
	await settle()
	check(ai.is_arena_active(), "同名导航重新接入后恢复")
	var replacement = navigation.duplicate()
	navigation.free()
	ai._physics_process(0.1)
	check(not ai.is_arena_active(), "导航节点被释放后不会访问失效引用")
	arena.add_child(replacement)
	ai.context.refresh_environment()
	await settle()
	check(ai.is_arena_active() and ai.navigation_region == replacement, "替换导航区域后绑定新节点")
	var zone = arena.get_node("CombatZone")
	var replacement_zone = zone.duplicate()
	zone.free()
	ai._physics_process(0.1)
	await settle()
	check(not ai.is_arena_active() and arena.players_inside.is_empty(), "战斗区释放后安全待命并清理进入记录")
	arena.add_child(replacement_zone)
	ai.context.refresh_environment()
	await settle()
	check(ai.is_arena_active() and arena.players_inside.has(player), "替换战斗区后重新连接入场信号")
	var reset_before: int = resets.first
	player.global_position = Vector3(-30, 0, 0)
	await settle()
	check(resets.first == reset_before + 1, "替换后的战斗区离场仍正确复位")
	player.global_position = arena.to_global(Vector3(1, 0, 2))
	await settle()
	var standalone = add_enemy(scene, Vector3(-40, 0, 0), "OutsideArena")
	standalone.get_node("AI")._physics_process(0.1)
	check(not standalone.get_node("AI").is_arena_active(), "未放进竞技场不会全地图激活")
	var invalid = add_enemy(container, Vector3(30, 0, 0), "OutsideZone")
	await settle()
	invalid.get_node("AI")._physics_process(0.1)
	check(not invalid.get_node("AI").is_arena_active() and invalid.position == Vector3(30, 0, 0), "区域外出生点停用且不自动传送")
	var in_wall = add_enemy(container, Vector3(-3.6225, 0, 0.8), "OutsideNavigation")
	await settle()
	check(not in_wall.get_node("AI").is_arena_active(), "区域内但导航不可站立的位置停用")
	var before: int = arena.enemies.size()
	invalid.free()
	check(arena.enemies.size() == before - 1, "释放敌人注销区域登记")
	# 重新挂父节点触发 exit/enter，服务必须恢复且旧空间任务不能遗留。
	second.reparent(container)
	await settle()
	other_ai._physics_process(0.1)
	check(arena.enemies.count(second) == 1 and other_ai.context.fire.context == other_ai.context and not other_ai.actions.is_empty(), "重新挂父节点恢复服务和动作且不重复注册")
	# 缺少玩家时安全等待，晚加入玩家仍能正常绑定。
	var isolated = other_arena.get_node("Enemy/AI")
	scene.remove_child(player)
	isolated.context.player = null
	isolated._physics_process(0.1)
	check(not isolated.is_arena_active(), "没有玩家时安全待命")
	player.position = other_arena.to_global(Vector3(0, 0, 0))
	scene.add_child(player)
	await settle()
	isolated._physics_process(0.1)
	check(isolated.player == player and isolated.is_arena_active(), "玩家晚加入时重新解析并按所属区域激活")
	print("ENEMY SCENE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
