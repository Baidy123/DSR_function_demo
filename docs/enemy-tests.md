# 敌人测试与诊断

本页说明当前验证入口、覆盖层次与需要保留的失败边界。全部旧用例结果、对照过程、日志位置和未完成项保存在[截至2026-10-28的历史记录](history/2026-10-28/enemy-tests.md)。历史通过数只描述当时代码、场景和夹具，不能视为当前工程全绿。

本次整理仅对照文档、代码、资源及测试登记，没有重新运行Godot或完整回归。当前功能与结构见[敌人AI](enemy-ai.md)，全项目测试入口见[项目目录](project-layout.md)。

## 选择和运行测试

以下命令从仓库根目录运行。将Godot路径换成本机实际console可执行文件；不要自动下载或换引擎版本来掩盖差异。

```powershell
python movement_demo/tests/run_regressions.py --list
python movement_demo/tests/run_regressions.py --check
python movement_demo/tests/enemy/run_enemy_regressions.py --godot "C:\Godot\Godot_console.exe" enemy_probability_test enemy_offscreen_fire_test
python movement_demo/tests/run_combat_regressions.py --godot "C:\Godot\Godot_console.exe" directional_tracking_test
```

`--list`显示实际登记，`--check`核对文件覆盖与重复登记，不启动Godot。敌人／战斗专项运行器接收不带.gd的测试名；不提供名字会跑其整套默认列表。需要统一跑指定套件时：

```powershell
python movement_demo/tests/run_regressions.py --godot "C:\Godot\Godot_console.exe" --suite enemy
```

运行器检查退出码、超时、SCRIPT ERROR、FAIL和ERROR输出，不能只看Godot退出0或最后一行PASS。当前公共运行器仅对根证书存储错误作特定过滤，不据此忽略其他资源、脚本或卸载错误。输出含日志和results.json；统一入口也可用--output指定本轮独立目录。日志是本地诊断产物，不提交。

运行时套件、编辑器脚本、需rendered场景的验收和维护工具分开执行。不要glob所有.gd逐一运行：有些是夹具、被其他测试调用的子测试或写资源工具。当前没有通用run_editor_regressions.py，编辑器测试按各自脚本约定运行。

## 按改动选择覆盖

下表列出代表性入口，完整登记以运行器为准。文件位于 `movement_demo/tests/enemy/`，特别注明的玩家／系统用例位于 `movement_demo/tests/`。

| 改动范围 | 代表性验证 |
| --- | --- |
| 兵种、训练、装配、撤销与生命周期 | enemy_modular_contract_test、enemy_configuration_cleanup_test、enemy_configuration_lifecycle_test、enemy_execution_contract_test |
| 个人评分与运行 | utility_score_test、utility_runtime_test、utility_budget_test |
| 中心概率、火控、换弹、屏外机会 | enemy_probability_test、enemy_firing_cadence_test、enemy_fire_decision_test、enemy_reload_test、enemy_offscreen_fire_test |
| 掩体区域、站位与枪线 | attack_points_test、attack_point_validation_test、attack_region_quality_test、cover_tactical_safety_test、enemy_firing_lane_test |
| 低墙、姿态与翻越 | low_cover_band_test、enemy_low_cover_contact_test、enemy_half_cover_test、enemy_vault_navigation_test、enemy_vault_link_runtime_test、enemy_vault_link_contract_test |
| 搜索证据与持续警戒 | search_reacquisition_test、search_pursuit_test、search_persistence_test、search_area_coverage_test、enemy_shared_contact_test |
| 团队任务、地图与同步 | squad_command_contract_test、squad_command_runtime_test、squad_map_observation_test、squad_cover_breach_test、squad_mixed_cooperation_test |
| 接敌恢复与派发连续性 | squad_contact_recovery_test、squad_dispatch_continuity_test、squad_melee_contact_test |
| 巡逻与队友通行 | squad_patrol_test、enemy_ally_spacing_runtime_test、enemy_ally_navigation_integration_test、enemy_ally_route_autonomous_test |
| 波次与出生搜索 | enemy_wave_test、enemy_wave_search_test、enemy_wave_events_test；关卡衔接另跑level_flow_test，真实增援屏障跑scene_reinforcement_test |
| 敌人眩晕／玩家近战破绽 | headshot_stagger_runtime_test；根测试目录melee_headshot_opening_test、player_enemy_melee_hit_test |
| 玩家锁定与精度兼容 | 根测试目录target_switch_test、directional_tracking_test、combat_compatibility_test |
| 听觉与声音显示 | 根测试目录hearing_test、movement_noise_modes_test、noise_debug_test |

