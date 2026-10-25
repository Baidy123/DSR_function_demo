extends "res://tests/headshot_test.gd"

## 复用真实玩家／射线夹具；本专项使用真正敌人身体与训练，不伪造受击结果。
var outcomes: Array[StringName] = []

func _additional_checks() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.1
	_box(floor_body, Vector3(50, 0.2, 50))
	world.add_child(floor_body)
	target.collision_layer = 0
	target.remove_from_group("combat_target")
	gun.damage = 10
	gun.headshot_damage_multiplier = 3
	gun.headshot_instant_kill_enabled = true
	gun.headshot_stagger_seconds = 0.6
	gun.headshot_stagger_refresh_mode = WeaponData.StaggerRefresh.KEEP_LONGER
	combat.equip_weapon(gun)
	combat.headshot_resolved.connect(func(_point, result): outcomes.append(result))
	var enemy = _enemy(Vector3(0, 0, -4), false)
	var deaths := [0]
	var hit_events := [0]
	enemy.died.connect(func(): deaths[0] += 1)
	enemy.hit_received.connect(func(_damage, _source): hit_events[0] += 1)
	for frame in 3: await physics_frame
	_shoot(1)
	check(enemy.is_dead and enemy.health == 0 and deaths[0] == 1 and hit_events[0] == 1 and not enemy.is_staggered(), "Execution kills a 10000-health enemy through exactly one original hit/death path")
	check(is_instance_valid(enemy.get_node("Body")) and not enemy.is_queued_for_deletion() and enemy.death_tween != null, "Execution retains original corpse and death animation")
	check(outcomes.back() == &"killed", "Actual lethal result produces the kill feedback")
	enemy.queue_free()
	for frame in 3: await physics_frame
	enemy = _enemy(Vector3(0, 0, -4), true)
	for frame in 3: await physics_frame
	_shoot(1)
	check(enemy.health == 9970 and enemy.is_staggered() and is_equal_approx(enemy.get_stagger_remaining_seconds(), 0.6), "Protected enemy receives 3x damage and configured 0.6-second stagger")
	check(outcomes.back() == &"staggered" and enemy.is_headshot_protected(), "Training protection has positive checkbox semantics and actual stagger feedback")
	check(enemy.get_hit_reaction_state().kind == &"headshot" and enemy.weapon_stability == 0 and enemy.get_center_probability() == 0, "Surviving headshot enters its dedicated state and clears aim accuracy")
	check(enemy.can_move() and enemy.can_turn() and enemy.can_melee() and enemy.get_hit_movement_multiplier() == 0 and enemy.get_effective_movement_multiplier(2) == 0, "Headshot reuses the hit-movement multiplier without replacing action eligibility")
	var rounds: int = enemy.ammo.magazine_rounds
	var pose: Transform3D = enemy.global_transform
	enemy.face_direction(Vector3.RIGHT, 1)
	enemy.move_character(Vector3.RIGHT, 0.01, 5)
	enemy.request_crouch(true)
	check(not enemy.begin_vault({"valid": true}), "The zero-speed state cannot start a new autonomous vault")
	check(enemy.ammo.magazine_rounds == rounds and enemy.global_basis != pose.basis and absf(enemy.global_position.x - pose.origin.x) < 0.001 and enemy.body_motion.crouch_requested, "Movement stays zero while turning and posture requests retain their original behavior")
	enemy.request_crouch(false)
	var body: Dictionary = enemy.get_node("AI").context.member_runtime_snapshot()
	check(not body.occupied and body.can_attack and body.movable and body.availability_reason != &"staggered", "Headshot does not inject occupation or assignment restrictions into the coordinator")
	var saved_cooldown := 0.8
	enemy.shot_cooldown = saved_cooldown
	enemy.update_weapon(0.2, player.get_torso_position())
	check(enemy.has_aim and is_equal_approx(enemy.shot_cooldown, 0.6), "Original aim tracking and cooldown continue during the headshot state")
	check(enemy.get_center_probability() == 0, "Headshot state prevents background accuracy recovery")
	enemy.face_direction(player.global_position - enemy.global_position, 1)
	enemy.update_weapon(1, player.get_torso_position())
	check(enemy.can_fire() and enemy.try_fire() and enemy.ammo.magazine_rounds == rounds - 1 and enemy.get_center_probability() == 0, "Actual gunfire remains possible at zero accuracy during the headshot state")
	enemy._physics_process(0.2)
	check(is_equal_approx(enemy.get_stagger_remaining_seconds(), 0.4), "Only body clock advances stagger, not AI or weapon updates")
	enemy.apply_hit_slowdown(0.2, 2)
	check(enemy.get_hit_movement_multiplier() == 0, "A later ordinary hit cannot overwrite the stronger active headshot slowdown")
	enemy.apply_stagger(0.1)
	check(is_equal_approx(enemy.get_stagger_remaining_seconds(), 0.4), "Default refresh does not shorten the remaining stagger")
	enemy.apply_stagger(0.9)
	check(is_equal_approx(enemy.get_stagger_remaining_seconds(), 0.9), "Default refresh replaces with a longer duration without adding durations")
	enemy.apply_stagger(0.2, WeaponData.StaggerRefresh.RESTART)
	check(is_equal_approx(enemy.get_stagger_remaining_seconds(), 0.2), "External restart policy uses the new duration exactly")
	paused = true
	enemy._physics_process(5)
	paused = false
	check(is_equal_approx(enemy.get_stagger_remaining_seconds(), 0.2), "Pause freezes the physical stagger clock")
	enemy.equip_weapon(enemy.weapon)
	check(enemy.is_staggered(), "Weapon switching does not clear stagger")
	check(enemy.weapon_stability == 0 and enemy.get_center_probability() == 0, "Weapon switching cannot restore accuracy during the headshot state")
	enemy._physics_process(0.21)
	check(not enemy.is_staggered() and is_equal_approx(enemy.get_hit_movement_multiplier(), 0.8), "Expiry reveals the still-active ordinary slowdown instead of restoring a stale speed")
	enemy.ammo.magazine_rounds = 1
	check(enemy.request_reload(), "Reload begins normally before interruption")
	enemy.update_weapon(0.25)
	_shoot(1)
	var loaded: int = enemy.ammo.magazine_rounds
	check(enemy.ammo.is_reloading, "Headshot does not cancel an existing reload")
	enemy.update_weapon(10)
	check(not enemy.ammo.is_reloading and enemy.ammo.magazine_rounds > loaded and enemy.get_center_probability() == 0, "Reload proceeds normally while accuracy remains zero")
	enemy.clear_stagger()
	check(enemy.begin_melee(1.2), "Melee windup can begin before interruption")
	_shoot(1)
	check(enemy.melee_active and is_equal_approx(enemy.melee_cooldown, 1.2), "Headshot leaves existing melee execution and its cooldown untouched")
	enemy.cancel_melee()
	enemy.clear_stagger()
	gun.headshot_stagger_seconds = 0
	_shoot(1)
	check(not enemy.is_staggered() and outcomes.back() == &"headshot", "Zero-duration configuration disables new stagger without disabling bonus damage")
	gun.headshot_stagger_seconds = 0.6
	gun.headshot_instant_kill_enabled = false
	enemy.get_node("Training").profile.tactics.headshot_protection = false
	var health_before: float = enemy.health
	_shoot(1)
	check(enemy.health == health_before - 30 and not enemy.is_dead and enemy.is_staggered(), "Weapon execution switch falls back to multiplier and stagger even without protection")
	enemy.reset_target()
	check(not enemy.is_staggered() and enemy.health == 10000, "Original reset clears stagger and restores health")
	enemy.get_node("Training").profile.tactics.headshot_protection = true
	enemy.health = 20
	_shoot(1)
	check(enemy.is_dead and not enemy.is_staggered() and outcomes.back() == &"killed", "Protected enemy can still die from multiplier damage, with death taking priority")
	enemy.queue_free()
	for frame in 3: await physics_frame
	await _snapshot_case()
	await _configurable_effect_case()
	await _vault_case()
	_resource_case()

