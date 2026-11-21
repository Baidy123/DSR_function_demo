@tool
extends MeshInstance3D
## Sweeps upholstered profiles around a single U-shaped frame.

const OUTER_X := 2.015
const REAR_Z := -2.405
const FRONT_Z := 1.52
const CORNER_RADIUS := 0.82
const SIDE_LENGTH := FRONT_Z - REAR_Z - CORNER_RADIUS
const CORNER_LENGTH := PI * CORNER_RADIUS * 0.5
const REAR_LENGTH := (OUTER_X - CORNER_RADIUS) * 2.0
const LENGTH := 2.0 * (SIDE_LENGTH + CORNER_LENGTH) + REAR_LENGTH
const SAMPLE_SPACING := 0.035

@export var base_material: Material
@export var cushion_material: Material
@export var backrest_material: Material

var _generated_mesh: ArrayMesh


func _validate_property(property: Dictionary) -> void:
	# In the editor, generating the preview must not add a scene mesh override.
	if property.name == &"mesh" and _generated_mesh != null and mesh == _generated_mesh:
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _ready() -> void:
	if mesh != null and not mesh.is_built_in():
		return
	var sofa := ArrayMesh.new()
	_add_profile(sofa, base_material, PackedVector2Array([
		Vector2(0.06, 0.002), Vector2(0.59, 0.002), Vector2(0.64, 0.045),
		Vector2(0.64, 0.36), Vector2(0.61, 0.405), Vector2(0.04, 0.405),
		Vector2(0.02, 0.36), Vector2(0.02, 0.045),
	]))
	_add_profile(sofa, cushion_material, PackedVector2Array([
		Vector2(0.13, 0.39), Vector2(0.57, 0.39), Vector2(0.64, 0.414),
		Vector2(0.67, 0.451), Vector2(0.67, 0.496), Vector2(0.646, 0.53),
		Vector2(0.60, 0.551), Vector2(0.16, 0.551), Vector2(0.11, 0.52),
		Vector2(0.10, 0.45),
	]), true)
	_add_profile(sofa, backrest_material, PackedVector2Array([
		Vector2(0.015, 0.385), Vector2(0.19, 0.385), Vector2(0.24, 0.55),
		Vector2(0.21, 0.68), Vector2(0.15, 1.44), Vector2(0.12, 1.495),
		Vector2(0.075, 1.52), Vector2(0.035, 1.505), Vector2(0.01, 1.455),
	]))
	_generated_mesh = sofa
	mesh = sofa


func _add_profile(sofa: ArrayMesh, material: Material, profile: PackedVector2Array,
		seamed := false) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var steps := ceili(LENGTH / SAMPLE_SPACING)
	var rings: Array[PackedVector3Array] = []
	for step in range(steps + 1):
		var distance := LENGTH * step / steps
		var frame := _frame_at(distance)
		var ring := PackedVector3Array()
		var seam := pow(absf(cos(distance / LENGTH * TAU * 6.0)), 36.0) if seamed else 0.0
		for point in profile:
			var inset := lerpf(point.x, 0.39, seam * 0.075)
			var height := lerpf(point.y, 0.41, seam * 0.14)
			ring.append(frame.origin + frame.basis.x * inset + Vector3.UP * height)
		rings.append(ring)

	for step in range(steps):
		for edge in range(profile.size()):
			var next := (edge + 1) % profile.size()
			var left := float(step) / steps * LENGTH / 0.88
			var right := float(step + 1) / steps * LENGTH / 0.88
			var bottom := (profile[edge].y - 0.45) / 1.05
			var top := (profile[next].y - 0.45) / 1.05
			_vertex(surface, rings[step][edge], Vector2(left, 1.0 - bottom))
			_vertex(surface, rings[step][next], Vector2(left, 1.0 - top))
			_vertex(surface, rings[step + 1][edge], Vector2(right, 1.0 - bottom))
			_vertex(surface, rings[step][next], Vector2(left, 1.0 - top))
			_vertex(surface, rings[step + 1][next], Vector2(right, 1.0 - top))
			_vertex(surface, rings[step + 1][edge], Vector2(right, 1.0 - bottom))

	for end in [0, steps]:
		surface.set_smooth_group(-1)
		var ring := rings[end]
		for i in range(1, ring.size() - 1):
			_vertex(surface, ring[0], profile[0])
			_vertex(surface, ring[i if end != 0 else i + 1], profile[i if end != 0 else i + 1])
			_vertex(surface, ring[i + 1 if end != 0 else i], profile[i + 1 if end != 0 else i])

	surface.generate_normals()
	surface.generate_tangents()
	surface.index()
	surface.commit(sofa)


func _vertex(surface: SurfaceTool, point: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(point)


func _frame_at(distance: float) -> Transform3D:
	var corner_x := OUTER_X - CORNER_RADIUS
	var corner_z := REAR_Z + CORNER_RADIUS
	if distance <= SIDE_LENGTH:
		return Transform3D(Basis.IDENTITY, Vector3(-OUTER_X, 0.0, FRONT_Z - distance))

	distance -= SIDE_LENGTH
	if distance <= CORNER_LENGTH:
		return _corner_frame(-corner_x, corner_z, PI + distance / CORNER_RADIUS)

	distance -= CORNER_LENGTH
	if distance <= REAR_LENGTH:
		return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-corner_x + distance, 0.0, REAR_Z))

	distance -= REAR_LENGTH
	if distance <= CORNER_LENGTH:
		return _corner_frame(corner_x, corner_z, PI * 1.5 + distance / CORNER_RADIUS)

	return Transform3D(Basis(Vector3.UP, PI), Vector3(OUTER_X, 0.0,
		corner_z + distance - CORNER_LENGTH))


func _corner_frame(x: float, z: float, angle: float) -> Transform3D:
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var origin := Vector3(x, 0.0, z) + radial * CORNER_RADIUS
	return Transform3D(Basis(Vector3.UP, PI - angle), origin)
