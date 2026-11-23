# 项目结构与模块职责

本页说明当前目录、场景与代码归属。功能和常用接口见[项目总览](../README.md)，专项用法见[文档导航](README.md)。路径以 `movement_demo/` 为根；现有节点路径、资源引用和脚本 UID 是复用边界，文档整理不迁移它们。

当前合并基线同时保留本地五关任务／货币商店与 upstream 场景调度结构。`LevelFlow` 在清场后只启用本关 `TavernReturnPortal`；返程门写入 `completed_level`、一次性玩家快照和酒馆检查点并返回酒馆，A 更新 `available_level` 后门口 `QuestPortal` 才指向下一关。结果按钮和自动加载是 SceneDirector 的可复用能力，当前五关实际没有使用“清场后自动进入下一关”。

`CampaignSaveService` 是单槽游戏存档的读写边界，默认路径为 `user://campaign_save.cfg`。酒馆内保存由 `SceneDirector.save_game()` 捕获当前 `GameState` 和玩家快照；关卡内保存只写入进入关卡前记录的 `GameState.last_tavern_state`，不读取实时战斗状态。有效存档在下次启动时由自动加载服务应用，`GameState` 以酒馆为恢复场景并标记开场镜头已处理，因此不会在载入存档后重播开场。用户设置仍由 `UserSettings` 独立写入 `user://settings.cfg`。

五关任务与任务金额由 `resources/stages/stage_table_template.tres` 保存，商品目录由 `resources/shop/shop_catalog.tres` 保存；`QuestCondition.int_at_least()` 提供整数下限条件，`QuestDefinition.money_reward` 配置完成时的固定货币，`GameState.rewarded_task_ids` 记录一次性任务发奖。货币商店由 `ShopController` 按目录解析可见商品、复核并执行购买，`ShopBoard` 只回传购买意图；`GameState.money`／`purchased_shop_item_ids` 与酒馆检查点同步。跨关快照由 `player_campaign_state.gd` 搬运；QuestPortal、返程门、死亡重开／回酒馆向导演请求加载，GameState 准备入关状态或最近酒馆检查点，加载获准后才提交关卡进度、商店旗标、货币、奖励记录和玩家快照。旧三选一奖励组件仍保留为兼容代码，不再接入主流程。

医疗包商品使用 `ADD_MEDKIT`、`medkit_data` 与购买数量 `amount`，由 Equipment 的 `can_add_medkits()`／`add_medkits()` 接收入库，沿用唯一库存与状态通知；检查器仅显示当前商品效果对应的资源槽。拥有类商品使用 `ShopItemDefinition.Effect.SET_FLAG` 与 `flag_key`；购买调用 `GameState.grant_shop_flag()`，旗标值由原 `flags` 字典唯一保存。检查点通过 `shop_flags` 捕获和恢复商店登记的旗标，不回滚唱片机等其他玩法旗标。任务面板只展示任务状态，已移除数值进度与进度条。

敌人、武器、弹药、爆头、波次、相机与表现模块的具体职责见后文和对应专项；逐阶段实施过程保存在[历史记录](history/2026-10-28/project-layout.md)，不作为当前接口说明。

## 目录

