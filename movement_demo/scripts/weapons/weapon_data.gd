class_name WeaponData
extends Resource

enum FireMode { SEMI_AUTO, AUTOMATIC }
enum AmmoType { RIFLE, PISTOL, SMG, SHOTGUN }

@export_group("弹匣与换弹")
## 玩家使用对应类型的共享备弹池；敌人仍使用有限弹匣、无限备弹。
@export_enum("步枪弹药:0", "手枪弹药:1", "冲锋枪弹药:2", "霰弹枪弹药:3") var ammo_type: int = AmmoType.PISTOL
## 每把枪独立保存弹匣余量；12发为可调试玩初值。
@export_range(1, 300, 1) var magazine_capacity: int = 12
## 正常换弹耗时（秒）。玩家奔跑倍率在Combat调整；敌人不受移动影响。
@export_range(0.1, 20.0, 0.1) var reload_seconds: float = 2.0

@export_group("共用参数")
## 武器显示名称。
@export var display_name: String = "测试手枪"
## 玩家或敌人实际开枪产生的逻辑声源；留空关闭。Audio Stream仅预留，不播放音频。
@export var shot_noise: NoiseData = preload("res://resources/noise/gunshot_noise.tres")
## 成功开火产生的声音半径（米），玩家和敌人都读取各自武器；0关闭枪声事件。
@export_range(0.0, 100.0, 0.5) var shot_noise_radius: float = 14.0
## 实际射线命中后的单发伤害。
@export_range(1.0, 1000.0, 1.0) var damage: float = 25.0
## 玩家锁定目标的最大距离（米）；敌人视野仍由 Perception 决定。
@export_range(0.5, 50.0, 0.5) var aim_range: float = 8.0
## 子弹射线的最大距离（米）。
@export_range(0.5, 200.0, 0.5) var fire_range: float = 30.0
## 玩家索敌扇形总角度，不是子弹散布角，也不修改敌人的视野。
@export_range(1.0, 180.0, 1.0) var cone_angle_degrees: float = 70.0
## 玩家锁定时的走路速度倍率，锁定期间禁跑；敌人移动由 AI 决定。
@export_range(0.1, 1.0, 0.05) var locked_move_multiplier: float = 0.5
## 玩家扳机操作：单发每次按下一枪，自动按住持续射击。敌人射击节奏仍由 AI 控制。
@export_enum("单发:0", "自动:1") var fire_mode: int = FireMode.SEMI_AUTO
## 两次射击的最短间隔（秒）。
@export_range(0.05, 3.0, 0.05) var shot_interval: float = 0.2

@export_group("概率模式参数（百分比）")
## 初始直射中心概率：0.5表示50%；松开瞄准也将概率限制到不超过本值。
@export_range(0.0, 1.0, 0.01) var initial_accuracy: float = 0.5
## 从初始概率恢复到100%需要的秒数，不含恢复延迟。
@export_range(0.1, 10.0, 0.1) var stabilize_seconds: float = 2.0
## 玩家移动惩罚最多将中心概率降到此值：0.35表示35%；不会抬高已经更低的概率。
@export_range(0.0, 1.0, 0.01) var moving_accuracy_cap: float = 0.35
## 玩家实际水平移动每米降低多少概率；0.15表示15个百分点，0表示不增加移动惩罚。
@export_range(0.0, 1.0, 0.005) var player_move_accuracy_loss_per_meter: float = 0.15
## 每枪结束后降低多少中心概率：0.05表示5个百分点，连续射击累积。
@export_range(0.0, 1.0, 0.01) var shot_accuracy_penalty: float = 0.25
## 射击惩罚的中心概率下限：0.1表示10%；不会抬高其他因素造成的更低概率。
@export_range(0.0, 1.0, 0.01) var minimum_accuracy: float = 0.1
## 玩家停步、停火后等多久开始恢复中心概率（秒）。
@export_range(0.0, 3.0, 0.05) var accuracy_recovery_delay: float = 0.6
## 目标慢速移动时，每米扣除的中心概率：0.03表示每米3个百分点。
@export_range(0.0, 0.5, 0.005) var target_move_accuracy_loss_per_meter_slow: float = 0.03
## 目标高速移动时，每米扣除的中心概率：0.10表示每米10个百分点。
@export_range(0.0, 0.5, 0.005) var target_move_accuracy_loss_per_meter_fast: float = 0.10
## 跟枪惩罚的概率下限，至少比射击下限高1个百分点，最高100%。
@export_range(0.0, 1.0, 0.01) var target_move_minimum_accuracy: float = 0.30
## 目标达到此速度（米/秒）时使用高速惩罚，较慢时在两种每米惩罚间插值。
@export_range(0.1, 30.0, 0.1) var target_move_fast_speed: float = 6.0

