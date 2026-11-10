# 测试入口、选择与结果判断

本页说明如何查询和运行已有验证，以及如何解释结果。AI 的真实场景、行为／性能边界见[敌人验证](enemy-tests.md)，模块职责见[项目结构](project-layout.md)。本轮文档整理不代表重新执行全部游戏测试。

## 当前五关定向记录

2026-11-05 商店网格布局：`shop_board_test` 扩至 39/39，验证商品区为 `GridContainer`、默认 3 列、
6 个商品自动占两行、隐藏商品不创建卡片，以及可用宽度变化时在 3／2／1 列之间切换。
`shop_flow_test` 与 98 项 `campaign_flow_test` 保持通过，确认网格改造没有改变购买、暂停、
武器覆盖和死亡退款行为。`run_regressions.py --check` 为 `Catalog OK`；已知 macOS 证书诊断和既有 UID 回退警告仍存在。

2026-11-04 货币商店、任务金额与检查点退款：蓝色商店 NPC 取代三选一。定向专项均以退出码 0 通过——
`shop_catalog_test` 30 项（初始三商品、顺序、按 ID 查询、重复 ID 过滤、非正效果数值与武器商品校验）、
`shop_state_test` 42 项（货币增减、一次性任务发奖、检查点退款／一次性购买回滚／入关快照）、
`shop_weapon_test` 27 项（`replace_weapon_slot` 校验、主副槽覆盖与当前关重试保留已购枪）、
`shop_board_test` 30 项（面板隐藏、ALWAYS、行渲染、购买意图回传、按钮禁用与武器槽位禁用）、
`shop_flow_test` 92 项（真实酒馆打开商店、三初始商品购买、武器解锁与一次性隐藏、余额不足、空目录／全锁定不暂停、交易顺序退款、暂停所有权、死亡关闭与边界拒绝）、
`quest_money_reward_test` 11 项（默认与主线 100、无奖励支线 0、只发一次、付费支线同步当前检查点）。
流程专项 `campaign_flow_test` 98 项、`campaign_checkpoint_test` 17/17、`scene_director_test` 150/150、
`level_flow_test` 87/87 全部通过；兼容专项 `reward_board_test` 14/14、`campaign_quest_task_test` 32 项通过。
`run_regressions.py --check` 为 `Catalog OK`，`git diff --check` 无输出。

本轮已知基线诊断（均不影响上述退出码）：macOS 每次启动都报告
`get_system_ca_certificates` 的 `Condition "ret != noErr"`；加载保存关卡时出现既有 `ext_resource, invalid UID`
回退到文本路径的警告（`camera_occlusion_demo.tscn`、`enemy/cooperation/intel_only.tres`、
`weapons/enemy_test_melee.tres`）；`shop_catalog_test` 在故意制造重复 ID 时输出一次预期诊断。旧逐关奖励验收测试
`reward_npc_test`、`quest_encounter_loop_test`、`reward_per_level_test`
已退役，不再计入 systems 清单；不据此宣称完整 systems 组全绿。

2026-11-04 二选一重生与酒店检查点：新增 `campaign_checkpoint_test` 9/9，验证最近完成关卡的系统进度和奖励领取记录回退、更早奖励保留，以及完成时玩家快照恢复。`campaign_flow_test` 扩至67/67，使用真实主场景、奖励 NPC/三选一面板和关卡验证“领取第1关系统进度奖励 → 解锁并进入第2关 → 死亡 → 返回酒店”后重新开放第1关三选一、锁回下一关入口并恢复完成时玩家状态；另一条真实流程验证首关未完成时死亡返回酒店仍保留任务接取且可重新进入第1关。`scene_director_test` 扩至149/149，覆盖真实死亡界面的两个按钮、无 LevelFlow 条件、酒店路径、事务式检查点恢复、错误提示与加载失败后切换回当前关重开。直接专项 `level_flow_test` 87/87、`player_health_test` 30/30、`weapon_slots_test` 35/35 通过，`reward_npc_test`、`reward_per_level_test`、`quest_encounter_loop_test` 亦通过；`run_regressions.py --check` 为 `Catalog OK`。本轮仍出现 macOS root certificate store 诊断和既有资源 UID 回退警告，直接专项进程均以0退出；不把该诊断记为干净输出，也不宣称统一系统组全绿。

