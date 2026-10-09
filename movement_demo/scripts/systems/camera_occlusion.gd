extends RefCounted

## 相机专用外观处理：查询原碰撞，独立复制材质，离开遮挡后还原原引用。
## Compatibility 不支持 GeometryInstance3D.transparency，不能用该属性淡出。
const MAX_HITS_PER_RAY := 16
const IGNORE_GROUP := &"camera_occlusion_ignore"
var _faded: Dictionary = {}
var _warned_materials: Dictionary = {}


func update(camera: Camera3D, actor: Node3D, height: float, delta: float,
		opacity: float, seconds: float, mask: int) -> void:
	if opacity >= 1.0:
		clear()
		return
	var obstructing: Dictionary = {}
	var visited: Dictionary = {}
	var center := actor.global_position + Vector3.UP * height * 0.55
	var side := camera.global_basis.x.normalized() * minf(0.25, height * 0.2)
	var points := [actor.global_position + Vector3.UP * height * 0.9,
		center, center - side, center + side, actor.global_position + Vector3.UP * height * 0.25]
	var space := camera.get_world_3d().direct_space_state
	for point: Vector3 in points:
		# 正交投影的射线互相平行，不能简单从相机原点连到角色。
		if camera.is_position_behind(point): continue
		var screen_point := camera.unproject_position(point)
		var origin := camera.project_ray_origin(screen_point)
		var query := PhysicsRayQueryParameters3D.create(origin, point, mask)
		query.hit_from_inside = true
		var excluded: Array[RID] = []
		if actor is CollisionObject3D: excluded.append(actor.get_rid())
		for _layer in MAX_HITS_PER_RAY:
			query.exclude = excluded
			var hit := space.intersect_ray(query)
			if hit.is_empty(): break
			excluded.append(hit.rid)
			var body = hit.collider
			if body is StaticBody3D and not body.is_in_group(IGNORE_GROUP) and not visited.has(body):
				visited[body] = true
				_collect_meshes(body, obstructing)
	for mesh: MeshInstance3D in obstructing:
		if not _faded.has(mesh):
			var entry := _capture(mesh)
			if not entry.is_empty(): _faded[mesh] = entry
	var target_opacity := clampf(opacity, 0.0, 1.0)
	var step := (1.0 - target_opacity) * maxf(0.0, delta) / seconds if seconds > 0.0 else 1.0
	for mesh in _faded.keys():
		if not is_instance_valid(mesh):
			_faded.erase(mesh)
			continue
		var entry: Dictionary = _faded[mesh]
		var target := target_opacity if obstructing.has(mesh) else 1.0
		entry.opacity = move_toward(float(entry.opacity), target, step)
		for item in entry.materials:
			var color: Color = item.material.albedo_color
			color.a = item.alpha * float(entry.opacity)
			item.material.albedo_color = color
		if is_equal_approx(float(entry.opacity), 1.0):
			_restore(mesh, entry)
			_faded.erase(mesh)


func _collect_meshes(node: Node, result: Dictionary) -> void:
	# 包括 Presentation 运行时的内部模型，但不跨进另一个物理对象或粒子节点。
	if node.is_in_group(IGNORE_GROUP): return
	if node is MeshInstance3D and node.is_visible_in_tree() and node.mesh != null:
		result[node] = true
	for child in node.get_children(true):
		if child is CollisionObject3D: continue
		_collect_meshes(child, result)


func _capture(mesh: MeshInstance3D) -> Dictionary:
	var entry := {"override": mesh.material_override, "surfaces": [], "materials": [], "opacity": 1.0}
	if mesh.material_override != null:
		var copy := _copy_material(mesh.material_override, entry.materials)
		if copy == null: return {}
		entry["copy_override"] = copy
		mesh.material_override = copy
	else:
		for surface in mesh.mesh.get_surface_count():
			var copy := _copy_material(mesh.get_active_material(surface), entry.materials)
			if copy == null: continue
			entry.surfaces.append({"index": surface, "original": mesh.get_surface_override_material(surface), "copy": copy})
			mesh.set_surface_override_material(surface, copy)
	return entry if not entry.materials.is_empty() else {}


func _copy_material(original: Material, copies: Array) -> BaseMaterial3D:
	if original != null and not original is BaseMaterial3D:
		# 不替换自定义着色器的视觉效果；需要它显式支持淡出后才能接入。
		if not _warned_materials.has(original.get_instance_id()):
			_warned_materials[original.get_instance_id()] = true
			push_warning("相机遮挡透明：自定义 ShaderMaterial 暂不支持自动淡出，请使用 StandardMaterial3D / ORMMaterial3D 或加入 camera_occlusion_ignore 组。")
		return null
	var material: BaseMaterial3D = original.duplicate() if original != null else StandardMaterial3D.new()
	var pass_copies: Array = []
	if material.next_pass != null:
		var next := _copy_material(material.next_pass, pass_copies)
		if next == null: return null
		material.next_pass = next
	copies.append({"material": material, "alpha": material.albedo_color.a})
	copies.append_array(pass_copies)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _restore(mesh: MeshInstance3D, entry: Dictionary) -> void:
	# 若别的表现逻辑已替换材质，不把旧引用强行覆盖回去。
	if entry.has("copy_override") and mesh.material_override == entry.copy_override:
		mesh.material_override = entry.override
	if mesh.mesh == null: return
	for surface in entry.surfaces:
		if surface.index < mesh.mesh.get_surface_count() and mesh.get_surface_override_material(surface.index) == surface.copy:
			mesh.set_surface_override_material(surface.index, surface.original)


func clear() -> void:
	for mesh in _faded:
		if is_instance_valid(mesh): _restore(mesh, _faded[mesh])
	_faded.clear()
	_warned_materials.clear()
