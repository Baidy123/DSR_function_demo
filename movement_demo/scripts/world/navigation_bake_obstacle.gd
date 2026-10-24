@tool
extends NavigationObstacle3D

## Native baking outline follows the physical instance, including inherited overrides.
## Editor polling is local to this helper; runtime uses resource/transform events.
var _shape: BoxShape3D
var _collision: CollisionShape3D
var _signature: Array = []
var _syncing := false
static var _parser: RID
static var _parser_users: int = 0

func _enter_tree() -> void:
	_parser_users += 1
	if _parser_users == 1:
		_parser = NavigationServer3D.source_geometry_parser_create()
		NavigationServer3D.source_geometry_parser_set_callback(_parser, _before_parse)

func _exit_tree() -> void:
	_parser_users -= 1
	if _parser_users == 0 and _parser.is_valid():
		NavigationServer3D.free_rid(_parser)
		_parser = RID()

static func _before_parse(_mesh: NavigationMesh, _source: NavigationMeshSourceGeometryData3D, node: Node) -> void:
	# Native parsing visits the body before its obstacle child. Refresh here so
	# even a same-frame runtime sibling-transform/shape replacement is current
	# before the native obstacle parser reads it. No outline is added twice.
	if node is StaticBody3D:
		var obstacle := node.get_node_or_null("NavigationBakeObstacle")
		if obstacle != null and obstacle.has_method("sync_geometry"): obstacle.sync_geometry()

func _ready() -> void:
	affect_navigation_mesh = true
	avoidance_enabled = false
	carve_navigation_mesh = false
	set_notify_transform(true)
	sync_geometry()
	set_process(Engine.is_editor_hint())

func _process(_delta: float) -> void:
	sync_geometry()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		sync_geometry()

func sync_geometry() -> void:
	if _syncing: return
	var collision := get_parent().get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D or collision.disabled:
		vertices = PackedVector3Array()
		_signature = []
		return
	if _shape != collision.shape:
		if is_instance_valid(_shape) and _shape.changed.is_connected(sync_geometry):
			_shape.changed.disconnect(sync_geometry)
		_shape = collision.shape
		_shape.changed.connect(sync_geometry)
	_collision = collision
	var signature := [collision.global_transform, _shape.size, global_transform]
	if signature == _signature: return
	_syncing = true
	var half := _shape.size * 0.5
	var bottom := INF
	var top := -INF
	for x in [-half.x, half.x]:
		for y in [-half.y, half.y]:
			for z in [-half.z, half.z]:
				var point := collision.to_global(Vector3(x, y, z))
				bottom = minf(bottom, point.y)
				top = maxf(top, point.y)
	# Native baking ignores vertex Y. Move the actual obstacle origin below
	# the physical bottom so tall boxes cannot retain a walkable floor inside.
	var origin := global_position
	origin.y = bottom - 0.5
	global_position = origin
	var outline := PackedVector3Array()
	for corner in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z)]:
		var point := to_local(collision.to_global(corner))
		point.y = 0.0
		outline.append(point)
	vertices = outline
	height = (top - bottom + 1.0) / maxf(global_basis.y.length(), 0.001)
	_signature = [collision.global_transform, _shape.size, global_transform]
	_syncing = false
