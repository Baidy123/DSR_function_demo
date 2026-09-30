extends SceneTree

const Ammo = preload("res://scripts/weapons/weapon_ammo.gd")
const MeleeWeapon = preload("res://resources/weapons/enemy_test_melee.tres")
const MeleeUnit = preload("res://resources/enemy/units/melee.tres")
const RangedUnit = preload("res://resources/enemy/units/ranged.tres")
var checks := 0
var failures := 0
var hits := 0
var saw_disruption := false
var saw_push := false
var hit_times: Array[float] = []
var elapsed := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gun: WeaponData = load("res://resources/weapons/enemy_test_pistol.tres")
	var weapon: WeaponData = MeleeWeapon.duplicate(true)
	check(WeaponData.new().fire_mode == WeaponData.FireMode.SEMI_AUTO and gun.fire_mode == WeaponData.FireMode.AUTOMATIC, "默认单发与旧自动武器编号保持")
	check(weapon.fire_mode == WeaponData.FireMode.MELEE and weapon.melee_enabled, "现成近战武器通过Fire Mode配置")
	var pool := {weapon.ammo_type: 36}
	var ammo = Ammo.new(weapon, pool, true)
	check(ammo.magazine_rounds == 0 and ammo.reserve_count() == 0, "近战武器没有有效弹匣和备弹")
	check(not ammo.can_fire() and not ammo.consume_round() and not ammo.start_reload(), "即使无限备弹，近战也不能开枪或换弹")
	ammo.advance_reload(10.0)
	check(pool[weapon.ammo_type] == 36 and not ammo.is_reloading, "近战不改变共享备弹或推进换弹")
	DirAccess.make_dir_recursive_absolute("res://logs/melee_weapon_work")
	var saved := ResourceSaver.save(weapon, "res://logs/melee_weapon_work/roundtrip.tres")
	var restored: WeaponData = load("res://logs/melee_weapon_work/roundtrip.tres")
	check(saved == OK and restored.fire_mode == WeaponData.FireMode.MELEE and restored.melee_damage == weapon.melee_damage, "Fire Mode及近战数值保存重载正确")

	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.health.debug_invincible = false
	player.combat.aim_mode = 0
	player.combat.accuracy = 1.0
	actor.get_node("UnitType").profile = MeleeUnit.duplicate(true)
	actor.equip_weapon(weapon)
	ai.refresh_configuration(true)
	actor.global_position = Vector3(24, 0, -2)
	actor.rotation = Vector3.ZERO
	player.global_position = Vector3(24, 0, -5)
	var player_start: Vector3 = player.global_position
	var health_before: float = player.health.health
	actor.melee_struck.connect(func(target, _settings, _direction):
		if target == player:
			hits += 1
			hit_times.append(elapsed)
			saw_disruption = saw_disruption or is_zero_approx(player.combat.accuracy)
			saw_push = saw_push or player._melee_push_remaining > 0.0)
	for frame in 4: await physics_frame
	check(ai.actions.size() == 3 and ai.actions.has(&"melee_engage") and not ai.actions.has(&"melee_strike"), "沿用近战兵原三个默认行为")
	# 保留实际地图、训练和评分；只配置既有兵种与武器，不调用挥击或强选动作。
	for frame in 360:
		await physics_frame
		elapsed += 1.0 / 60.0
		ai._physics_process(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
		if hits >= 2: break
	check(actor.melee_count >= 2 and hits >= 2, "现有近战兵由原Utility接近并连续自主命中玩家")
	check(is_equal_approx(player.health.health, health_before - hits * weapon.melee_damage) and hits > 0, "近战按装备武器的伤害实际扣除玩家生命")
	check(saw_disruption and saw_push and player.global_position.distance_to(player_start) > 0.1, "命中清零玩家准度并产生实际物理击退")
	check(hit_times.size() >= 2 and hit_times[1] - hit_times[0] >= weapon.melee_interval - 0.02, "连续攻击遵守基础近战冷却")
	check(actor.shot_count == 0 and actor.ammo.magazine_rounds == 0 and not actor.ammo.is_reloading, "整个交战没有枪械射击或换弹")

	# 验证攻击距离确实来自武器，不会停在原训练的1.3米之外。
	ai.reset_actions()
	actor.equip_weapon(weapon.duplicate(true))
	actor.weapon.melee_range = 1.0
	player.health.health = health_before
	player._clear_melee_push()
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(24, 0, -4.5)
	var hits_before := hits
	for frame in 240:
		await physics_frame
		elapsed += 1.0 / 60.0
		ai._physics_process(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
		if hits > hits_before: break
	check(hits > hits_before, "一米近战武器也能在原接近行为下成功命中")
	ai.reset_actions()
	actor.weapon.melee_enabled = false
	var attacks_before: int = actor.melee_count
	for frame in 60:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
	check(actor.melee_count == attacks_before and hits == hits_before + 1, "关闭武器近战后不继续攻击")

	actor.get_node("UnitType").profile = RangedUnit.duplicate(true)
	actor.equip_weapon(MeleeWeapon)
	actor.ammo.magazine_rounds = 1
	check(actor.weapon == null and not actor.can_melee() and not actor.can_use_firearms() and not actor.try_fire() and not actor.request_reload(), "远程兵无权装备纯近战，不能挥击、开枪或换弹")
	actor.equip_weapon(gun)
	actor.ammo.magazine_rounds = 0
	check(actor.can_use_firearms() and actor.request_reload(), "换回远程武器恢复原枪械资格和换弹")
	actor.equip_weapon(MeleeWeapon)
	check(actor.weapon == gun and actor.ammo.is_reloading, "运行时拒绝近战装备请求，保留原有效枪械及进度")
	actor.get_node("UnitType").profile = MeleeUnit.duplicate(true)
	actor.equip_weapon(MeleeWeapon)
	actor._physics_process(1.0)
	check(actor.begin_melee(0.6), "具备资格的近战兵可开始基础挥击")
	actor.get_node("UnitType").profile = RangedUnit.duplicate(true)
	var health_at_change: float = player.health.health
	check(not actor.execute_melee(player, ai.context.melee.weapon_settings(), Vector3.FORWARD) and player.health.health == health_at_change, "失去兵种资格后未完成挥击不能结算伤害")
	actor._physics_process(0.01)
	check(actor.weapon == null and not actor.melee_active, "更换兵种后取消无资格装备与未完成攻击")
	var held: WeaponData = player.combat.weapon
	player.combat.equip_weapon(MeleeWeapon)
	check(player.combat.weapon == held, "玩家直接装备入口拒绝纯近战并保留原枪械")
	var slots = player.get_node("WeaponSlots")
	var invalid_slot: int = 1 - slots.active_slot
	if invalid_slot == 0: slots.primary_weapon = MeleeWeapon
	else: slots.secondary_weapon = MeleeWeapon
	check(not slots.select_slot(invalid_slot) and player.combat.weapon == held, "玩家不能切到误配纯近战的槽位")
	scene.queue_free()
	await process_frame
	await process_frame
	for has_fallback in [true, false]:
		var configured = load("res://scenes/main.tscn").instantiate()
		var configured_slots = configured.get_node("Player/WeaponSlots")
		configured_slots.primary_weapon = MeleeWeapon
		configured_slots.secondary_weapon = gun if has_fallback else MeleeWeapon
		configured_slots.starting_slot = 0
		configured.get_node("Arena/Enemy").weapon = MeleeWeapon
		root.add_child(configured)
		current_scene = configured
		check(configured.get_node("Player/Combat").weapon == (gun if has_fallback else null), "玩家出生误配时选择有效备用槽或保持无武器")
		check(configured.get_node("Arena/Enemy").weapon == null, "远程兵出生误配纯近战时按未装备处理")
		configured.queue_free()
		await process_frame
		await process_frame
	print("Enemy melee weapon: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
