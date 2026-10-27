extends "res://tests/headshot_execution_test.gd"

## 原玩家近战请求、真实物理射线及原敌人身体的联合回归。
## 仅在测试实例中固定武器参数，所有保存资源保持不变。
func _additional_checks() -> void:
	target.collision_layer = 0
	target.remove_from_group("combat_target")
	gun.damage = 10
	gun.headshot_damage_multiplier = 3
	gun.headshot_instant_kill_enabled = false
	gun.headshot_stagger_seconds = 0
	gun.melee_damage = 1
	gun.melee_range = 1.6
	gun.melee_stamina_cost = 0
	gun.melee_knockback_distance = 0
	gun.melee_slow_seconds = 2
	gun.melee_slow_multiplier = 0.5
	gun.melee_headshot_accuracy_threshold = 0.7
	combat.equip_weapon(gun)
	var enemy = _enemy(Vector3(0, 0, -1.2), true)
	var other = _enemy(Vector3(3, 0, -1.2), true)
	for frame in 3: await physics_frame
	check(_swing(), "Real player melee begins and reaches its actual hit frame")
	var state: Dictionary = enemy.get_melee_stun_state()
	check(combat.last_melee_target == enemy and enemy.health == 9999 and state.active and state.opening_available, "Actual melee grants one opening to the surviving enemy")
	check(not other.get_melee_stun_state().active and not player.has_method("get_melee_stun_state"), "Other enemy and player receive no opening state")
	check(is_equal_approx(state.remaining_seconds, 2) and is_equal_approx(state.accuracy_threshold, 0.7), "Target stores the attack's duration and absolute threshold")
	state.opening_available = false
	check(enemy.get_melee_stun_state().opening_available, "Read-only snapshot cannot mutate the enemy's state")
	var generation: int = enemy.get_melee_stun_state().generation
	enemy._physics_process(0.5)
	gun.melee_slow_seconds = 7
	gun.melee_headshot_accuracy_threshold = 0.2
	check(_swing(), "A second real melee is possible after the original weapon cooldown")
	state = enemy.get_melee_stun_state()
	check(is_equal_approx(state.remaining_seconds, 1.5) and is_equal_approx(state.accuracy_threshold, 0.7) and state.generation == generation, "Repeated melee does not extend, replace or restart the opening")
	check(enemy.health == 9998 and enemy.get_hit_movement_multiplier() < 1, "Repeated melee retains original damage and ordinary slowdown")
	gun.melee_slow_seconds = 2
	gun.melee_headshot_accuracy_threshold = 0.7
	var before: float = enemy.health
	_shoot(0.5)
	state = enemy.get_melee_stun_state()
	check(enemy.health == before - 10 and state.active and not state.opening_available, "Zero-probability actual gun hit consumes the opening while stun remains")
	check(not enemy.consume_melee_opening(generation), "The same opening cannot be consumed twice")
	_swing()
	check(not enemy.get_melee_stun_state().opening_available, "Further melee cannot regrant a consumed opening before expiry")
	var remaining: float = enemy.get_melee_stun_state().remaining_seconds
	enemy.apply_hit_slowdown(0.2, 10)
	check(enemy.get_melee_stun_state().remaining_seconds == remaining, "Ordinary gunshot slowdown cannot extend the separate stun clock")
	paused = true
	enemy._physics_process(5)
	paused = false
	check(enemy.get_melee_stun_state().remaining_seconds == remaining, "Pause freezes stun and opening lifetime")
	enemy.equip_weapon(enemy.weapon)
	combat.equip_weapon(gun)
	check(enemy.get_melee_stun_state().remaining_seconds == remaining, "Attacker and defender weapon changes preserve the current target state")
	enemy._physics_process(remaining + 0.01)
	check(not enemy.get_melee_stun_state().active and enemy.get_hit_movement_multiplier() < 1, "Stun expiry does not remove a longer ordinary slowdown")
	_swing()
	check(enemy.get_melee_stun_state().opening_available and enemy.get_melee_stun_state().generation != generation, "A later melee after expiry creates a fresh opening")
	check(not enemy.consume_melee_opening(generation) and enemy.get_melee_stun_state().opening_available, "An old generation cannot consume a newer opening")
	gun.headshot_enabled = false
	before = enemy.health
	_shoot(1)
	check(enemy.health == before - 10 and not enemy.get_melee_stun_state().opening_available, "A weapon with headshots disabled still consumes its actual gun-hit opportunity")
	gun.headshot_enabled = true
	_renew(enemy)
	gun.damage = 0
	_shoot(0.5)
	check(not enemy.get_melee_stun_state().opening_available, "An accepted zero-damage gun hit still consumes its one opening opportunity")
	gun.damage = 10
	await _geometry_and_snapshots(enemy, other)
	await _target_probability(enemy, other)
	await _shotgun_openings(enemy, other)
	await _callback_generation(enemy, other)
	await _visual_state(enemy, other)
	await _self_reset_callbacks(enemy)
	await _player_isolation(enemy)
	await _lifecycle_opening(enemy)
	enemy.queue_free()
	other.queue_free()
	await process_frame

