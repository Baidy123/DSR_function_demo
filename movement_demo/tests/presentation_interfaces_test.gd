extends SceneTree

const Visual = preload("res://scripts/systems/presentation/visual_presentation.gd")
const State = preload("res://scripts/systems/presentation/presentation_state.gd")
const Fixture = preload("res://tests/presentation_fixture.gd")
const Effects = preload("res://scripts/systems/effects/impact_effects.gd")
const Receiver = preload("res://scripts/systems/effects/impact_receiver.gd")
var failures := 0
var checks := 0
var model: PackedScene


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)
	else: print("PASS ", label)


func settle(count: int = 3) -> void:
	for frame in count: await physics_frame


func run() -> void:
	model = Fixture.model_scene()
	await test_visual()
	await test_effects()
	await test_real_scene()
	print("Presentation checks: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func test_visual() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var placeholder := MeshInstance3D.new()
	placeholder.name = "Body"
	host.add_child(placeholder)
	var view := Visual.new()
	view.placeholder_paths.assign([^"../Body"])
	host.add_child(view)
	check(not view.has_model() and placeholder.visible, "空模型保留占位外观")
	view.animation_profile = Fixture.profile()
	view.model_scene = model
	await settle()
	check(view.has_model() and not placeholder.visible, "有效模型替换占位外观")
	var state := State.new()
	view.apply_state(state)
	check(view.player.current_animation == "Idle", "待机映射")
	state.local_velocity = Vector3(0, 0, -3)
	view.apply_state(state)
	check(view.player.current_animation == "Walk", "移动映射")
	state.sprinting = true
	view.apply_state(state)
	check(view.player.current_animation == "Run", "冲刺映射")
	view.animation_profile.sprint = &"Missing"
	view.apply_state(state)
	check(view.player.current_animation == "Walk", "缺失冲刺回退移动")
	state.reloading = true
	state.reload_progress = 0.5
	view.apply_state(state)
	check(view.player.current_animation == "Reload" and is_equal_approx(view.player.current_animation_position, 0.5), "换弹姿态定位半程")
	view.play_event(&"hit")
	check(view.current_state == &"reload", "受击表现不打断换弹")
	view._process(0.3)
	check(is_equal_approx(view.player.current_animation_position, 0.5), "动画不自行推进换弹进度")
	state.reloading = false
	state.local_velocity = Vector3.ZERO
	view.apply_state(state)
	view.play_event(&"fire")
	view._process(0.25)
	view.play_event(&"fire")
	check(is_zero_approx(view.player.current_animation_position), "连续实际开火可重新触发")
	view._process(1.1)
	check(view.current_state == &"idle", "一次性动作结束回到最新状态")
	state.dead = true
	view.death_during_pause = true
	view.apply_state(state)
	paused = true
	view._process(1.1)
	check(view.current_state == &"dead" and is_equal_approx(view.model.get_node("Torso").rotation.x, PI / 2), "暂停中的死亡动画播完保持末帧")
	paused = false
	view.reset_presentation()
	check(view.model.get_node("Torso").rotation.is_zero_approx(), "无 RESET 片段也恢复初始姿态")
	check(not placeholder.visible, "复位不会重新显示旧身体")
	var second := Visual.new()
	second.model_scene = model
	second.animation_profile = view.animation_profile
	host.add_child(second)
	view.play_event(&"fire")
	view._process(0.4)
	check(second.current_state == &"idle" and second.player.current_animation_position < 0.1, "共享模型与配置的播放状态独立")
	check(second.player.get_animation(&"Idle") != view.player.get_animation(&"Idle"), "动画资源按实例隔离")
	second.animation_profile = Fixture.profile()
	second.animation_profile.dead = &""
	var fallback := State.new()
	fallback.dead = true
	second.apply_state(fallback)
	await settle(25)
	check(is_equal_approx(second._pivot.rotation.x, PI / 2), "有模型但缺死亡片段时使用倒地回退")
	second.reset_presentation()
	check(second._pivot.transform.is_equal_approx(Transform3D.IDENTITY), "复位清除模型倒地回退")
	view.model_scene = null
	await settle()
	check(placeholder.visible and not view.has_model(), "清除模型恢复旧外观")
	# 动画若修改材质属性，也不能污染共用 PackedScene 或另一实例。
	var tinted_root := model.instantiate()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	tinted_root.get_node("Torso").material_override = material
	var animation: Animation = tinted_root.get_node("AnimationPlayer").get_animation(&"Hit").duplicate(true)
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, ^"Torso:material_override:albedo_color")
	animation.track_insert_key(track, 0.0, Color.WHITE)
	animation.track_insert_key(track, 1.0, Color.RED)
	var library := AnimationLibrary.new()
	library.add_animation(&"Tint", animation)
	tinted_root.get_node("AnimationPlayer").add_animation_library(&"test", library)
	var tinted := PackedScene.new()
	tinted.pack(tinted_root)
	tinted_root.free()
	view.model_scene = tinted
	second.model_scene = tinted
	view.animation_profile = Fixture.profile()
	view.animation_profile.hit = &"test/Tint"
	await settle()
	view.play_event(&"hit")
	view._process(0.5)
	var first_material = view.model.get_node("Torso").material_override
	var second_material = second.model.get_node("Torso").material_override
	check(first_material != second_material, "动画写入的材质资源独立复制")
	check(second_material.albedo_color == Color.WHITE and first_material.albedo_color != Color.WHITE, "材质动画不影响另一模型")
	view.reset_presentation()
	check(first_material.albedo_color == Color.WHITE, "复位恢复材质初始值")
	host.queue_free()
	await settle()


