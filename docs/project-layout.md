# 项目结构与模块职责

本页说明当前目录、场景与代码归属。功能和常用接口见[项目总览](../README.md)，专项用法见[文档导航](README.md)。路径以 `movement_demo/` 为根；现有节点路径、资源引用和脚本 UID 是复用边界，文档整理不迁移它们。

当前合并基线同时保留本地五关任务／奖励与 upstream 场景调度结构。`LevelFlow` 在清场后只启用本关 `TavernReturnPortal`；返程门写入 `completed_level` 与一次性玩家快照并返回酒馆，A 更新 `available_level` 后门口 `QuestPortal` 才指向下一关。结果按钮和自动加载是 SceneDirector 的可复用能力，当前五关实际没有使用“清场后自动进入下一关”。

五关任务和奖励分别由 `resources/stages/stage_table_template.tres`、`resources/rewards/level_rewards.tres` 保存；`QuestCondition.int_at_least()` 提供整数下限条件，`GameState.claimed_reward_levels` 按关记录一次领取，`RewardBoard` 只回传奖励选择。跨关快照由 `player_campaign_state.gd` 搬运，死亡重开不消费旧关快照。

敌人、武器、弹药、爆头、波次、相机与表现模块的具体职责见后文和对应专项；逐阶段实施过程保存在[历史记录](history/2026-10-28/project-layout.md)，不作为当前接口说明。

## 目录

```text
movement_demo/
├── project.godot                 工程与输入配置，主入口为 scenes/main.tscn
├── scenes/
│   ├── main.tscn          酒馆主场景，F5 入口；含任务、奖励 NPC、竞技场与关卡传送门
│   ├── arena.tscn         战斗区域与敌人实例
│   ├── enemy/             公共 enemy.tscn，types/兵种继承场景，levels/lvl_N/关卡预设
│   ├── player/            独立 player.tscn、player_camera_rig.tscn 与战斗／生命／装备子场景
│   ├── world/             掩体、训练区域、墙体、交互物与场景入口
│   │   ├── levels/        Lvl_1–5 独立地图，含区域、导航、已保存小队／波次及地图实体
│   │   └── objects/       具体交互物：酒馆关卡门、五关返程门、酒杯、终端、唱片机
│   ├── presentation/      模型包装场景和独立接口演示
│   ├── effects/           共用命中特效管理器和粒子场景
│   └── ui/                对话、任务／奖励、关卡流程与游玩说明场景
├── scripts/
│   ├── enemy/             身体、AI 协调、装配与评分入口
│   │   ├── actions/       默认行为、战术动作和共用动作执行组件
│   │   ├── config/        兵种、训练、动作定义及参数资源脚本
│   │   └── services/      感知、记忆、上下文、射击、搜索提示/覆盖和空间查询
│   ├── player/            玩家移动、战斗、生命和装备
│   ├── weapons/           武器数据与弹药执行
│   ├── rewards/           关卡、选项与奖励表资源脚本
│   ├── world/             掩体、训练靶、区域、门、NPC、交互物与屏障
│   │   ├── quest_portal.gd       按任务与 A 解锁进度进入对应关卡
│   │   ├── tavern_return_portal.gd 记录关卡完成与玩家快照并返回酒馆
│   │   └── interactions/  交互效果基类、注入上下文与各效果实现
│   ├── ui/                对话、锁定准星、任务／奖励、关卡流程与游玩说明
│   ├── debug/             调试开关、协调器路径；声音圈及旧攻击区域预览默认关闭
│   └── systems/           场景调度、关卡流程、相机、公共状态、声音数据与正式场景切换
│       ├── stage/         阶段、任务与 NPC 状态控制器
│       ├── presentation/  模型挂载、动画配置与表现状态
│       └── effects/       命中快照、表面配置与特效生命周期
├── resources/
│   ├── enemy/
│   │   ├── actions/       可配置动作 .tres
│   │   ├── units/         兵种模板 .tres
│   │   ├── cooperation/   三档团队意识模板与旧区域兼容绑定 .tres
│   │   └── training/      训练配置 .tres；levels/lvl_N/保存关卡独立训练
│   ├── weapons/           玩家与敌人的武器 .tres
│   ├── player/            玩家医疗包效果与时间等静态配置
│   ├── noise/             移动声、枪声配置
│   ├── animations/        动画对应表
│   ├── effects/           表面命中特效配置
│   ├── rewards/           五关独立的三选一奖励配置
│   ├── navigation/        烘焙导航资源
│   ├── stages/            阶段／任务／NPC 状态规则配置表
│   └── dialogue/          NPC 对话、导入元数据与原有剧情源文件
├── tests/
│   ├── enemy/             敌人测试、公共辅助和回归运行器
│   ├── run_regressions.py  统一清单检查与分组回归入口
│   ├── regression_runner.py 共用进程执行与失败判定
│   └── 其他系统测试与测试资源
├── addons/                编辑器插件及第三方依赖
└── logs/                  运行日志与验证输出，Git 忽略
```