func _swing() -> bool:
	combat.cancel_melee()
	combat.begin_frame(2, false)
	var started: bool = combat.request_melee()
	combat.begin_frame(1, false)
	return started

func _renew(enemy) -> void:
	enemy.clear_hit_effects()
	_swing()

func _geometry_and_snapshots(enemy, other) -> void:
	_renew(enemy)
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 0.9, -0.6)
	_box(wall, Vector3(2, 2, 0.1))
	world.add_child(wall)
	for frame in 3: await physics_frame
	var before: float = enemy.health
	_shoot(1)
	check(enemy.health == before and enemy.get_melee_stun_state().opening_available, "A wall-blocked shot does not consume the target's opening")
	enemy.clear_hit_effects()
	_swing()
	check(enemy.health == before and not enemy.get_melee_stun_state().active, "A wall-blocked melee does not create an opening")
	wall.queue_free()
	for frame in 3: await physics_frame
	combat.cancel_melee()
	combat.begin_frame(2, false)
	check(combat.request_melee(), "Snapshot case starts through the original melee request")
	gun.melee_slow_seconds = 6
	gun.melee_headshot_accuracy_threshold = 0.1
	combat.begin_frame(1, false)
	var state: Dictionary = enemy.get_melee_stun_state()
	check(state.active and is_equal_approx(state.remaining_seconds, 2) and is_equal_approx(state.accuracy_threshold, 0.7), "Changing the resource during windup cannot change the frozen attack")
	gun.melee_slow_seconds = 2
	gun.melee_headshot_accuracy_threshold = 0.7
	enemy.clear_hit_effects()
	gun.melee_slow_seconds = 0
	before = enemy.health
	_swing()
	check(enemy.health == before - 1 and not enemy.get_melee_stun_state().active, "Zero duration retains instant melee damage without persistent stun")
	gun.melee_slow_seconds = 2
	gun.melee_headshot_opening_enabled = false
	_swing()
	check(not enemy.get_melee_stun_state().opening_available, "Melee opening switch prevents the threshold benefit")
	gun.melee_headshot_opening_enabled = true
	enemy.clear_hit_effects()
	other.clear_hit_effects()
	other.global_position = Vector3(0, 0, -1.2)
	enemy.global_position = Vector3(0, 0, -4)
	for frame in 3: await physics_frame
	_swing()
	var distant_before: float = enemy.health
	combat.locked_target = enemy
	combat.is_aiming = true
	combat.accuracy = 0.5
	combat.shot_cooldown = 0
	combat.shoot()
	check(not other.get_melee_stun_state().opening_available and enemy.health == distant_before, "Actual intervening enemy consumes its opening; the distant locked target is unchanged")
	other.global_position = Vector3(3, 0, -1.2)
	enemy.global_position = Vector3(0, 0, -1.2)
	for frame in 3: await physics_frame

func _target_probability(enemy, other) -> void:
	_renew(enemy)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 8, 5)
	camera.look_at(enemy.global_position)
	camera.current = true
	var reticle = combat.get_node("HUD/Reticle")
	reticle.set_process(false)
	combat.is_aiming = true
	combat.accuracy = 0.8
	combat.locked_target = enemy
	reticle._process(0)
	check(reticle._headshot_ready and enemy.get_melee_stun_state().opening_available, "Reticle sees the current target's benefit without consuming it")
	combat.locked_target = other
	reticle._process(0)
	check(not reticle._headshot_ready and combat.accuracy == 0.8, "Switching targets removes the benefit without modifying player precision")
	var reference := RandomNumberGenerator.new()
	reference.seed = 9182
	combat._headshot_rng.seed = 9182
	var expected: float = 30 if reference.randf() < 1.0 / 3.0 else 10
	var before: float = enemy.health
	_shoot(0.8)
	check(is_equal_approx(before - enemy.health, expected) and combat._headshot_rng.state == reference.state, "Eighty-percent real shot uses the target's seventy-percent linear threshold")
	combat.locked_target = enemy
	combat.accuracy = 0.8
	reticle._process(0)
	check(not reticle._headshot_ready and enemy.get_melee_stun_state().active, "Consumed opening disappears from prediction while the stun continues")
	gun.headshot_accuracy_threshold = 0.5
	_renew(enemy)
	combat._headshot_rng.seed = 100
	reference.seed = 100
	expected = 30 if reference.randf() < 0.6 else 10
	before = enemy.health
	_shoot(0.8)
	check(is_equal_approx(before - enemy.health, expected), "Opening never raises a gun's already lower normal threshold")
	gun.headshot_accuracy_threshold = 0.9
	reticle.set_process(true)
	camera.queue_free()
	await process_frame