func test_effects() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var service := Effects.new()
	service.name = "ImpactEffects"
	host.add_child(service)
	var body := StaticBody3D.new()
	host.add_child(body)
	var receiver := Receiver.new()
	receiver.name = "ImpactReceiver"
	body.add_child(receiver)
	var hit := {"collider": body, "position": Vector3(2, 1, 3), "normal": Vector3.RIGHT}
	check(Effects.find_for(body) == service, "只使用最近祖先的特效服务")
	check(service.capture_hit({}, Vector3.FORWARD, body) == null, "未命中不创建事件")
	service.dispatch_impact(service.capture_hit(hit, Vector3.LEFT, body))
	check(service.active_count() == 0, "空配置不生成粒子")
	service.default_profile = load("res://resources/effects/metal_example.tres")
	receiver.profile = service.default_profile.duplicate(true)
	receiver.profile.surface_offset = 0.08
	var override_event = service.capture_hit(hit, Vector3.LEFT, body)
	check(is_equal_approx(override_event.profile.surface_offset, 0.08) and is_equal_approx(service.default_profile.surface_offset, 0.02), "对象表面配置覆盖默认且不改默认资源")
	receiver.profile = null
	var event = service.capture_hit(hit, Vector3.LEFT, body)
	service.dispatch_impact(event)
	service.dispatch_impact(event)
	check(service.active_count() == 1, "同一个命中事件仅生成一次")
	var other_service := Effects.new()
	host.add_child(other_service)
	other_service.dispatch_impact(event)
	check(other_service.active_count() == 0, "多个服务不重复消费同一事件")
	var effect = service._active[0].node
	check(effect.global_basis.y.is_equal_approx(Vector3.RIGHT), "粒子朝向墙面法线")
	check(effect.global_position.is_equal_approx(hit.position + Vector3.RIGHT * 0.02), "粒子使用命中点及外偏移")
	receiver.enabled = false
	check(service.capture_hit(hit, Vector3.LEFT, body) == null, "显式禁用不使用默认效果")
	receiver.enabled = true
	service.max_active = 2
	for i in 4: service.dispatch_impact(service.capture_hit(hit, Vector3.LEFT, body))
	check(service.active_count() == 2, "特效数量有上限")
	paused = true
	await settle(5)
	check(service.active_count() == 2, "暂停不消耗特效寿命")
	paused = false
	event = service.capture_hit({"collider": body, "position": Vector3.ZERO, "normal": Vector3.ZERO}, Vector3.DOWN, body)
	body.free()
	service.dispatch_impact(event)
	check(service._active[-1].node.global_basis.y.is_equal_approx(Vector3.UP), "目标删除与零法线仍安全播放")
	service._process(5.0)
	check(service.active_count() == 0, "超时清理所有特效")
	await settle()
	var finished_event = service.capture_hit({"position": Vector3.ZERO, "normal": Vector3.UP}, Vector3.DOWN, host)
	service.dispatch_impact(finished_event)
	service._active[0].node.finished.emit()
	check(service.active_count() == 0, "完成信号立即回收")
	host.queue_free()
	await settle()