仓库根的 `docs/gameplay/` 保存现行使用说明，`docs/history/` 保存整理前的实施和验证记录；`docs/superpowers/plans/`、`specs/` 保持原计划／设计依据。

## 玩家与武器

`scenes/Lvl_1.svg` 至 `Lvl_5.svg` 是关卡俯视参考图；`scenes/world/levels/lvl_1.tscn` 至 `lvl_5.tscn` 是独立地图，根节点复用原区域控制器，含 CombatZone、已保存 Squad／波次与 NavigationRegion3D。地图实体在导航区域的 Environment 下，内部掩体继承原预制场景，外围墙和地板为普通静态碰撞体。各图独立引用 `resources/navigation/lvl_N_navigation.tres`。维护命令 `tests/bake_levels.gd` 解析完整碰撞并用盒体轮廓排除实体内部及顶部导航，不由游戏加载。尺寸、编号差异及重烘方式见 [关卡地图](gameplay/LEVEL_MAPS.md)。

五张地图当前均保存玩家、相机、灯光、小队和敌人波次，可单独 F6 试玩；实际人数与部署以场景保存值为准。`EnemyWaves` 入口按用户要求改名 `SceneDirector`，但 Wave／Squad 层级保持，区域、导航、角色与资源 UID 不迁移。

阶段、任务与 NPC 状态规则集中在 `scripts/systems/stage/`：阶段判定、任务状态与状态解析各一个控制器，配置表资源脚本与 `resources/stages/` 下的 `.tres` 配套维护。控制器挂在 `main.tscn`、按 group 互相查找，不新增全局单例；NPC 只按 `npc_id` 与接收接口被驱动，不反向依赖控制器。见 [阶段与任务](gameplay/STAGE_STATE.md)。

正式场景切换统一经过 `scripts/systems/scene_transition.gd`。该入口在释放当前场景前，把 `World3D.environment` 与 `fallback_environment` 恢复为显式中性环境，避免 GL Compatibility 在目标场景没有 `WorldEnvironment` 时沿用上一场景的环境光。酒馆关卡门、五关返程门和死亡重开都使用这一入口；目标场景自身配置的 `WorldEnvironment` 仍可在加载后覆盖该中性回退。

`scripts/debug/coordinator_paths.gd` 保留 DebugSettings 入口，使用世界空间 Mesh 绘制 RTS 路线、箭头和站位，以及面积观察状态、责任预约和未来路线。每秒最多十次读取公开副本，不调用导航、规划或补写观察；成员颜色在死亡减员后保持稳定。当前 `main.tscn` 按用户确认保留任务面板、奖励面板及交互演示物；五关场景不挂载这套酒馆任务节点，交互组件仍可由 `tests/interaction_fixture.gd` 独立装配验证。五关清场后仍只开放返程门，回酒馆与 A 交互后才解锁下一关。

| 文件／组件 | 职责与接口边界 |
| --- | --- |
| `player/player.gd` | 真实移动、碰撞、耐力、姿态和翻越；移动前后调用 Combat 的帧入口 |
| `player/player_combat_v3.gd` | 锁定、鼠标辅助、转身、准度、扳机、当前枪弹药、射击和玩家近战 |
| `player/target_switch_gesture.gd` | 仅累计鼠标净位移、时间和新输入标记，不持有目标或场景 |
| `player/player_weapon_slots.gd` / Equipment | 装备配置、槽位、每槽运行状态、共享备弹和唯一医疗包库存 |
| `player/player_health.gd` | 生命、伤害、治疗结算、自身失能与死亡通知；场景后续由调度器决定 |
| `player/player_medkit.gd` | 治疗资格、输入中断、冻结参数与计时，向 Health 交付回血 |
| `weapons/weapon_data.gd` | 静态枪械参数、收敛和爆头等纯数值规则；不保存角色运行进度 |
| `weapons/weapon_ammo.gd` | 每枪弹匣与装填计时，玩家／敌人共用；策略由调用方决定 |
| `weapons/shotgun_ballistics.gd` | 弹丸采样、物理射线与近弹几何，伤害归各方射击入口 |
| `weapons/headshot_resolver.gd` | 按实际目标冻结每枪结果与一次破绽消费，再交付受击 |
| `ui/lock_reticle.gd` | 只读准度、目标概率和转身状态，显示准星／菱形／转向标记 |

