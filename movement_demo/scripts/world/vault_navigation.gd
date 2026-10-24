extends RefCounted

## Region-owned static graph seeds. Actors still perform their complete preflight.
const WALK_LAYER: int = 1
const VAULT_LAYER: int = 2
const SLOT_SPACING: float = 1.5
const MAX_WALL_LINKS: int = 16
const MAX_REGION_LINKS: int = 128
var revision: int = 0
var ready: bool = false
var truncated_wall_count: int = 0
var truncated_region: bool = false
var _region: NavigationRegion3D
var _tree: SceneTree
var _container: Node3D
var _pending: Array[Node] = []
var _watched: Array[Node] = []
var _signatures: Dictionary = {}
var _covers: Array[Node3D] = []
var _seeds: Array[Dictionary] = []
var _links: Dictionary = {}
var _cursor: int = 0
var _region_transform: Transform3D
var _mesh: NavigationMesh
var _mesh_signature: Array = []
var _building: bool = false

func bind_region(region: NavigationRegion3D) -> void:
	if region == _region and is_instance_valid(region): return
	release()
	if not is_instance_valid(region) or not region.is_inside_tree(): return
	_region = region
	_tree = region.get_tree()
	_container = Node3D.new()
	_container.name = "_VaultNavigation"
	_region.add_child(_container)
	_region.get_tree().node_added.connect(_node_added)
	_region.get_tree().node_removed.connect(_node_removed)
	_rebuild()

func advance(max_items: int = 4) -> void:
	if not is_instance_valid(_region) or not _region.is_inside_tree():
		release()
		return
	var mesh_signature := [_region.navigation_mesh, _region.global_transform, _region.enabled, _region.navigation_layers, _region.get_navigation_map()]
	if mesh_signature != _mesh_signature:
		_rebuild()
	for unused in maxi(0, max_items):
		if not _pending.is_empty():
			var node: Node = _pending.pop_back()
			if not is_instance_valid(node) or _owned(node) or node is CharacterBody3D: continue
			for child in node.get_children(): _pending.append(child)
			if node is CollisionShape3D:
				_watched.append(node)
				_signatures[node.get_instance_id()] = _signature(node)
			if node is Node3D and node.has_method("is_low_cover"):
				_covers.append(node)
				_watched.append(node)
				_signatures[node.get_instance_id()] = _signature(node)
			continue
		if _building:
			if not _covers.is_empty():
				var cover: Node3D = _covers.pop_back()
				if is_instance_valid(cover): _queue_slots(cover)
				continue
			if not _seeds.is_empty():
				_add_seed(_seeds.pop_back())
				continue
			_building = false
			ready = true
		if _watched.is_empty(): continue
		_cursor %= _watched.size()
		var node := _watched[_cursor]
		_cursor += 1
		if not is_instance_valid(node) or _signature(node) != _signatures.get(node.get_instance_id()):
			_rebuild()
			break

func connections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for owner_id in _links:
		var connection := resolve_link(owner_id)
		if not connection.is_empty(): result.append(connection)
	return result

func resolve_link(owner_id: int) -> Dictionary:
	if not is_instance_valid(_region) or not _region.is_inside_tree() or not _region.enabled: return {}
	var data: Dictionary = _links.get(owner_id, {})
	if data.is_empty(): return {}
	var link := instance_from_id(owner_id) as NavigationLink3D
	var cover := instance_from_id(data.cover_id) as Node3D
	if not is_instance_valid(link) or link.get_parent() != _container or not _region.is_ancestor_of(link): return {}
	if not is_instance_valid(cover) or not _region.is_ancestor_of(cover): return {}
	if data.cover_revision != revision or _signature(cover) != _signatures.get(cover.get_instance_id()): return {}
	var collision := cover.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or _signature(collision) != _signatures.get(collision.get_instance_id()): return {}
	if _region.global_transform != _region_transform or _region.navigation_mesh != _mesh: return {}
	return data.duplicate(true)

