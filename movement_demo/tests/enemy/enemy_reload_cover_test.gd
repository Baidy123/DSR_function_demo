extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var arena = scene.get_node("Arena")
	var enemy = arena.get_node("Enemy")
	var ai = enemy.get_node("AI")
	var cover = ai.cover
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	Fixture.configure_timing(enemy)
	ai.search.debug_tracking_cheat = false
	cover.selection.debug_cover_selection = false
	cover.covering_retreat_chance = 0.0
	cover.run_speed_multiplier = 2.0
	# 仅测试实例采用较慢步速及长换弹，使原有两秒余量不足以掩盖限速影响。
	enemy.move_speed = 0.75
	enemy.weapon.reload_seconds = 20.0
	player.global_position = arena.to_global(Vector3(0, 0, 2.5))
	for reload_during_transfer in [false, true]:
		enemy.cancel_reload()
		cover.reset()
		enemy.global_position = arena.to_global(Vector3(-5, 0, -3.5))
		enemy.velocity = Vector3.ZERO
		cover.hide_position = arena.to_global(Vector3(-5, 0, 2.5))
		cover.active_cover_body = arena.get_node("NavigationRegion3D/Environment/CoverA")
		cover.threat_origin = player.global_position + Vector3.UP * 0.8
		cover.look_position = player.global_position
		for frame in range(5):
			await physics_frame
		check(cover._selected_cover_blocks(cover.hide_position, cover.threat_origin), "测试终点有实际掩体遮挡")
		cover._start_move(cover.Phase.RUN_TO_COVER, cover.hide_position)
		var detoured := false
		for frame in range(900):
			await physics_frame
			if reload_during_transfer and frame == 30:
				enemy.ammo.magazine_rounds = 0
				check(enemy.request_reload(), "掩体转移途中可以开始换弹")
			enemy.update_weapon(1.0 / 60.0)
			var before_timer: float = cover.timer
			var before_position: Vector3 = enemy.global_position
			var before_retries: int = cover.cover_detour_retries
			var direction: Vector3 = cover.step(1.0 / 60.0, false)
			if cover.cover_detour_retries > before_retries:
				print("DETOUR frame=", frame, " timer=", before_timer, " pos=", before_position, " reload=", reload_during_transfer)
			enemy.move_character(direction, 1.0 / 60.0, cover.movement_multiplier())
			detoured = detoured or cover.cover_detour_retries > 0
			if cover.phase != cover.Phase.RUN_TO_COVER:
				break
		var label := "途中换弹" if reload_during_transfer else "正常快速转移"
		check(cover.phase == cover.Phase.HIDE, label + "沿同一实际路线抵达躲藏位置")
		check(not detoured, label + "持续推进时不会因预计速度过快而误触发绕行")
	# 换弹只补偿移动时限，不延长掩体后的等待或观察时间。
	for waiting_phase in [cover.Phase.HIDE, cover.Phase.WATCH]:
		cover.phase = waiting_phase
		cover.timer = 1.0
		cover.step(0.2, false)
		check(is_equal_approx(cover.timer, 0.8), "换弹不放慢躲藏/观察计时%s" % waiting_phase)
	print("ENEMY RELOAD COVER: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("PASS " if ok else "FAIL ", label)