Equipment 交接当前枪给 Combat；相机订阅 `weapon_changed`，表现订阅真实射击结果。鼠标辅助沿原 Combat 执行，不新增第二份锁定或自由瞄准状态。主动转身固定读取当前武器低速跟枪项，真实目标移动仍独立按原速度插值，两项损耗取较大者。

## 敌人、区域与小队

| 层 | 责任 |
| --- | --- |
| Enemy 身体 | 实际移动、碰撞、枪械、近战、生命及受击；报告执行事实 |
| `enemy/enemy_ai.gd` | 个人决策或团队任务执行，交接原动作、身体与火控 |
| Training / Profile | 感知、搜索、战术参数与动作能力；本场装配按现有冻结规则应用 |
| `enemy/actions/` | 各动作的候选、执行和共同命令提案，沿原生命周期调用 |
| `enemy/services/` | 感知、记忆、路线、规划与有限私有值记录，各服务保持单一职责 |
| `world/squad_controller.gd` | Squad 配置、区域注册与生命周期；Profile 独占团队等级 |
| 小队协调器 | 1／2级团队任务、规划与公共约束；0级及无绑定个人沿原个人决策 |
| `world/shooting_range.gd` | 区域激活、注册、时钟、导航／公共查询及离场复位 |

只有个人分支运行个人 Utility；团队成员即使暂时失败、占用或只剩一人，仍按团队指挥边界执行。身体不选择战术，私有值记录服务不另建调度循环。详细服务契约、训练适用范围和故障处理见[敌人 AI](enemy-ai.md)。

## 波次、关卡与补给

- `world/enemy_wave_controller.gd` 是 SceneDirector 场景入口兼容脚本，原 UID 保留；五关入口已按用户要求改名，Wave/Squad层级不动。`enemy_wave_runtime.gd` 执行模板、合法出生、各波状态、搜索与清理；`enemy_wave_definition.gd` 保存部署、事件节点与手选镜头配置。
- `systems/scene_director.gd` 是入口内部的场景核心，不依赖Wave或PlayGuide；`scene_flow_runner.gd` 推进资源规则与动作，`scene_pause_coordinator.gd` 统一记录拥有者。仅内部核心使用Always，区域和敌人保持可暂停。
- `systems/scene_event.gd` 是可放入场景的事件节点，来源信号或trigger()统一发triggered；`scene_event_trigger/filter/subscription.gd` 适配和过滤，`scene_flow_rule/action.gd` 保存静态配置。接线见[教程](gameplay/SCENE_DIRECTOR.md)。
- `systems/level_flow.gd` 保留五关表和结果视图，`ui/play_guide.gd` 提供可选begin/cancel/finished，`ui/scene_result_view.gd` 绑定原Health死亡UI；它们只显示并报告请求，暂停与加载由核心决定。旧Main的区域在没有入口时为场景玩家绑定同一核心，避免多区域重复接管。五关当前只走返程门闭环；酒馆任务系统读取关卡进度，但不参与 LevelFlow 的返程门与解锁动作。
- `world/ammo_drop_controller.gd` 管理区域掉落选择、数量与生命周期，`ammo_drop_position.gd` 检查合法落点，`ammo_pickup.gd` 显示并执行一次领取。
- `scenes/enemy/levels/lvl_N/` 与 `resources/enemy/training/levels/lvl_N/` 保存各关兵种／训练。共享资源仍可能被跨关引用，修改前核对实际使用者。
- 导航烘焙命令会写资源，属于维护工具；不能作为普通游戏加载流程或默认回归一起执行。

## 相机、表现与内容

