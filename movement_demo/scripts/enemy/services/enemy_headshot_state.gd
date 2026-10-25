extends RefCounted

## 独立的被爆头状态。身体持有并推进，仅维持速度／精度效果的期限；死亡不进入本状态。
## 不读取AI、资源或动画，不创建独立节点或更新循环。
var remaining: float = 0.0
var movement_multiplier: float = 0.0
var accuracy_cap: float = 0.0

func active() -> bool:
	return remaining > 0.0

func apply(seconds: float, refresh_mode: int, movement: float, accuracy: float) -> bool:
	if not is_finite(seconds) or seconds <= 0.0: return false
	remaining = seconds if refresh_mode == WeaponData.StaggerRefresh.RESTART else maxf(remaining, seconds)
	# 时长遵循刷新策略，效果强度使用本次武器快照；不反查当前武器。
	movement_multiplier = clampf(movement, 0.0, 1.0) if is_finite(movement) else 0.0
	accuracy_cap = clampf(accuracy, 0.0, 1.0) if is_finite(accuracy) else 0.0
	return true

func advance(delta: float) -> bool:
	var was_active := active()
	remaining = maxf(0.0, remaining - maxf(0.0, delta))
	return was_active and not active()

func clear() -> void:
	remaining = 0.0
