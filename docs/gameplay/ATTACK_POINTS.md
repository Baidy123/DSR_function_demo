# 掩体攻击位置

攻击位置是从掩体几何生成、再经运行检查筛选的候选区域。是否采用由兵种能力、训练解锁及个人／团队决策共同决定；旧版“发现掩体即按概率优先冲向攻击点”的叙述不再代表当前选择流程。完整旧方向、实施与失败记录见[历史记录](../history/2026-10-28/gameplay/ATTACK_POINTS.md)。

## 区域配置

选择使用 `scripts/world/cover_region.gd` 的掩体根节点：

| 字段 | 脚本默认值 | 作用 |
| --- | --- | --- |
| Attack Inner Radius | 0.55米 | 高墙角攻击区内半径 |
| Attack Outer Radius | 1.5米 | 高墙角攻击区外半径 |
| Attack Sample Spacing | 0.4米 | 攻击区径向／圆弧采样最大间距 |
| Wall Gap | 0.55米 | 墙面到躲藏带近边距离 |
| Hide Depth | 0.4米 | 躲藏带宽度；低墙外围带同样使用 |
| Show Attack Points In Editor | 开启 | 显示区域预览，不改变运行选择 |
| Low Cover / Vault Enabled | 默认关闭 | 标记低墙／允许尝试翻越；仍需真实几何校验 |

保存的掩体覆盖优先，尺寸和间距会受节点变换影响。高掩体四角各形成墙外270°扇环，排除墙内90°，围绕碰撞盒生成；不是在四角各放一个固定点。低掩体改用完整外围站／蹲共用带，不应用高墙的角内圈排除与高墙 Peek 区。

## 候选资格与使用

候选必须检查实际导航路径、完整身体站位、墙体和队友占用、公共预约，以及从计划姿态枪口到合法已知目标样本的射界。未来站姿位置按站姿身体与枪口核对，不能借当前蹲姿通过狭窄空间。

高掩体进攻评估目标轮廓暴露，并将可用射界计入质量；低墙使用自己的站／蹲观察和射击规则，不机械套用高墙暴露阈值。枪口近处与中心有效通道必须安全；远处外围散布被墙挡住可以降低质量，不能据此把全部合法中心射线一律拒绝。具体采样是有限近似，不是连续空间穷举。

在 **UnitType** 中确认该兵种提供相应战术，在 **Training → 战术解锁** 启用。默认行为与可选战术分开维护，训练不会自动创造兵种没有的能力。个人模式由统一Utility比较候选；普通／强配合由协调器选择具备命令提案资格的已装配动作。当前掩体进攻动作已有engage岗位、分帧攻击点提案和真实执行入口，须满足可见、有弹及原几何条件；不是只供个人模式使用。接入范围和验证边界见[敌人AI](../enemy-ai.md)。

编辑时先核对掩体碰撞与模型一致，再调整区域尺寸和采样间距。减小间距会增加候选与查询负担，不保证战术一定胜出；地图边缘、队友占位或无合法射界时没有可用点是正常结果。完整操作见[竞技场](ARENA.md)。

## 代码职责

路径相对 `movement_demo/`：

| 层次 | 入口 |
| --- | --- |
| 碰撞盒到候选区域 | `scripts/world/cover_region.gd`、`low_cover_geometry.gd` |
| 空间查询、候选筛选和预算 | `scripts/enemy/services/enemy_cover_selection.gd`、`enemy_spatial_evaluator.gd` |
| 攻击几何细化 | `scripts/enemy/services/enemy_attack_geometry.gd` |
| 个人掩体进攻动作 | `scripts/enemy/actions/enemy_attack_position_action.gd` |
| 共用掩体移动与低墙射击 | `enemy_cover_motion.gd`、`enemy_low_cover_cycle.gd` |
| 选择与团队任务 | `enemy_action_selector.gd`、`services/squad_coordination.gd` |

几何服务只查询与估计，不决定行为，不取得其他可选动作的运行实例。缓存只能在约定的只读批次内复用，执行时仍需重新验证动态障碍与占位。

## 验证与限制

相关入口包括 `attack_points_test`、`attack_point_validation_test`、`attack_region_quality_test`、`low_cover_band_test`、`cover_tactical_safety_test` 及真实掩体运行测试。静态区域正确、候选质量正确、动作确实执行和帧耗时达标分别验证，不能互相替代。

旧高墙专项的通过数不覆盖后续低墙、团队调度或用户地图修改。本次只整理说明；当前失败、性能门槛和日志要求见[敌人测试](../enemy-tests.md)。