func _enemy(at: Vector3, protected: bool):
	var enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
	enemy.max_health = 10000
	enemy.weapon = WeaponData.new()
	enemy.weapon.shot_noise = null
	enemy.get_node("AI").process_mode = Node.PROCESS_MODE_DISABLED
	enemy.get_node("Training").profile = EnemyTrainingProfile.new()
	enemy.get_node("Training").profile.tactics.headshot_protection = protected
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = at
	return enemy

func _snapshot_case() -> void:
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	gun.headshot_chance = 1
	gun.headshot_instant_kill_enabled = true
	gun.shotgun.pellet_damage = 10
	gun.shotgun.pattern = ShotgunPattern.new()
	gun.shotgun.pattern.points = PackedVector2Array([Vector2(-1, 0), Vector2(1, 0)])
	gun.shotgun.pattern_angle_degrees = 10
	gun.shotgun.stable_jitter_degrees = 0
	gun.shotgun.unstable_jitter_degrees = 0
	var left = _enemy(Vector3(-0.7, 0, -4), true)
	var right = _enemy(Vector3(0.7, 0, -4), true)
	var mutation := func(_damage, _source):
		gun.headshot_chance = 0
		gun.headshot_damage_multiplier = 8
		gun.headshot_stagger_seconds = 4
		gun.headshot_movement_multiplier = 0.7
		gun.headshot_accuracy_cap = 0.4
		right.get_node("Training").profile.tactics.headshot_protection = false
	left.hit_received.connect(mutation, CONNECT_ONE_SHOT)
	for frame in 3: await physics_frame
	_shoot(1)
	check(left.health == 9970 and right.health == 9970 and is_equal_approx(right.get_stagger_remaining_seconds(), 0.6), "First target callback cannot alter this shot's later damage, protection or stagger snapshot")
	check(right.get_hit_reaction_state().movement_multiplier == 0 and right.get_hit_reaction_state().accuracy_cap == 0, "This shot also freezes movement and accuracy effects before callbacks")
	_shoot(1)
	check(left.health == 9960 and right.health == 9960, "Next shot reads externally modified chance rather than reusing the old snapshot")
	gun.headshot_chance = 1
	gun.headshot_instant_kill_enabled = false
	_shoot(1)
	check(left.health == 9880 and right.health == 9880 and right.get_stagger_remaining_seconds() == 4, "Next shot applies externally modified non-default damage multiplier and duration")
	check(is_equal_approx(right.get_hit_reaction_state().movement_multiplier, 0.7) and is_equal_approx(right.get_hit_reaction_state().accuracy_cap, 0.4), "Next shot reads externally modified movement and accuracy effects")
	left.queue_free()
	right.queue_free()
	for frame in 3: await physics_frame