## The native link identifies a wall; personal traversal may choose a different
## crossing along its whole face. These are static proposals, never occupancy
## reads of a hidden character. Walking, arc and live landing checks still run.
func area_candidates(owner_id: int, from: Vector3, destination: Vector3, radius: float, excluded: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source := resolve_link(owner_id)
	if source.is_empty(): return result
	var cover := instance_from_id(source.cover_id) as Node3D
	var collision := cover.get_node("CollisionShape3D") as CollisionShape3D
	var size: Vector3 = collision.shape.size
	var along := 0 if size.x * collision.global_basis.x.length() >= size.z * collision.global_basis.z.length() else 2
	var across := 2 if along == 0 else 0
	var scale: float = collision.global_basis[along].length()
	var start := collision.to_local(from)
	var target := collision.to_local(destination)
	var fraction := clampf(-start[across] / (target[across] - start[across]), 0.0, 1.0) if absf(target[across] - start[across]) > 0.001 else 0.5
	var half: float = size[along] * 0.5
	var ideal := clampf(lerpf(start[along], target[along], fraction), -half, half)
	var original: float = collision.to_local(source.feet_entry)[along]
	var spacing := maxf(0.8, radius * 2.0 + 0.1) / scale
	var used: Array[int] = []
	for value: float in [ideal, original, original + spacing, original - spacing, ideal + spacing, ideal - spacing]:
		var offset := clampf(value, -half, half)
		if excluded.has(source.link_key) and absf(offset - original) < spacing - 0.001: continue
		var slot := roundi(offset * scale / 0.05)
		if used.has(slot): continue
		used.append(slot)
		var key := "%s:area:%d" % [source.link_key, slot]
		if excluded.has(key): continue
		var candidate := source.duplicate(true)
		var shift: Vector3 = collision.global_basis[along] * (offset - original)
		for field in ["entry", "exit", "feet_entry", "feet_exit"]: candidate[field] += shift
		candidate.crossing_key = key
		result.append(candidate)
		if result.size() == 2: break
	return result

func release() -> void:
	if is_instance_valid(_tree):
		if _tree.node_added.is_connected(_node_added): _tree.node_added.disconnect(_node_added)
		if _tree.node_removed.is_connected(_node_removed): _tree.node_removed.disconnect(_node_removed)
	_tree = null
	if is_instance_valid(_mesh) and _mesh.changed.is_connected(_mesh_changed): _mesh.changed.disconnect(_mesh_changed)
	_clear_links()
	if is_instance_valid(_container): _container.free()
	_container = null
	_region = null
	_mesh = null
	_pending.clear()
	_watched.clear()
	_signatures.clear()
	_covers.clear()
	_seeds.clear()
	ready = false
	_building = false
	revision += 1

func _owned(node: Node) -> bool:
	return is_instance_valid(_container) and (node == _container or _container.is_ancestor_of(node))

func _node_added(node: Node) -> void:
	if is_instance_valid(_region) and not _owned(node) and not _dynamic(node) and _region.is_ancestor_of(node): _rebuild()

func _dynamic(node: Node) -> bool:
	while node != null and node != _region:
		if node is CharacterBody3D: return true
		node = node.get_parent()
	return false

func _node_removed(node: Node) -> void:
	if node == _region:
		release()
	elif _signatures.has(node.get_instance_id()):
		_rebuild()

func _mesh_changed() -> void:
	_rebuild()

func _clear_links() -> void:
	for owner_id in _links:
		var link := instance_from_id(owner_id) as NavigationLink3D
		if is_instance_valid(link): link.free()
	_links.clear()
	if is_instance_valid(_container):
		for link in _container.get_children(): link.free()

func _rebuild() -> void:
	if not is_instance_valid(_region): return
	_clear_links()
	if is_instance_valid(_mesh) and _mesh.changed.is_connected(_mesh_changed): _mesh.changed.disconnect(_mesh_changed)
	_mesh = _region.navigation_mesh
	if is_instance_valid(_mesh): _mesh.changed.connect(_mesh_changed)
	_region_transform = _region.global_transform
	_mesh_signature = [_mesh, _region_transform, _region.enabled, _region.navigation_layers, _region.get_navigation_map()]
	revision += 1
	ready = false
	_building = true
	_pending = [_region]
	_watched.clear()
	_signatures.clear()
	_covers.clear()
	_seeds.clear()
	_cursor = 0
	truncated_wall_count = 0
	truncated_region = false

func _signature(node: Node) -> Array:
	if node is CollisionShape3D:
		return [node.global_transform, node.shape, node.shape.size if node.shape is BoxShape3D else str(node.shape), node.disabled]
	return [node.global_transform, node.low_cover, node.vault_enabled]

func _queue_slots(cover: Node3D) -> void:
	if _mesh == null or not _region.enabled or not cover.is_low_cover() or not cover.vault_enabled: return
	var collision := cover.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.disabled or not collision.shape is BoxShape3D: return
	var size: Vector3 = collision.shape.size
	var basis := collision.global_basis
	if basis.y.normalized().dot(Vector3.UP) < 0.999: return
	var x := size.x * basis.x.length()
	var z := size.z * basis.z.length()
	var along: int = 0 if x >= z else 2
	var across: int = 2 if along == 0 else 0
	if size[across] * basis[across].length() > 1.2: return
	var radius := maxf(0.35, _mesh.agent_radius)
	# Include both physical ends, even for walls shorter than the agent diameter.
	# Each seed still has to pass the full standing/lifted capsule checks.
	var usable := size[along] * basis[along].length()
	var requested := maxi(1, ceili(usable / SLOT_SPACING) + 1)
	if requested > MAX_WALL_LINKS:
		truncated_wall_count += 1
		push_warning("Vault navigation: %s uses %d uniformly spread channels (requested %d)." % [_region.get_path_to(cover), MAX_WALL_LINKS, requested])
	var count := mini(MAX_WALL_LINKS, requested)
	for index in count:
		var distance := 0.0 if count == 1 else lerpf(-usable * 0.5, usable * 0.5, float(index) / (count - 1))
		_seeds.append({"cover": cover, "along": along, "across": across, "distance": distance, "index": index, "radius": radius})

func _add_seed(seed: Dictionary) -> void:
	if _links.size() >= MAX_REGION_LINKS:
		if not truncated_region:
			truncated_region = true
			push_warning("Vault navigation: %s reached %d channels; remaining static channels are omitted." % [_region.get_path(), MAX_REGION_LINKS])
		return
	var cover: Node3D = seed.cover
	if not is_instance_valid(cover) or not _region.is_ancestor_of(cover): return
	var collision := cover.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.disabled or not collision.shape is BoxShape3D: return
	var half: Vector3 = collision.shape.size * 0.5
	var basis := collision.global_basis
	var gap: float = seed.radius + maxf(_mesh.cell_size * 2.0, 0.15)
	if gap > 1.5: return
	var point := Vector3(0, -half.y, 0)
	point[seed.along] = seed.distance / basis[seed.along].length()
	point[seed.across] = half[seed.across] + gap / basis[seed.across].length()
	var a := collision.to_global(point)
	point[seed.across] = -point[seed.across]
	var b := collision.to_global(point)
	var exclusions: Array[RID] = []
	var floor_a := _floor(a, exclusions)
	var floor_b := _floor(b, exclusions)
	if floor_a.is_empty() or floor_b.is_empty(): return
	a = floor_a.position
	b = floor_b.position
	if absf(a.y - b.y) > 0.35: return
	var top: float = cover.get_top_height()
	if top - a.y < 0.45 or top - a.y > 1.3 or top - b.y < 0.45 or top - b.y > 1.3: return
	var nav_a := NavigationServer3D.region_get_closest_point(_region.get_rid(), a)
	var nav_b := NavigationServer3D.region_get_closest_point(_region.get_rid(), b)
	if not _endpoint(a, nav_a) or not _endpoint(b, nav_b): return
	if not _clear(a, a, 1.75, seed.radius, exclusions) or not _clear(b, b, 1.75, seed.radius, exclusions): return
	var lift_a := Vector3(a.x, top + 0.06, a.z)
	var lift_b := Vector3(b.x, top + 0.06, b.z)
	if not _clear(a, lift_a, 1.0, seed.radius, exclusions) or not _clear(lift_a, lift_b, 1.0, seed.radius, exclusions) or not _clear(lift_b, b, 1.0, seed.radius, exclusions): return
	var link := NavigationLink3D.new()
	link.navigation_layers = VAULT_LAYER
	link.bidirectional = true
	link.enter_cost = 0.0
	link.travel_cost = 1.0
	_container.add_child(link)
	link.set_navigation_map(_region.get_navigation_map())
	link.start_position = link.to_local(nav_a)
	link.end_position = link.to_local(nav_b)
	var owner_id := link.get_instance_id()
	_links[owner_id] = {"link_key": "%s:%d:%d" % [_region.get_path_to(cover), seed.index, revision], "cover_id": cover.get_instance_id(),
		"cover_revision": revision, "entry": nav_a, "exit": nav_b, "feet_entry": a, "feet_exit": b,
		"direction": Vector3(b.x - a.x, 0.0, b.z - a.z).normalized(), "duration": maxf(0.8, (a.distance_to(lift_a) + lift_a.distance_to(lift_b) + lift_b.distance_to(b)) / 8.0), "owner_id": owner_id}

func _endpoint(feet: Vector3, nav: Vector3) -> bool:
	return Vector2(feet.x - nav.x, feet.z - nav.z).length() <= 0.05 and absf(feet.y - nav.y) <= 0.5

func _floor(point: Vector3, exclusions: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.4, point - Vector3.UP * 0.45, 1, exclusions)
	var ignored := exclusions.duplicate()
	for unused in 64:
		var hit := _region.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): return {}
		if hit.collider is CharacterBody3D:
			ignored.append(hit.rid)
			query.exclude = ignored
			continue
		return hit if hit.normal.dot(Vector3.UP) >= 0.8 else {}
	return {}

