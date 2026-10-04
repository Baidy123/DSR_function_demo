@tool
class_name ImpactProfile
extends Resource

## Node3D 特效包装场景，根脚本实现 start(event) 和 finished 信号。留空不生成粒子。
@export var effect_scene: PackedScene
## 沿命中表面法线向外偏移，避免效果埋进墙面。
@export_range(0.0, 0.2, 0.001) var surface_offset: float = 0.015
## 即使自定义特效未发 finished，达到此寿命也强制回收（游戏秒数）。
@export_range(0.05, 30.0, 0.05) var max_lifetime: float = 2.0