`squad_command_runtime_test.gd`使用真实感知、AI、身体与武器，覆盖接敌、搜索、换弹、减员及重载。它还支持脚本专用参数：--level=0/1/2、--search、--crowded、--blocked-exit、--mixed、--patrol、--handoff等，组合和条件应核对脚本。直接调用时把脚本参数放Godot的 `--` 之后；普通套件运行器不转发这些参数。

```powershell
& "C:\Godot\Godot_console.exe" --headless --path movement_demo --script res://tests/enemy/squad_command_runtime_test.gd -- --level=2 --search --handoff
```

--patrol针对1／2级未警戒巡逻；强配合--search --handoff核对真实遮挡后的连续搜索与同步。运行时间或超时设定须容纳测试本身，不能借延长进程超时放宽单帧或行为时限。

## 编辑器、画面与维护工具

| 入口 | 运行条件与边界 |
| --- | --- |
| enemy/enemy_training_inspector_test.gd | 独立headless editor脚本；检查战术选项、包含来源与资源操作 |
| weapon_fire_mode_inspector_test.gd | 独立headless editor脚本；覆盖模式字段和玩家／敌人上下文显示 |
| enemy/test_enemy_probability_inspector.gd | Godot AI编辑器夹具，需打开对应敌人场景；不是普通SceneTree回归 |
| shotgun_inspector_test.gd | 独立headless editor脚本 |
| shotgun_pattern_editor_test.gd | 编辑器或脚本规定的preview-runtime分支；画面抓取需渲染环境 |
| target_switch_test.gd的--capture | 非headless画面分支；普通逻辑通过不等于已核对PNG |
| bake_arena.gd／bake_levels.gd | 写入导航的维护命令，不能当测试自动批量运行 |

脚本运行条件最终以 `run_regressions.py` 的SPECIAL登记和各脚本实现为准。编辑器插件、UndoRedo、鼠标捕获、画面布局及实际手感不能全部由headless逻辑验证替代。

## 验收应证明什么

1. **结构与权限**：原节点路径、脚本UID、资源引用、动作装配、个人／团队决策分流保持；无隐藏坐标泄漏、无未训练能力、无穿墙／超射程攻击。
2. **真实行为**：从合法感知到候选、接受、身体移动、实际开火／挥击／换弹全链路推进。只出现任务、意图或状态文字不算角色执行成功。
3. **几何**：使用完整胶囊路线、计划姿态枪口、实际遮挡、导航与队友占位。测试玩家不能被摆进墙中，再把未命中解释成AI停滞。
4. **生命周期**：暂停／对话、死亡、退队、减员、区域离开与重载、动作撤销、换枪、旧任务反馈及资源共享。
5. **时间与性能**：分别统计真实进展、首次派发、全员警戒、正常火控停顿及整队帧成本。不能把任务版本未变化直接等同于无动作，也不能只量候选生成时间。
6. **当前地图**：至少在相关保存场景上确认加载与行为。固定小夹具、短时启动和完整关卡战斗覆盖不同，结论分别报告。

原团队性能验收常使用P99<16毫秒／峰值<50毫秒，具体以对应测试断言为准。约2500微秒准备预算不限制不可中断单次几何查询，也不包含全部成员执行成本；不得把预算数当作实测帧耗时。性能失败必须保留，不能为了通过调低候选质量或提高门槛。

## 历史仍需关注的失败与边界

以下是归档中明确记录的结果，**未在本次文档整理中复测**。后续已有针对性复验的项目应以其完整上下文判断，不能只引用最早一次失败或偶发一次通过。

| 范围 | 保留事实 |
| --- | --- |
| 六人接敌派发 | 2026-10-27提前发布合法整表后，行为专项18/19；唯一失败仍为整队P99，约31.972毫秒／峰38.277毫秒，原16／50门槛未改 |
| 接敌警戒恢复 | 同日普通现场29/30、局部堵路31/32，行为通过而P99仍超限；分别约24.352／22.902毫秒，不能写为整体性能达标 |
| 强配合同掩体同步 | 定向失效／保留矩阵曾76/76；默认整场仍出现同步准备、齐备放行、早到等待和偶发时限／性能波动。偶发33/33不代表稳定全绿 |
| 搜索持续性与追查 | 历史search_persistence_test有17/22、search_pursuit_test有29/30；涉及覆盖轮次、累计时间、冻结线索、目击年龄及峰值等，未靠放宽断言处理 |
| 检查器撤销 | 玩家25°半角项新增覆盖通过，但weapon_fire_mode_inspector_test当次46/47；既有缺少即时通知时撤销刷新失败，退出有RID／资源清理ERROR |
| 火控、换弹、近战与霰弹旧预期 | 历史有声音断言、支援点射、纯近战武器模式／实伤、霰弹固定图样点数与低稳定度保持失败；部分与用户保存资源或旧夹具前提有关，须对照后续复验，不能直接修改用户资源凑通过 |
| 原个人Utility | 历史掩体候选专项存在24/25等未通过结果；恢复旧权重仍同项失败，不能算作本次评分调整造成或已修复 |
| 波次出生搜索 | 当次专项79/79及原波次80/80通过；不覆盖所有地图难度，也不消除独立追查／持续搜索旧失败 |
| 五关加载 | 历史五关各短时启动90帧可加载，卸载有成员移除警告；不代表完整五关自主战斗、通关或手感验收 |

