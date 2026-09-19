class_name WeaponData
extends Resource

## 武器在战斗 HUD 中显示的名称；每把枪可单独保存为一份 .tres 资源。
@export var display_name: String = "测试手枪"
## 两种模式共用：实际射线命中后的单发伤害；训练靶只计数，不扣生命。
@export_range(1.0, 1000.0, 1.0) var damage: float = 25.0
## 两种模式共用：允许锁定和保持锁定的最大距离（米），不决定 v3 弹道射程。
@export_range(0.5, 50.0, 0.5) var aim_range: float = 8.0
## 两种模式共用：v3 瞬时弹道射线的最大距离（米）；独立 Combat 场景的旧 v2 仍用 Aim Range。
@export_range(0.5, 200.0, 0.5) var fire_range: float = 30.0
## 两种模式共用：索敌扇形总角度，只决定选择哪个锁定目标，不是子弹散布角。
@export_range(1.0, 180.0, 1.0) var cone_angle_degrees: float = 70.0
## 仅新散布锥模式：稳定度1.0时的最小散布半角（度）；0可完全收拢，大于0仍有三维散布。旧概率模式不读取。
@export_range(0.0, 45.0, 0.1) var min_spread_angle_degrees: float = 0.0
## 仅新散布锥模式：稳定度0.0时的最大散布半角（度）；全开角是本值两倍。小于最小值时按最小值处理；旧模式不读取。
@export_range(0.0, 45.0, 0.1) var max_spread_angle_degrees: float = 12.0
## 两种模式共用的初始值（0～1），装备时设置，松开瞄准时也限制到不超过它。
## 新模式：稳定度，当前半角=最大半角×(1-稳定度)+最小半角×稳定度，0.5不等于50%命中率。
## 旧模式：直射中心的概率；未直射时随机偏转8～20度，最终命中仍取决于碰撞。保留accuracy属性名以兼容资源。
@export_range(0.0, 1.0, 0.01) var initial_accuracy: float = 0.5
## 无玩家/目标移动和射击惩罚时，从初始值恢复到1.0的秒数，不含恢复延迟；从更低值恢复更久。
## 新模式逐渐收拢到最小散布；旧模式逐渐恢复到100%直射中心。
@export_range(0.1, 10.0, 0.1) var stabilize_seconds: float = 2.0
## 玩家实际移动时，将当前值限制到这个上限（0～1），不会抬高已经更低的值。
## 新模式限制稳定度，所以移动时不能完全收拢；旧模式限制直射中心概率。不是移动时的最大散布角。
@export_range(0.0, 1.0, 0.01) var moving_accuracy_cap: float = 0.35
## 两种模式共用：锁定时的走路速度倍率；锁定期间不能奔跑。
@export_range(0.1, 1.0, 0.05) var locked_move_multiplier: float = 0.5
## 每枪结束后从当前值扣除的量（0～1），连续射击累积；0.05表示扣5个百分点，不是扣5度。
## 新模式：降低稳定度，半角增加约“本值×(最大半角-最小半角)”，达到射击下限时会截断。
## 旧模式：降低直射中心概率；本枪先使用扣除前的值取弹道，惩罚影响后续射击。
@export_range(0.0, 1.0, 0.01) var shot_accuracy_penalty: float = 0.25
## 射击惩罚能压到的当前值下限（0～1）；若其他因素已压得更低，开枪不会抬高它。
## 新模式：稳定度下限，间接限制连射能扩大的半角；不是最小散布角。旧模式：直射中心概率下限。
@export_range(0.0, 1.0, 0.01) var minimum_accuracy: float = 0.1
## 停止玩家移动和射击后等待的恢复延迟（秒）。新模式等待后恢复稳定度并收拢；旧模式恢复中心概率。
## 目标持续移动时仍受下面的跟枪惩罚，可能无法完全恢复。
@export_range(0.0, 3.0, 0.05) var accuracy_recovery_delay: float = 0.6
## 两种模式共用：两次有效射击的最短间隔（秒）；冷却中按下射击不执行。
@export_range(0.05, 3.0, 0.05) var shot_interval: float = 0.2

## 锁定目标低速移动时，每实际移动1米扣多少当前值；0.03表示每米扣3个百分点。
## 新模式扣稳定度、扩大散布；旧模式扣中心概率。仅主场景v3使用，独立旧v2不读取跟枪参数。
@export_range(0.0, 0.5, 0.005) var target_move_accuracy_loss_per_meter_slow: float = 0.03
## 锁定目标高速移动时，每米最多扣多少当前值；0.10表示每米扣10个百分点。
## 新模式扣稳定度、扩大散布；旧模式扣中心概率。按实际速度在慢/高速每米惩罚间插值。
@export_range(0.0, 0.5, 0.005) var target_move_accuracy_loss_per_meter_fast: float = 0.10
## 仅跟枪惩罚的下限：新模式为稳定度下限，旧模式为中心概率下限，不是散布角。
## v3取本值与Minimum Accuracy+0.01的较大值，最高1.0；其他惩罚造成的更低值保留，允许恢复到此下限。
@export_range(0.0, 1.0, 0.01) var target_move_minimum_accuracy: float = 0.30
## 两种模式共用：目标达到这个速度（米/秒）时使用高速每米惩罚；低于它时在慢/高速惩罚间插值。
@export_range(0.1, 30.0, 0.1) var target_move_fast_speed: float = 6.0
