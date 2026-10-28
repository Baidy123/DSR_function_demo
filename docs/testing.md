# 测试入口、选择与结果判断

本页说明如何查询和运行已有验证，以及如何解释结果。AI 的真实场景、行为／性能边界见[敌人验证](enemy-tests.md)，模块职责见[项目结构](project-layout.md)。本轮文档整理不代表重新执行全部游戏测试。

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
| 五关与波次 | `level_flow_test`、敌人波次专项；使用真实保存场景验证 |
| 场景调度与编辑器接线 | `scene_director_test`、`scene_event_node_test`、`enemy_wave_events_test`；无Wave/无Guide、暂停拥有者、事件过滤/失效、加载失败重试 |
| 增援与独立演出 | `scene_reinforcement_test`、`presentation_camera_test`；真实生成屏障、手动Marker3D、取消/返回；相机专项另有真实渲染模式 |
| 任务与交互 | systems 中条件、任务、阶段、面板、唱片机与交互专项 |
| UI、检查器、美术 | 对应编辑器／渲染入口，不能只用 headless 代替 |

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