func _shotgun_openings(enemy, other) -> void:
	_renew(enemy)
	other.clear_hit_effects()
	enemy.global_position = Vector3(-0.7, 0, -4)
	other.global_position = Vector3(0.7, 0, -4)
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	gun.shotgun.pattern = ShotgunPattern.new()
	gun.shotgun.pattern.points = PackedVector2Array([Vector2(-1, 0), Vector2(-1, 0), Vector2(1, 0)])
	gun.shotgun.pattern_angle_degrees = 10
	gun.shotgun.stable_jitter_degrees = 0
	gun.shotgun.unstable_jitter_degrees = 0
	gun.shotgun.pellet_damage = 10
	combat.equip_weapon(gun)
	for frame in 3: await physics_frame
	var reference := RandomNumberGenerator.new()
	reference.seed = 917
	combat._headshot_rng.seed = 917
	var expected: float = 60 if reference.randf() < 1.0 / 3.0 else 20
	var before: float = enemy.health
	var other_before: float = other.health
	var hits := [0, 0]
	enemy.hit_received.connect(func(_damage, _source): hits[0] += 1)
	other.hit_received.connect(func(_damage, _source): hits[1] += 1)
	_shoot(0.8)
	check(is_equal_approx(before - enemy.health, expected) and other.health == other_before - 10, "One shell evaluates each actual target's own opening separately")
	check(hits == [1, 1] and combat._headshot_rng.state == reference.state and not enemy.get_melee_stun_state().opening_available, "Two pellets use one target roll, one damage callback and one opening consumption")
	gun.fire_mode = WeaponData.FireMode.SEMI_AUTO
	combat.equip_weapon(gun)
	enemy.global_position = Vector3(0, 0, -1.2)
	other.global_position = Vector3(3, 0, -1.2)
	for frame in 3: await physics_frame

func _player_isolation(enemy) -> void:
	enemy.clear_hit_effects()
	player.get_node("Health").debug_invincible = false
	player.get_node("Health").restore_health(100)
	enemy.equip_weapon(gun)
	var before: float = player.get_node("Health").health
	var settings := {"damage": 1.0, "range": 1.6, "angle": 90.0, "height": 1.0,
		"distance": 0.0, "duration": 0.1, "effects": gun.get_attack_effects(true)}
	var direction: Vector3 = (player.global_position - enemy.global_position).normalized()
	check(enemy.begin_melee(0.5) and enemy.execute_melee(player, settings, direction), "Enemy sharing the same weapon actually hits the player through its melee executor")
	check(player.get_node("Health").health == before - 1 and player.get_hit_movement_multiplier() < 1 and not player.has_method("get_melee_stun_state"), "Enemy melee retains player damage and slowdown without an enemy-only opening")
	check(not enemy.get_melee_stun_state().active, "An attacking enemy does not grant itself a melee opening")
	enemy.cancel_melee()

func _self_reset_callbacks(enemy) -> void:
	# 本目标在真实受击通知中复位；原攻击不再向新生命交付后续状态。
	enemy.clear_hit_effects()
	gun.hit_speed_loss = 0.5
	gun.hit_speed_loss_seconds = 2
	gun.headshot_stagger_seconds = 1
	enemy.hit_received.connect(func(_damage, _source): enemy.reset_target(), CONNECT_ONE_SHOT)
	_shoot(1)
	check(enemy.health == enemy.max_health and is_equal_approx(enemy.get_hit_movement_multiplier(), 1.0), "Self-reset in hit_received prevents old gunshot slowdown on the new life")
	check(not enemy.is_staggered(), "Self-reset in hit_received prevents the old headshot state on the new life")
	enemy.global_position = Vector3(0, 0, -1.2)
	gun.headshot_stagger_seconds = 0
	gun.hit_speed_loss = 0
	gun.melee_knockback_distance = 1
	for frame in 3: await physics_frame
	enemy.weapon_effects_received.connect(func(_effects): enemy.reset_target(), CONNECT_ONE_SHOT)
	_swing()
	check(enemy.health == enemy.max_health and enemy._hit_push_remaining == 0 and enemy._hit_push_velocity == Vector3.ZERO and not enemy.get_melee_stun_state().active, "Self-reset in weapon_effects_received prevents old melee push and stun on the new life")
	gun.melee_knockback_distance = 0
	enemy.global_position = Vector3(0, 0, -1.2)
	for frame in 3: await physics_frame

