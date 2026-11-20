class_name TavernSeat
extends Marker3D

const Geometry = preload("res://scripts/systems/character_geometry.gd")

@export_node_path("PhysicsBody3D") var furniture_collision: NodePath
@export var swivel := false
@export var share_table_with_opposite_sofa := false
@export_range(0.4, 3.0, 0.05) var reach := 1.55
@export_range(0.4, 2.5, 0.01) var npc_exit_distance := 0.9

@onready var _furniture := get_node_or_null(furniture_collision) as PhysicsBody3D
var _occupant: WeakRef
var _return_position: Vector3


func _ready() -> void:
	add_to_group(&"tavern_seat")


func begin_scene_action(request: SceneRequest) -> void:
	var actor := request.node(&"player") as CharacterBody3D
	if not request.is_current() or actor == null or actor.is_in_dialogue or actor.is_dead() or actor.is_vaulting():
		request.fail("seat_unavailable")
		return
	var success := try_leave(actor) if request.parameters.get("leave", false) else (
		offer_score(actor) < INF and claim(actor, actor.global_position))
	if success:
		request.complete()
	else:
		request.fail("seat_blocked")


func cancel_scene_action(_request: SceneRequest, _reason: StringName) -> void:
	pass


func occupant() -> CharacterBody3D:
	return _occupant.get_ref() as CharacterBody3D if _occupant != null else null


func shares_table_with(other: TavernSeat) -> bool:
	if other == null:
		return false
	if get_parent() == other.get_parent():
		return not swivel
	if not share_table_with_opposite_sofa or not other.share_table_with_opposite_sofa:
		return false
	var table_group := get_parent().get_parent().get_parent()
	return table_group.has_node("Table") and table_group == other.get_parent().get_parent().get_parent()


func offer_score(actor: CharacterBody3D) -> float:
	if occupant() != null or not actor.has_method(&"seat_body_dimensions"):
		return INF
	var offset := global_position - actor.global_position
	var flat := Vector3(offset.x, 0.0, offset.z)
	var forward := -actor.global_basis.z
	forward.y = 0.0
	var alignment := forward.normalized().dot(flat.normalized())
	if flat.length_squared() > reach * reach or absf(offset.y) > 1.4 or alignment < 0.4:
		return INF
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 1.30,
		global_position + Vector3.UP * 0.67, actor.collision_mask, _excluded_rids(actor))
	if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return INF
	return flat.length() + 0.7 * (1.0 - alignment) if _has_room(actor) else INF


func claim(actor: CharacterBody3D, exit_position: Vector3) -> bool:
	if occupant() != null or not actor.has_method(&"sit_at_seat") or actor.current_seat() != null or not _has_room(actor):
		return false
	_occupant = weakref(actor)
	_return_position = exit_position
	actor.tree_exiting.connect(_on_actor_exiting, CONNECT_ONE_SHOT)
	if is_instance_valid(_furniture):
		actor.add_collision_exception_with(_furniture)
	var yaw := global_rotation.y
	if swivel:
		var towards := actor.global_position - global_position
		yaw = atan2(-towards.x, -towards.z) if Vector2(towards.x, towards.z).length() > 0.05 else actor.global_rotation.y
	actor.sit_at_seat(self, global_position, yaw)
	return true


func try_leave(actor: CharacterBody3D) -> bool:
	if actor != occupant():
		return false
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var dimensions: Vector2 = actor.seat_body_dimensions(false)
	for offset in [Vector3.ZERO, side * 0.44, -side * 0.44, -forward * 0.18, forward * 0.44]:
		var destination: Vector3 = _return_position + offset + Vector3.UP * 0.025
		if not Geometry.can_occupy(actor, destination, dimensions.y, dimensions.x):
			continue
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.55,
			destination + Vector3.UP * 1.22, actor.collision_mask, _excluded_rids(actor))
		if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		release(actor)
		actor.stand_from_seat(destination)
		return true
	return false


func release(actor: CharacterBody3D) -> void:
	if actor != occupant():
		return
	if actor.tree_exiting.is_connected(_on_actor_exiting):
		actor.tree_exiting.disconnect(_on_actor_exiting)
	if is_instance_valid(_furniture):
		actor.remove_collision_exception_with(_furniture)
	_occupant = null


func _on_actor_exiting() -> void:
	var actor := occupant()
	if actor != null:
		release(actor)


func _has_room(actor: CharacterBody3D) -> bool:
	var dimensions: Vector2 = actor.seat_body_dimensions(true)
	var query := Geometry.capsule_query(actor, global_position, dimensions.y, dimensions.x)
	query.exclude = _excluded_rids(actor)
	return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _excluded_rids(actor: CharacterBody3D) -> Array[RID]:
	var result: Array[RID] = [actor.get_rid()]
	if is_instance_valid(_furniture):
		result.append(_furniture.get_rid())
	return result
