extends SceneTree

var checks := 0
var failures := 0

class PhysicsGate extends Node:
	signal reached
	func _physics_process(_delta: float) -> void:
		set_physics_process(false)
		reached.emit()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	root.get_node("DebugSettings").enabled = false
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	ai.set_physics_process(false)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	var context = ai.context
	var selection = ai.cover_selection
	for body in ai.navigation_region.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor": body.collision_layer = 0
	actor.global_position = Vector3(25, 0, -2)
	player.global_position = Vector3(20, 0, -4)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = BoxShape3D.new()
	wall_shape.shape.size = Vector3(0.3, 3, 3)
	wall.add_child(wall_shape)
	scene.add_child(wall)
	wall.global_position = Vector3(22, 1.5, 0)
	# A moved static capsule updates the physics query world immediately. Godot
	# kinematic bodies keep next_transform until the step; see the player case below.
	var ally := StaticBody3D.new()
	var ally_shape := CollisionShape3D.new()
	ally_shape.shape = CapsuleShape3D.new()
	ally_shape.shape.radius = 0.35
	ally_shape.shape.height = 1.8
	ally_shape.position.y = 0.9
	ally.add_child(ally_shape)
	scene.add_child(ally)
	ally.global_position = Vector3(26, 0, 2)
	for frame in 5: await physics_frame
	var gate := PhysicsGate.new()
	root.add_child(gate)
	await gate.reached
	gate.queue_free()
	var from := Vector3(25, 1, 0)
	var to := Vector3(20, 1, 0)
	var point := Vector3(25, 0, 2)
	var rays: int = selection.environment_ray_queries
	var spaces: int = context.position_free_queries
	context.begin_geometry_evaluation()
	var hit: Dictionary = selection.environment_ray(from, to)
	var environment_query_id: int = selection._environment_query.get_instance_id()
	var first_free: bool = context.is_position_free(point)
	check(not context.fire.has_clear_firing_lane(from, to - from, from.distance_to(to)), "只读批次火控完整枪线仍拒绝实际硬墙")
	for repeat in 5:
		selection.environment_ray(from, to)
		context.is_position_free(point)
	check(hit.get("collider") == wall and first_free, "批次查询仍使用实际环境碰撞和真实身体空间")
	check(selection.environment_ray_queries == rays + 1 and context.position_free_queries == spaces + 1, "同一候选批次重复射线与占位各仅做一次物理查询")
	selection.environment_ray(from + Vector3.UP * 0.1, to + Vector3.UP * 0.1)
	check(selection._environment_query.get_instance_id() == environment_query_id, "同批次不同端点复用查询参数而不减少实际射线采样")
	rays += 1
	context.begin_geometry_evaluation()
	selection.environment_ray(from, to)
	context.is_position_free(point)
	context.end_geometry_evaluation()
	selection.environment_ray(from, to)
	context.is_position_free(point)
	check(selection.environment_ray_queries == rays + 1 and context.position_free_queries == spaces + 1, "内层评估结束不清除仍属于外层只读批次的结果")
	check(selection._environment_query.get_instance_id() == environment_query_id, "内层结束仍复用外层的独立环境查询对象")
	context.end_geometry_evaluation()
	check(selection._environment_query == null and selection._environment_space == null, "批次结束释放查询参数和物理世界引用，执行继续读取实时状态")
	var frame_id := Engine.get_physics_frames()
	_move_body(wall, Vector3(22, 1.5, 6))
	_move_body(ally, point)
	check(selection.environment_ray(from, to).is_empty(), "批次结束后同帧移走硬遮挡立即重新检测射线")
	check(not context.is_position_free(point), "批次结束后同帧胶囊碰撞体移入落脚点立即阻止提交")
	check(Engine.get_physics_frames() == frame_id and selection.environment_ray_queries == rays + 2 and context.position_free_queries == spaces + 2, "提交查询没有借等下一物理帧使旧缓存失效")
	check(context.fire.has_clear_firing_lane(from, to - from, from.distance_to(to)), "批次结束后同帧移走硬墙使底层枪线立即恢复")
	_move_body(wall, Vector3(22, 1.5, 0))
	check(not context.fire.has_clear_firing_lane(from, (to - from).normalized(), from.distance_to(to)), "执行期同帧重新遮挡立即使底层完整枪线失效")
	_move_body(wall, Vector3(22, 1.5, 6))
	_move_body(ally, Vector3(26, 0, 2))
	context.begin_geometry_evaluation()
	check(context.fire.has_clear_firing_lane(from, to - from, from.distance_to(to)), "Clear planning lane initializes the batch muzzle query")
	var muzzle_space = context.fire._muzzle_space
	var muzzle_exclude: Array[RID] = context.fire._muzzle_query.exclude.duplicate()
	check(muzzle_space != null and muzzle_exclude == selection._ray_query(from, to).exclude, "Muzzle batch uses the original actor/player exclusions and real physics space")
	context.begin_geometry_evaluation()
	check(context.fire.has_clear_firing_lane(from + Vector3.UP * 0.1, to - from, from.distance_to(to)), "Distinct batch lane still checks its own full line and muzzle volume")
	context.end_geometry_evaluation()
	check(context.fire._muzzle_space == muzzle_space and context.fire._muzzle_query.exclude == muzzle_exclude, "Nested batch retains the outer muzzle space and exclusion list")
	context.end_geometry_evaluation()
	check(context.fire._muzzle_space == null and context.fire._muzzle_query.exclude.is_empty(), "Outermost batch releases muzzle space and exclusions before execution")
	var muzzle_obstacle := StaticBody3D.new()
	var muzzle_obstacle_shape := CollisionShape3D.new()
	muzzle_obstacle_shape.shape = BoxShape3D.new()
	muzzle_obstacle_shape.shape.size = Vector3(0.08, 0.2, 0.08)
	muzzle_obstacle.add_child(muzzle_obstacle_shape)
	scene.add_child(muzzle_obstacle)
	_move_body(muzzle_obstacle, from + Vector3(-0.35, 0.0, 0.12))
	check(selection.has_clear_line(from, to) and not context.fire.has_clear_firing_lane(from, to - from, from.distance_to(to)), "Same-frame off-center obstruction still blocks the real muzzle volume after batch exit")
	_move_body(muzzle_obstacle, from + Vector3.UP * 5.0)
	check(context.fire.has_clear_firing_lane(from, to - from, from.distance_to(to)) and context.fire._muzzle_space == null, "Execution rechecks same-frame muzzle clearance without retaining a batch space")
	muzzle_obstacle.queue_free()
	_move_body(player, point)
	await physics_frame
	check(PhysicsServer3D.body_get_state(player.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM).origin.is_equal_approx(point), "运动体经过真实物理步后服务端姿态已同步")
	context.begin_geometry_evaluation()
	check(context.is_position_free(point) and not context.is_position_free(point, true), "规划继续排除隐藏玩家，实际身体避障仍可明确包含玩家")
	var shape_queries: int = context.position_free_queries
	context.is_position_free(point, false, true)
	check(context.position_free_queries == shape_queries + 1, "不同蹲姿身体高度拥有独立占位查询")
	context.end_geometry_evaluation()
	_move_body(player, Vector3(23, 0, 0))
	await physics_frame
	context.begin_geometry_evaluation()
	check(selection.environment_ray(from, to).is_empty() and context.is_position_free(point), "隐藏玩家移动不会变成环境遮挡或改变排除玩家的规划可用性")
	context.end_geometry_evaluation()
	ai.action_selector.assess_options(ai, false)
	check(context._geometry_evaluation_depth == 0 and selection._geometry_evaluation_depth == 0, "正常选择器和空间评估返回时不遗留只读批次")
	check(context._position_evaluation_cache.is_empty() and selection._environment_ray_cache.is_empty() and context.fire._lane_cache.is_empty(), "批次缓存随评估结束释放，不跨动作执行保留")
	print("GEOMETRY BATCH: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _move_body(body: CollisionObject3D, point: Vector3) -> void:
	if body is CharacterBody3D:
		body.move_and_collide(point - body.global_position)
	else:
		body.global_position = point
		body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
