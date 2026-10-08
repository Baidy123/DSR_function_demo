extends SceneTree

const Ranged = preload("res://resources/enemy/units/ranged.tres")
const Melee = preload("res://resources/enemy/units/melee.tres")
const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for invalid_melee in [false, true]:
		await _check_loadout(invalid_melee)
	print("RANGED EQUIPMENT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _check_loadout(invalid_melee: bool) -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	var melee := WeaponData.new()
	melee.fire_mode = WeaponData.FireMode.MELEE
	enemy.get_node("UnitType").profile = Ranged.duplicate(true)
	enemy.get_node("Training").profile = EnemyTrainingProfile.new()
	enemy.weapon = melee if invalid_melee else null
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	root.add_child(scene)
	current_scene = scene
	player.health.debug_invincible = true
	enemy.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(24, 0, 2.8)
	enemy.look_at(player.global_position)
	for frame in 5: await physics_frame
	for frame in 60:
		if ai.context.environment_ready(): break
		await physics_frame
	check(ai.context.environment_ready() and ai.perception.can_see_player(), "无武器回归具备真实可见目标与有效导航")
	check(enemy.weapon == null, "空装备或远程误配近战均按无有效武器处理：" + str(invalid_melee))
	ai.context.update_evidence(1.0 / 60.0, true)
	var engage = ai.actions[&"engage"]
	var stale: Dictionary = engage.option({}, 0.0, 0.0)
	var candidates = engage.collect_candidates(true)
	check(candidates is Array and candidates.is_empty(), "无有效武器时不生成射击候选或读取空武器射程")
	check(not engage.validate(stale, true), "无武器时拒绝旧的原地射击候选")
	ai.training.profile.selected_tactics.assign([&"cover", &"covering_retreat", &"attack_position", &"exit_suppression"])
	ai.refresh_configuration(true)
	for frame in 30:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	check(enemy.shot_count == 0 and not enemy.ammo.is_reloading and ai.current_action != engage, "装配远程战术的完整AI循环允许空装备，不选择枪械接敌")
	Fixture.configure_timing(enemy)
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	enemy.global_position = Vector3(24, 0, -2)
	enemy.look_at(player.global_position)
	var gun: WeaponData = enemy.weapon
	for frame in 240:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		if enemy.shot_count > 0: break
	check(ai.current_action == engage and enemy.shot_count > 0, "装备合法枪械后由原Utility自主接敌并实际开火")
	var shots: int = enemy.shot_count
	enemy.equip_weapon(null)
	check(not engage.valid(true) and not engage.validate(stale, true), "正在射击时卸下武器立即使旧执行与候选失效")
	await physics_frame
	ai._physics_process(1.0 / 60.0)
	check(ai.current_action != engage and enemy.shot_count == shots and ai.context.fire.request.is_empty(), "无需等待保持期即取消旧射击请求，不多开一枪")
	enemy.equip_weapon(gun)
	for frame in 240:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		if enemy.shot_count > shots: break
	check(enemy.shot_count > shots, "重新装备后恢复真实射击，不留下永久禁用状态")
	enemy.get_node("UnitType").profile = Melee.duplicate(true)
	ai.refresh_configuration(true)
	enemy.equip_weapon(melee)
	enemy.get_node("UnitType").profile = Ranged.duplicate(true)
	ai.refresh_configuration(true)
	for frame in 5:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	check(enemy.weapon == null and ai.current_action != ai.actions[&"engage"], "近战切回远程并卸下不兼容武器后仍可运行完整决策")
	enemy.equip_weapon(gun)
	enemy.shooting_enabled = false
	gun.melee_enabled = true
	player.global_position = enemy.global_position + Vector3.FORWARD
	enemy.look_at(player.global_position)
	for frame in 3: await physics_frame
	ai.context.update_evidence(1.0 / 60.0, ai.perception.can_see_player())
	var melee_candidates: Array = ai.actions[&"engage"].collect_candidates(true)
	check(not melee_candidates.is_empty() and melee_candidates.all(func(candidate): return candidate.get("plan") == &"melee"), "关闭枪械执行时仍保留有效的近战推开方案")
	scene.queue_free()
	await process_frame
	await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