```text
movement_demo/
├── project.godot                 工程与输入配置，主入口为 scenes/main.tscn
├── scenes/
│   ├── main.tscn          酒馆主场景，F5 入口；含任务、商店 NPC（RewardNPC）、竞技场与关卡传送门
│   ├── arena.tscn         战斗区域与敌人实例
│   ├── access_denied/hub/ 酒馆建筑、家具、碰撞与灯光；不拥有任务、货币或商店状态
│   ├── enemy/             公共 enemy.tscn，types/兵种继承场景，levels/lvl_N/关卡预设
│   ├── player/            独立 player.tscn、player_camera_rig.tscn 与战斗／生命／装备子场景
│   ├── world/             掩体、训练区域、墙体、交互物与场景入口
│   │   ├── levels/        Lvl_1–5 独立地图，含区域、导航、已保存小队／波次及地图实体
│   │   └── objects/       具体交互物：酒馆关卡门、五关返程门、酒杯、终端、唱片机
│   ├── presentation/      模型包装场景和独立接口演示
│   ├── cinematic/         CinematicShot3D 单镜头数据场景
│   ├── effects/           共用命中特效管理器和粒子场景
│   ├── debug/             可选 Debug CanvasLayer，含 CinematicCameraDebug
│   └── ui/                对话、任务面板、货币商店、关卡流程与游玩说明场景
├── scripts/
│   ├── enemy/             身体、AI 协调、装配与评分入口
│   │   ├── actions/       默认行为、战术动作和共用动作执行组件
│   │   ├── config/        兵种、训练、动作定义及参数资源脚本
│   │   └── services/      感知、记忆、上下文、射击、搜索提示/覆盖和空间查询
│   ├── player/            玩家移动、战斗、生命和装备
│   ├── weapons/           武器数据与弹药执行
│   ├── rewards/           关卡、选项与奖励表资源脚本
│   ├── shop/              商品定义、目录与货币商店控制器
│   ├── world/             掩体、训练靶、区域、门、NPC、交互物与屏障
│   │   ├── quest_portal.gd       按任务与 A 解锁进度进入对应关卡
│   │   ├── tavern_return_portal.gd 记录关卡完成、玩家快照与酒馆检查点并返回酒馆
│   │   └── interactions/  交互效果基类、注入上下文与各效果实现
│   ├── ui/                对话、锁定准星、任务面板、货币商店、关卡流程与游玩说明
│   ├── debug/             调试开关、协调器路径与 CinematicCameraDebug；声音圈及旧攻击区域预览默认关闭
│   └── systems/           场景调度、关卡流程、相机、公共状态、用户设置、游戏存档、声音数据与正式场景切换
│       ├── cinematic/     CinematicCameraController 与一次性酒馆开场 Shot
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
│   ├── rewards/           旧三选一奖励配置（兼容保留）
│   ├── shop/              货币商店商品目录
│   ├── navigation/        烘焙导航资源
│   ├── stages/            阶段／任务／NPC 状态规则配置表
│   └── dialogue/          NPC 对话、导入元数据与原有剧情源文件
├── tests/
│   ├── cinematic_*_test.gd 镜头数据、执行器、控制器、Wave/场景动作、Debug 与打断矩阵
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

当前布局以 `main.png` 为参考。`main.tscn` 的 `BarEnvironment` 使用 `svg_tavern_environment.tscn`。大厅两张圆桌之间是一面全高终端墙。连续桌台绕墙一圈，外圈设高脚凳，墙体双面各有三块装饰投影。南侧休息区用低围栏围合，北侧左右各留一个入口，分别对准沙发间的两条过道，区内三张桌分别配两条相向的单侧沙发。卡座使用独立的 U 形菱格皮革沙发，落地底座、坐垫和靠背沿两个圆角连续成形。大厅使用圆形高脚桌，搭配加高的圆形转凳。酒保以胶囊表示，站在吧台内侧，委托人 A 在北侧卡座外。仅右上角卡座保留门帘，玩家经过时拉开，离开门槛后自动合拢。原 `Interactables/LevelPortal` 兼任南侧正门，沿用任务进关流程。半椭圆拱顶点唱机位于吧台下方，出生和返程位置在南门内侧。实际地板和外墙由 `BarEnvironment/Architecture` 提供。

正式场景切换统一经过 `scripts/systems/scene_transition.gd`。该入口在释放当前场景前，把 `World3D.environment` 与 `fallback_environment` 恢复为显式中性环境，避免 GL Compatibility 在目标场景没有 `WorldEnvironment` 时沿用上一场景的环境光。酒馆关卡门、五关返程门、死亡重开和返回酒馆都使用这一入口；目标场景自身配置的 `WorldEnvironment` 仍可在加载后覆盖该中性回退。

`scripts/debug/coordinator_paths.gd` 保留 DebugSettings 入口，使用世界空间 Mesh 绘制 RTS 路线、箭头和站位，以及面积观察状态、责任预约和未来路线。每秒最多十次读取公开副本，不调用导航、规划或补写观察；成员颜色在死亡减员后保持稳定。当前 `main.tscn` 按用户确认保留任务面板、商店面板及交互演示物；五关场景不挂载这套酒馆任务节点，交互组件仍可由 `tests/interaction_fixture.gd` 独立装配验证。五关清场后仍只开放返程门，回酒馆与 A 交互后才解锁下一关。

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

酒馆与五关各明确装配一个 SceneDirector。`scene_request.gd` 保存请求身份、弱节点引用与一次性结果，`scene_request_scheduler.gd` 是导演内部的排队／去重／取消管理。`scene_interaction_executor.gd` 适配 NPC 转身、对话／商店开始和收尾；导演保存暂停、鼠标及玩家限制，界面报告真实结束，包括首句尚未加载完成的取消。区域通过本场查找共享核心，缺失时诊断，不再隐式创建。

`scene_script_executor.gd` 负责即时公开方法与可取消脚本适配，校验完成／取消合同，释放真实执行而非只清理订阅。SceneFlowRunner 保存动作的请求句柄，失败、区域复位和卸载都会取消它；纯等待仍并行。RUN_SCRIPT 追加在原枚举末尾，旧资源编号与 UID 保留。滑门动画通过后台提供者接入，伤害与局部受击表现仍由原组件执行。规则切场与交互切场共用事务加载适配。

`scene_transition_executor.gd` 执行导演批准的加载，经 SceneTransition 在最终边界复核身份；GameState.prepare_scene_transition 只准备数据，commit_scene_transition 在引擎接受后、目标 _ready 前提交，并在完整状态写好后通知订阅者。父交互的合法加载链保留到终态，其他旧执行取消；普通加载失败归还控制，结果／死亡失败保留重试。InteractionContext 注入导演和执行身份，效果可等待子请求，跨关旧来源不再补发 interacted。

波次候选在物理边界取得导演请求，Runtime 的 authorize_deployment 是紧邻真实提交的纯检查，保留原空间／清空业务。出场镜头沿唯一 wave_committed 回调安排；完成请求等前台、手摆演出和活动电影镜头收尾后，导演才调用 LevelFlow.execute_scene_completion 启用原出口。公开 start_encounter／request_wave／show_completion 为兼容请求入口，区域取消同时核对 scope_owner。

排队规则通过内部启动条件复核，条件失效时取消本次执行。Runtime 的 deployment_failed 将实际部署错误传回导演，结束仍在等待的请求。加载父链在引擎接受前保留独立取消入口和弱来源监听，接受后的旧场景退出由加载适配完成收尾。

- `world/enemy_wave_controller.gd` 是 SceneDirector 场景入口兼容脚本，原 UID 保留；五关入口已按用户要求改名，Wave/Squad层级不动。`enemy_wave_runtime.gd` 执行模板、合法出生、各波状态、搜索与清理；`enemy_wave_definition.gd` 保存部署、事件节点与手选镜头配置。
- `enemy_wave_definition.gd` 的 `cinematic_shot_path` 在真实部署后提交单 Shot；SceneDirector 负责“新 Shot → 旧 Wave 手摆 → 整场默认”的优先级，控制器忙时不回滚已部署敌人。
- `systems/scene_director.gd` 是入口内部的场景核心，不依赖Wave或PlayGuide；`scene_flow_runner.gd` 推进资源规则与动作，`scene_pause_coordinator.gd` 统一记录拥有者。仅内部核心使用Always，区域和敌人保持可暂停。
- `systems/scene_event.gd` 是可放入场景的事件节点，来源信号或trigger()统一发triggered；`scene_event_trigger/filter/subscription.gd` 适配和过滤，`scene_flow_rule/action.gd` 保存静态配置。接线见[教程](gameplay/SCENE_DIRECTOR.md)。
- `systems/level_flow.gd` 保留五关表和结果视图，`ui/play_guide.gd` 提供可选begin/cancel/finished，`ui/scene_result_view.gd` 绑定原Health死亡UI；它们只显示并报告请求，暂停与加载由核心决定。五关当前只走返程门闭环；酒馆任务系统读取关卡进度，但不参与 LevelFlow 的返程门与解锁动作。
- `world/ammo_drop_controller.gd` 管理区域掉落选择、数量与生命周期，`ammo_drop_position.gd` 检查合法落点，`ammo_pickup.gd` 显示并执行一次领取。
- `scenes/enemy/levels/lvl_N/` 与 `resources/enemy/training/levels/lvl_N/` 保存各关兵种／训练。共享资源仍可能被跨关引用，修改前核对实际使用者。
- 导航烘焙命令会写资源，属于维护工具；不能作为普通游戏加载流程或默认回归一起执行。

## 相机、表现与内容

`scenes/ui/pause_menu.tscn` 与 `scripts/ui/pause_menu.gd` 由场景导演核心在运行时装配，提供 Esc 暂停、用户设置、操作说明和退出确认，只展示界面并回传意图。`SceneDirector.request_pause_menu()`／`resume_from_pause_menu()` 持有和释放共享暂停协调器的独立令牌；关闭子页不释放世界暂停。说明复用原 `play_guide.tscn`，保留原 `LevelFlow/PlayGuide` 节点路径与显式教程接口，入口 `guide_path` 默认留空，酒馆和五关不再自动显示说明。

`scripts/systems/user_settings.gd` 作为 `UserSettings` 自动加载，保存基础设置的窗口模式、分辨率和垂直同步，以及战斗设置的鼠标辅助和换锁灵敏度，默认路径为 `user://settings.cfg`。设置页将基础与战斗偏好分为两栏，控件变化只保留在待保存状态；统一点击“保存设置”后才调用 `commit_settings()` 校验、写入、应用并通知。分辨率应用同时更新 `Window.content_scale_size` 和窗口尺寸；这避免 `canvas_items` 只改变外框、2D虚拟画布仍固定为1152×648。`canvas_items` 下3D仍按实际窗口或显示器输出像素渲染，本设置不充当独立3D渲染缩放；全屏3D像素由显示器决定，2D界面按所选虚拟画布缩放。返回、Esc 或关闭菜单丢弃未保存值；进入操作说明再返回则保留待保存值。首次没有配置文件时显示“默认设置，尚未保存”，不会把未应用的内置值伪装成已保存。玩家战斗组件入场时读取已保存值，成功保存后通过 `user_settings_combat` 组同步当前玩家。错误类型、越界枚举与缺失键回退默认值；保存失败不提交候选值，并由设置页提示“设置未应用”。窗口模式按平台生成选项，macOS 只提供窗口与无边框全屏；headless 验证跳过真实窗口调用。脚本测试模式默认不读取开发者本机配置，只有显式设置 `DSR_USER_SETTINGS_CONFIG` 时才启用隔离配置。该配置文件与 `GameState` 的本次运行关卡、货币、装备及恢复点快照相互独立。

