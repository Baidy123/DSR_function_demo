extends RefCounted

## 只判断实际活动相机的画面边界；物理遮挡仍由各自原射线判定。
## 无相机的逻辑模拟不增加渲染依赖；正常关卡使用所属Viewport的活动相机。
static func contains_actor(actor: Node3D, edge_margin: float = 0.0) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.is_visible_in_tree(): return false
	var camera := actor.get_viewport().get_camera_3d()
	if camera == null: return true
	var point: Vector3 = actor.get_torso_position() if actor.has_method("get_torso_position") else actor.global_position + Vector3.UP * 0.8
	if not camera.is_position_in_frustum(point): return false
	var viewport := camera.get_viewport().get_visible_rect()
	return viewport.grow(-minf(edge_margin, minf(viewport.size.x, viewport.size.y) * 0.1)).has_point(camera.unproject_position(point))