@export_group("散布锥模式参数（角度）")
## 完全稳定时的最小散布半角；0度可完全收拢，大于0仍会随机射偏。
@export_range(0.0, 45.0, 0.1, "suffix:°") var min_spread_angle_degrees: float = 0.0
## 最不稳定时的最大散布半角，通常不小于最小半角；全开角是半角两倍。
@export_range(0.0, 45.0, 0.1, "suffix:°") var max_spread_angle_degrees: float = 12.0
## 装备时的散布半角；松开瞄准后，散布也不会比本值更小。
@export_range(0.0, 45.0, 0.1, "suffix:°") var initial_spread_angle_degrees: float = 6.0
## 停稳并经过恢复延迟后，每秒收拢多少度；0表示不自动收拢。
@export_range(0.0, 90.0, 0.1, "suffix:°/s") var spread_recovery_degrees_per_second: float = 3.0
## 持枪者移动惩罚最多把半角扩大到多少度；若已经更散，不会反过来收拢。
@export_range(0.0, 45.0, 0.1, "suffix:°") var moving_spread_angle_degrees: float = 7.8
## 持枪者实际水平移动每米扩大多少度；随距离逐渐累积，0表示不增加移动散布。
@export_range(0.0, 45.0, 0.05, "suffix:°/m") var player_move_spread_degrees_per_meter: float = 3.0
## 每枪结束后扩大多少度，连续射击累积；例如1表示半角增加1度。
@export_range(0.0, 45.0, 0.05, "suffix:°") var shot_spread_penalty_degrees: float = 3.0
## 仅连射惩罚最多把半角扩大到多少度；不会收拢其他因素已经扩得更大的散布。
@export_range(0.0, 45.0, 0.1, "suffix:°") var shot_max_spread_angle_degrees: float = 10.8
## 持枪者停步、停火后等多久开始收拢（秒）。
@export_range(0.0, 3.0, 0.05) var spread_recovery_delay: float = 0.6
## 目标慢速移动时，每米扩大多少度。
@export_range(0.0, 45.0, 0.01, "suffix:°/m") var target_move_spread_degrees_per_meter_slow: float = 0.36
## 目标高速移动时，每米扩大多少度。
@export_range(0.0, 45.0, 0.01, "suffix:°/m") var target_move_spread_degrees_per_meter_fast: float = 1.2
## 仅跟枪惩罚最多把半角扩大到多少度；不会把其他原因造成的更大散布继续扩大。
@export_range(0.0, 45.0, 0.1, "suffix:°") var target_move_max_spread_angle_degrees: float = 8.4
## 目标达到此速度（米/秒）时使用高速每米扩散；较慢时在慢/高速扩散之间插值。
@export_range(0.1, 30.0, 0.1) var spread_target_move_fast_speed: float = 6.0


## 两套输入在这里换算，战斗脚本继续共用惩罚、等待、恢复流程。
func get_aim_settings(use_spread: bool) -> Dictionary:
	if not use_spread:
		return {
			"initial": initial_accuracy,
			"recovery": (1.0 - initial_accuracy) / maxf(stabilize_seconds, 0.01),
			"moving_cap": moving_accuracy_cap,
			"player_move_loss": maxf(0.0, player_move_accuracy_loss_per_meter),
			"shot_penalty": shot_accuracy_penalty,
			"shot_floor": minimum_accuracy,
			"delay": accuracy_recovery_delay,
			"slow": target_move_accuracy_loss_per_meter_slow,
			"fast": target_move_accuracy_loss_per_meter_fast,
			"target_floor": minf(1.0, maxf(target_move_minimum_accuracy, minimum_accuracy + 0.01)),
			"fast_speed": target_move_fast_speed,
		}
	var minimum: float = clampf(min_spread_angle_degrees, 0.0, 45.0)
	var maximum: float = clampf(max_spread_angle_degrees, minimum, 45.0)
	var span: float = maximum - minimum
	# 零宽度的锥始终使用同一角度，变化量为0，避免除零。
	var degrees_to_fraction: float = 1.0 / span if span > 0.00001 else 0.0
	return {
		"initial": _angle_to_stability(initial_spread_angle_degrees, minimum, span),
		"recovery": maxf(0.0, spread_recovery_degrees_per_second) * degrees_to_fraction,
		"moving_cap": _angle_to_stability(moving_spread_angle_degrees, minimum, span),
		"player_move_loss": maxf(0.0, player_move_spread_degrees_per_meter) * degrees_to_fraction,
		"shot_penalty": maxf(0.0, shot_spread_penalty_degrees) * degrees_to_fraction,
		"shot_floor": _angle_to_stability(shot_max_spread_angle_degrees, minimum, span),
		"delay": maxf(0.0, spread_recovery_delay),
		"slow": maxf(0.0, target_move_spread_degrees_per_meter_slow) * degrees_to_fraction,
		"fast": maxf(0.0, target_move_spread_degrees_per_meter_fast) * degrees_to_fraction,
		"target_floor": _angle_to_stability(target_move_max_spread_angle_degrees, minimum, span),
		"fast_speed": spread_target_move_fast_speed,
	}


func _angle_to_stability(angle: float, minimum: float, span: float) -> float:
	if span <= 0.00001:
		return 1.0
	return 1.0 - clampf((angle - minimum) / span, 0.0, 1.0)
