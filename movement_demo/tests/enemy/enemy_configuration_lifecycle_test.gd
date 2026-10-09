extends SceneTree

const Library = preload("res://scripts/enemy/enemy_action_library.gd")
class CoverQueue extends RefCounted:
	var spatial
	var channel: StringName
	func is_enabled() -> bool: return true
	func evaluation_channel() -> StringName: return channel
	func evaluation_points() -> Array: return spatial.cover_points()
	func evaluation_priority_count() -> int: return 0
	func evaluation_weight() -> int: return 1
	func evaluate_point(_point: Variant) -> Dictionary: return {}

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(actor)
	ai.cover_selection.debug_attack_points = false
	ai.cover_selection.debug_cover_selection = false
	player.get_node("Health").debug_invincible = true
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(22, 0, -2)
	actor.face_direction(player.global_position - actor.global_position, 10.0)
	for frame in range(8): await physics_frame
	var ids: Array[StringName] = [&"cover", &"attack_position", &"covering_retreat", &"suppression", &"cooperate"]
	# 刻意保留旧实例，模拟调试器/外部观察者仍在查看旧动作，不能靠释放时机保证正确性。
	var retained: Array = []
	for mask in range(32):
		retained.append_array(ai.actions.values())
		ai.training.profile.selected_tactics.clear()
		for bit in ids.size():
			if mask & (1 << bit): ai.training.profile.selected_tactics.append(ids[bit])
		ai.refresh_configuration(true)
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		var expected: Dictionary = Library.resolve(ai.unit_type.profile, ai.training.profile).definitions
		check(ai.actions.size() == expected.size() and ai.actions.keys().all(func(id): return expected.has(id)), "组合%d只装配有效动作" % mask)
		var owners_current := true
		var registered: Array = []
		for job in ai.context.spatial.jobs:
			for owner in job.owners:
				var action = owner.get_ref()
				registered.append(action)
				owners_current = owners_current and action != null and ai.actions.get(action.action_id) == action
		check(owners_current, "组合%d空间任务只引用当前实例，恢复同名动作不复活旧实例" % mask)
		check(ai.actions.values().all(func(action): return registered.has(action)), "组合%d撤销部分动作不会误删同通道其他动作的空间注册" % mask)
		check(ai.context.fire.request.is_empty() or expected.has(ai.context.fire.request.owner), "组合%d没有撤销动作遗留的开火请求" % mask)
	var removed_attack = ai.actions[&"attack_position"]
	ai.training.profile.selected_tactics.erase(&"attack_position")
	ai.refresh_configuration(true)
	ai.training.profile.selected_tactics.append(&"attack_position")
	ai.refresh_configuration(true)
	await physics_frame
	ai.context.spatial.advance_evaluation()
	var attack_jobs: Array = ai.context.spatial.jobs.filter(func(job): return job.channel == &"attack_position")
	check(attack_jobs.size() == 1 and attack_jobs[0].owners.size() == 1 and attack_jobs[0].owner.get_ref() == ai.actions[&"attack_position"] and attack_jobs[0].owner.get_ref() != removed_attack, "同帧撤销再恢复时空间任务不得复用旧实例")
	# 两个消费者同轮读取同一真实几何；清理任一队列不能清理另一队列。
	var geometry = load("res://scripts/enemy/services/enemy_spatial_evaluator.gd").new()
	geometry.context = ai.context
	var first := CoverQueue.new()
	first.spatial = geometry
	first.channel = &"ownership_first"
	var second := CoverQueue.new()
	second.spatial = geometry
	second.channel = &"ownership_second"
	geometry.register(first)
	geometry.register(second)
	geometry.advance_evaluation()
	var point_count: int = geometry.jobs[1].points.size()
	check(point_count > 0 and geometry.jobs[0].points == geometry.jobs[1].points, "同轮几何消费者获得一致的有效掩体列表")
	geometry.jobs[0].points.clear()
	check(geometry.jobs[1].points.size() == point_count, "清理一个消费者的队列不清空其他消费者的候选")
	var wall = geometry.regions()[0]
	var old_position: Vector3 = wall.global_position
	var before: Array = geometry.cover_points()
	wall.global_position += Vector3.RIGHT * 0.5
	var after: Array = geometry.cover_points()
	check(before != after and geometry.jobs[1].points.size() == point_count, "初始化结束后同帧几何改变立即重算且不修改已有队列")
	wall.global_position = old_position
	# 同一份资源供两个敌人引用，ready后必须成为互相隔离的运行快照。
	var source: EnemyTrainingProfile = load("res://resources/enemy/training/arena.tres")
	var source_fingerprint := source.fingerprint()
	var other = actor.duplicate()
	other.name = "ConfigurationIsolationEnemy"
	other.get_node("Training").profile = source
	other.get_node("AI").set_physics_process(false)
	actor.get_parent().add_child(other)
	var other_ai = other.get_node("AI")
	other_ai.cover_selection.debug_attack_points = false
	check(other_ai.training.profile != source and other_ai.training.profile.tactics != source.tactics, "敌人运行配置深复制，不写回共享资源")
	other_ai.training.profile.set_setting(&"tactics", &"damage_accuracy_penalty", 0.23)
	other_ai.training.profile.set_setting(&"tactics", &"nearby_shot_accuracy_penalty", 0.04)
	other_ai.refresh_configuration(true)
	check(source.fingerprint() == source_fingerprint and ai.training.profile.setting(&"tactics", &"damage_accuracy_penalty") == 0.15, "另一敌人调参不改变本敌人或资源文件")
	var path := "res://logs/aim_training_roundtrip.tres"
	check(ResourceSaver.save(other_ai.training.profile, path) == OK, "准度参数可保存")
	var restored = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(is_equal_approx(restored.setting(&"tactics", &"damage_accuracy_penalty"), 0.23) and is_equal_approx(restored.setting(&"tactics", &"nearby_shot_accuracy_penalty"), 0.04), "重载保留两个惩罚参数")
	check(restored.tactics.overridden.has("damage_accuracy_penalty") and restored.tactics.overridden.has("nearby_shot_accuracy_penalty"), "新字段遵守显式覆盖维护协议")
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	actor.weapon_stability = 0.8
	actor.receive_hit(1.0)
	check(is_equal_approx(actor.weapon_stability, 0.65), "移除全部战术后受伤准度仍由公共射击服务处理一次")
	var replacement := EnemyTrainingProfile.new()
	replacement.set_setting(&"tactics", &"damage_accuracy_penalty", 0.3)
	ai.training.profile = replacement
	ai.refresh_configuration(true)
	actor.weapon_stability = 0.8
	actor.receive_hit(1.0)
	check(is_equal_approx(actor.weapon_stability, 0.5), "运行替换训练配置后读取新参数，不重复连接事件")
	ai.training.profile = null
	ai.refresh_configuration(true)
	actor.weapon_stability = 0.8
	actor.receive_hit(1.0)
	check(is_equal_approx(actor.weapon_stability, 0.65), "训练资源缺省时使用默认惩罚，基础流程可运行")
	actor.reset_target()
	check(is_equal_approx(actor.weapon_stability, actor.weapon.get_aim_settings(false).initial) and actor.weapon_recovery_timer == 0.0, "重生清理准度与恢复计时")
	print("CONFIGURATION LIFECYCLE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
