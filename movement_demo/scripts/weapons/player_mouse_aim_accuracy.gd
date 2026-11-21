@tool
class_name PlayerMouseAimAccuracy
extends Resource

## 鼠标瞄准的武器参数。运行中的准度、冷却与弹药仍由 Combat 持有。
@export_group("收敛与爆头")
## 从最低到最高准度使用的曲线。
@export_enum("线性:0", "二次:1", "指数:2") var convergence_model: int = 0

## 完整收敛时间，不含开火、换弹或受击后的恢复等待。
@export_range(0.01, 60.0, 0.01, "or_greater", "suffix:s") var convergence_seconds := 4.0:
	set(value):
		convergence_seconds = maxf(value, 0.01) if is_finite(value) and value > 0.0 else 4.0

## 指数曲线的前后速度差，0 等同线性。
@export_range(0.0, 10.0, 0.1) var convergence_exponent_k := 3.0
## 超过此基础准度开始产生爆头概率，满准度时实际命中必爆头。
@export_range(0.0, 0.99, 0.01) var headshot_accuracy_threshold := 0.9

@export_group("散布锥（角度）")
@export_range(0.0, 45.0, 0.1, "suffix:°") var min_spread_angle_degrees := 0.0
@export_range(0.0, 45.0, 0.1, "suffix:°") var max_spread_angle_degrees := 12.0
## 装备和松开瞄准时的散布基准。
@export_range(0.0, 45.0, 0.1, "suffix:°") var initial_spread_angle_degrees := 6.0
@export_range(0.0, 45.0, 0.05, "suffix:°") var shot_spread_penalty_degrees := 3.0
@export_range(0.0, 45.0, 0.1, "suffix:°") var shot_max_spread_angle_degrees := 10.8
@export_range(0.0, 45.0, 0.05, "suffix:°/m") var player_move_spread_degrees_per_meter := 3.0
@export_range(0.0, 45.0, 0.1, "suffix:°") var moving_spread_angle_degrees := 7.8
@export_range(0.0, 3.0, 0.05, "suffix:s") var spread_recovery_delay := 0.6

@export_group("概率模式（百分比）")
@export_range(0.0, 1.0, 0.01) var initial_accuracy := 0.5
@export_range(0.0, 1.0, 0.01) var shot_accuracy_penalty := 0.25
@export_range(0.0, 1.0, 0.01) var minimum_accuracy := 0.1
@export_range(0.0, 1.0, 0.005) var player_move_accuracy_loss_per_meter := 0.15
@export_range(0.0, 1.0, 0.01) var moving_accuracy_cap := 0.35
@export_range(0.0, 3.0, 0.05, "suffix:s") var accuracy_recovery_delay := 0.6

@export_group("霰弹随机偏移与稳定度")
## 单颗弹丸的随机偏移半角，固定图样由武器的 Shotgun 配置提供。
@export_range(0.0, 5.0, 0.01, "suffix:°") var stable_jitter_degrees := 0.08
@export_range(0.0, 5.0, 0.01, "suffix:°") var unstable_jitter_degrees := 0.55
@export_range(0.0, 1.0, 0.01) var starting_stability := 0.65
@export_range(0.0, 1.0, 0.01) var movement_loss_per_meter := 0.12
@export_range(0.0, 1.0, 0.01) var movement_stability_floor := 0.45
@export_range(0.0, 1.0, 0.01) var shell_stability_loss := 0.18
@export_range(0.0, 1.0, 0.01) var shell_stability_floor := 0.1
@export_range(0.0, 3.0, 0.05, "suffix:s") var stability_recovery_delay := 0.35
