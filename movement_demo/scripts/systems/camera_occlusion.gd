extends RefCounted

## 只处理明确标记的天花板／装饰物；按模型表面查询，不新增玩法碰撞。
## Compatibility 不支持 GeometryInstance3D.transparency，不能用该属性淡出。
const FADE_GROUP := &"camera_fadeable"
const IGNORE_GROUP := &"camera_occlusion_ignore"
var _faded: Dictionary = {}
var _warned_materials: Dictionary = {}


func update(camera: Camera3D, actor: Node3D, height: float, delta: float,
		opacity: float, seconds: float, mask: int) -> void:
	if opacity >= 1.0:
		clear()
		return
	var obstructing: Dictionary = {}
	var candidates: Dictionary = {}
	for decoration in camera.get_tree().get_nodes_in_group(FADE_GROUP):
		if not _has_excluded_ancestor(decoration): _collect_meshes(decoration, candidates)
	var center := actor.global_position + Vector3.UP * height * 0.55
	var side := camera.global_basis.x.normalized() * minf(0.25, height * 0.2)
	var points := [actor.global_position + Vector3.UP * height * 0.9,
		center, center - side, center + side, actor.global_position + Vector3.UP * height * 0.25]
	var origins: Array[Vector3] = []
	var targets: Array[Vector3] = []
	for point: Vector3 in points:
		# 正交投影的射线互相平行，不能简单从相机原点连到角色。
		if camera.is_position_behind(point): continue
		origins.append(camera.project_ray_origin(camera.unproject_position(point)))
		targets.append(point)
	for mesh: MeshInstance3D in candidates:
		if mesh.get_world_3d() != camera.get_world_3d() or (mesh.layers & camera.cull_mask & mask) == 0: continue
		# 导入模型可能用0.01等非零缩放；不能把其很小的行列式当成零。
		if mesh.global_basis.determinant() == 0.0: continue
		var inverse := mesh.global_transform.affine_inverse()
		var bounds := mesh.mesh.get_aabb()
		for index in origins.size():
			var from := inverse * origins[index]
			var to := inverse * targets[index]
			if bounds.intersects_segment(from, to) == null: continue
			# Godot 复用 Mesh 的三角形查询缓存；精确表面检查避免镂空装饰误淡出。
			var triangles := mesh.mesh.generate_triangle_mesh()
			if triangles != null and not triangles.intersect_segment(from, to).is_empty():
				obstructing[mesh] = true
				break
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
	# 标记专用容器时包括其内部模型；角色和玩法掩体始终排除。
	if _is_excluded(node): return
	if node is MeshInstance3D and node.is_visible_in_tree() and node.mesh != null:
		result[node] = true
	for child in node.get_children(true):
		_collect_meshes(child, result)


func _is_excluded(node: Node) -> bool:
	return node is CharacterBody3D or node.is_in_group("cover_region") or node.is_in_group(IGNORE_GROUP)


func _has_excluded_ancestor(node: Node) -> bool:
	while node != null:
		if _is_excluded(node): return true
		node = node.get_parent()
	return false


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
