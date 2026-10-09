extends SceneTree

class Target extends CharacterBody3D:
	var hits := 0
	var damage_received := 0.0
	var hit_effects := Vector4.ZERO
	var is_in_dialogue := false
	func is_dead() -> bool: return false
	func receive_melee_hit(damage: float, _origin: Vector3, distance: float, duration: float, _direction: Vector3,
			slow_multiplier: float = 1.0, slow_seconds: float = 0.0) -> void:
		hits += 1
		damage_received += damage
		hit_effects = Vector4(distance, duration, slow_multiplier, slow_seconds)

var checks := 0
var failures := 0
var scene
var actor
var ai
var controller
var target: Target
const INTENT := {"owner": &"engage"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	actor = scene.get_node("Arena/Enemy")
	ai = actor.get_node("AI")
	controller = ai.context.melee
	ai.set_physics_process(false)
	actor.set_physics_process(false)
	scene.get_node("Player").set_physics_process(false)
	for cover in get_nodes_in_group("cover_region"): cover.collision_layer = 0
	target = Target.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.35
	shape.shape.height = 1.6
	shape.position.y = 0.8
	target.add_child(shape)
	scene.add_child(target)
	target.global_position = Vector3(24, 0, -3.2)
	actor.global_position = Vector3(24, 0, -2)
	actor.rotation = Vector3.ZERO
	ai.context.player = target
	var weapon := WeaponData.new()
	weapon.melee_windup_seconds = 0.1
	weapon.melee_recovery_seconds = 0.2
	weapon.melee_interval = 0.7
	actor.equip_weapon(weapon)
	await frames(4)
	ai.utility_current = {"id": &"engage", "plan": &"melee"}
	check(controller.can_request(true), "可见近距目标可请求基础挥击")
	controller.update(0.0, true, {"owner": &"not_authorized"})
	check(not actor.melee_active and actor.melee_count == 0, "未授权请求不能启动身体执行")
	ai.utility_current = {"id": &"search"}
	controller.update(0.0, true, INTENT)
	check(not actor.melee_active, "已装配但未选中的动作也不能启动挥击")
	ai.utility_current = {"id": &"engage", "plan": &"melee"}
	actor.ammo.magazine_rounds = 1
	actor.request_reload()
	controller.update(0.0, true, INTENT)
	check(actor.melee_active and not actor.ammo.is_reloading and target.hits == 0, "开始前摇中断换弹且不立即命中")
	check(not actor.request_reload() and not actor.try_fire(), "挥击期间身体拒绝换弹和开火")
	controller.update(0.05, true, INTENT)
	check(target.hits == 0, "前摇未完不造成伤害")
	weapon.melee_damage = 99.0
	weapon.melee_knockback_distance = 2.0
	weapon.melee_knockback_seconds = 0.4
	weapon.melee_slow_multiplier = 0.8
	weapon.melee_slow_seconds = 1.2
	controller.update(0.05, true, INTENT)
	check(target.hits == 1 and target.damage_received == 25.0, "实际伤害使用开始时快照且不依赖玩家Combat")
	check(target.hit_effects.is_equal_approx(Vector4(1.0, 0.2, 0.5, 0.5)), "敌人击退与减速使用当前武器出手时快照")
	check(not get_nodes_in_group("enemy_melee_effect").is_empty(), "空模型也显示敌人剑光")
	controller.update(0.3, true, INTENT)
	check(target.hits == 1 and not actor.melee_active, "收招不重复伤害并结束动作")
	check(actor.melee_cooldown == 0.7, "控制器推进不重复扣减身体冷却")
	actor._physics_process(0.4)
	check(is_equal_approx(actor.melee_cooldown, 0.3), "身体物理入口独立推进冷却")
	controller.cancel()
	actor.equip_weapon(weapon)
	check(is_equal_approx(actor.melee_cooldown, 0.3) and not actor.can_melee(), "取消与换枪不刷新冷却")
	actor._physics_process(0.3)
	var presentation = actor.get_node("Presentation")
	var adapter = actor.get_node("EnemyPresentation")
	var fixture = preload("res://tests/presentation_fixture.gd")
	presentation.animation_profile = fixture.profile()
	presentation.animation_profile.melee = &"Shoot"
	presentation.model_scene = fixture.model_scene()
	await frames(3)
	controller.update(0.0, true, INTENT)
	check(presentation.current_state == &"melee" and presentation._clip == &"Shoot", "敌人使用自身控制器驱动可选近战动画")
	controller.update(0.05, true, INTENT)
	adapter._sync()
	check(is_equal_approx(presentation._time, 1.0 / 6.0), "敌人动画进度跟随前摇和收招")
	presentation._process(1.0)
	check(is_equal_approx(presentation._time, 1.0 / 6.0), "表现播放不推进敌人攻击计时")
	controller.cancel()
	presentation.model_scene = null
	actor._physics_process(1.0)
	controller.update(0.0, true, INTENT)
	target.global_position.z = -4.5
	await frames(3)
	controller.update(0.1, true, INTENT)
	check(target.hits == 1, "目标可在前摇期间离开范围躲开")
	controller.cancel()
	actor._physics_process(1.0)
	target.global_position = Vector3(24, 0, -3.2)
	await frames(3)
	var wall := StaticBody3D.new()
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	box.shape.size = Vector3(2, 2, 0.15)
	wall.add_child(box)
	scene.add_child(wall)
	wall.global_position = Vector3(24, 1, -2.6)
	await frames(3)
	check(not controller.can_request(true), "墙体遮挡拒绝近战")
	wall.queue_free()
	await frames(3)
	target.global_position.y = 2.0
	await frames(3)
	check(not controller.can_request(true), "高度不符不能近战")
	target.global_position = Vector3(24, 0, -0.8)
	await frames(3)
	check(not controller.can_request(true), "背后不属于本次挥击正面")
	target.global_position = Vector3(24, 0, -3.2)
	await frames(3)
	controller.update(0.0, true, INTENT)
	paused = true
	controller.update(1.0, true, INTENT)
	check(controller.elapsed == 0.0 and target.hits == 1, "暂停冻结动作且不补算命中")
	paused = false
	target.is_in_dialogue = true
	controller.update(0.2, true, INTENT)
	check(not actor.melee_active and target.hits == 1, "对话取消未出手挥击")
	target.is_in_dialogue = false
	actor._physics_process(1.0)
	controller.update(0.0, true, INTENT)
	ai.context.permitted.erase(&"engage")
	controller.update(0.2, true, INTENT)
	check(not actor.melee_active and target.hits == 1, "撤销权限立即取消且不结算攻击")
	ai.refresh_configuration(true)
	actor.reset_target()
	check(actor.melee_cooldown == 0.0 and controller.phase == controller.Phase.READY, "区域复位清理冷却和控制器阶段")
	actor.global_position = Vector3(24, 0, -2)
	actor.rotation = Vector3.ZERO
	ai.utility_current = {"id": &"engage", "plan": &"melee"}
	await frames(3)
	controller.update(0.0, true, INTENT)
	actor.receive_hit(10000.0)
	check(not actor.melee_active and controller.phase == controller.Phase.READY, "死亡清理进行中的近战")
	scene.queue_free()
	await process_frame
	await process_frame
	print("Enemy melee execution: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
