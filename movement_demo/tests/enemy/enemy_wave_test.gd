extends SceneTree

const Controller = preload("res://scripts/world/enemy_wave_controller.gd")
const Wave = preload("res://scripts/world/enemy_wave_definition.gd")
const Region = preload("res://scripts/world/shooting_range.gd")
const SquadScene = preload("res://scenes/world/squad.tscn")
const EnemyScene = preload("res://scenes/enemy/levels/lvl_1/melee.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("DebugSettings").enabled = false
	await _templates()
	print("ENEMY WAVES: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _templates() -> void:
	var region = Node3D.new()
	region.set_script(Region)
	region.name = "TemplateRegion"
	region.position = Vector3(31, 0, 4)
	region.rotation.y = 0.7
	var controller = Controller.new()
	controller.name = "EnemyWaves"
	region.add_child(controller)
	var first = Wave.new()
	first.name = "First"
	controller.add_child(first)
	var second = Wave.new()
	second.name = "Second"
	second.position = Vector3(-3, 0, 1)
	controller.add_child(second)
	var external = SquadScene.instantiate()
	external.name = "Squad"
	region.add_child(external)
	first.existing_squads.assign([NodePath("../../Squad")])
	var nested = SquadScene.instantiate()
	second.add_child(nested)
	var template = EnemyScene.instantiate()
	template.max_health = 173.0
	template.position = Vector3(2, 0, -2)
	template.rotation.y = 0.9
	external.add_child(template)
	# 故意让关卡拥有手工新增成员；未经规范化直接 pack(Squad) 会漏掉它。
	template.owner = region
	var material := StandardMaterial3D.new()
	material.resource_local_to_scene = true
	material.albedo_color = Color.BLUE
	template.get_node("Body").material_override = material
	var weapon = template.weapon
	var training = template.get_node("Training").profile
	var profile = external.profile
	var transform_before: Transform3D = template.transform
	var later = EnemyScene.instantiate()
	nested.add_child(later)
	var entries := [0]
	template.tree_entered.connect(func(): entries[0] += 1)
	later.tree_entered.connect(func(): entries[0] += 1)
	root.add_child(region)
	check(entries[0] == 0 and not is_instance_valid(template) and not is_instance_valid(later), "捕获早于所有受管成员入树，原模板节点释放")
	check(region.enemies.is_empty() and get_nodes_in_group("shot_listener").is_empty() and get_nodes_in_group("combat_target").is_empty(), "未来波次无区域注册、近弹监听或战斗目标")
	check(controller.debug_snapshot().errors.is_empty() and controller.debug_snapshot().wave_count == 2, "原路径引用和直接子小队共用捕获流程")
	var copies: Array[Dictionary] = controller._instantiate_wave(0)
	check(copies.size() == 1 and copies[0].members.size() == 1, "保留关卡拥有的手工成员")
	var enemy = copies[0].members[0]
	check(enemy.max_health == 173.0 and enemy.transform == transform_before and enemy.get_child_count() == 11, "完整保留生命、部署朝向及公共组件")
	check(enemy.weapon == weapon and enemy.get_node("Training").profile == training and copies[0].root.profile == profile, "普通武器、嵌套训练与小队 Profile 保持共享引用")
	check(enemy.get_node("Body").material_override != material and enemy.get_node("Body").material_override.albedo_color == Color.BLUE, "实例覆盖的 local_to_scene 资源独立且值保留")
	region.add_child(copies[0].root)
	check(region.get_node("Squad/" + str(enemy.name)) == enemy and enemy.global_transform.is_equal_approx(region.global_transform * transform_before), "运行副本恢复原节点路径及区域变换")
	check(region.enemies.has(enemy) and enemy.get_node("AI").is_in_group("shot_listener") and enemy.health == 173.0, "仅运行副本正常就绪并注册原 AI")
	enemy.receive_hit(20.0)
	copies[0].root.free()
	var again: Array[Dictionary] = controller._instantiate_wave(0)
	check(again[0].members[0].max_health == 173.0 and again[0].members[0].transform == transform_before, "再次生成仍使用未受伤未移动的部署快照")
	again[0].root.free()
	var next: Array[Dictionary] = controller._instantiate_wave(1)
	check(next[0].parent.get_ref() == second, "后续波保留直接子小队的原父节点")
	next[0].root.free()
	check(region.enemies.is_empty() and get_nodes_in_group("shot_listener").is_empty(), "销毁运行副本沿原流程注销")
	region.free()
	await process_frame
	check(not is_instance_valid(controller), "关卡卸载释放控制器及内存部署资源")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
