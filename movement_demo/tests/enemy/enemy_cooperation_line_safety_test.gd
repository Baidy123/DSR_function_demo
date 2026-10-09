extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failures := 0
var scene
var arena
var first
var second
var observer
var partner
var board

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	arena = scene.get_node("Arena")
	root.add_child(scene)
	current_scene = scene
	first = arena.get_node("Enemy")
	second = load("res://scenes/enemy/enemy.tscn").instantiate()
	arena.add_child(second)
	for actor in [first, second]:
		Fixture.configure_timing(actor)
		Fixture.set_training_action(actor.get_node("AI"), &"cooperate", true)
		actor.get_node("AI").set_physics_process(false)
		actor.faction_id = &"enemy"
		actor.communication_group = &"line_test_radio"
		arena.cooperation.register(actor.get_node("AI").context)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.global_position = Vector3.ZERO
	observer = first.get_node("AI").context
	partner = second.get_node("AI").context
	board = arena.cooperation
	for frame in 5: await physics_frame
	first.global_position = Vector3(18, 0, 0)
	second.global_position = Vector3(20, 0, 0)
	_publish(observer)
	_publish(partner)
	var origin := Vector3(17, 0.9, 0)
	var endpoint := Vector3(23, 0.9, 0)
	check(_matches(origin, endpoint) and not observer.cooperation_line_safe(origin, endpoint), "专用查询和旧snapshot几何在真实新鲜友军阻挡时等价")
	var cases: Array[Dictionary] = [
		{"body": Vector3(20, 0, 0.399), "from": origin, "to": endpoint},
		{"body": Vector3(20, 0, 0.4), "from": origin, "to": endpoint},
		{"body": Vector3(20, 0, 0.401), "from": origin, "to": endpoint},
		{"body": Vector3(23.3, 0, 0), "from": origin, "to": endpoint},
		{"body": Vector3(23.41, 0, 0), "from": origin, "to": endpoint},
		{"body": Vector3(16.7, 0, 0), "from": origin, "to": endpoint},
		{"body": Vector3(16.59, 0, 0), "from": origin, "to": endpoint},
		{"body": Vector3(20, 0.9, 0), "from": origin, "to": endpoint},
		{"body": Vector3(20, 0.901, 0), "from": origin, "to": endpoint},
		{"body": Vector3(20, 0, 0), "from": Vector3(20, 0.9, 0), "to": Vector3(20, 0.9, 0)},
		{"body": Vector3(20, 0, 0), "from": Vector3(24, 0.9, 0), "to": Vector3(24, 0.9, 0)},
		{"body": Vector3(20, 0.5, 0), "from": Vector3(17, 0.9, 0), "to": Vector3(23, 2.0, 0)},
	]
	var boundaries_match := true
	for item in cases:
		second.global_position = item.body
		_publish(partner)
		boundaries_match = boundaries_match and _matches(item.from, item.to)
	check(boundaries_match, "横向/高度严格边界、两端外侧、零长和斜线段均与旧算法逐例等价")
	second.global_position = Vector3(20, 0, 0)
	_publish(partner)
	board.advance(0.349)
	check(_matches(origin, endpoint) and not board.line_safe(observer, origin, endpoint), "0.35秒内保留原快照新鲜度资格")
	board.advance(0.002)
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "超时状态立即失效，不复用此前阻挡结果")
	_publish(partner)
	second.global_position = Vector3(20, 0, 2)
	check(_matches(origin, endpoint) and not board.line_safe(observer, origin, endpoint), "未发布的新位置不会改变原status.position语义")
	_publish(partner)
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "同帧发布移出弹道的位置立即生效")
	second.global_position = Vector3(20, 0, 0)
	_publish(partner)
	check(_matches(origin, endpoint) and not board.line_safe(observer, origin, endpoint), "同帧再次进入弹道也立即阻止射击")
	observer.begin_cooperation_preview()
	var preview: Dictionary = observer.cooperation_snapshot()
	var original_preview: Dictionary = preview.duplicate(true)
	var preview_matches := true
	for repeat in 10:
		preview_matches = preview_matches and not observer.cooperation_line_safe(origin, endpoint) and board.line_safe_from_members(observer, origin, endpoint, preview.members) == _legacy_safe(origin, endpoint)
	check(preview_matches and preview == original_preview, "同一只读候选批次复用已验证成员，几何结果等价且不修改快照")
	observer.end_cooperation_preview()
	second.global_position = Vector3(20, 0, 2)
	_publish(partner)
	check(observer.cooperation_line_safe(origin, endpoint) and _matches(origin, endpoint), "候选批次结束后同帧发布新位置，执行查询立即读取实时结果")
	second.global_position = Vector3(20, 0, 0)
	_publish(partner)

	second.communication_group = &"separate_radio"
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "通信身份改变但尚未重新注册时旧身份不能授权查询")
	board.register(partner)
	_publish(partner)
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "异通信组保持旧snapshot过滤规则")
	first.communication_group = &"separate_radio"
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "查询者身份改变同样立即使旧注册失效")
	board.register(observer)
	_publish(observer)
	check(_matches(origin, endpoint) and not board.line_safe(observer, origin, endpoint), "双方以相同新身份重新注册后恢复原友军阻挡")
	second.faction_id = &"line_test_ally"
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "阵营即时改变时不借用旧友军身份")
	board.register(partner)
	_publish(partner)
	board.set_relation(first.faction_id, second.faction_id, &"allied")
	check(_matches(origin, endpoint) and not board.line_safe(observer, origin, endpoint), "显式结盟且同组的存活成员保留相同保护")
	board.set_relation(first.faction_id, second.faction_id, &"hostile")
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "撤销同盟立即清除本查询的友军资格")
	board.set_relation(first.faction_id, second.faction_id, &"allied")

	var task: Dictionary = board.claim(partner, {"kind": &"search", "position": second.global_position, "duration": 4.0, "owner_action": &"cooperate"})
	var before: Dictionary = board.snapshot(observer, observer.cooperation_target_id())
	for repeat in 10: board.line_safe(observer, origin, endpoint)
	var after: Dictionary = board.snapshot(observer, observer.cooperation_target_id())
	check(not task.is_empty() and before == after, "重复专用查询不改状态、任务认领、期限或快照内容")
	second.receive_hit(second.max_health)
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "死亡即时失效，无需等待旧发布状态超时")
	second.reset_target()
	second.global_position = Vector3(20, 0, 0)
	board.register(partner)
	_publish(partner)
	check(_matches(origin, endpoint) and not board.line_safe(observer, origin, endpoint), "真实复活重新发布后恢复阻挡")
	partner.detach_environment()
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "离开战斗区会注销成员，旧位置不能继续阻挡")
	partner.refresh_environment()
	_publish(partner)
	check(_matches(origin, endpoint) and not board.line_safe(observer, origin, endpoint), "重新入区后使用新的注册和位置")
	board.reset()
	check(_matches(origin, endpoint) and board.line_safe(observer, origin, endpoint), "区域reset清空未发布状态，专用查询不保留旧缓存")
	print("COOPERATION LINE SAFETY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _publish(context) -> void:
	context.cooperation_publish_execution({})

func _matches(origin: Vector3, endpoint: Vector3) -> bool:
	return board.line_safe(observer, origin, endpoint) == _legacy_safe(origin, endpoint)

# Keep the former public implementation as the independent behavioral oracle.
func _legacy_safe(origin: Vector3, endpoint: Vector3) -> bool:
	for member in board.snapshot(observer, observer.cooperation_target_id()).members:
		if member.id == first.get_instance_id(): continue
		var torso: Vector3 = member.position + Vector3.UP * 0.9
		var closest := Geometry3D.get_closest_point_to_segment(torso, origin, endpoint)
		if Vector2(torso.x - closest.x, torso.z - closest.z).length() < 0.4 and absf(torso.y - closest.y) < 0.9:
			return false
	return true

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