func test_real_scene() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await settle()
	var actor = scene.get_node("Player")
	var combat = actor.get_node("Combat")
	var enemy = scene.get_node("Arena/Enemy")
	enemy.get_node("AI").set_physics_process(false)
	actor.set_physics_process(false)
	var view = actor.get_node("Visual/Presentation")
	var enemy_view = enemy.get_node("Presentation")
	check(not view.has_model() and actor.get_node("Visual/Body").visible, "主场景默认保留玩家外观")
	check(not enemy_view.has_model() and enemy.get_node("Body").visible, "主场景默认保留敌人外观")
	check(scene.get_node("ImpactEffects").default_profile == null, "主场景默认不启用特效")
	view.animation_profile = Fixture.profile()
	view.model_scene = model
	enemy_view.animation_profile = Fixture.profile()
	enemy_view.model_scene = model
	await settle()
	var adapter = enemy.get_node("EnemyPresentation")
	adapter.set_physics_process(false)
	adapter.motion.reset(enemy)
	enemy.position.x += 0.1
	adapter._physics_process(1.0 / 60.0)
	check(enemy_view.current_state == &"sprint", "敌人实际快移触发冲刺")
	adapter._physics_process(1.0 / 60.0)
	check(enemy_view.current_state == &"idle", "敌人停止后退出冲刺")
	enemy.ammo.magazine_rounds -= 1
	enemy.request_reload()
	enemy.ammo.reload_progress = 0.55
	adapter._physics_process(1.0 / 60.0)
	check(enemy_view.current_state == &"reload" and is_equal_approx(enemy_view.player.current_animation_position, 0.55), "敌人换弹由 Ammo 驱动")
	check(not adapter.state.sprinting, "敌人换弹时退出冲刺表现")
	enemy.receive_hit(100000.0)
	check(enemy_view.current_state == &"dead" and enemy.death_tween == null, "敌人模型死亡不叠加旧 Tween")
	enemy_view._process(1.1)
	enemy.reset_target()
	check(enemy_view.current_state == &"idle" and enemy_view.model.get_node("Torso").rotation.is_zero_approx(), "敌人真实复位恢复动画姿态")
	check(not enemy.get_node("Body").visible and not enemy.get_node("FrontMarker").visible, "敌人复位保持模型可见策略")
	# 换弹半程接口与切枪状态仍由 Combat 决定。
	combat.ammo.magazine_rounds -= 1
	combat.request_reload()
	combat.ammo.reload_progress = 0.6
	actor.get_node("PlayerPresentation")._sync()
	check(view.current_state == &"reload" and is_equal_approx(view.player.current_animation_position, 0.6), "玩家换弹真实进度映射")
	combat.interrupt_reload()
	actor.get_node("PlayerPresentation")._sync()
	check(view.current_state != &"reload" and is_equal_approx(combat.ammo.reload_checkpoint, 0.5), "半程中断退出动画但保留逻辑阶段")
	combat._resume_reload_if_ready()
	actor.get_node("PlayerPresentation")._sync()
	check(is_equal_approx(view.player.current_animation_position, 0.5), "续换从实际保留半程开始")
	combat.cancel_reload()
	await test_dialogue(scene, actor)
	await test_shots(scene, actor, enemy)
	var health = actor.get_node("Health")
	health.debug_invincible = false
	health.receive_hit(100000.0)
	check(paused and view.current_state == &"dead", "真实玩家死亡暂停并通知动画")
	view._process(1.1)
	check(is_equal_approx(view.player.current_animation_position, 1.0), "真实死亡暂停中保持最后姿态")
	paused = false
	scene.queue_free()
	await settle()