func _configurable_effect_case() -> void:
	gun.fire_mode = WeaponData.FireMode.SEMI_AUTO
	gun.headshot_stagger_seconds = 1.5
	gun.headshot_movement_multiplier = 0.4
	gun.headshot_accuracy_cap = 0.2
	var enemy = _enemy(Vector3(0, 0, -4), true)
	for frame in 3: await physics_frame
	enemy.weapon_stability = 1
	_shoot(1)
	check(is_equal_approx(enemy.get_hit_movement_multiplier(), 0.4) and is_equal_approx(enemy.get_center_probability(), 0.2), "Actual hit applies this weapon's 40-percent movement and 20-percent accuracy limit")
	enemy.apply_hit_slowdown(0.8, 3)
	check(is_equal_approx(enemy.get_hit_movement_multiplier(), 0.2), "Original melee/gunshot slowdown remains effective when it is stronger")
	enemy.weapon_stability = 0.1
	enemy.update_weapon(0, player.get_torso_position())
	check(is_equal_approx(enemy.get_center_probability(), 0.1), "Configured accuracy cap never raises worse current accuracy")
	for frame in 2: await physics_frame
	enemy.weapon_recovery_timer = 0
	enemy.update_weapon(1, player.get_torso_position())
	check(is_equal_approx(enemy.get_center_probability(), 0.2) and is_equal_approx(enemy.weapon_stability, 0.2), "Original accuracy recovery can reach but not exceed the configured cap")
	enemy.queue_free()
	await process_frame

