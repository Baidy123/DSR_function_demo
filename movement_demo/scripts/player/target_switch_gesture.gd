extends RefCounted

## 只累计鼠标净位移；由 Combat 根据候选屏幕间距判断触发并消费，不持有场景节点。
const MOTION_NOISE_PIXELS := 0.15
const STALE_MOTION_USEC := 120000
var _displacement := Vector2.ZERO
var _last_motion_usec: int = -1
var _has_new_motion := false


func reset() -> void:
	_displacement = Vector2.ZERO
	_last_motion_usec = -1
	_has_new_motion = false


func feed_motion(relative: Vector2, now_usec: int) -> void:
	if not relative.is_finite() or relative.length() <= MOTION_NOISE_PIXELS:
		return
	# 只让过期的小位移失效；没有切换后的等待／停顿锁。
	if _last_motion_usec >= 0 and now_usec - _last_motion_usec >= STALE_MOTION_USEC:
		_displacement = Vector2.ZERO
	_last_motion_usec = now_usec
	_displacement += relative
	_has_new_motion = true


func take_motion() -> Vector2:
	if not _has_new_motion: return Vector2.ZERO
	_has_new_motion = false
	return _displacement


func consume() -> void:
	# 丢弃余量，一次大甩动不能在后续帧自动连跳；新的移动可立刻继续累积。
	_displacement = Vector2.ZERO
	_has_new_motion = false
