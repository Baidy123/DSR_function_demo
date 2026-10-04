extends Node3D

signal finished
## 示例及自定义粒子场景可直接复用本根脚本；管理器另有最大寿命保护。
@export_range(0.05, 30.0, 0.05) var duration: float = 0.8
var _elapsed: float = 0.0
var _started: bool = false


func start(_event) -> void:
	_elapsed = 0.0
	_started = true
	for node in find_children("*", "", true, false):
		if node is GPUParticles3D or node is CPUParticles3D:
			node.one_shot = true
			node.restart()
			node.emitting = true


func _process(delta: float) -> void:
	if not _started: return
	_elapsed += delta
	if _elapsed >= duration:
		_started = false
		finished.emit()
