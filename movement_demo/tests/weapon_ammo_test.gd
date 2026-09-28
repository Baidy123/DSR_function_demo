extends SceneTree

var checks := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	check(ResourceLoader.exists("res://scripts/weapons/weapon_ammo.gd"), "共享弹药状态脚本存在")
	if failed > 0:
		finish()
		return
	var Ammo = load("res://scripts/weapons/weapon_ammo.gd")
	var weapon := WeaponData.new()
	weapon.set("magazine_capacity", 12)
	weapon.set("reload_seconds", 2.0)
	var kind: int = weapon.get("ammo_type")
	var pool := {kind: 36}
	var ammo = Ammo.new(weapon, pool)
	check(ammo.magazine_rounds == 12 and ammo.reserve_count() == 36, "出生满弹匣且备弹独立于弹匣")
	check(not ammo.start_reload(), "满弹匣不开始换弹")
	for index in range(12):
		check(ammo.consume_round(), "弹匣内第%d发成功消耗" % (index + 1))
	check(not ammo.consume_round() and ammo.magazine_rounds == 0, "空弹匣拒绝开火且不变负数")
	check(not ammo.is_reloading, "消耗最后一发不自动换弹")
	check(ammo.start_reload(), "有备弹时可请求换弹")
	check(not ammo.consume_round(), "换弹期间拒绝消耗子弹")
	ammo.advance_reload(0.5)
	check(is_equal_approx(ammo.reload_progress, 0.25) and ammo.magazine_rounds == 0 and pool[kind] == 36, "进度不足时不提前转移备弹")
	check(not ammo.start_reload() and is_equal_approx(ammo.reload_progress, 0.25), "重复请求不重置正在进行的换弹")
	ammo.advance_reload(1.0, 0.5)
	check(is_equal_approx(ammo.reload_progress, 0.5), "途中奔跑仅减慢后续进度")
	ammo.advance_reload(1.0)
	check(not ammo.is_reloading and ammo.magazine_rounds == 12 and pool[kind] == 24, "途中停止奔跑正常完成并只扣所需备弹")
	ammo.consume_round()
	ammo.start_reload()
	ammo.advance_reload(0.5)
	ammo.cancel_reload()
	check(ammo.magazine_rounds == 11 and pool[kind] == 24 and not ammo.is_reloading, "中断保留原弹匣与备弹")
	ammo.start_reload()
	check(ammo.reload_progress == 0.0, "中断后重新换弹从零开始")
	ammo.advance_reload(2.0)
	check(ammo.magazine_rounds == 12 and pool[kind] == 23, "未打空换弹保留余弹只补缺口")
	var second = Ammo.new(weapon, pool)
	second.magazine_rounds = 0
	second.start_reload()
	second.advance_reload(2.0)
	check(second.magazine_rounds == 12 and ammo.magazine_rounds == 12 and pool[kind] == 11, "同资源两枪弹匣独立但共用备弹")
	ammo.magazine_rounds = 0
	ammo.start_reload()
	ammo.advance_reload(2.0)
	check(ammo.magazine_rounds == 11 and pool[kind] == 0, "备弹不足时只装入剩余备弹")
	check(not ammo.start_reload(), "无备弹不启动换弹")
	var infinite = Ammo.new(weapon, {}, true)
	for cycle in range(3):
		infinite.magazine_rounds = 0
		infinite.start_reload()
		infinite.advance_reload(2.0)
	check(infinite.magazine_rounds == 12 and pool[kind] == 0, "无限备弹反复补满但不影响玩家备弹")
	var empty = Ammo.new()
	check(not empty.consume_round() and not empty.start_reload(), "未装备武器安全拒绝操作")
	ammo.magazine_rounds = 0
	pool[kind] = 12
	ammo.start_reload()
	for frame in range(120):
		ammo.advance_reload(1.0 / 60.0)
	check(not ammo.is_reloading and ammo.magazine_rounds == 12, "60Hz恰好两秒完成不多等一帧")
	check(weapon.get("magazine_capacity") == 12 and weapon.get("reload_seconds") == 2.0, "运行状态不改共享武器配置")
	finish()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("PASS " if ok else "FAIL ", label)


func finish() -> void:
	print("WEAPON AMMO: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)
