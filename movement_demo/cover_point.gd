class_name CoverPoint
extends Marker3D

## 这个躲藏点“真正依赖”的掩体。
## 在 Inspector 中把对应墙体的 StaticBody3D 拖进来。
@export var cover_body: StaticBody3D
