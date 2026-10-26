extends SceneTree

const View = preload("res://scripts/systems/combat_view.gd")
const Perception = preload("res://scripts/enemy/services/enemy_perception.gd")
var checks := 0
var failures := 0

class Context extends RefCounted:
	var actor
	var player
	var values := {}
	func setting(_section, key, fallback): return values.get(key, fallback)
	func can_use_action(_owner): return true

class PerceptionHost extends Node:
	var context

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _frames(count: int = 3) -> void:
	for frame in count: await physics_frame
	await process_frame

func _run() -> void:
	root.get_node("DebugSettings").enabled = false
	var scene := Node3D.new()
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	var pistol := WeaponData.new()
	pistol.aim_range = 18.0
	player.get_node("Equipment").primary_weapon = pistol
	scene.add_child(player)
	var camera = load("res://scenes/player/player_camera_rig.tscn").instantiate()
	camera.view_transition_seconds = 0.0
	scene.add_child(camera)
	var enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
	# 测试身体、火控资格和感知距离，避免导航／选战术改变固定边界位置。
	enemy.get_node("AI").free()
	var context := Context.new()
	context.actor = enemy
	context.player = player
	var host := PerceptionHost.new()
	host.context = context
	enemy.add_child(host)
	var perception := Perception.new()
	host.add_child(perception)
	enemy.position = Vector3(0, 0, -5)
	enemy.rotation.y = PI
	enemy.weapon = WeaponData.new()
	enemy.weapon.aim_range = 12.0
	scene.add_child(enemy)
	var floor_visual := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(50, 50)
	floor_visual.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.12, 0.15, 0.19)
	floor_visual.material_override = floor_material
	scene.add_child(floor_visual)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, 15, 0)
	scene.add_child(light)
	root.add_child(scene)
	current_scene = scene
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	await _frames()
	root.get_node("DebugSettings").enabled = false
	check(camera.size > 13.0 and _corners_fit(camera, player, 18.0), "18米锁定距离扩大画面，实际投影四角在距离内")
	var short_size: float = camera.size
	var longer := pistol.duplicate() as WeaponData
	longer.aim_range = 22.0
	camera.view_transition_seconds = 0.15
	player.get_node("Combat").equip_weapon(longer)
	check(is_equal_approx(camera.size, short_size), "长距离武器从当前大小开始平滑扩展")
	await _frames(15)
	check(camera.size > short_size and _corners_fit(camera, player, 22.0), "22米武器按实际范围扩展，角落保持可达")
	var long_size: float = camera.size
	player.get_node("Combat").equip_weapon(pistol)
	check(is_equal_approx(camera.size, long_size), "切短距离武器也从当前大小开始，不瞬间切镜头")
	await _frames(4)
	check(camera.size < long_size and camera.size > short_size, "短距离镜头收窄存在真实过渡帧")
	await _frames(12)
	check(is_equal_approx(camera.size, short_size) and _corners_fit(camera, player, 18.0), "平滑收窄完成后恢复18米范围")
	camera.view_transition_seconds = 0.0
	var window_size := root.size
	for dimensions in [Vector2i(900, 900), Vector2i(1600, 700)]:
		root.size = dimensions
		await _frames()
		check(_corners_fit(camera, player, 18.0), "窗口比例 %s 改变后仍按真实四角限制" % dimensions)
	root.size = window_size
	await _frames()
	var combat = player.get_node("Combat")
	check(combat._visible_target_point(enemy).is_finite(), "画面内目标通过真实锁定距离及身体射线检查")
	check(is_equal_approx(perception.sight_distance, 14.0), "远程感知距离取自身武器12米加2米余量")
	context.values[&"use_weapon_sight_range"] = false
	context.values[&"sight_distance"] = 7.0
	check(is_equal_approx(perception.sight_distance, 7.0), "关闭武器感知联动时尊重训练视距")
	context.values[&"use_weapon_sight_range"] = true
	var melee := enemy.weapon.duplicate() as WeaponData
	melee.fire_mode = WeaponData.FireMode.MELEE
	var gun = enemy.weapon
	enemy.weapon = melee
	check(is_equal_approx(perception.sight_distance, 7.0), "近战视距保留训练值，不被短近战范围限制")
	enemy.weapon = gun
	enemy.update_weapon(2.0, player.get_torso_position())
	check(View.contains_actor(enemy, 8.0) and enemy.try_fire(), "屏幕内敌人可通过原身体入口真实开火")
	var ammo_before: int = enemy.ammo.magazine_rounds
	var shots_before: int = enemy.shot_count
	enemy.position = Vector3(40, 0, 0)
	enemy.offscreen_fire_chance = 0.0
	await _frames()
	enemy.look_at(player.global_position)
	enemy.update_weapon(2.0, player.get_torso_position())
	check(not View.contains_actor(enemy) and not enemy.try_fire() and enemy.ammo.magazine_rounds == ammo_before and enemy.shot_count == shots_before and enemy.shot_cooldown > 0.0, "屏幕外0%跳过射击、不消耗弹药但消耗冷却")
	check(not combat._visible_target_point(enemy).is_finite(), "屏幕外目标不被锁定")
	# 普通／记忆火控的屏外概率及节奏由enemy_offscreen_fire_test使用真实Context覆盖。
	enemy.position = Vector3(0, 0, -5)
	enemy.rotation.y = PI
	await _frames()
	enemy.update_weapon(2.0, player.get_torso_position())
	check(enemy.try_fire() and enemy.shot_count == shots_before + 1, "重新进入画面后不受屏外0%限制，恢复真实开火资格")
	var bar = enemy.get_node("HealthBar")
	enemy.receive_hit(enemy.max_health * 0.6)
	check(is_equal_approx(bar.ratio, 0.4) and bar.visible and bar.find_children("*", "Label3D").is_empty(), "血条显示剩余比例，不包含生命数字标签")
	if OS.get_cmdline_user_args().has("--capture"):
		await _frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/combat_view_20261025/health_bar.png")
	enemy.receive_hit(10000.0)
	check(not bar.visible, "死亡立即隐藏血条")
	enemy.reset_target()
	check(bar.visible and is_equal_approx(bar.ratio, 1.0), "复位恢复满血条")
	scene.queue_free()
	await process_frame
	context.actor = null
	context.player = null
	print("COMBAT VIEW: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _corners_fit(camera: Camera3D, player: Node3D, distance: float) -> bool:
	var size := camera.get_viewport().get_visible_rect().size
	for corner in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var origin := camera.project_ray_origin(corner)
		var direction := camera.project_ray_normal(corner)
		for elevation in [0.0, 1.75]:
			var t: float = (player.global_position.y + elevation - origin.y) / direction.y
			var point: Vector3 = origin + direction * t - player.global_position
			if Vector2(point.x, point.z).length() > distance: return false
	return true
