class_name TavernStaffDoor
extends StaticBody3D

@onready var _panel: Node3D = $Mesh
@onready var _closed_height := _panel.position.y
var _users: Dictionary = {}
var _animation: Tween


func open_for(actor: PhysicsBody3D) -> void:
	var id := actor.get_instance_id()
	if _users.has(id):
		return
	_users[id] = true
	actor.add_collision_exception_with(self)
	if _users.size() == 1:
		_slide_to(_closed_height + 2.35)


func close_for(actor: PhysicsBody3D) -> void:
	if not _users.erase(actor.get_instance_id()):
		return
	actor.remove_collision_exception_with(self)
	if _users.is_empty():
		_slide_to(_closed_height)


func _slide_to(height: float) -> void:
	if _animation != null:
		_animation.kill()
	_animation = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_animation.tween_property(_panel, "position:y", height, 0.28)
