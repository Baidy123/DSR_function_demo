extends Node3D

const Event = preload("res://scripts/systems/effects/impact_event.gd")
const Receiver = preload("res://scripts/systems/effects/impact_receiver.gd")
@export var default_profile: ImpactProfile
@export_range(1, 512, 1) var max_active: int = 64
var _active: Array[Dictionary] = []
var _regions: Dictionary = {}
var _warned: Dictionary = {}


static func find_for(source: Node) -> Node:
	var ancestor := source
	while is_instance_valid(ancestor):
		var service := ancestor.get_node_or_null("ImpactEffects")
		if service != null and service.has_method("capture_hit") and service.has_method("dispatch_impact"): return service
		ancestor = ancestor.get_parent()
	return null


func capture_hit(hit: Dictionary, shot_direction: Vector3, source: Node):
	if hit.is_empty() or not hit.has("position"): return null
	var target = hit.get("collider")
	var receiver = target.get_node_or_null("ImpactReceiver") if is_instance_valid(target) and target is Node else null
	if receiver != null and not receiver is Receiver: receiver = null
	if receiver != null and not receiver.enabled: return null
	var event = Event.new()
	event.position = hit.position
	event.direction = shot_direction.normalized()
	event.normal = hit.get("normal", Vector3.ZERO)
	if event.normal.is_zero_approx(): event.normal = -event.direction
	if event.normal.is_zero_approx(): event.normal = Vector3.UP
	event.normal = event.normal.normalized()
	event.collider = weakref(target) if is_instance_valid(target) else null
	event.source = weakref(source) if is_instance_valid(source) else null
	event.receiver = weakref(receiver) if receiver != null else null
	event.profile = receiver.profile if receiver != null and receiver.profile != null else default_profile
	var region := _find_region(target as Node)
	if region == null: region = _find_region(source)
	if region != null:
		event.region = weakref(region)
		_bind_region(region)
	return event


func dispatch_impact(event) -> void:
	if event == null or event.consumed: return
	event.consumed = true
	if event.receiver != null:
		var receiver = event.receiver.get_ref()
		if is_instance_valid(receiver): receiver.notify_impact()
	play_impact(event, event.profile)


func play_impact(event, profile: ImpactProfile) -> void:
	if profile == null or profile.effect_scene == null: return
	var effect := profile.effect_scene.instantiate()
	if not effect is Node3D or not effect.has_method("start") or not effect.has_signal("finished"):
		if not _warned.has(profile):
			_warned[profile] = true
			push_warning("ImpactEffects: 特效需要 Node3D 根节点、start(event) 方法和 finished 信号。")
		effect.free()
		return
	while _active.size() >= maxi(1, max_active): _release(_active[0].node)
	add_child(effect)
	# 全局 +Y 对齐表面；与法线不平行的参考轴保证墙面和地面都稳定。
	var normal: Vector3 = event.normal
	var reference := Vector3.RIGHT if absf(normal.dot(Vector3.FORWARD)) > 0.95 else Vector3.FORWARD
	var right := normal.cross(reference).normalized()
	var basis := Basis(right, normal, right.cross(normal).normalized())
	effect.global_transform = Transform3D(basis, event.position + normal * profile.surface_offset)
	var region_id := 0
	if event.region != null and is_instance_valid(event.region.get_ref()): region_id = event.region.get_ref().get_instance_id()
	_active.append({"node": effect, "remaining": maxf(0.05, profile.max_lifetime), "region": region_id})
	effect.finished.connect(_release.bind(effect), CONNECT_ONE_SHOT)
	effect.start(event)


func _process(delta: float) -> void:
	for entry in _active.duplicate():
		entry.remaining -= delta
		if not is_instance_valid(entry.node) or entry.remaining <= 0.0: _release(entry.node)


func _release(effect) -> void:
	for index in range(_active.size() - 1, -1, -1):
		if _active[index].node == effect: _active.remove_at(index)
	if is_instance_valid(effect) and not effect.is_queued_for_deletion():
		effect.hide()
		effect.queue_free()


func active_count() -> int:
	return _active.size()


func clear_region(region: Node) -> void:
	if is_instance_valid(region): _clear_region_id(region.get_instance_id())


func _clear_region_id(id: int) -> void:
	for entry in _active.duplicate():
		if entry.region == id: _release(entry.node)


func _region_exited(id: int) -> void:
	_clear_region_id(id)
	var ref = _regions.get(id)
	var region = ref.get_ref() if ref != null else null
	if is_instance_valid(region) and region.presentation_reset.is_connected(clear_region):
		region.presentation_reset.disconnect(clear_region)
	_regions.erase(id)


func _bind_region(region: Node) -> void:
	var id := region.get_instance_id()
	if _regions.has(id): return
	_regions[id] = weakref(region)
	region.presentation_reset.connect(clear_region)
	region.tree_exiting.connect(_region_exited.bind(id), CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	for ref in _regions.values():
		var region = ref.get_ref()
		if not is_instance_valid(region): continue
		if region.presentation_reset.is_connected(clear_region): region.presentation_reset.disconnect(clear_region)
		var exit_callback := _region_exited.bind(region.get_instance_id())
		if region.tree_exiting.is_connected(exit_callback): region.tree_exiting.disconnect(exit_callback)
	_regions.clear()
	for entry in _active.duplicate(): _release(entry.node)


func _find_region(node: Node) -> Node:
	while is_instance_valid(node):
		if node.has_signal("presentation_reset"): return node
		node = node.get_parent()
	return null