func _callback_generation(enemy, other) -> void:
	_renew(enemy)
	other.clear_hit_effects()
	# 首颗实际目标的受击回调改变后续目标；命中集合已经由真实霰弹射线冻结。
	enemy.global_position = Vector3(-0.7, 0, -4)
	other.global_position = Vector3(0.7, 0, -4)
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	gun.shotgun.pattern.points = PackedVector2Array([Vector2(-1, 0), Vector2(1, 0)])
	combat.equip_weapon(gun)
	for frame in 3: await physics_frame
	var hits := [0]
	other.hit_received.connect(func(_damage, _source): hits[0] += 1)
	enemy.hit_received.connect(func(_damage, _source):
		other.reset_target()
		other.global_position = Vector3(0.7, 0, -4)
	, CONNECT_ONE_SHOT)
	_shoot(1)
	check(other.health == other.max_health and hits[0] == 0, "A later pellet target reset by an earlier hit callback cannot receive damage from the old shot")
	# 同一物理命中快照不能重放两次结算；用真实身体验证回调边界，不替代上方真实弹道。
	var resolver = preload("res://scripts/weapons/headshot_resolver.gd")
	var pending: Array = resolver.resolve({other: 1}, 10, gun.get_headshot_settings(1), combat._headshot_rng)
	var before: float = other.health
	resolver.apply(pending[0], player.global_position, gun.get_attack_effects())
	resolver.apply(pending[0], player.global_position, gun.get_attack_effects())
	check(other.health == before - 30, "Replaying the same resolved hit cannot deliver damage twice")
	gun.fire_mode = WeaponData.FireMode.SEMI_AUTO
	combat.equip_weapon(gun)
	enemy.global_position = Vector3(0, 0, -1.2)
	other.global_position = Vector3(3, 0, -1.2)
	for frame in 3: await physics_frame

func _lifecycle_opening(enemy) -> void:
	_renew(enemy)
	var generation: int = enemy.get_melee_stun_state().generation
	enemy.reset_target()
	check(not enemy.get_melee_stun_state().active and not enemy.consume_melee_opening(generation), "Reset clears the opening and invalidates its generation")
	enemy.global_position = Vector3(0, 0, -1.2)
	for frame in 3: await physics_frame
	_renew(enemy)
	enemy.clear_hit_effects()
	check(not enemy.get_melee_stun_state().active, "Original hit-effect cleanup also clears melee stun")
	_renew(enemy)
	enemy.receive_hit(enemy.health + 1, Vector3.ZERO)
	check(enemy.is_dead and not enemy.get_melee_stun_state().active, "Death clears both stun and opening before corpse retention")
	enemy.reset_target()
	enemy.global_position = Vector3(0, 0, -1.2)
	for frame in 3: await physics_frame
	_renew(enemy)
	world.remove_child(enemy)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	check(not enemy.get_melee_stun_state().active, "Scene removal and re-entry cannot retain an old opening")

func _visual_state(enemy, other) -> void:
	_renew(enemy)
	var adapter = enemy.get_node("EnemyPresentation")
	adapter._sync()
	var effect = adapter._melee_stun_effect
	check(is_instance_valid(effect) and effect.visible, "Melee stun creates the reusable visible head effect")
	if not is_instance_valid(effect): return
	var position_before: Vector3 = effect.global_position
	var star_before: Vector3 = effect._stars[0].position
	enemy.consume_melee_opening(enemy.get_melee_stun_state().generation)
	adapter._sync()
	check(effect.visible, "Consuming the opening keeps the head effect until stun expiry")
	paused = true
	await create_timer(0.03, true).timeout
	paused = false
	check(effect._stars[0].position == star_before, "Pause freezes the real head-effect animation")
	enemy._physics_process(0.2)
	enemy.global_position.x += 0.5
	adapter._sync()
	check(effect._stars[0].position != star_before and is_equal_approx(effect.global_position.x - position_before.x, 0.5), "Head-effect phase comes from body time and follows actual movement")
	var other_adapter = other.get_node("EnemyPresentation")
	other_adapter._sync()
	check(not is_instance_valid(other_adapter._melee_stun_effect) or not other_adapter._melee_stun_effect.visible, "A shared effect resource does not activate on an unaffected enemy")
	enemy.clear_hit_effects()
	adapter._sync()
	check(not effect.visible, "Original effect cleanup hides the head effect")
	enemy.global_position = Vector3(0, 0, -1.2)
	for frame in 3: await physics_frame