func _vault_case() -> void:
	var enemy = _enemy(Vector3(3, 0, -4), true)
	var cover = load("res://scenes/world/low_cover.tscn").instantiate()
	world.add_child(cover)
	cover.global_position = Vector3(3, 0.5, -5)
	# 原几何查询生成合法翻越，实际推进到墙上再中断。
	for frame in 3: await physics_frame
	var low_cover = preload("res://scripts/world/low_cover_geometry.gd")
	var plan: Dictionary = low_cover.query_vault_at(enemy, cover, enemy.global_position, Vector3.FORWARD, 0.6, false)
	check(plan.get("valid", false) and enemy.begin_vault(plan), "Real low-cover geometry starts a valid vault before stagger")
	if enemy.is_vaulting():
		enemy.body_motion.advance(0.2)
		enemy.apply_stagger(0.6)
		check(enemy.body_motion.falling and enemy.is_staggered(), "Stagger switches vault to the existing safe landing path")
		for frame in 180:
			enemy._physics_process(1.0 / 60.0)
			await physics_frame
			if not enemy.is_vaulting(): break
		check(not enemy.is_vaulting() and enemy.is_on_floor(), "Interrupted vault lands without leaving the body suspended")
	enemy.queue_free()
	cover.queue_free()
	await process_frame

func _resource_case() -> void:
	var data := WeaponData.new()
	data.headshot_chance = 0.15
	data.headshot_instant_kill_enabled = false
	data.headshot_damage_multiplier = 2.5
	data.headshot_stagger_seconds = 1.4
	data.headshot_movement_multiplier = 0.35
	data.headshot_accuracy_cap = 0.25
	data.headshot_stagger_refresh_mode = WeaponData.StaggerRefresh.RESTART
	var training := EnemyTrainingProfile.new()
	training.tactics.headshot_protection = true
	DirAccess.make_dir_recursive_absolute("res://logs/headshot_execution")
	ResourceSaver.save(data, "res://logs/headshot_execution/weapon.tres")
	ResourceSaver.save(training, "res://logs/headshot_execution/training.tres")
	var restored = ResourceLoader.load("res://logs/headshot_execution/weapon.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var restored_training = ResourceLoader.load("res://logs/headshot_execution/training.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.get_headshot_settings(1) == data.get_headshot_settings(1), "Every external weapon setting survives resource save/reload, including explicit old 2.5x")
	check(restored_training.setting(&"tactics", &"headshot_protection", false) and restored_training.tactics.overridden.has("headshot_protection"), "Training protection saves under the unchanged tactics key with explicit override semantics")
	var duplicate = training.duplicate(true)
	duplicate.tactics.headshot_protection = false
	check(training.tactics.headshot_protection and not duplicate.tactics.headshot_protection, "Independent training copies cannot modify each other's protection")
	data.headshot_movement_multiplier = NAN
	data.headshot_accuracy_cap = -1
	check(data.get_headshot_settings(1).movement_multiplier == 0 and data.get_headshot_settings(1).accuracy_cap == 0, "Non-finite and negative effect parameters are sanitized in the weapon snapshot")
	data.headshot_movement_multiplier = 2
	data.headshot_accuracy_cap = 2
	check(data.get_headshot_settings(1).movement_multiplier == 1 and data.get_headshot_settings(1).accuracy_cap == 1, "External effect parameters cannot exceed one hundred percent")