func _clear(from: Vector3, to: Vector3, height: float, radius: float, exclusions: Array[RID]) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = maxf(0.01, radius - 0.005)
	shape.height = maxf(shape.radius * 2.0, height - 0.02)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = exclusions.duplicate()
	var ignored := exclusions.duplicate()
	query.margin = 0.001
	var space := _region.get_world_3d().direct_space_state
	for point in [from, to]:
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (height * 0.5 + 0.01))
		for unused in 64:
			var hits := space.intersect_shape(query, 32)
			if hits.is_empty(): break
			var dynamic_only := true
			for hit in hits:
				if hit.collider is CharacterBody3D: ignored.append(hit.rid)
				else: dynamic_only = false
			if not dynamic_only: return false
			query.exclude = ignored
		query.motion = Vector3.ZERO
	query.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * (height * 0.5 + 0.01))
	query.motion = to - from
	# Include dynamic bodies anywhere along the swept volume in the exclusion
	# set, without reading their positions or using them to enable/disable links.
	for unused in 64:
		var fractions := space.cast_motion(query)
		if fractions.size() != 2: return false
		if fractions[0] >= 0.9999: return true
		query.transform.origin += query.motion * minf(1.0, fractions[1] + 0.001)
		var motion := query.motion
		query.motion = Vector3.ZERO
		var hits := space.intersect_shape(query, 32)
		if hits.is_empty(): return false
		for hit in hits:
			if not hit.collider is CharacterBody3D: return false
			ignored.append(hit.rid)
		query.exclude = ignored
		query.motion = motion
		query.transform.origin = from + Vector3.UP * (height * 0.5 + 0.01)
	return false
