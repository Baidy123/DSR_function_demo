extends RefCounted

var previous: Vector3
var initialized: bool = false


func reset(actor: Node3D) -> void:
	previous = actor.global_position
	initialized = true


func sample(actor: Node3D, delta: float, ordinary_speed: float) -> Vector3:
	if not initialized:
		reset(actor)
		return Vector3.ZERO
	var distance := actor.global_position - previous
	previous = actor.global_position
	distance.y = 0.0
	# 场景放置、传送不应触发行走；复位另外显式清除采样基准。
	if delta <= 0.0 or distance.length() > maxf(1.0, ordinary_speed * delta * 4.0): return Vector3.ZERO
	return actor.global_basis.orthonormalized().inverse() * (distance / delta)
