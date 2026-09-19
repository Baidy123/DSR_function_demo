class_name WeaponData
extends Resource

## 武器在战斗 HUD 中显示的名称；每把枪可单独保存为一份 .tres 资源。
@export var display_name: String = "测试手枪"
## 实际射线命中目标后传入的单发伤害；训练靶只计数，不扣生命。
@export_range(1.0, 1000.0, 1.0) var damage: float = 25.0
## 允许锁定和保持锁定的最大距离（米）；v3 的弹道射程另设 Fire Range，v2 还用本值决定弹道长度。
@export_range(0.5, 50.0, 0.5) var aim_range: float = 8.0
## v3 实际子弹射线的最大距离（米）；Aim Range 只决定锁定范围。
## 独立 Combat 场景仍使用的 v2 沿用其旧射程计算，不读取本项。
@export_range(0.5, 200.0, 0.5) var fire_range: float = 30.0
## 扇形总角度，而不是半角。
@export_range(1.0, 180.0, 1.0) var cone_angle_degrees: float = 70.0
## 装备时的初始精度（0～1），也用于松开瞄准时限制精度；表示直指瞄准中心的概率，仍可能被墙阻挡。
@export_range(0.0, 1.0, 0.01) var initial_accuracy: float = 0.5
## 无移动和射击惩罚时，从 Initial Accuracy 恢复到 1.0 所需的秒数；不含恢复延迟，从更低精度恢复会更久。
@export_range(0.1, 10.0, 0.1) var stabilize_seconds: float = 2.0
## 玩家实际移动时的精度上限（0～1）；仅压低超过上限的精度，不会抬高更低值。
@export_range(0.0, 1.0, 0.01) var moving_accuracy_cap: float = 0.35
## 锁定时的走路速度倍率；锁定期间不能奔跑。
@export_range(0.1, 1.0, 0.05) var locked_move_multiplier: float = 0.5
## 每枪扣除的精度（0～1），例如 0.05 表示扣 5 个百分点；连续射击会累积。
@export_range(0.0, 1.0, 0.01) var shot_accuracy_penalty: float = 0.25
## 射击惩罚能压到的精度下限（0～1）；若其他因素已令精度更低，开枪不会把它抬高。
@export_range(0.0, 1.0, 0.01) var minimum_accuracy: float = 0.1
## 停止移动和射击后，再等多久开始恢复精度。
@export_range(0.0, 3.0, 0.05) var accuracy_recovery_delay: float = 0.6
## 两次有效射击之间的最短间隔（秒）；冷却中按下的射击不会执行。
@export_range(0.05, 3.0, 0.05) var shot_interval: float = 0.2

## 以下跟枪参数仅由 player_combat_v3.gd 使用；独立 Combat 场景的 v2 尚不读取。
## 目标移动较慢时，每实际移动 1 米扣除的精度比例。0.03 = 3%。
@export_range(0.0, 0.5, 0.005) var target_move_accuracy_loss_per_meter_slow: float = 0.03
## 目标高速移动时，每实际移动 1 米最多扣除的精度比例。0.10 = 10%。
@export_range(0.0, 0.5, 0.005) var target_move_accuracy_loss_per_meter_fast: float = 0.10
## 仅由“锁定目标移动”这一项惩罚造成的精度下限。
## v3 取本值与 Minimum Accuracy + 0.01 的较大值，最高为 1.0；其他惩罚造成的更低精度仍保留。
@export_range(0.0, 1.0, 0.01) var target_move_minimum_accuracy: float = 0.30
## 当目标速度达到这个值（m/s）时，按高速每米惩罚计算；低于它时在慢/高速惩罚之间插值。
@export_range(0.1, 30.0, 0.1) var target_move_fast_speed: float = 6.0
