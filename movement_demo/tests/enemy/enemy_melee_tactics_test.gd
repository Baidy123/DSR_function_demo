extends SceneTree

const MeleeUnit = preload("res://resources/enemy/units/melee.tres")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	enemy.get_node("UnitType").profile = MeleeUnit.duplicate(true)
	enemy.get_node("Training").profile.selected_tactics.assign([&"melee_cover", &"melee_rush"])
	enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	check(ai.actions.has(&"melee_cover") and ai.actions.has(&"melee_rush"), "近战兵通过训练装配掩体接近和短程突进")
	if failures > 0:
		quit(1)
		return
	enemy.global_position = Vector3(24, 0, 1)
	enemy.rotation = Vector3.ZERO
	player.global_position = Vector3(24, 0, -4.5)
	for frame in 5: await physics_frame
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	var rush = ai.actions[&"melee_rush"]
	check(rush.collect_candidates(true).is_empty(), "较远且未观察到换弹时不提前突进")
	var gun := WeaponData.new()
	gun.reload_seconds = 4.0
	player.combat.equip_weapon(gun)
	player.combat.ammo.infinite_reserve = true
	player.combat.ammo.magazine_rounds = 0
	check(player.combat.request_reload(), "真实换弹提供突进机会")
	var origin: Vector3 = enemy.global_position
	var saw_rush := false
	var saw_fast_motion := false
	var saw_hit := false
	for frame in 120:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		saw_rush = saw_rush or ai.utility_current.get("id") == &"melee_rush"
		saw_fast_motion = saw_fast_motion or Vector2(enemy.velocity.x, enemy.velocity.z).length() > enemy.move_speed * 1.5
		saw_hit = saw_hit or enemy.melee_count > 0
		if saw_hit: break
	check(saw_rush and saw_fast_motion, "原Utility自主选择换弹突进并产生真实加速移动")
	check(enemy.global_position.distance_to(origin) > 2.0 and saw_hit, "突进实际拉近距离并接续原近战挥击")
	check(rush.cooldown_remaining() > 0.0, "完成突进后仍处于冷却")
	var cooldown: float = rush.cooldown_remaining()
	ai._cancel_utility_execution(&"switch")
	check(is_equal_approx(cooldown, rush.cooldown_remaining()), "普通动作切换不会刷新突进冷却")
	var saved_position: Vector3 = enemy.global_position
	var saved_target: Vector3 = ai.agent.target_position
	for repeat in 5: ai.action_selector.assess_options(ai, ai.perception.can_see_player())
	check(enemy.global_position == saved_position and ai.agent.target_position == saved_target and is_equal_approx(cooldown, rush.cooldown_remaining()), "候选评估不移动角色、不改导航、不推进冷却")
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	check(ai.actions.size() == 3 and not ai.actions.has(&"melee_rush"), "撤销训练后仍只有原三个默认行为")
	check(ai.context.spatial.jobs.all(func(job): return job.owners.all(func(owner): return owner.get_ref() != rush)), "撤销战术时显式清除空间任务")
	print("Melee tactics: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
