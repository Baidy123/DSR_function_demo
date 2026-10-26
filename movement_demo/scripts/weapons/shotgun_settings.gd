@tool
class_name ShotgunSettings
extends Resource

const MAX_PATTERN_ANGLE_DEGREES := 15.0
enum SpreadMode { RANDOM, NO_INWARD }

# 与原角度一起保存。加载时不运行标定换算，避免资源字段顺序改变旧枪性能。
@export_storage var pattern_calibration_distance_m: float = 4.0

@export_group("逐发装填")
## 开启后按每发时间逐发补入弹匣，装好一发才扣一发备弹；关闭保持原整匣换弹。
## 玩家新按右键瞄准即可中断，已有余弹时瞄准扣扳机也可中断；按住右键再按 R 仍能装填。
## 切枪／快速换弹被奔跑打断同样保留已装弹量，未完成的一发清零且不扣备弹。
@export var shell_by_shell_reload: bool = false
## 每装入一发需要的秒数，仅逐发装填开启时使用；奔跑中开始的慢速装填仍乘原换弹速度倍率。
## 容量仍用武器 Magazine Capacity；开启后不使用武器的整匣 Reload Seconds。
@export_range(0.1, 5.0, 0.05, "suffix:s") var shell_reload_seconds: float = 0.6

@export_group("霰弹图样")
## 随机偏移保持原360°扰动；不向圆心偏移只排除朝图样原点的方向，允许侧向和很小的偏移。
## 中心弹丸仍可向四周偏移；不改图样点位，不强制沿径向外扩。旧资源默认随机偏移。
@export_enum("随机偏移", "不向圆心偏移") var spread_mode: int = SpreadMode.RANDOM
## 每个图样点对应一颗弹丸；拖入独立 ShotgunPattern 资源。留空为中心一颗。
@export var pattern: ShotgunPattern = preload("res://resources/weapons/patterns/balanced.tres"):
	set(value):
		if pattern == value: return
		pattern = value
		# 通知依赖当前图样的覆盖读数；只替换引用，不复制或修改点位。
		emit_changed()
## 每颗实际命中弹丸的伤害；同一枪命中同一目标时合计伤害，只施加一次命中干扰。
@export_range(0.0, 1000.0, 0.5) var pellet_damage: float = 8.0
## 固定图样的角度尺度；坐标为 1 的点在此角度。精度不会改变此值。
## 例如 3 度在 10 米处约偏离中心 0.52 米；距离越远，实际覆盖越大。
@export_range(0.0, 15.0, 0.05, "suffix:°") var pattern_angle_degrees: float = 3.0
## 完全稳定时，每颗弹丸独立随机偏差的最大角度；0 可精确复现图样。
@export_range(0.0, 5.0, 0.01, "suffix:°") var stable_jitter_degrees: float = 0.08
## 最不稳定时，每颗弹丸独立随机偏差的最大角度；不平移或缩放整幅图样。
@export_range(0.0, 5.0, 0.01, "suffix:°") var unstable_jitter_degrees: float = 0.55

@export_group("霰弹稳定度")
## 装备／松开瞄准后的稳定度上限；0 最不稳定、1 最稳定，与命中概率无关。
@export_range(0.0, 1.0, 0.01) var starting_stability: float = 0.65
## 持枪者移动每米损失的稳定度。
@export_range(0.0, 1.0, 0.01) var movement_loss_per_meter: float = 0.12
## 移动造成的损失最多降到此值，不抬高已因受伤等原因变低的稳定度。
@export_range(0.0, 1.0, 0.01) var movement_stability_floor: float = 0.45
## 每枪损失的稳定度，只扣一次，不按弹丸数重复。
@export_range(0.0, 1.0, 0.01) var shell_stability_loss: float = 0.18
## 射击造成的损失最多降到此值。
@export_range(0.0, 1.0, 0.01) var shell_stability_floor: float = 0.1
## 新的稳定度损失后，等待多久开始恢复。
@export_range(0.0, 3.0, 0.05, "suffix:s") var stability_recovery_delay: float = 0.35
## 目标慢速／快速移动时，每米造成的跟枪稳定度损失。
## 玩家只按平行容差处理后的有效横向距离计算；敌人沿用原目标位移。
@export var tracking_loss_per_meter: Vector2 = Vector2(0.03, 0.1)
## 跟枪造成的损失最多降到此值。
@export_range(0.0, 1.0, 0.01) var tracking_stability_floor: float = 0.3
## 目标达到此速度时使用快速跟枪损失。
## 玩家读取有效横向速度；径向速度不增加损失。敌人保留原目标速度计算。
@export_range(0.1, 30.0, 0.1, "suffix:m/s") var tracking_fast_speed: float = 6.0