设置页的“保存游戏”是另一个独立入口，不触发设置提交。`SceneDirector` 在酒馆捕获当前状态和玩家快照；在关卡内只使用离开酒馆时写下的完整快照。没有该快照的直接 F6 关卡入口会禁用保存并提示“没有可保存的酒馆进度”。存档服务先写 `.tmp` 并校验，再替换正式单槽文件；启动主文件不可用时可从有效 `.bak` 恢复。Debug 总开关开启后，“重置全部进度”先要求确认，把正式与备份文件暂存为重置 pending 文件，真实加载主酒馆并清空 `GameState` 后才删除 pending；加载失败会恢复原存档和旧进度。用户设置文件不在重置范围，Debug 总开关也在场景替换中保持开启。

相机根 `systems/player_camera.gd` 统一绑定玩家、读取武器 Aim Range、控制视野过渡；`camera_occlusion.gd` 仅处理显式标记装饰的材质副本与还原。CameraGroundAnchor 过滤翻越抬升。保持原 Phantom Camera 跟随和更新关系。

| 文件／组件 | 职责与接口边界 |
| --- | --- |
| `systems/campaign_save_service.gd` / CampaignSaveService | 单槽游戏存档编码、校验、备份恢复、启动应用与事务式重置文件维护 |
| SceneDirector 存档入口 | `can_save_game()`、`save_game()`、`request_debug_reset_progress()`；区分酒馆保存与最后酒馆快照保存 |
| `systems/cinematic/cinematic_shot_3d.gd` / `scenes/cinematic/` | 作者单镜头数据：机位、镜头参数、三阶段时间、暂停和确定性抖动；运行时不自行切换活动相机 |
| `systems/cinematic/cinematic_camera_controller.gd` | SceneDirector 可见子控制器；单 Shot 准入、SceneRequest、暂停令牌、阶段推进、取消和只读 snapshot |
| `systems/cinematic/opening_cinematic_demo.gd` | 首次酒馆入场黑场、NPC 平移、停留、返回及本次运行内一次性状态 |
| `systems/presentation_camera.gd` | 玩家相机与演出相机之间的通用执行器；复制可见画面、执行旧式移动或新式 Cinematic Shot、返回最新玩家视野并交接遮挡 |
| `debug/cinematic_camera_debug.gd` | Debug 构建下枚举当前场 Shot，只调用控制器 `play_shot`／`cancel_shot`；不拥有相机或暂停 |

