extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0
var scene
var arena
var actors: Array = []
var walls: Array[Node] = []

func _initialize() -> void:
	_run.call_deferred()

func _setup() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	arena = scene.get_node("Arena")
	var navigation: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-8, 0.5, -8), Vector3(8, 0.5, -8), Vector3(8, 0.5, 8), Vector3(-8, 0.5, 8)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	for body in navigation.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor":
			body.collision_layer = 0
			body.remove_from_group("cover_region")
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.global_position = arena.to_global(Vector3(6, 0, 7))
	actors.append(arena.get_node("Enemy"))
	var second = load("res://scenes/enemy/enemy.tscn").instantiate()
	second.position = Vector3(0, 0, 0)
	arena.add_child(second)
	actors.append(second)
	for actor in actors:
		actor.get_node("AI").set_physics_process(false)
		Fixture.configure_timing(actor)
		actor.get_node("AI").training.profile.selected_tactics.clear()
		actor.get_node("AI").refresh_configuration(true)
		actor.debug_shooting = false
	for frame in 12: await physics_frame

func _run() -> void:
	await _setup()
	await _reset(Vector3(-3, 0, 0), Vector3(0, 0, 0))
	var open := await _travel(Vector3(3, 0, 0), Vector3.INF, 360)
	check(open.first_arrived and open.safe, "开阔地沿原目标实际绕过站定友军，双方胶囊始终分离")
	check(open.first_side > 0.25 or open.second_side > 0.25, "通过真实侧向移动让出空间，没有穿透或临时关闭碰撞")

	await _reset(Vector3(-3, 0, 0), Vector3(-2.1, 0, 0))
	var following := await _travel(Vector3(3, 0, 0), Vector3(4, 0, 0), 330)
	check(following.first_arrived and following.second_arrived and following.safe and following.first_side < 0.25, "同向行进保持安全跟随，不为前方正常移动友军反复横跳")

	_make_corridor(true)
	await _reset(Vector3(-3, 0, 0), Vector3(3, 0, 0))
	var opposing := await _travel(Vector3(3, 0, 0), Vector3(-3, 0, 0), 600)
	check(opposing.first_arrived and opposing.second_arrived and opposing.safe, "迎面窄路利用真实侧向凹位稳定让行，双方都抵达原目标")

	await _reset(Vector3(-3, 0, 0), Vector3(0, 0, 0))
	actors[1].weapon.reload_seconds = 10.0
	actors[1].ammo.magazine_rounds = 1
	check(actors[1].request_reload(), "站定换弹者真实开始身体换弹")
	var reloading := await _travel(Vector3(3, 0, 0), Vector3.INF, 480)
	check(reloading.first_arrived and reloading.safe and reloading.second_side > 0.25, "站定换弹者可在身体许可内短暂让入凹位，不永久堵住通道")
	check(actors[1].ammo.is_reloading and actors[1].ammo.magazine_rounds == 1 and actors[1].shot_count == 0, "局部让行保留真实换弹计时、余弹和开火互斥")

	_clear_walls()
	_make_corridor(false)
	await _reset(Vector3(-1.2, 0, 0), Vector3(1.2, 0, 0))
	var closed := await _travel(Vector3(3, 0, 0), Vector3(-3, 0, 0), 360)
	check(not closed.first_arrived and not closed.second_arrived and closed.safe and closed.maximum_side < 0.2, "完全无法错身的窄路保持碰撞边界，不穿墙或穿过友军")
	check(closed.late_motion < 0.35, "无出口时有限尝试后稳定停步，不持续左右抖动")

	_clear_walls()
	await _reset(Vector3(-3, 0, 0), Vector3(7, 0, 7))
	var alone := await _travel(Vector3(3, 0, 0), Vector3.INF, 190)
	check(alone.first_arrived and alone.first_side < 0.001 and alone.safe, "没有邻近友军时原直线方向与移动速度保持不变")

	await _reset(Vector3(-3, 0, 0), Vector3(0, 0, 0))
	actors[1].faction_id = &"hostile_test"
	arena.cooperation.set_relation(&"enemy", &"hostile_test", &"hostile")
	var hostile := await _travel(Vector3(3, 0, 0), Vector3.INF, 240)
	check(not hostile.first_arrived and hostile.first_side < 0.001 and hostile.second_side < 0.001 and hostile.safe, "敌对角色不参与友军让路协议，不能借合作移动绕过敌对阻挡")

	await _reset(Vector3(-1.1, 0, 0), Vector3(0, 0, 0))
	check(actors[1].begin_melee(0.5), "互斥对照真实进入近战前摇")
	var immobile: Vector3 = actors[1].global_position
	await _travel(Vector3(3, 0, 0), Vector3.INF, 12)
	check(actors[1].global_position.distance_to(immobile) < 0.001, "身体前摇禁止移动时不因友军请求越权侧移")
	actors[1].cancel_melee()
	print("ALLY NAVIGATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _reset(first: Vector3, second: Vector3) -> void:
	for index in actors.size():
		var actor = actors[index]
		actor.reset_target()
		actor.faction_id = &"enemy"
		actor.global_position = arena.to_global(first if index == 0 else second)
		actor.velocity = Vector3.ZERO
		actor.get_node("NavigationAgent3D").target_position = actor.global_position
	for frame in 4: await physics_frame

func _travel(first: Vector3, second: Vector3, frames: int) -> Dictionary:
	var goals: Array[Vector3] = [arena.to_global(first), arena.to_global(second) if second.is_finite() else Vector3.INF]
	var previous: Array[Vector3] = [actors[0].global_position, actors[1].global_position]
	var start_z := [actors[0].global_position.z, actors[1].global_position.z]
	var result := {"first_arrived": false, "second_arrived": false, "safe": true, "first_side": 0.0, "second_side": 0.0, "maximum_side": 0.0, "late_motion": 0.0}
	for frame in frames:
		await physics_frame
		# 每帧交替提交顺序，测试不能依赖始终先处理某个实例。
		for index in [frame % 2, 1 - frame % 2]:
			var actor = actors[index]
			var direction := Vector3.ZERO
			if goals[index].is_finite():
				direction = goals[index] - actor.global_position
				direction.y = 0.0
				var distance := direction.length()
				direction = direction.normalized() * minf(1.0, distance / maxf(0.001, actor.move_speed * STEP))
			actor.move_character(direction, STEP)
			var moved: Vector3 = actor.global_position - previous[index]
			result.safe = result.safe and Vector2(moved.x, moved.z).length() <= actor.move_speed * STEP + 0.005
			if frame >= frames - 90: result.late_motion += Vector2(moved.x, moved.z).length()
			previous[index] = actor.global_position
			var sideways: float = absf(actor.global_position.z - start_z[index])
			result["first_side" if index == 0 else "second_side"] = maxf(result["first_side" if index == 0 else "second_side"], sideways)
			result.maximum_side = maxf(result.maximum_side, sideways)
		var separation: Vector3 = actors[0].global_position - actors[1].global_position
		result.safe = result.safe and Vector2(separation.x, separation.z).length() >= 0.68
		for index in 2:
			if goals[index].is_finite():
				var remaining: Vector3 = actors[index].global_position - goals[index]
				result["first_arrived" if index == 0 else "second_arrived"] = Vector2(remaining.x, remaining.z).length() < 0.12
	print("ALLY MOVE ", result, " positions=", actors[0].global_position, ", ", actors[1].global_position)
	return result

func _make_corridor(pocket: bool) -> void:
	if not pocket:
		_wall(Vector3(0, 1, -0.55), Vector3(8, 2, 0.2))
		_wall(Vector3(0, 1, 0.55), Vector3(8, 2, 0.2))
		return
	_wall(Vector3(0, 1, -0.7), Vector3(8, 2, 0.2))
	_wall(Vector3(-2.45, 1, 0.7), Vector3(3.1, 2, 0.2))
	_wall(Vector3(2.45, 1, 0.7), Vector3(3.1, 2, 0.2))
	_wall(Vector3(0, 1, 1.7), Vector3(2, 2, 0.2))
	_wall(Vector3(-1, 1, 1.2), Vector3(0.2, 2, 1))
	_wall(Vector3(1, 1, 1.2), Vector3(0.2, 2, 1))

func _wall(point: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	scene.add_child(body)
	body.global_position = arena.to_global(point)
	walls.append(body)

func _clear_walls() -> void:
	for wall in walls: wall.queue_free()
	walls.clear()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
