extends "res://enemy_action.gd"

## 当前小步只比较稳枪和开火；可见性、反应、冷却、动作权限由调用方先过滤。
enum Action { NONE, STEADY, FIRE }

## 稳定度正在提高时，继续稳枪可获得多少额外分数。
var recovery_gain_weight: float:
	get: return _setting(&"recovery_gain_weight", 0.35)
	set(value): _set_setting(&"recovery_gain_weight", value)
## 敌人被逼近到最小交战距离以内时，增加多少开火分数。
var close_range_weight: float:
	get: return _setting(&"close_range_weight", 0.35)
	set(value): _set_setting(&"close_range_weight", value)
## 已具备射击条件却选择等待时，每秒增加多少开火分数；避免永远等不到目标精度。
var wait_pressure_per_second: float:
	get: return _setting(&"wait_pressure_per_second", 0.45)
	set(value): _set_setting(&"wait_pressure_per_second", value)

var selected_action: Action = Action.NONE
var fire_score: float = 0.0
var steady_score: float = 0.0
var wait_seconds: float = 0.0

## recovery_rate 是本次真实恢复的稳定度/秒；close_pressure 为0～1的近身压力。
## 只比较分数，不读取隐藏玩家位置，不改变武器精度，也不直接执行开火。
func choose_action(delta: float, stability: float, target: float, recovery_rate: float, close_pressure: float) -> Action:
	wait_seconds += maxf(0.0, delta)
	var quality: float = clampf(stability / maxf(target, 0.0001), 0.0, 1.0) if target > 0.0 else 1.0
	var recovery_benefit: float = clampf(recovery_rate / maxf(target, 0.0001), 0.0, 1.0)
	# 不追求无限精度：达到目标后，继续等待的额外收益归零。
	steady_score = 1.0 + recovery_benefit * (1.0 - quality) * maxf(0.0, recovery_gain_weight)
	fire_score = quality + clampf(close_pressure, 0.0, 1.0) * maxf(0.0, close_range_weight)
	fire_score += wait_seconds * maxf(0.05, wait_pressure_per_second)
	selected_action = Action.FIRE if fire_score >= steady_score else Action.STEADY
	return selected_action

func on_shot_fired() -> void:
	# 只有真正发射后才消耗等待压力；保留本次分数供调试查看。
	wait_seconds = 0.0

func reset() -> void:
	selected_action = Action.NONE
	fire_score = 0.0
	steady_score = 0.0
	wait_seconds = 0.0