`SceneDirector/CinematicCameraController/PresentationCamera` 是固定执行层级，`SceneDirector/CinematicShots` 是可见作者容器。直接 `play_shot()` 使用 SCENE scope；Wave 的 `cinematic_shot_path` 使用 REGION scope；`PLAY_CINEMATIC_SHOT` 继承规则 scope。`busy` 不排队、不替换、不回滚敌人，非对话前台与暂停菜单反向占用也会拒绝镜头。玩家相机仍由 Phantom 和武器视野组件控制，原相机不交给总调度每帧移动。旧式 Marker3D／Node3D 演出继续由同一执行器兼容，新 Shot 优先，遮挡辅助同一时刻只有一个拥有者。

`Main/OpeningCinematicDemo` 是独立的一次性开场节点：首次进入时从 `GameState` 取得播放资格，锁玩家并黑场渐亮，之后动态创建临时 `OpeningNPCPan` Shot，从玩家相机实际地面焦点平移到 `NPC`，停留后退回最新玩家画面。完成、失败或取消都会隐藏遮罩、解除玩家锁并释放临时 Shot；返回酒馆不会再次播放。读取有效存档启动时，存档中的已处理状态会抑制开场；Debug 重置全部进度会清除该标记并恢复初始酒馆。

控制器在死亡、加载、区域复位、控制器／场景卸载、源相机失效、活动 Shot 删除、调试取消和外部相机接管时统一结束；区域复位按请求 scope 只清理 REGION，SCENE 继续。暂停、鼠标与相机所有权分别由共享协调器与原相机恢复。专项为 `cinematic_controller_test`、`cinematic_camera_test`、`cinematic_wave_trigger_test`、`cinematic_debug_test` 和 `cinematic_interruption_test`。

