extends CanvasLayer

## Read-only RTS routes in world space. No screen panel or navigation queries.
const REFRESH_SECONDS := 0.1
const COLORS := [Color("55dcff"), Color("ffcf5c"), Color("e196ff"), Color("79e6a4"), Color("ff9696"), Color("a6b9ff")]
var snapshots: Array[Dictionary] = []
var refresh_count := 0
var _elapsed := 0.0
var _settings: Node
var _mesh := ImmediateMesh.new()
var _paths: MeshInstance3D
var _material := StandardMaterial3D.new()
var _member_colors: Dictionary = {}
var _next_color := 0

func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_paths = MeshInstance3D.new()
	_paths.name = "GroundRoutes"
	_paths.mesh = _mesh
	_paths.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_paths)
	_settings = get_parent()
	_settings.changed.connect(_apply_debug_mode)
	_apply_debug_mode(_settings.enabled)

func _apply_debug_mode(enabled: bool) -> void:
	set_process(enabled)
	_paths.visible = enabled
	_elapsed = 0.0
	if not enabled:
		snapshots.clear()
		_mesh.clear_surfaces()

func _process(delta: float) -> void:
	_elapsed -= delta
	if _elapsed > 0.0: return
	_elapsed = REFRESH_SECONDS
	snapshots.clear()
	for actor in get_tree().get_nodes_in_group("combat_target"):
		var ai := actor.get_node_or_null("AI")
		if ai == null or not ai.get("context") is RefCounted: continue
		var value: Dictionary = ai.context.coordination_debug_snapshot()
		if value.is_empty(): continue
		value.member_path = str(actor.get_path())
		snapshots.append(value)
	snapshots.sort_custom(func(a, b): return a.member_path < b.member_path)
	if snapshots.is_empty():
		_member_colors.clear()
		_next_color = 0
	refresh_count += 1
	_rebuild_routes()

func _rebuild_routes() -> void:
	_mesh.clear_surfaces()
	if snapshots.is_empty(): return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for index in snapshots.size():
		var value := snapshots[index]
		var key: String = value.member_path
		if not _member_colors.has(key):
			_member_colors[key] = COLORS[_next_color % COLORS.size()]
			_next_color += 1
		var color: Color = _member_colors[key]
		var height: float = value.position.y + 0.06
		_route(value.get("route", PackedVector3Array()), height, color, false)
		_route(value.get("next_route", PackedVector3Array()), height, Color(color, 0.5), true)
		_ring(value.position, height, 0.42, color)
		_ring(value.get("staging_position", Vector3.INF), height, 0.3, Color(color, 0.6))
		_ring(value.get("target_position", Vector3.INF), height, 0.45, color)
		var goal: Vector3 = value.get("goal", value.get("personal_goal", Vector3.INF))
		if goal.is_finite() and goal != value.get("staging_position") and goal != value.get("target_position"):
			_ring(goal, height, 0.3, color)
	_mesh.surface_end()

func _route(points: PackedVector3Array, height: float, color: Color, dashed: bool) -> void:
	for index in range(1, points.size()):
		var a := Vector3(points[index - 1].x, height, points[index - 1].z)
		var b := Vector3(points[index].x, height, points[index].z)
		if not a.is_finite() or not b.is_finite(): continue
		var length := a.distance_to(b)
		if length < 0.01: continue
		var direction := (b - a) / length
		if dashed:
			for dash in ceili(length / 0.55):
				_strip(a + direction * dash * 0.55, a + direction * minf(length, dash * 0.55 + 0.3), 0.045, color)
		else:
			_strip(a, b, 0.075, color)
			var count := maxi(1, floori(length / 2.0))
			for arrow in count:
				var tip := a.lerp(b, float(arrow + 1) / float(count + 1))
				var side := Vector3.UP.cross(direction) * 0.18
				_triangle(tip, tip - direction * 0.3 + side, tip - direction * 0.3 - side, color)

func _ring(point: Vector3, height: float, radius: float, color: Color) -> void:
	if not point.is_finite(): return
	point.y = height
	for index in 24:
		var a := point + Vector3.RIGHT.rotated(Vector3.UP, TAU * index / 24.0) * radius
		var b := point + Vector3.RIGHT.rotated(Vector3.UP, TAU * (index + 1) / 24.0) * radius
		_strip(a, b, 0.055, color)

func _strip(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var side := Vector3.UP.cross((b - a).normalized()) * width * 0.5
	_triangle(a - side, a + side, b + side, color)
	_triangle(a - side, b + side, b - side, color)

func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_add_vertex(b)
	_mesh.surface_add_vertex(c)