2026-11-02 五关任务链、逐关奖励与 Debug 一键通关：新增 `campaign_quest_task_test` 22/22，验证任务面板五条主线、A 解锁后的进行中状态和返程后的完成状态。新增 `reward_per_level_test` 39/39，验证第1～5关分别开放一次三选一、领取状态互不影响，以及每关独立标题、说明和数值配置。`debug_complete_level_test` 现为10/10，验证按钮受 Debug 总开关控制、只完成当前关、重复点击不重复发信号、开放返程门、保持可操作且不直接切场景。`quest_conditions_test` 扩至 19/19，覆盖整数状态字段下限条件。

2026-11-02 五关酒馆往返与跨关状态：`campaign_flow_test` 46/46，覆盖五关返程门、A 逐关解锁、门口动态目标和跨关生命/当前槽位/双武器/双弹匣/共享备弹/医疗包；死亡仍重开当前关并恢复该关配置。`level_flow_test` 现为87/87，使用五张真实保存地图和真实敌人死亡逐关清场，验证每关只开放返程门、返回酒馆、与 A 交互后再进入下一关，第5关结束后停在酒馆。`player_health_test` 30/30 与 `weapon_slots_test` 35/35 保持；旧波次卸载警告仍存在。

2026-11-03 合并 upstream/main 后定向复验：`scene_director_test` 137/137、`scene_event_node_test` 99/99、`scene_reinforcement_test` 111/111、`level_flow_test` 87/87、`debug_complete_level_test` 10/10、`player_health_test` 30/30、`player_medkit_lifecycle_test` 20/20、`weapon_slots_test` 35/35、`enemy_wave_test` 80/80、`enemy_wave_events_test` 118/118，`campaign_flow_test` 全部通过。`run_regressions.py --check` 为 `Catalog OK`。统一系统组在当前 macOS 环境把 `get_system_ca_certificates` 的 `Condition "ret != noErr"` 判为错误，并同时列出既有移动输入、Debug Overlay 与声音专项失败，因此该轮报告为0/29；上述直接专项进程均以0退出，不能据此宣称整个系统组全绿。

2026-11-02 酒馆结算奖励 NPC：`reward_npc_test`，17/17 验证竞技场清场不再弹窗、完成后按 E 打开三选一、领取状态跨酒馆重载保留，以及第1关已领取后第2关仍能重新打开；`quest_encounter_loop_test` 22/22 覆盖急救包／弹药／系统进度三条路径，`reward_board_test` 14/14 保持单次选择。兼容控制器 `encounter_controller_edge_test` 改为隔离夹具，独立覆盖未完成关卡、死亡、缺面板、外部暂停和重复领取；该测试会主动验证缺失面板拒绝路径，因此保留为 standalone special。真实主场景 `stage_system_test`、`quest_portal_test`（10/10）与 `combat_clear_signal_test`（9/9）通过。`interaction_test` 仍为 6/7，唯一失败是文档已记录的“离开后按 E 不触发”，修改前基线相同。

