extends RefCounted

## 身体独占的近战眩晕记录；没有节点、资源引用或独立更新循环。
## 与普通受击减速分开计时，枪击和重复近战不能续期或重置已消费破绽。
var remaining: float = 0.0
var duration: float = 0.0
var generation: int = 0
var opening_available: bool = false
var accuracy_threshold: float = 0.9

func apply(settings: Dictionary) -> void:
	var seconds: float = settings.get("seconds", 0.0)
	if remaining > 0.0 or not is_finite(seconds) or seconds <= 0.0: return
	generation += 1
	remaining = seconds
	duration = seconds
	opening_available = settings.get("opening_enabled", false)
	var threshold: float = settings.get("accuracy_threshold", 0.9)
	accuracy_threshold = clampf(threshold, 0.0, 0.99) if is_finite(threshold) else 0.9

func advance(delta: float) -> void:
	if remaining <= 0.0 or not is_finite(delta) or delta <= 0.0: return
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0: clear()

func consume(expected_generation: int) -> bool:
	if remaining <= 0.0 or not opening_available or generation != expected_generation: return false
	opening_available = false
	return true

func snapshot() -> Dictionary:
	return {"active": remaining > 0.0, "remaining_seconds": remaining,
		"elapsed_seconds": duration - remaining, "generation": generation,
		"opening_available": remaining > 0.0 and opening_available, "accuracy_threshold": accuracy_threshold}

func clear() -> void:
	generation += 1 # 复位后旧枪击快照不能消费新一轮状态。
	remaining = 0.0
	duration = 0.0
	opening_available = false