相机根 `systems/player_camera.gd` 统一绑定玩家、读取武器 Aim Range、控制视野过渡；`camera_occlusion.gd` 仅处理显式标记装饰的材质副本与还原。CameraGroundAnchor 过滤翻越抬升。保持原 Phantom Camera 跟随和更新关系。

`systems/presentation_camera.gd` 和 `scenes/player/presentation_camera.tscn` 是独立演出相机。目的地由编辑器绑定Marker3D/Node3D；复制可见画面后切入，返回前通过玩家相机的有限同步接口刷新，再切回。原玩家相机不交给总调度每帧移动，遮挡辅助同一时刻只有一个拥有者。

`systems/presentation/` 读取实际状态驱动模型／动画，`systems/effects/` 管理命中快照、表面配置与特效生命周期。表现不改变伤害、枪口、碰撞或 AI；UI 不替代业务状态的唯一写入者。

`world/interactions/` 的效果只通过 InteractionContext 使用注入引用。`systems/stage/` 中阶段、任务和 NPC 状态控制器各自拥有数据，通过只读查询和变化信号协作；普通节点按组绑定，NPC 只按稳定 ID 接收状态。

## 文件与文档维护约束

1. 修改前阅读 README、本页及涉及的专项说明；敌人任务同时检查敌人说明与验证要求。
2. 按既有职责扩展，保留节点路径、资源引用、脚本 UID 和用户配置；新增脚本放入对应职责目录，不把临时诊断放入运行目录。
3. 用户确认的方向是实现依据。不能为了迁就实现改写原设计、放宽测试，或把默认值／建议写成用户逐项确认要求。
4. 功能、接口或职责变化时更新相应当前章节和使用说明。README 保持项目入口，详细参数放专项文档，逐次验证和历史过程单独记录，避免再次堆积成更新流水。
5. 资源只保存配置，实例组件保存运行状态；同一状态只保留一个权威写入入口，UI、相机和诊断读取或订阅。
6. 验证覆盖实际行为及结构约束；历史通过数、运行无错误或一次成功不能替代完整验收。
7. 普通阶段提交、推送及本地修改保护遵循仓库 [AGENTS.md](../AGENTS.md)；不得借文档整理同步远端、覆盖其他任务或改写历史计划。

## 当前奖励接口补充

`main.tscn` 的任务奖励闭环由 `scripts/systems/stage/encounter_controller.gd`、`scripts/world/reward_npc.gd` 与 `GameState` 共同承担：每关返回后与 `RewardNPC` 按 E 交互，控制器按当前 `completed_level` 读取该关奖励并打开三选一。选定后写入对应关卡的 `claimed_reward_levels`，只关闭本关资格。返回酒馆的玩家状态可被奖励直接修改，门口传送门进入下一关前再次捕获，因此治疗和补给会延续。竞技场 `combat_cleared` 不再触发奖励。

奖励面板 `scenes/ui/reward_board.tscn` + `scripts/ui/reward_board.gd` 是默认隐藏的三选一界面；`process_mode` 设为 ALWAYS，因此场景树暂停时仍能处理输入，每次显示只允许发出一个 `reward_selected`。面板本身不写玩家、弹药或进度，只回传所选奖励 id 给遭遇控制器。对应测试有 `tests/reward_npc_test.gd`（NPC 交互与跨重载防重复）、`tests/quest_encounter_loop_test.gd`（三条奖励路径）、`tests/encounter_controller_edge_test.gd`（资格、死亡、暂停和缺面板边界）与 `tests/reward_board_test.gd`（面板单次选择）。

`scripts/world/quest_portal.gd` 是酒馆门口的五关传送门：首次进入仍要求 `task_a` 进行中，之后只读 `GameState.completed_level`／`available_level`，A 未解锁下一关时阻止进入。它按可用关卡更新 `ChangeSceneEffect.scene_path`，交互前捕获玩家状态。原门禁卡、门禁读卡器和屏障资源已删除；任务面板默认隐藏，Tab 切换。

五关实际接入仍按本地确认流程运行：LevelFlow 只开放返程门，`QuestPortal` 在 A 解锁后才指向下一关；SceneDirector 的按钮切关／加载能力仅作为独立场景编排功能保留，不能据此改写当前五关入口。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](history/2026-10-28/project-layout.md)。历史通过数不代表当前本地配置已重新验证。

## 旧章节引用

<a id="文档维护约束"></a>

文档维护约束：[整理前对应章节](history/2026-10-28/project-layout.md#文档维护约束)。