`systems/presentation/` 读取实际状态驱动模型／动画，`systems/effects/` 管理命中快照、表面配置与特效生命周期。表现不改变伤害、枪口、碰撞或 AI；UI 不替代业务状态的唯一写入者。

`world/interactions/` 的效果只通过 InteractionContext 使用注入引用。`systems/stage/` 中阶段、任务和 NPC 状态控制器各自拥有数据，通过只读查询和变化信号协作；普通节点按组绑定，NPC 只按稳定 ID 接收状态。

## 文件与文档维护约束

1. 修改前阅读 README、本页及涉及的专项说明；敌人任务同时检查敌人说明与验证要求。
2. 按既有职责扩展，保留节点路径、资源引用、脚本 UID 和用户配置；新增脚本放入对应职责目录，不把临时诊断放入运行目录。
3. 用户确认的方向是实现依据。不能为了迁就实现改写原设计、放宽测试，或把默认值／建议写成用户逐项确认要求。
4. 功能、接口或职责变化时更新相应当前章节和使用说明。README 保持项目入口，详细参数放专项文档，逐次验证和历史过程单独记录，避免再次堆积成更新流水。
5. 资源只保存配置，实例组件保存运行状态；同一状态只保留一个权威写入入口，UI、相机和诊断读取或订阅。
6. 验证覆盖实际行为及结构约束；历史通过数、运行无错误或一次成功不能替代完整验收。新脚本与测试保留 Godot 生成的 `.uid` sidecar，但不得顺带提交与当前任务无关的 UID。
7. 普通阶段提交、推送及本地修改保护遵循仓库 [AGENTS.md](../AGENTS.md)；不得借文档整理同步远端、覆盖其他任务或改写历史计划。

