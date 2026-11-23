@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"tactics"

## 【个人与协调器共用】身体被动能力；与当前选择的动作无关。
## 开启后免于爆头秒杀，仍承受攻击武器配置的倍率伤害和存活硬直；关闭允许秒杀。
## 属于训练的被动防护，个人和团队均生效，不依赖当前战术。团队配置改动在重新加载战斗后生效。
@export var headshot_protection: bool = false:
	set(value):
		headshot_protection = value
		mark_override(&"headshot_protection")

## 【仅协调器】协调器判断真实压力下是否需要掩体避险；个人 Utility 不读取此阈值。
## 团队指挥下的抗压阈值；越低越早请求避险。压力来自实际受击与近弹，
## 默认0.4，单次受击约增加0.5；两类压力每秒各衰减0.5。只使用已训练掩体能力。
@export_range(0.0, 4.0, 0.05) var stress_tolerance: float = 0.4:
	set(value):
		stress_tolerance = clampf(value, 0.0, 4.0)
		mark_override(&"stress_tolerance")

@export_group("受击反应倍率")
## 【个人与协调器共用】身体被动能力；与当前选择的动作无关。
## 攻击武器造成的命中精度损失倍率，射击与附带近战共用；0免除、0.5减半、1正常、2加倍。
## 武器损失20%×0.5=扣10个百分点，精度80%变70%；不改变伤害或擦过影响。
@export_range(0.0, 10.0, 0.05, "suffix:×") var hit_accuracy_loss_multiplier: float = 1.0:
	set(value):
		hit_accuracy_loss_multiplier = maxf(0.0, value) if is_finite(value) else 0.0
		mark_override(&"hit_accuracy_loss_multiplier")
## 【个人与协调器共用】身体被动能力；与当前选择的动作无关。
## 敌方弹道擦过的精度损失倍率；0免除、0.5减半、1正常、2加倍。范围取自攻击武器，与命中损失独立。
## 免除精度损失仍保留真实近弹压力和警戒，不要求解锁掩体战术；遵守本场训练配置读取规则。
@export_range(0.0, 10.0, 0.05, "suffix:×") var suppression_accuracy_loss_multiplier: float = 1.0:
	set(value):
		suppression_accuracy_loss_multiplier = maxf(0.0, value) if is_finite(value) else 0.0
		mark_override(&"suppression_accuracy_loss_multiplier")
## 【个人与协调器共用】身体被动能力；与当前选择的动作无关。
## 命中速度损失倍率，射击与附带近战共用；武器减速30%×0.5=减速15%、保留85%自主速度。
## 0免除减速，1正常，2加倍；只缩放损失，不改变时长、击退或重力，擦过不减速。
@export_range(0.0, 10.0, 0.05, "suffix:×") var hit_speed_loss_multiplier: float = 1.0:
	set(value):
		hit_speed_loss_multiplier = maxf(0.0, value) if is_finite(value) else 0.0
		mark_override(&"hit_speed_loss_multiplier")

@export_group("")

## 【个人与协调器共用】统一火控在个人动作和团队命令下均读取。
## 接敌侧移/后退和掩护撤退时允许开火；关闭后只在停稳时射击，转身冲刺仍停火。
@export var fire_while_moving: bool = true:
	set(value):
		fire_while_moving = value
		mark_override(&"fire_while_moving")
## 【个人与协调器共用】统一火控在个人动作和团队命令下均读取。
## 首次发现或重新取得有效视线后，至少观察多久才允许射击（秒）；0可关闭。
@export_range(0.0, 5.0, 0.05) var fire_reaction_seconds: float = 0.3:
	set(value):
		fire_reaction_seconds = value
		mark_override(&"fire_reaction_seconds")
## 【个人与协调器共用】统一火控在个人动作和团队命令下均读取。
## 普通交火（含接敌跑打）希望达到的中心概率；0.7表示70%，不是最终命中率。
## 用作FireDecision评分的精度偏好，低于目标也可选择射击；掩护撤退不等待稳枪。
@export_range(0.0, 1.0, 0.05) var fire_stability_target: float = 0.7:
	set(value):
		fire_stability_target = value
		mark_override(&"fire_stability_target")
## 【个人与协调器共用】统一火控在个人动作和团队命令下均读取。
## 普通交战每轮开火机会数；屏幕外随机跳过也计一次，不按命中次数计数。
@export_range(1, 20, 1) var burst_shot_count: int = 3:
	set(value):
		burst_shot_count = value
		mark_override(&"burst_shot_count")
## 【个人与协调器共用】统一火控在个人动作和团队命令下均读取。
## 每轮最后一枪后的停火时间（秒）；与枪械冷却并行，必须都结束才能再开火。
@export_range(0.0, 10.0, 0.05) var burst_pause_seconds: float = 1.8:
	set(value):
		burst_pause_seconds = value
		mark_override(&"burst_pause_seconds")
## 【个人与协调器共用】统一火控在个人动作和团队命令下均读取。
## AI 扣扳机的最短间隔倍率；不改变 WeaponData 或玩家机械射速，1恢复原间隔。
@export_range(1.0, 5.0, 0.05) var shot_interval_multiplier: float = 1.5:
	set(value):
		shot_interval_multiplier = value
		mark_override(&"shot_interval_multiplier")
## 【仅协调器】统一火控仅在协调器发布有效队友支援需求时扩展点射；个人模式没有该需求。
## 仅在响应真实队友推进／换弹／撤退请求时延长一轮；请求消失即恢复普通短点射。
@export_range(1, 20, 1) var support_burst_shot_count: int = 6:
	set(value):
		support_burst_shot_count = value
		mark_override(&"support_burst_shot_count")
## 【个人与协调器共用】个人用于选位距离；团队火控用作近距开火压力阈值，不决定团队阵形距离。
## 远程敌人希望保持的距离区间，单位为米。
@export_range(1.0, 20.0, 0.5) var ranged_min_distance: float = 4.0:
	set(value):
		ranged_min_distance = value
		mark_override(&"ranged_min_distance")
## 【仅个人 Utility】个人远程选位；协调器使用自己的阵形与重规划规则。
## 远程期望距离上限（米）；与下限共同决定射击候选点的采样范围。
@export_range(2.0, 25.0, 0.5) var ranged_max_distance: float = 6.0:
	set(value):
		ranged_max_distance = value
		mark_override(&"ranged_max_distance")
## 【仅个人 Utility】个人远程选位；协调器使用自己的阵形与重规划规则。
## 选位有冷却，且有效目标会继续沿用，避免频繁左右换路。
@export_range(0.1, 5.0, 0.05) var ranged_repath_seconds: float = 0.75:
	set(value):
		ranged_repath_seconds = value
		mark_override(&"ranged_repath_seconds")
## 【个人与协调器共用】接近辅助与团队突进资格会读取；团队普通近战停点仍按冻结武器攻击范围计算。
## 近战接近时的停止距离（米）；远程保持距离由 Ranged Min/Max Distance 控制。
@export var stopping_distance: float = 1.3:
	set(value):
		stopping_distance = value
		mark_override(&"stopping_distance")
