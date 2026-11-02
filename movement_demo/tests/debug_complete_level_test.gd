extends SceneTree

## Debug 一键通关：受总开关控制，只完成当前关，触发一次原完成信号并开放返程门。
## 运行：godot --headless --path movement_demo --script res://tests/debug_complete_level_test.gd

const LEVEL_ONE := preload("res://scenes/world/levels/lvl_1.tscn")

const WATCHDOG_SECONDS := 20.0
const EXPECTED_CHECKS := 9

var failures := 0
var checks_run := 0
var _finished := false


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label_text: String) -> void:
	checks_run += 1
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func _run() -> void:
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)
	var scene: Node = LEVEL_ONE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var guide = scene.get_node("LevelFlow/PlayGuide")
	guide.get_node("Backdrop/Panel/Content/Close").pressed.emit()
	await process_frame

	var waves: Node = scene.get_node("EnemyWaves")
	var return_portal: Interactable = scene.get_node("TavernReturnPortal")
	var health = scene.get_node("Player/Health")
	var button := health.get_node_or_null("Debug/Controls/CompleteLevel") as Button
	check(button != null, "Debug 控制栏提供一键通关按钮")
	if button == null:
		_finish(scene)
		return
	check(button.visible and button.disabled, "Debug 总开关关闭时一键通关不可用")
	var completed := [0]
	waves.encounter_completed.connect(func() -> void: completed[0] += 1)

	health.debug_invincible = true
	await process_frame
	check(not button.disabled, "Debug 总开关开启后一键通关可用")
	button.pressed.emit()
	await process_frame
	await process_frame
	check(completed[0] == 1, "一键通关发出一次原关卡完成信号")
	check(return_portal.visible and return_portal.enabled and return_portal.monitoring,
		"一键通关后开放当前关返程门")
	check(waves.debug_snapshot().state == "COMPLETED", "一键通关将当前波次控制器置为完成")

	button.pressed.emit()
	await process_frame
	check(completed[0] == 1, "重复点击不重复发出完成信号")
	check(not scene.get_node("LevelFlow/Result").visible, "一键通关仍走返程门而不是旧按钮面板")
	check(current_scene == scene, "一键通关不直接切换或跳过酒馆")

	if checks_run != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d（脚本报错会中断后续检查）" % [EXPECTED_CHECKS, checks_run])
	_finish(scene)


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	push_error("debug complete level test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node) -> void:
	if _finished:
		return
	_finished = true
	paused = false
	if is_instance_valid(scene):
		scene.queue_free()
	if failures == 0:
		print("debug complete level checks: all passed")
	else:
		print("debug complete level checks: %d failed" % failures)
	quit(1 if failures > 0 else 0)