完整对照副本、失败列表、时间采样与日志路径见[历史测试记录](history/2026-10-28/enemy-tests.md)。忽略目录日志可能只存在当时机器，归档保留文字证据不等于日志已经提交。

玩家目标切换近期还覆盖屏幕方向、按住右键无锁选敌、连续切换、击杀后继续辅助、平滑转向和转向中实际射击。测试中的替身目标命中／移出目标组不能冒充完整EnemyActor死亡生命周期；需按真实夹具报告覆盖。功能说明以[射击与锁定](gameplay/COMBAT.md)为准，不把旧通过次数累加成新的总验收。

## 失败处理与交付记录

先记录当前Git状态、引擎版本、场景／资源与调用参数，再区分实现错误、旧夹具前提、环境加载问题和真实性能／行为失败。需要对照时用隔离副本保留相同地图与资源，只替换待比较代码；不能在用户工作区回退配置或混入远端内容。

修改测试前应说明前提为何过时，并保留原断言所保护的行为目标。用户调过武器、图样、训练或地图时，不以测试旧默认值倒推并覆盖用户设置。修正夹具并不等于修复运行逻辑；未稳定复现或未确认根因要明确记录。

交付至少报告修改范围、实际运行命令、通过／失败、脚本和资源错误、未覆盖范围及必要证据。同步功能文档后只提交核对过的本阶段文件，不提交日志、导入缓存、临时探针或其他任务改动。阶段提交／推送遵守仓库AGENTS规则。

## 旧章节引用

<a id="2026-10-14-协作查询性能优化"></a>

2026-10-14 协作查询性能优化：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-14-协作查询性能优化)。

<a id="2026-10-14-目的地预约批量筛选优化"></a>

2026-10-14 目的地预约批量筛选优化：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-14-目的地预约批量筛选优化)。

<a id="2026-10-15-连射与协作阶段收尾"></a>

2026-10-15 连射与协作阶段收尾：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-15-连射与协作阶段收尾)。

<a id="2026-10-15-连射时的岗位资格查询"></a>

2026-10-15 连射时的岗位资格查询：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-15-连射时的岗位资格查询)。

<a id="2026-10-21-半身掩体接触保持"></a>

2026-10-21 半身掩体接触保持：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-21-半身掩体接触保持)。

<a id="2026-10-21-斜向失视漏判掩体与墙前提前结束"></a>

2026-10-21 斜向失视漏判掩体与墙前提前结束：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-21-斜向失视漏判掩体与墙前提前结束)。

<a id="2026-10-22-强配合共享接敌时盲站观察岗位"></a>

2026-10-22 强配合共享接敌时盲站观察岗位：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-22-强配合共享接敌时盲站观察岗位)。

<a id="2026-10-23-仅共享情报时搜索反复停步"></a>

2026-10-23 仅共享情报时搜索反复停步：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-23-仅共享情报时搜索反复停步)。

<a id="2026-10-23-强配合先到者等待与逐轮续接"></a>

2026-10-23 强配合：先到者等待与逐轮续接：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-23-强配合先到者等待与逐轮续接)。

<a id="2026-10-24-共用翻越路线执行"></a>

2026-10-24 共用翻越路线执行：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-24-共用翻越路线执行)。

<a id="2026-10-24-关卡兵种继承示范"></a>

2026-10-24 关卡兵种继承示范：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-24-关卡兵种继承示范)。

<a id="2026-10-24-半身掩体全宽翻越"></a>

2026-10-24 半身掩体全宽翻越：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-24-半身掩体全宽翻越)。

<a id="2026-10-24-可训练的近战堵截"></a>

2026-10-24 可训练的近战堵截：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-24-可训练的近战堵截)。

<a id="2026-10-24-翻越评分偏好"></a>

