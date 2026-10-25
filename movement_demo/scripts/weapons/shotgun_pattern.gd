@tool
class_name ShotgunPattern
extends Resource

## 图样名称，只用于选择和预览。
@export var display_name: String = "自定义图样"
## 每个点就是一颗弹丸。X 向右、Y 向上；(0, 0) 是瞄准中心。
## 坐标乘武器的 Pattern Angle Degrees 得到角偏移；不要按精度缩放这些点。
## 空数组回退为一颗中心弹丸，最多使用前 64 个点。
@export var points: PackedVector2Array = PackedVector2Array([Vector2.ZERO])


func valid_points() -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		if point.is_finite(): result.append(point.clamp(Vector2(-1, -1), Vector2(1, 1)))
		if result.size() == 64: break
	if result.is_empty(): result.append(Vector2.ZERO)
	return result