2026-10-27 接敌派发：`squad_dispatch_continuity_test` 使用保存第五关第二波六人队、原训练装备和持续移动玩家，检查完整玩家胶囊路径、首次整表派发／真实移动时间、全警戒和全员无实际动作窗口、实际移动／挥击及原P99／峰值门槛。`-- --contract-only` 单独运行14项目标更新、成员候选完成、提前事务拒绝及搜索隔离边界；`-- --trace` 追加前180帧准备／组合／提交记录。原始失败、最终结果与性能限制见[敌人测试](enemy-tests.md#接敌派发空窗2026-10-27)，不以“任务版本没变”单独认定全队停工。

## 验证原则

- 优先验证用户遇到的实际问题和本次直接影响的接口；必要检查通过后停止，不默认跑全量。
- 自动检查不能否定真实试玩问题，也不能替代输入手感、模型和画面检查。
- 保留原断言、时间和性能门槛；资源配置与旧夹具不一致时记录原因，不为全绿修改用户数据。
- 分开报告断言、进程退出、脚本／资源诊断、性能和实际渲染。未运行的项目不能记为通过。
- 测试或诊断放在既有 tests／忽略日志目录，不混入运行组件；新增或移除专项同步维护登记。

## 查询实际清单

在仓库根目录使用：

```powershell
python movement_demo/tests/run_regressions.py --list
python movement_demo/tests/run_regressions.py --check
```

`--list` 读取实际登记并区分运行专项和特殊入口；`--check` 只检查覆盖、重复和路径，不启动 Godot，也不证明玩法通过。

| 入口 | 用途 |
| --- | --- |
| `tests/run_regressions.py` | 统一 systems／combat／enemy 分组、清单和本次报告 |
| `tests/run_combat_regressions.py` | 指定玩家／战斗专项，无参数时运行该组默认清单 |
| `tests/enemy/run_enemy_regressions.py` | 指定敌人专项，无参数时运行敌人默认清单 |
| `tests/regression_runner.py` | 共用进程执行、日志、超时和失败判定，不是独立游戏脚本 |

## 运行选定专项

将路径替换成实际 Godot 控制台程序位置。例如鼠标锁定与跟枪：

```powershell
python movement_demo/tests/run_combat_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe target_switch_test directional_tracking_test
```

按组运行使用 `run_regressions.py --godot <程序路径> --suite combat`，可以重复 `--suite` 选择组；省略分组会运行全部运行组，应在需要时明确使用。输出目录可通过统一入口的 `--output` 指定。

带场景参数的专项使用 Godot 原生入口，参数放在 `--` 之后。不同 AI 专项的参数和时间预算见[敌人验证](enemy-tests.md)，不要把所有 `.gd` 文件直接遍历运行。

## 按功能选检查

| 改动 | 优先入口／范围 |
| --- | --- |
| 鼠标辅助、换锁、转身 | `target_switch_test`，相关可见性／战斗兼容 |
| 跟枪、收敛、受击精度 | `directional_tracking_test`、`aim_convergence_test`、`aim_disruption_test` |
| 爆头与近战破绽 | 爆头、执行及 `melee_headshot_opening_test`，按需敌人状态专项 |
| 装备、弹药、装填 | 武器槽、玩家换弹／接续、霰弹装填、`ammo_drop_test` |
| 生命与治疗 | `player_health_test`、`player_medkit_test`、`player_medkit_lifecycle_test` |
| 相机与独立复用 | `player_camera_test`、`player_scene_reuse_test`、`camera_occlusion_test` |
| 五关、检查点与波次 | `campaign_checkpoint_test`、`campaign_flow_test`、`level_flow_test`、敌人波次专项；使用真实保存场景验证 |
| 场景调度与编辑器接线 | `scene_director_test`、`scene_event_node_test`、`enemy_wave_events_test`；无Wave/无Guide、暂停拥有者、事件过滤/失效、两个死亡按钮、加载失败重试 |
| 增援与独立演出 | `scene_reinforcement_test`、`presentation_camera_test`；真实生成屏障、手动Marker3D、取消/返回；相机专项另有真实渲染模式 |
| 任务与交互 | systems 中条件、任务、阶段、面板、唱片机与交互专项 |
| 货币商店与任务金额 | `shop_catalog_test`、`shop_state_test`、`shop_weapon_test`、`shop_board_test`、`shop_flow_test`、`quest_money_reward_test` |
| UI、检查器、美术 | 对应编辑器／渲染入口，不能只用 headless 代替 |
| `systems` | 移动、奔跑、NPC 交互、听觉、声音模式、Debug、表现接口／复位、对话文件扫描，以及任务条件、五关任务链、阶段接线、任务面板、唱片机支线、五关酒馆往返、跨关玩家状态、货币商店（目录／状态／武器／面板／流程）、任务金额、Debug 一键通关、奖励板兼容；由统一入口登记 |
| `combat` | `tests/run_combat_regressions.py` 的原玩家战斗清单 |
| `enemy` | `tests/enemy/run_enemy_regressions.py` 的原敌人清单 |

酒馆传送门专项检查正式切换后的 `World3D` 中性回退环境；关卡流程专项使用真实五关逐波清敌，检查每关返程门、A 解锁、动态门口传送和当前关重开。检查点专项验证死亡回酒店会恢复最近完成任务时的进度、奖励资格与玩家状态。当前五关仍使用返程门，不依赖按钮直接切关；SceneDirector 的加载能力由独立场景调度专项验证。

## 特殊入口与会写入的维护工具

| 类型 | 运行要求 |
| --- | --- |
| 检查器保存、原生撤销 | 对应 `--editor --script` 或 Godot AI 编辑器夹具，按实际清单 SPECIAL 说明执行 |
| 模型、准星、全屏和截图 | 实际渲染实例及对应 capture 参数，检查生成画面 |
| `*_fixture.gd`、动作替身 | 由所属测试装配，不作为独立专项 |
| 战斗兼容的子脚本 | 由 `combat_compatibility_test` 调度，避免重复算通过数量 |
| `bake_arena.gd`、`bake_levels.gd` | 写导航的维护命令，绝不自动当作回归运行 |

保持旧测试替换关系可追溯；旧竞技场条目到当前敌人专项的映射保留在历史记录。新测试必须以实际可运行文件为准。

## 如何判断通过

共用运行器要求退出码为0，且没有 `SCRIPT ERROR:`、行首 `FAIL` 或 `ERROR:`；仅原有 root certificate store 诊断按运行器既定规则例外。超时、启动失败或脚本解析错误均为失败。断言全部通过但存在资源／RID清理错误时，不能记作严格无错误通过。

输出包含每项 `.log`、`_stdout.log` 和 `results.json`；运行器记录首批错误，完整证据看原日志。日志放在 `movement_demo/logs/`，由 `.gdignore` 隔离，不提交缓存、截图或诊断副本。Dialogue Manager 的扫描路径保持只指向实际对话源。

场景调度的真实鼠标交接需渲染模式，不能用headless证明鼠标捕获。可运行：

```powershell
E:/Godot/Godot_v4.7.2-stable_win64_console.exe --path movement_demo --script res://tests/scene_reinforcement_test.gd -- --mouse-ownership-only
```

它检查真实右键瞄准捕获→增援暂停→暂停期间松开→返回或死亡后无旧捕获残留。默认headless分支保留真实生成/AI/暂停/镜头测试，并明确跳过此显示服务相关分支。

## 当前需要保留的验证边界

以下是已有验证记录，日期和原输出见[历史记录](history/2026-10-28/testing.md)及[敌人验证](enemy-tests.md)：

| 范围 | 已有记录与限制 |
| --- | --- |
| 鼠标辅助 | 最近专项250/250、可见性19/19、兼容77/77；击杀续接使用真实射线与移出战斗组的伤害回调夹具，不等于完整敌人生命／AI流程验收 |
| 固定低速转身 | 该阶段换锁196/196、方向跟枪56/56；不能把转身等效速度重新插值成高速目标损耗 |
| 武器槽／自动开火 | 旧夹具引用已删除副武器，或假定主枪为单发；当前保存资源可能已改为自动枪 |
| 霰弹 | 旧断言假定图样零均值、固定弹匣或 RANDOM 模式；用户图样／模式修改会改变这些假设 |
| 检查器 | 部分原生撤销刷新项和退出时资源诊断已有失败；功能断言与干净退出分别报告 |
| 团队 AI | 部分行为已通过，整队P99性能仍有未达标记录；不能以任务表或派发成功代替真实行动及原预算 |
| 输入与表现 | 多DPI、不同鼠标设备、密集交战及新美术仍需实际试玩 |

本轮仅整理说明与链接，不重新评价这些历史结果，也不修改任何断言、资源或性能阈值。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](history/2026-10-28/testing.md)。历史通过数不代表当前本地配置已重新验证。

## 旧章节引用

<a id="需要其他环境的测试"></a>

需要其他环境的测试：[整理前对应章节](history/2026-10-28/testing.md#需要其他环境的测试)。

<a id="验证范围与试玩优先级"></a>

验证范围与试玩优先级：[整理前对应章节](history/2026-10-28/testing.md#验证范围与试玩优先级)。
