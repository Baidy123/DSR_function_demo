# 测试入口与维护

## 验证范围与试玩优先级

2026-10-23 用户明确要求：必要回归可以做，可有可无且耗时的检查不做。优化阶段以当前保存地图中的真实问题复现、修改前后对照及直接受影响的行为为主，不默认运行全量回归来建立基线。

- 开始验证前明确本次要回答的问题，优先使用已有现场入口。自动检查通过不能否定用户试玩发现的问题，也不能替代实际行动与手感验收。
- 修改执行行为时检查对应现场；修改跨模块协议时补查相关身份、预约或清理边界。仅新增或修改确实能捕获本次故障的断言，不为内部函数搬迁逐个补测试。
- 必要检查通过后结束验证。只有新修改、失败或明确的关联风险才扩大或重复检查；不为提高通过数量运行无关套件，不顺带修理无关旧夹具。
- 保留原断言、时间与性能门槛，原有失败仍如实记录；未运行项目不计作通过。下文全量与分组命令是可用入口，不是每次任务的必跑清单。

## 本次协调器定向入口

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path movement_demo --script res://tests/enemy/squad_command_runtime_test.gd -- --level=1 --search
```

将 `--level=1` 改为 `2` 检查强协同实际屏障，`0` 检查个人 Utility；`--crowded` 复现三人墙角入口，`--blocked-exit` 用实例内实体封堵一端，`--mixed` 检查近战/远程及不同训练。运行中不注入任务接受、视野、到位或开火结果。图形模式追加 `--capture-debug` 保存当前路线画面到忽略目录。测试不写回保存场景、训练或武器资源。

将 `--search` 换成 `--patrol`，配合 `--level=1` 或 `--level=2`，单独运行20秒未警戒巡逻。此分支检查前后两段真实移动、每人到达多个不同巡逻点、持续团队归属及身体间距，用于防止到第一个点后停住。

`--level=2 --contact-edge` 使用现场捕获的真实站位，验证一人看见玩家但枪口无合法瞄准点时，队伍能够换位并在8秒内实际射击；不注入无效瞄准、目击或任务结果。

将 `--search` 换成 `--melee`，配合等级1或2检查远程兵贴身自卫：保存地图中玩家逐一接近三名成员，统计实际命中、击退、非零前摇与正常收招，检查挥击期间任务保持、移动/射击/换弹互斥、收招后任务恢复，以及真实换弹被打断后的续换。最后在实例中关闭武器近战并再次贴近，检查禁止挥击。角色由协调器正常分配，贴身后可能从侧翼变为警戒等岗位；测试核对模板的三种分工及三名成员实际命中，不伪造固定岗位或命中结果。

`--level=2 --search` 逐帧核对每轮搜索参与者的真实准备位置、放行及先完成者保持岗位，不只累计“出现过等待”。追加 `--handoff` 会在实例里放置第二道墙，将玩家移到墙后，专门验证连续两轮同步和真实完成后的等待；该用例不承诺发现被第二道墙遮挡的玩家。原保存地图及入口封堵用例仍检查8秒内重新目击，接敌和完整搜索采样分别检查整队 AI+区域 P99 <16毫秒、峰值<50毫秒。

纯值组合边界为 `squad_command_contract_test.gd`。旧协调器的候选注入、advisory/个人接管和旧任务表专项已移除，明确清单与承接关系见 [敌人测试](enemy-tests.md#当前回归)。仍适用的共享情报、友军枪线、个人执行及压制检查保留。旧报告中的套数不代表本次全量通过。

## 查询当前清单

在仓库根目录运行：

```powershell
python movement_demo/tests/run_regressions.py --list
python movement_demo/tests/run_regressions.py --check
```

`--list` 直接读取敌人与玩家运行器的 `TESTS`，同时列出系统专项及需要其他运行环境的脚本；数量以此输出为准。`--check` 检查遗漏、重复与失效路径，不启动 Godot，也不表示游戏测试通过。新增或移除测试时同步维护清单与其调用关系。

## 运行游戏回归

地图维护命令 `tests/bake_levels.gd` 只重烘五张独立地图的导航，已列入维护脚本排除清单，不作为回归运行；用法与实体轮廓排除说明见 [关卡地图](gameplay/LEVEL_MAPS.md)。

```powershell
python movement_demo/tests/run_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe
python movement_demo/tests/run_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe --suite systems
python movement_demo/tests/run_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe --suite combat --suite enemy
```

| 分组 | 内容与清单来源 |
| --- | --- |
| `systems` | 移动、奔跑、NPC 交互、听觉、声音模式、Debug、表现接口／复位、对话文件扫描，以及任务条件、任务状态、阶段接线、任务面板和唱片机支线；由统一入口登记。可选交互物原型测试仅在本地文件存在时加入 |
| `combat` | `tests/run_combat_regressions.py` 的原玩家战斗清单 |
| `enemy` | `tests/enemy/run_enemy_regressions.py` 的原敌人清单 |

默认按系统、玩家、敌人顺序串行运行。统一入口为每次运行创建独立的 `logs/regressions/<时间>/`，分组保留 `results.json`、完整进程输出和 Godot 日志，总报告为 `report.json`。`--output` 可指定一个尚不存在的目录，避免覆盖旧结果。普通脚本超时仍为75秒；新的保存地图小队连续实战专项为180秒，旧协调器专项已从清单退出。

原有单组／定向命令仍可使用：

```powershell
python movement_demo/tests/run_combat_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe dialogue_cache_test interaction_test
python movement_demo/tests/enemy/run_enemy_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe enemy_basic_capabilities_test enemy_scene_test
```

两个旧入口继续写各自固定日志目录；需要保留多轮结果时使用统一入口或另存日志。共用进程执行及判错逻辑位于 `tests/regression_runner.py`：非零退出、超时、启动失败、`SCRIPT ERROR:`、`FAIL `／`FAIL:` 和普通 `ERROR:` 均判失败；仅沿用此前针对 `root certificate store` 的例外。

游戏回归必须保留实际运行基线。用户场景、武器或训练的本地修改可能与某些旧夹具的固定预期不同；保留失败及必要的修改前对照，不通过覆盖用户资源、跳过失败或放宽断言取得全绿。当前敌人整体性能与旧行为未完成项见 [敌人测试](enemy-tests.md#当前回归)和 [待办](TODO.md)。测试登记、局部通过及完整通过是不同事实。

PR #2 的五套任务／阶段测试已登记到 `systems`。2026-10-19 在 PR 与 `main` 的独立合并工作树中，任务条件、任务状态、阶段接线、任务面板、唱片机支线、交互物、Debug、相机共8/8套通过；竞技场场景整合与敌人场景共2/2套通过，主场景180帧启动无脚本或引擎错误。清单检查与运行器自身8项检查通过。空缓存首次导入出现已有的字体导入前引用错误，第二次导入退出码0且无错误。该记录仅代表本次合并定向验证，不代表完整系统、战斗或敌人回归全绿。

## 需要其他环境的测试

| 类型 | 入口与运行方式 |
| --- | --- |
| 兼容子检查 | 瞄准模式、散布、移动精度、武器模式参数、第一碰撞物由 `combat_compatibility_test` 调用；`range_reset_test` 由 `presentation_range_reset_test` 调用，均不重复计数 |
| 编辑器独立脚本 | `presentation_editor_test`、`weapon_fire_mode_inspector_test`、`enemy/enemy_training_inspector_test` 使用 `--headless --editor --script`；编辑器退出时的资源提示与断言结果分别记录，见 [敌人测试](enemy-tests.md)及 [表现说明](gameplay/PRESENTATION.md) |
| 已打开编辑器的测试 | `test_cover_instance_save`、`test_weapon_mode_inspector`、`enemy/test_enemy_probability_inspector` 依赖 Godot AI 测试工具和相应打开场景；操作编辑器节点，不进入普通批处理 |
| 图形输入专项 | `player_health_ui_test` 在独立渲染的 Main 中调用 `await script.new().run(scene)`，依赖真实 GUI 输入，见 [生命与界面](gameplay/PLAYER_HEALTH.md) |
| 尚待迁移的旧夹具 | `combat_test`、`combat_refinement_test`、`range_door_test`、`target_health_test` 保留原脚本及有效断言。前两者含旧移动精度预期，后两者依赖固定出生位置／武器弹药；需逐项迁移后才能纳入批处理，不计为当前已自动覆盖 |
| 辅助脚本 | `presentation_fixture`、`enemy_fire_fixture`、`modular_probe_action` 由正式测试加载 |
| 维护工具 | `bake_arena.gd` 会写入导航资源，是显式烘焙命令，不属于回归测试 |

不要通过通配符直接执行整个 `tests/`；脚本继承、辅助资源、编辑器环境与导航写入工具的运行方式不同。

运行器自身检查不需要 Godot：

```powershell
python -B movement_demo/tests/regression_runner_test.py
```

## 旧竞技场测试的替代关系

2026-10-13 移除未被运行器调用的 `tests/arena_test.gd` 及其 UID。它仍访问身体上已迁走的感知、记忆和状态接口，并要求交战搜索最终停止。下表按原断言列出迁移或已有覆盖；这些映射不替代实际运行结果。

| 原断言 | 当前覆盖 |
| --- | --- |
| `arena_instanced_in_main`、`navigation_baked` | `enemy_basic_capabilities_test` 检查 Main 中的竞技场与真实已烘焙导航；`enemy_scene_test` 覆盖绑定、激活与资源生命周期 |
| `clear_view_detects_player`、`behind_enemy_not_detected` | `enemy_basic_capabilities_test` 使用 `AI/Perception` 检查真实正面视线及近身范围外的背面拒绝 |
| `visible_player_is_remembered`、`wall_blocks_vision`、`hidden_player_does_not_update_memory` | `search_persistence_test`、`search_reacquisition_test` 保留真实目击、遮挡失视及隐藏坐标不刷新记忆 |
| `enemy_visits_last_seen_position`、`navigation_detours_around_wall`、`navigation_reaches_far_side` | `search_evidence_test` 的真实到点推进，以及 `search_reacquisition_test`／`search_pursuit_test` 的实际绕墙、重新目击与攻击；故障恢复由 `search_navigation_recovery_test` 覆盖 |
| `search_eventually_stops` | 旧交战搜索终止预期已被持续警戒要求替代；`search_persistence_test` 检查跨时限、多轮实走、死亡／离场复位及纯声音调查仍可结束 |
| `dead_enemy_stops_and_unlocks` | `enemy_basic_capabilities_test` 验证死亡身体拒绝移动并退出 `combat_target`；`search_persistence_test` 检查死亡清理搜索 |

## 对话文件扫描与日志隔离

`logs/.gdignore` 同时作为 Godot 与 Dialogue Manager 文件扫描的目录边界。验证副本保存在该目录下；项目的 `internationalization/locale/translations_pot_files` 只登记实际对话源，不保存副本路径。插件本地兼容补丁及升级复核见 [LOCAL_CHANGES.md](../movement_demo/addons/dialogue_manager/LOCAL_CHANGES.md)。

## 2026-10-13 首批维护验证

- 运行器自身8/8项通过，覆盖脚本报错但退出0、两种失败前缀、非零退出、超时、启动失败、原证书例外及完整清单检查。原敌人／玩家 `TESTS` 内容和顺序逐项一致。
- 对话扫描相同夹具修改前4/6、修改后6/6；两份隔离工程都在日志目录放入对话副本，编辑器重扫后原版仍登记该文件，修复版不登记。本地项目清除了443条日志副本路径，保留3条实际对话源；已有提交配置本身没有这些日志条目，因此没有将本地配置的其他差异顺带提交。
- 本地工程的隔离副本定向系统／玩家检查4/5，NPC 交互的“离开后按 E 不触发”失败在修改前副本也复现。四套敌人专项均被本地 `Enemy2/3/4` 与旧固定 `Enemy` 路径不一致阻断；原基础执行和场景测试的限定帧数启动对照复现同样错误，这不是完整基线回归。原场景及资源保持本地状态。
- 仅含本轮维护补丁的独立提交副本：统一入口完整玩家战斗26/26；敌人基础执行29/29、场景28/28、持续搜索22/22、重新发现34/34，共4/4套、113项。扫描、弹药、医疗包、区域复位的定向检查通过；上述NPC交互失败仍存在。未运行系统组全套、完整敌人回归或重新宣称性能达标。
- 首次空缓存编辑器启动在修改前／修改后副本均出现字体导入前引用与 Dialogue Manager 初始主题设置错误；完成导入后的第二次启动均无这些错误。首次输出保留，未扩大运行器错误过滤。

本轮日志、首次失败、前后对照与汇总保存在本地 `movement_demo/logs/structure_maintenance_20261013/`，不提交 Git。后续 AI 内部拆分和角色场景复用尚未实施。