func test_dialogue(scene: Node, actor: Node) -> void:
	var ui = scene.get_node("DialogueUI")
	var npc = scene.get_node("NPC")
	var other = scene.get_node("NPCB")
	for source in [npc, other]:
		source.get_node("Presentation").animation_profile = Fixture.profile()
		source.get_node("Presentation").model_scene = model
	await settle()
	await ui.open_dialogue(actor, npc.dialogue_resource, npc.dialogue_start, npc)
	check(npc.get_node("Presentation").current_state == &"dialogue", "真实对话通知发起 NPC")
	check(other.get_node("Presentation").current_state == &"idle", "其他 NPC 不跟随交谈")
	ui._close_dialogue()
	check(npc.get_node("Presentation").current_state == &"idle", "对话关闭恢复待机")
	ui.open_dialogue(actor, npc.dialogue_resource, npc.dialogue_start, npc)
	ui._close_dialogue()
	await settle(5)
	check(not ui.dialogue_panel.visible and ui.dialogue_player == null, "旧异步台词不会重新打开关闭的对话")


func test_shots(scene: Node, actor: Node3D, enemy: Node3D) -> void:
	var service = scene.get_node("ImpactEffects")
	service.default_profile = load("res://resources/effects/metal_example.tres")
	# 远离现有地图，用真实碰撞墙隔开射击者和目标。
	var zone := Area3D.new()
	zone.add_to_group("combat_zone")
	var zone_shape := CollisionShape3D.new()
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(30, 10, 30)
	zone_shape.shape = zone_box
	zone.add_child(zone_shape)
	scene.add_child(zone)
	zone.global_position = Vector3(100, 0, 100)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 5, 1)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = Vector3(100, 0.8, 96)
	actor.global_position = Vector3(100, 0, 100)
	actor.rotation = Vector3.ZERO
	enemy.global_position = Vector3(100, 0, 90)
	await settle()
	var combat = actor.get_node("Combat")
	combat.weapon = combat.weapon.duplicate(true)
	combat.weapon.fire_range = 30.0
	combat.aim_mode = combat.AimMode.PROBABILITY
	combat.accuracy = 1.0
	combat.is_aiming = true
	combat.shot_cooldown = 0.0
	var before: int = service.active_count()
	combat.shoot()
	check(combat.last_shot_collider == wall and service.active_count() == before + 1, "玩家真实子弹撞墙产生一次粒子")
	check(actor.get_node("Visual/Presentation").current_state == &"fire", "玩家真实开火通知动画")
	before = service.active_count()
	combat._ray_to(wall.global_position)
	check(service.active_count() == before, "瞄准射线不产生粒子")
	combat.shoot()
	check(service.active_count() == before, "冷却中未发射不产生粒子")
	enemy.global_position = Vector3(100, 0, 100)
	actor.global_position = Vector3(110, 0, 100)
	enemy.rotation = Vector3.ZERO
	enemy.weapon_stability = 1.0
	enemy.has_aim = true
	enemy.aim_acquired = true
	enemy.aim_direction = Vector3.FORWARD
	enemy.shot_cooldown = 0.0
	await settle()
	before = service.active_count()
	check(enemy.try_fire(), "敌人测试具备真实发射条件")
	check(enemy.last_shot_collider == wall and service.active_count() == before + 1, "敌人真实子弹撞墙也产生一次粒子")
	check(enemy.get_node("Presentation").current_state == &"fire", "敌人真实开火通知动画")
	var arena = scene.get_node("Arena")
	service.dispatch_impact(service.capture_hit({"collider": enemy, "position": enemy.global_position, "normal": Vector3.UP}, Vector3.DOWN, actor))
	var region_count := 0
	for entry in service._active:
		if entry.region == arena.get_instance_id(): region_count += 1
	before = service.active_count()
	arena._reset_targets()
	check(region_count > 0 and service.active_count() == before - region_count, "区域复位只清除所属特效")
	wall.queue_free()
	zone.queue_free()