@export_group("敌人恢复（原算法）")
## 仅敌人：从初始稳定度恢复到1的时间；初始为1时表示从0到1。
## 玩家统一使用所属武器的收敛时间／公式，不读取本项。保留原保存键与默认值。
@export_range(0.1, 10.0, 0.1, "suffix:s") var settle_seconds: float = 1.2


## 两种旧瞄准模式都只复用稳定度生命周期；霰弹不使用中心命中抽签或整团散布锥。
func get_aim_settings(_use_spread: bool) -> Dictionary:
	var initial := clampf(starting_stability, 0.0, 1.0)
	return {
		"initial": initial,
		"recovery": (1.0 - initial if initial < 1.0 else 1.0) / maxf(0.01, settle_seconds),
		"moving_cap": clampf(movement_stability_floor, 0.0, 1.0),
		"player_move_loss": maxf(0.0, movement_loss_per_meter),
		"shot_penalty": clampf(shell_stability_loss, 0.0, 1.0),
		"shot_floor": clampf(shell_stability_floor, 0.0, 1.0),
		"delay": maxf(0.0, stability_recovery_delay),
		"slow": maxf(0.0, tracking_loss_per_meter.x),
		"fast": maxf(0.0, tracking_loss_per_meter.y),
		"target_floor": clampf(maxf(tracking_stability_floor, shell_stability_floor + 0.01), 0.0, 1.0),
		"fast_speed": maxf(0.1, tracking_fast_speed),
	}


func get_jitter_degrees(stability: float) -> float:
	var minimum := clampf(stable_jitter_degrees, 0.0, 5.0)
	return lerpf(maxf(minimum, clampf(unstable_jitter_degrees, 0.0, 5.0)), minimum, clampf(stability, 0.0, 1.0))


func get_pattern_points() -> PackedVector2Array:
	return pattern.valid_points() if pattern != null else PackedVector2Array([Vector2.ZERO])


## 标定距离处整个正方形画板的面积，含空白，不包含随机偏移。
func get_pattern_coverage_area() -> float:
	return coverage_area_at(pattern_calibration_distance_m, pattern_angle_degrees)


## 无状态换算，预览可复用算法而不读取任何武器资源。
static func coverage_area_at(distance_m: float, angle_degrees: float) -> float:
	var side := 2.0 * distance_m * tan(deg_to_rad(clampf(angle_degrees, 0.0, MAX_PATTERN_ANGLE_DEGREES)))
	return side * side


## 距离和面积共同定义散布。非法组合返回 NAN，调用者必须拒绝整次修改。
static func calibration_angle_degrees(distance_m: float, area_m2: float) -> float:
	if not is_finite(distance_m) or distance_m <= 0.0 or not is_finite(area_m2) or area_m2 < 0.0:
		return NAN
	var angle := rad_to_deg(atan(sqrt(area_m2) / (2.0 * distance_m)))
	if angle > MAX_PATTERN_ANGLE_DEGREES + 0.000001: return NAN
	return minf(angle, MAX_PATTERN_ANGLE_DEGREES)


## 修改距离时传入原面积；修改面积时传入原距离。成功才一起写入，不修改图样。
func set_pattern_calibration(distance_m: float, area_m2: float) -> bool:
	var angle := calibration_angle_degrees(distance_m, area_m2)
	if not is_finite(angle): return false
	pattern_calibration_distance_m = distance_m
	pattern_angle_degrees = angle
	emit_changed()
	return true
