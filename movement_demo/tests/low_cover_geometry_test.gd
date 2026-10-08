extends SceneTree

const Geometry = preload("res://scripts/systems/character_geometry.gd")
const LowCover = preload("res://scripts/world/low_cover_geometry.gd")
var checks := 0
var failed := 0
var world: Node3D

class TestActor extends CharacterBody3D:
	var crouching := true
	func is_crouching() -> bool: return crouching

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor := _box(Vector3(20, 0.5, 20), Vector3(0, -0.25, 0))
	var actor := _actor(Vector3(0, 0, 0.85))
	var cover = load("res://scenes/world/low_cover.tscn").instantiate()
	world.add_child(cover)
	await physics_frame
	await physics_frame
	check(cover.is_low_cover() and is_equal_approx(cover.get_top_height(), 1.1), "低墙按真实碰撞高度识别")
	check(cover.has_node("Mesh") and cover.has_node("CollisionShape3D") and cover.has_node("Presentation"), "保留原掩体节点路径")
	check(Geometry.can_occupy(actor, actor.position, 1.75, 0.35), "原地可站立")
	check(not LowCover.aim_cover(actor, Vector3.FORWARD).is_empty(), "正对低墙可辅助起身")
	check(LowCover.aim_cover(actor, Vector3.BACK).is_empty(), "背向低墙不自动站起")
	var plan := LowCover.query_vault(actor, Vector3.FORWARD)
	check(plan.get("valid", false), "整段抬升越墙落地可通行: %s" % plan.get("reason"))
	if plan.get("valid", false):
		check(LowCover.sample_vault(plan, 0).is_equal_approx(actor.position), "轨迹从真实身体位置开始")
		check(LowCover.sample_vault(plan, 1).is_equal_approx(plan.exit) and plan.exit.z < -0.6, "轨迹落点位于墙另一侧")
		check(LowCover.sample_vault(plan, 0.5).y > cover.get_top_height(), "整个身体脚底高于墙顶")
	var before: Transform3D = actor.transform
	for candidate in cover.get_candidates(Vector3(0, 0, -3), actor.position):
		check(candidate.get("crouch", false) and candidate.get("stand") == candidate.hide, "低墙提供同落点站起与蹲藏")
		break
	check(actor.transform == before, "候选和翻越查询不移动身体")
	check(not LowCover.query_vault_at(actor, cover, Vector3(1.45, 0, 0.85), Vector3.FORWARD).valid, "靠墙角不足整身空间拒绝翻越")
	var ceiling := _box(Vector3(4, 0.2, 4), Vector3(0, 1.6, 0))
	await physics_frame
	await physics_frame
	check(Geometry.can_occupy(actor, actor.position, 1.0, 0.35) and not Geometry.can_occupy(actor, actor.position, 1.75, 0.35), "低顶允许蹲姿拒绝站立")
	check(not LowCover.query_vault(actor, Vector3.FORWARD).valid, "低顶阻挡翻越通道或落地空间")
	ceiling.free()
	var obstacle := _actor(Vector3(0, 0, -0.8))
	obstacle.add_to_group("combat_target")
	await physics_frame
	await physics_frame
	check(not LowCover.query_vault(actor, Vector3.FORWARD).valid, "真实执行查询包含落点其他角色")
	check(LowCover.query_vault_at(actor, cover, actor.position, Vector3.FORWARD, 0.8, true).valid, "规划不通过隐藏角色占位泄漏坐标")
	obstacle.free()
	var saved_transform: Transform3D = cover.transform
	cover.rotation.y = PI * 0.5
	cover.scale = Vector3(1.1, 1.0, 1.0)
	actor.position = Vector3(0.85, 0, 0)
	await physics_frame
	await physics_frame
	check(LowCover.query_vault(actor, Vector3.LEFT).valid, "旋转缩放后的低墙仍可翻越")
	cover.transform = saved_transform
	actor.position = Vector3(0, 0, 0.85)
	cover.vault_enabled = false
	await physics_frame
	check(not LowCover.query_vault(actor, Vector3.FORWARD).valid, "低墙可单独关闭翻越")
	cover.vault_enabled = true
	cover.scale.y = 2
	await physics_frame
	check(not cover.is_low_cover() and not LowCover.query_vault(actor, Vector3.FORWARD).valid, "实际高度超标不冒充低墙")
	cover.scale = Vector3.ONE
	var target := _actor(Vector3(0, 0, -0.66))
	target.add_to_group("player")
	actor.position = Vector3(0, 0, 1.0)
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(actor.position + Vector3.UP * 1.55, target.position + Vector3.UP * 0.97, 1, [actor.get_rid(), target.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider == cover, "1.66米内头顶样本仍可能被1.1米墙挡住，需准确情报兜底")
	var intel := LowCover.proximity_cover(actor, target, 2.0)
	check(not intel.is_empty() and intel.position == target.position, "近距情报返回准确位置而非随机误差")
	target.crouching = false
	check(LowCover.proximity_cover(actor, target).is_empty(), "站姿不触发蹲藏兜底")
	target.crouching = true
	check(LowCover.proximity_cover(actor, target, 1.0).is_empty(), "范围外不报告")
	var extra_wall := _box(Vector3(3, 2.5, 0.1), Vector3(0, 1.25, 0.5))
	await physics_frame
	await physics_frame
	check(LowCover.proximity_cover(actor, target).is_empty(), "额外高墙阻隔不报告")
	extra_wall.free()
	target.position.y = -1
	check(LowCover.proximity_cover(actor, target).is_empty(), "隔层不报告")
	floor.free()
	target.free()
	await physics_frame
	check(not LowCover.query_vault(actor, Vector3.FORWARD).valid, "没有落地地面拒绝翻越")
	world.free()
	print("LOW COVER GEOMETRY: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func _actor(position: Vector3) -> TestActor:
	var actor := TestActor.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75
	collision.shape = capsule
	collision.position.y = 0.875
	actor.add_child(collision)
	world.add_child(actor)
	actor.position = position
	return actor

func _box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = position
	return body

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)