2026-10-24 翻越评分偏好：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-24-翻越评分偏好)。

<a id="2026-10-24-高掩体烘焙高度基准"></a>

2026-10-24 高掩体烘焙高度基准：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-24-高掩体烘焙高度基准)。

<a id="2026-10-25-个人翻越评分加权"></a>

2026-10-25 个人翻越评分加权：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-25-个人翻越评分加权)。

<a id="2026-10-25-运行时翻越区域与真实玩家跟进"></a>

2026-10-25 运行时翻越区域与真实玩家跟进：[整理前对应章节](history/2026-10-28/enemy-tests.md#2026-10-25-运行时翻越区域与真实玩家跟进)。

<a id="出生快速追查2026-10-26"></a>

出生快速追查（2026-10-26）：[整理前对应章节](history/2026-10-28/enemy-tests.md#出生快速追查2026-10-26)。

<a id="出生点附近的有序巡逻2026-10-26"></a>

出生点附近的有序巡逻（2026-10-26）：[整理前对应章节](history/2026-10-28/enemy-tests.md#出生点附近的有序巡逻2026-10-26)。

<a id="后续波次出生搜索2026-10-26"></a>

后续波次出生搜索（2026-10-26）：[整理前对应章节](history/2026-10-28/enemy-tests.md#后续波次出生搜索2026-10-26)。

<a id="屏外开火概率2026-10-26"></a>

屏外开火概率（2026-10-26）：[整理前对应章节](history/2026-10-28/enemy-tests.md#屏外开火概率2026-10-26)。

<a id="强配合同掩体同步连续性2026-10-27"></a>

强配合同掩体同步连续性（2026-10-27）：[整理前对应章节](history/2026-10-28/enemy-tests.md#强配合同掩体同步连续性2026-10-27)。

<a id="当前回归"></a>

当前回归：[整理前对应章节](history/2026-10-28/enemy-tests.md#当前回归)。

<a id="接敌派发空窗2026-10-27"></a>

接敌派发空窗（2026-10-27）：[整理前对应章节](history/2026-10-28/enemy-tests.md#接敌派发空窗2026-10-27)。

<a id="接敌警戒成员恢复2026-10-27"></a>

接敌警戒成员恢复（2026-10-27）：[整理前对应章节](history/2026-10-28/enemy-tests.md#接敌警戒成员恢复2026-10-27)。

<a id="旧测试失败原因与当前地图复验2026-10-26"></a>

旧测试失败原因与当前地图复验（2026-10-26）：[整理前对应章节](history/2026-10-28/enemy-tests.md#旧测试失败原因与当前地图复验2026-10-26)。

<a id="玩家枪械跟枪半角2026-10-27"></a>

玩家枪械跟枪半角（2026-10-27）：[整理前对应章节](history/2026-10-28/enemy-tests.md#玩家枪械跟枪半角2026-10-27)。

<a id="移除个人训练cooperation2026-10-26"></a>

移除个人训练Cooperation（2026-10-26）：[整理前对应章节](history/2026-10-28/enemy-tests.md#移除个人训练cooperation2026-10-26)。

<a id="第五关近战落点与真实命中2026-10-27"></a>

第五关近战落点与真实命中（2026-10-27）：[整理前对应章节](history/2026-10-28/enemy-tests.md#第五关近战落点与真实命中2026-10-27)。

<a id="血条相机范围屏幕禁射与尸体保留2026-10-25"></a>

血条、相机范围、屏幕禁射与尸体保留（2026-10-25）：[整理前对应章节](history/2026-10-28/enemy-tests.md#血条相机范围屏幕禁射与尸体保留2026-10-25)。

<a id="躲藏倾向与squad评分接口2026-10-26"></a>

躲藏倾向与Squad评分接口（2026-10-26）：[整理前对应章节](history/2026-10-28/enemy-tests.md#躲藏倾向与squad评分接口2026-10-26)。

<a id="近战破绽与线性爆头2026-10-27"></a>

近战破绽与线性爆头（2026-10-27）：[整理前对应章节](history/2026-10-28/enemy-tests.md#近战破绽与线性爆头2026-10-27)。

<a id="霰弹模式2026-10-25"></a>

霰弹模式（2026-10-25）：[整理前对应章节](history/2026-10-28/enemy-tests.md#霰弹模式2026-10-25)。

<a id="霰弹禁止向圆心偏移2026-10-26"></a>

霰弹禁止向圆心偏移（2026-10-26）：[整理前对应章节](history/2026-10-28/enemy-tests.md#霰弹禁止向圆心偏移2026-10-26)。