## 货币商店与旧奖励接口

`main.tscn` 的货币商店闭环由 `scripts/world/reward_npc.gd`（保留 `RewardNPC` 节点路径与脚本 UID，标签为“商店”）、`scripts/shop/shop_controller.gd` 与 `scripts/ui/shop_board.gd` 共同承担：RewardNPC 向导演请求 shop，获准后 ShopController 解析目录、配置面板并执行购买；导演管理暂停和结束。购买时控制器复核余额与效果、修改 `GameState`／玩家／装备、扣款并记录一次性购买，面板只回传 `purchase_requested(item_id, slot)`。死亡或来源离场取消商店请求，只释放本次控制。

任务金额由 `scripts/systems/stage/quest_controller.gd` 在任务首次进入 `COMPLETED` 时调用 `GameState.claim_task_reward(task_id, amount, completed_level)`；`QuestDefinition.money_reward` 默认 100，五个主线任务为 100，不奖励的唱片机支线显式保持 0。发奖同时把该任务 ID 和新增金额补写进当前战役关卡的酒馆检查点，不依赖任务 `stage_index`，避免返回酒馆后重复发钱或漏写支线奖励。

旧三选一组件保留为兼容代码，不再接入主流程：`scripts/rewards/reward_level.gd`／`reward_option.gd`／`reward_table.gd`、`scripts/systems/stage/encounter_controller.gd`、`scripts/ui/reward_board.gd` 与 `scenes/ui/reward_board.tscn`、`resources/rewards/level_rewards.tres` 保留文件与脚本 UID，供独立复用和 `tests/reward_board_test.gd` 验证。旧主流程测试 `reward_npc_test.gd`、`quest_encounter_loop_test.gd`、`reward_per_level_test.gd` 已退役；`encounter_controller_edge_test.gd` 改为隔离夹具兼容专项；新增 `shop_catalog_test`、`shop_state_test`、`shop_weapon_test`、`shop_board_test`、`shop_flow_test`、`quest_money_reward_test` 进入统一 systems 清单。

`scripts/world/quest_portal.gd` 是酒馆门口的五关传送门：首次进入仍要求 `task_a` 进行中，之后只读 `GameState.completed_level`／`available_level`，A 未解锁下一关时阻止进入。它按可用关卡更新 `ChangeSceneEffect.scene_path`，获准交互后为加载准备玩家快照。原门禁卡、门禁读卡器和屏障资源已删除；任务面板默认隐藏，Tab 切换。

五关实际接入仍按本地确认流程运行：LevelFlow 只开放返程门，`QuestPortal` 在 A 解锁后才指向下一关；SceneDirector 的按钮切关／加载能力仅作为独立场景编排功能保留，不能据此改写当前五关入口。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](history/2026-10-28/project-layout.md)。历史通过数不代表当前本地配置已重新验证。

## 旧章节引用

<a id="文档维护约束"></a>

文档维护约束：[整理前对应章节](history/2026-10-28/project-layout.md#文档维护约束)。
