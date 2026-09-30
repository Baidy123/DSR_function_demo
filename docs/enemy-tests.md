# 敌人测试与诊断

此目录集中保存敌人验证脚本、测试辅助和运行器；游戏主场景不加载这里的测试。运行代码说明见 [敌人模块化 AI](enemy-ai.md)。

## 当前回归

2026-09-30 玩家近战初次接入后完整敌人回归35/35通过，记录见 [玩家阶段](superpowers/plans/2026-09-30-player-melee.md)。随后用户授权远程敌人阶段，新增 `enemy_melee_execution_test.gd`（24项）和 `enemy_melee_utility_test.gd`，完整敌人回归37/37通过。层级纠正后 Utility 专项扩展为15项，验证现有接敌的 `engage / melee` 方案、实际推开和退让接续、同一行为内方案区分与中断边界、武器关闭近战、兵种装配隔离；不新增独立挥击行为。执行专项继续验证独立执行、动画同步与生命周期。玩家侧另有 `tests/player_enemy_melee_hit_test.gd`（15项），验证两种准度模式、切枪、30／60／120 Hz 物理击退、瞄准切换和墙体阻挡。见 [远程敌人接入记录](superpowers/plans/2026-09-30-ranged-enemy-melee.md)。

2026-09-30 增加 [表现接口验证](gameplay/PRESENTATION.md#维护与验证)。`utility_budget_test` 和 `attack_point_validation_test` 现在只在运行实例中明确启用其测试所需的攻击占位，避免依赖用户当前的训练勾选；不改保存的训练资源。涉及20毫秒预算的测试应避免与资源导入等高负载任务并行。

近战层级纠正后完整敌人回归再次37/37通过，基础执行24/24、Utility 近战15/15。默认行为仍为原4个，训练与战术目录没有增加挥击；协调器、选择器和统一评分公式沿用原实现。

在仓库根目录运行：

```powershell
python movement_demo/tests/enemy/run_enemy_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe
```

运行器 `TESTS` 列出当前 40 套正式回归。末尾可指定测试名（不含 `.gd`）。日志固定写入 `movement_demo/logs/enemy_regressions/`，同名结果覆盖。

Fire Mode 近战武器新增 `enemy_melee_weapon_test`，26/26 项通过：验证原单发／自动编号、新武器保存重载、无弹药／换弹、近战兵自主接近并连续实际命中、伤害／准度／击退、短武器距离、关闭近战，以及玩家／远程兵拒绝装备、出生错误配置和切换兵种取消未完成攻击。测试只配置现有兵种和武器，不直接选中近战行为来代替自主攻击验证。

武器模式面板专项：`--headless --editor --path movement_demo --script res://tests/weapon_fire_mode_inspector_test.gd`。2026-09-30 用户报告已打开的编辑器切换近战后仍显示远程字段；现场确认模式为2、插件隐藏规则有效，但旧资源实例的 setter 未发出刷新通知。原7项测试通过不足以覆盖此情况。现扩展为14项，通过真实下拉框验证直接资源与敌人内嵌 Weapon、即时通知缺失、切回枪械、原生撤销／重做及数值保留。新增用例在修复前失败，检查器增加延迟刷新后14/14通过；当前用户编辑器也已确认远程字段隐藏。和现有编辑器专项一样，退出时的 RID／资源占用提示单独记录，不等于运行时回归出错。

Fire Mode 版本本地工作区完整敌人回归41/41、玩家战斗回归14/14通过。此工作区包含另行保留的共享压制参数修改；本阶段提交不包含该无关修改及其专项，提交副本另外验证依赖完整性和相关行为，不能将它们混写为本次新增近战功能。

按暂存区导出的独立提交副本首次导入通过，无脚本／资源错误；敌人相关回归7/7（近战武器、基础执行、Utility 请求、持续追近、执行契约、模块协议、原武器）和玩家战斗完整回归14/14通过。该副本未带入上述本地压制改动与用户武器／训练配置，用于确认提交内容可独立运行。

基础执行接口整理的 `enemy_execution_contract_test`（16项）验证前摇移动／转向／开火／换弹互斥、收招移动、受击外力、取消冷却及表现快照隔离。它随本次依赖一并保留；与此无关的共享压制参数专项仍留在本地。

`enemy_melee_approach_test` 覆盖正常交战后玩家持续追近：保留场景武器、训练和掩体，先推进一秒交战使退路候选就绪，再驱动六秒实际玩家移动。不手动选中近战，也不堵住退路。5项检查包含进入有效范围、自主出手、命中击退、收招退让和前摇／开火互斥；该场景在修复前出现合法近战长期未被选中的失败，修复后通过。

此前正常追近修复后完整敌人回归38/38通过，追近5/5、基础近战执行24/24、Utility 近战15/15；保留原有装配、射击、退让与性能断言，编辑器导入无脚本／资源错误。

掩体专项包含 `cover_tactical_safety_test`（威胁近身路线、真实玩家身体阻挡、失败点排除）和 `stationary_cover_search_test`（玩家持续静止，敌人从躲藏推进调查并恢复开火）。`attack_point_validation_test` 已迁移到当前公共上下文接口，检查部分遮身、贴角余量、射界、感知距离及绿色预览与动作评估的一致性。`utility_suppression_blocked_test` 还验证两种压制同时参选时，出口压制能够实际胜出并开火。

`attack_region_quality_test` 隔离外围墙，检查 3 个距离、8 个方向共 24 组视角的可用区域面积、部分身体遮挡、内圈排除和外围散布容错；感知及射程上限由 `attack_point_validation_test` 单独覆盖。`close_range_spacing_test` 使用真实移动，验证满血未受击时退让、玩家持续逼近时再次后撤、后撤开火及失视信息边界。`utility_budget_test` 保留 20 毫秒耗时门槛和 180 帧覆盖检查。

`exit_suppression_geometry_test` 隔离外围墙后使用真实碰撞，覆盖敌人自身到两端的等距／不等距评分与统一选择器结果、贴墙及窄缝、间隙扩大后恢复、仅中点可站立但进出受阻、动态封堵、无关邻墙、旋转缩放与短边出口。移动隐藏玩家不得改变评分或可用出口；评分预览不得改写运行中的瞄准与连射状态。最后以已锁定旧出口的状态切换目标，验证跟枪途中不射击、跟上后真实子弹朝向新出口，并在60帧内检查双压制评分与通行复核合计小于20毫秒。`utility_suppression_blocked_test` 继续检查统一选择器实际选择并执行出口压制，以及记忆中心超距但真实出口仍在射程内；范围按新的身体入口采样设置为2.6米。

`enemy_configuration_lifecycle_test` 遍历 32 种战术选择，检查实际装配、空间任务所有者、共享查询通道和开火请求；另外检查同帧撤销再恢复、两个敌人的训练深复制、参数保存重载、替换/缺省训练资源及重生清理。测试刻意持有旧实例，避免把“恰好被释放”当作正确注销。原模块协议检查还覆盖动态扩展、能力限制、包含循环和协调器无具体战术分支。

`reload_approach_timing_test` 启用攻击站位后逐帧检查玩家靠近、实际动作切换与换弹计时，另外执行合法长路线的边走边换，检查弹匣尚有余弹时也不能在换弹过程中开枪。显示分别验证准备阶段、跨动作保留的实际进度、关闭Debug仍能看见进度，以及补满后继续转移的阶段，不能仅凭动作名称判断是否仍在换弹。

玩家及双方准度验证使用 `python movement_demo/tests/run_combat_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe`，当前 14 套入口，日志在 `movement_demo/logs/combat_regressions/`。其中 `aim_disruption_test` 验证双方真实直击/擦身弹道、墙体遮挡、换弹最低准度及恢复、重复惩罚排除和移动火力缓存边界；兼容入口复用玩家瞄准模式、散布、移动惩罚、模式参数和第一碰撞物检查。`player_reload_checkpoint_test` 覆盖50%边界、重复奔跑中断、前半程取消后真实开火、后半程强制续换禁射、两槽隔离、慢速方式保留、共享备弹耗尽及死亡重开；原换弹测试继续驱动真实Shift输入。另覆盖弹药、生命与自动射击，以及玩家近战功能、表现、物理、战斗区域、体力和敌人近战受击。

`enemy_fire_fixture.gd` 是公共辅助，`modular_probe_action.gd` 验证动态扩展；二者不单独运行。检查器使用编辑器模式：

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --editor --path E:/Godot/movement_demo --script res://tests/enemy/enemy_training_inspector_test.gd
```

该面板测试当前 14 项断言通过。Godot 4.7.2 使用 `--editor --script` 自定义 `SceneTree` 退出时仍报告编辑器 RID / 资源未释放；只等待初始化后退出的空脚本也能复现。因此将面板断言结果与编辑器退出检查分开记录，不把它算入上述无错误回归集合。测试会等待首次扫描完成，避免另行中断文件扫描。

## 本次清理增加的覆盖

`enemy_scene_test` 验证直接/容器内拖入、实例配置与搜索进度隔离、实际开火、跨区隔离、去重复位、导航自身延迟同步、导航/战斗区释放替换、区域外及不可站立出生点、无玩家/晚加入、注销和重新挂父节点。无效布置用例预期产生待命警告。

`enemy_configuration_cleanup_test` 检查七个失效字段及资源覆盖键移除、有效字段保存重载、默认与显式覆盖语义，以及嵌套场景的参数/位置保存。`search_components_test` 覆盖六种衰减、最低倍率、零概率、误差样本和随机调用顺序。`search_area_coverage_test` 从旧脚本迁移三个种子的实际导航搜寻，独立更密地面采样验证覆盖超过90%，失败目标和路径拐点不计覆盖，死亡/复位清理进度。

`enemy_firing_lane_test` 取代旧平面全锥测试，验证真实三维枪口空间、外围散布降低评分、当前枪口朝障碍暂缓及转出后命中。`enemy_basic_capabilities_test`、`enemy_reload_test`、`attack_hold_regression_test`、`attack_points_test`、`enemy_weapon_test`、`enemy_probability_test` 已迁移并加入正式运行器，保留身体执行、换弹脚步、实际站位保持、四面与旋转缩放几何、换枪与概率实射。概率测试显式提供足够弹药，避免空匣后重复统计上一枪。

27个失效历史入口的替代关系逐项列在 [清理映射](superpowers/plans/2026-09-29-enemy-cleanup-test-mapping.md)，包括已被统一评分替代的旧概率触发规则；不是按文件名批量丢弃有效测试。

听觉另运行 `--script res://tests/hearing_test.gd`，已迁移到当前动作/配置接口，保留45项逻辑声音、真实移动/开枪、权限、搜索、多人和资源保存检查。`test_enemy_probability_inspector.gd` 需要打开场景的编辑器测试环境，继续作为专项保留，不属于 headless 运行器。

已被替代的旧结构迁移、固定优先级、旧权限测试和性能探针已删除，见 [实施记录](superpowers/plans/2026-09-29-enemy-modular-ai.md)。
