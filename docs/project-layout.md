# 项目目录结构

协调器现按 [2026-10-23 完整重写计划](superpowers/plans/2026-10-23-squad-coordinator-rewrite.md)维护。旧调度器、个人选优中的团队耦合及其专用检查已退出；路径和被场景引用的 UID 保留。当前接口见 [敌人 AI](enemy-ai.md)。

## 文档维护约束

- 用户已确认的功能方向、职责分层和结构约束是实现依据。授权新增功能或维护 MD，不等于授权改变这些方向；不得为了迁就现有代码而倒改要求。
- 明确区分“用户确认的要求”“当前实现与默认参数”“尚未确认的建议”。agent 的实现选择、推测和调参不能自行写成用户要求；实施记录及测试通过也不能代替用户对方向变更的确认。
- 修改 MD 时只更新与任务有关的内容，保留原有约束及理由。发现文档、代码与用户指示不一致时，依据用户明确指示和原有设计核对纠正；不能仅因某份 agent 文档更新时间较新，就用它覆盖原方向。不得通过改写文档或降低测试要求来掩盖实现偏离。

```text
movement_demo/
├── project.godot          Godot 工程入口
├── scenes/
│   ├── main.tscn          主场景，F5 默认入口
│   ├── arena.tscn         战斗区域与敌人实例
│   ├── enemy/             可直接拖入竞技场的 enemy.tscn
│   ├── player/            玩家战斗、生命与武器槽场景
│   ├── world/             掩体、训练区域、墙体、交互物与门禁通道场景
│   │   ├── levels/        Lvl_1–5 独立地图，含区域、导航、空 Squad 及地图实体
│   │   └── objects/       具体交互物：门禁卡、酒杯、终端、唱片机
│   ├── presentation/      模型包装场景和独立接口演示
│   ├── effects/           共用命中特效管理器和粒子场景
│   └── ui/                对话界面场景
├── scripts/
│   ├── enemy/             身体、AI 协调、装配与评分入口
│   │   ├── actions/       默认行为、战术动作和共用动作执行组件
│   │   ├── config/        兵种、训练、动作定义及参数资源脚本
│   │   └── services/      感知、记忆、上下文、射击、搜索提示/覆盖和空间查询
│   ├── player/            玩家移动、战斗、生命和武器槽
│   ├── weapons/           武器数据与弹药执行
│   ├── world/             掩体、训练靶、区域、门、NPC、交互物与屏障
│   │   └── interactions/  交互效果基类、注入上下文与各效果实现
│   ├── ui/                对话界面与锁定准星
│   ├── debug/             调试开关、协调器路径；声音圈及旧攻击区域预览默认关闭
│   └── systems/           公共游戏状态与声音数据
│       ├── stage/         阶段、任务与 NPC 状态控制器
│       ├── presentation/  模型挂载、动画配置与表现状态
│       └── effects/       命中快照、表面配置与特效生命周期
├── resources/
│   ├── enemy/
│   │   ├── actions/       可配置动作 .tres
│   │   ├── units/         兵种模板 .tres
│   │   ├── cooperation/   三档团队意识模板与旧区域兼容绑定 .tres
│   │   └── training/      训练配置 .tres
│   ├── weapons/           玩家与敌人的武器 .tres
│   ├── player/            玩家医疗包效果与时间等静态配置
│   ├── noise/             移动声、枪声配置
│   ├── animations/        动画对应表
│   ├── effects/           表面命中特效配置
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

新增运行脚本按职责放入对应目录；新增敌人动作实现放 `scripts/enemy/actions/`，其定义资源放 `resources/enemy/actions/`。新增交互效果放 `scripts/world/interactions/`，具体交互物场景放 `scenes/world/objects/`；交互物与效果只通过 `InteractionContext` 使用注入的状态，不直接查找全局节点。测试或临时诊断不要放回工程根目录，也不要混入运行脚本目录。

`scenes/Lvl_1.svg` 至 `Lvl_5.svg` 是关卡俯视参考图；`scenes/world/levels/lvl_1.tscn` 至 `lvl_5.tscn` 是独立地图，根节点复用原区域控制器，含 CombatZone、空 Squad、NavigationRegion3D。地图实体在导航区域的 Environment 下，内部掩体继承原预制场景，外围墙和地板为普通静态碰撞体。各图独立引用 `resources/navigation/lvl_N_navigation.tres`。维护命令 `tests/bake_levels.gd` 解析完整碰撞并用盒体轮廓排除实体内部及顶部导航，不由游戏加载。尺寸、编号差异及重烘方式见 [关卡地图](gameplay/LEVEL_MAPS.md)。

阶段、任务与 NPC 状态规则集中在 `scripts/systems/stage/`：阶段判定、任务状态与状态解析各一个控制器，配置表资源脚本与 `resources/stages/` 下的 `.tres` 配套维护。控制器挂在 `main.tscn`、按 group 互相查找，不新增全局单例；NPC 只按 `npc_id` 与接收接口被驱动，不反向依赖控制器。见 [阶段与任务](gameplay/STAGE_STATE.md)。

`scripts/debug/coordinator_paths.gd` 保留 DebugSettings 入口，使用世界空间 Mesh 绘制 RTS 路线、箭头和站位，以及面积观察状态、责任预约和未来路线。每秒最多十次读取公开副本，不调用导航、规划或补写观察；成员颜色在死亡减员后保持稳定。主场景不含任务面板和五个交互演示物，组件由 `tests/interaction_fixture.gd` 独立装配验证。

| 文件 | 当前职责 |
| --- | --- |
| `enemy/services/squad_combat_tactics.gd` | 按冻结武器与合法目标生成近战攻击点、远程交叉/后侧射位，评价整队射界及近战路线冲突，提交前刷新近战停点；不选择动作，无任务所有权或身体控制。 |
| `enemy/services/enemy_command_offers.gd` | AI 持有的统一提案适配器，按共同截止时间轮询已装配动作、保留不同执行器和空间方案；只返回纯值，不提交任务或执行身体。 |
| `enemy/services/squad_support.gd` | 协调器持有的任务身份关联、实际掩护观察核对、累计等待期限和短段独立恢复建议；清理完成/替换/减员关系，无独立循环或任务提交权。 |
| `world/squad_controller.gd` | Squad 配置、区域注册、单次区域时钟推进、销毁；不增加独立 AI 循环。 |
| `enemy/services/squad_coordination.gd` | 本场能力档案、默认模板、持续目标、全员任务表、反馈、逐轮同步与共同续接、原子提交与生命周期。 |
| `enemy/services/squad_contract.gd` | 纯值任务身份、状态、能力角色、观察步骤字段及整队默认模板。 |
| `enemy/services/enemy_team_planner.gd` | 全成员岗位组合搜索，按模板能力与几何排除不完整方案；限制重复入口、比较检查/掩护组合及侧翼人数。 |
| `enemy/services/enemy_search_formation.gd` | 根据合法线索生成两端检查、远侧掩护和接敌站位，验证完整路线、观察/枪线；提供入口前后关注点及冻结的任务机动速度。 |
| `enemy/services/squad_traffic.gd` | 全队通行顺序、准备点占位与离开顺序、观察线互挡、当前阻挡者与剩余路线计算。 |
| `enemy/services/squad_search.gd` | 编排合法线索、地图覆盖和多段路线；hint 改变优先级，不清空观察历史。 |
| `enemy/services/squad_map_coverage.gd` | 各小队独立的地图/楼层面积样本、观察时长与来源、当前监视、复查及局部几何失效；不控制身体或下达任务。 |
| `enemy/services/squad_search_route.gd` | 从未查/待复查面积准备有限观察路线与未来步骤，导航和预计收益不算实际覆盖。 |
| `enemy/services/enemy_visual_observation.gd` | 各档共用的严格视角、真实眼高与站/蹲藏身空间检查；不使用近距全向警觉替代视觉观察。 |
| `enemy/services/squad_defense.gd` | 正常交战掩体候选、受压升级、有限躲藏/探出/撤回步骤及预算内几何准备；从冻结训练资格生成任务，不接管身体或调用个人选优。 |
| `enemy/services/enemy_cooperation.gd` | 区域关系、合法情报存储、公共物理预约；只通过协调器收发团队情报。 |
| `enemy/services/enemy_context.gd` | 能力/身体值接口、情报适配、任务接受/反馈与只读诊断；转交动作状态纯值快照，不持有动作对象。 |
| `enemy/enemy_ai.gd` | 按等级分流个人 Utility 与命令执行；负责原动作/身体/火控交接，发布已装配动作的命令状态。 |
| `enemy/actions/enemy_action.gd` | 共同提案/校验和命令执行协议、只读运行状态钩子与实际路线游标，按准备点进度切换入口前后关注点；个人模式保留原 begin/tick/cancel。 |
| `enemy/actions/enemy_melee_rush_action.gd` | 声明有限接敌机动能力，沿通用命令路线执行短程加速；持有本动作时限和冷却，个人与团队入口共用原时钟及基础挥击。 |

团队避险的执行适配位于原 `enemy_cover_action.gd` / `enemy_covering_retreat_action.gd` 的命令入口，按协调器路线执行躲藏、探出和撤回；原个人 `begin/tick` 保留。抗压值属于 `config/tactics_settings.gd`，通过 Training 保存并由 AI 装配成能力档案；压力事实仍来自原受击/近弹接口，Context 只补充运行快照字段。无新增场景节点或第二套身体/火控。

每个 Squad 持有独立协调器，区域显式绑定也接入同类实例。没有绑定时使用仅情报路由，不创建隐式团队指挥。只有 0 级运行个人 Utility；1/2 级在准备、失败、占用和单人状态也持续归队伍指挥。

基础公共预约继续由区域服务提供，个人分支仅做物理排重；团队全员目的地经新事务一次提交。`enemy_tactical_map.gd` 仍为区域唯一静态地图索引。原 `enemy_cover_inspection_geometry.gd` 只提供合法线索的静态几何，不拥有任务；旧 `enemy_flank_route.gd` 已无调用并移除，新侧翼路线在新几何模块中验证。

团队验证入口为保存地图实战 `squad_command_runtime_test.gd`、最小组合边界 `squad_command_contract_test.gd` 及实体遮挡/面积记录 `squad_map_observation_test.gd`；旧协调器测试的明确替换清单与保留专项见 [敌人测试](enemy-tests.md)。原个人行为夹具 `enemy_fire_fixture.gd` 保留，旧任务注入 helper 删除。

`enemy/config/cooperation_settings.gd` 注册资源类 `EnemyCooperationSettings`，供 Squad 和旧区域绑定的 Profile 明确声明类型。资源创建与预设拖放沿用 Godot 原生检查器；不将 Profile 声明成 GDScript 选择槽，不新增第二份节点等级。原资源路径/UID 和 `cooperation` 参数消费规则保留。`enemy_training_inspector_test.gd` 同时核对原生类型筛选、三个预设、独立资源保存与原有训练面板操作。

`enemy/services/enemy_fire_controller.gd` 统一维护普通短点射、真实队友需求下的掩护长点射、轮间停顿及 AI 扳机间隔，参数在 `config/tactics_settings.gd`。当前默认普通3发、支援6发、停顿1.8秒、AI 间隔倍率1.5；竞技场训练保存的普通枪数／停顿同步为3／1.8。动作、空间预测和协作窗口消费 Fire 的统一时序查询，切换意图不重置已消耗的枪数与间隔；长点射不越过请求和枪线条件。`WeaponData`、身体机械最大射速及玩家开火保持独立，不因 AI 节奏调整而修改。

本轮专项沿用同一回归运行器：`enemy_cover_inspection_test.gd` 覆盖两端检查、证据权限与回退；`enemy_firing_cadence_test.gd` 覆盖短长点射、有限窗口、自主实际掩护与单敌人开关对照；`enemy_ally_spacing_test.gd` / `enemy_ally_spacing_runtime_test.gd` 覆盖基础间距及实际多人移动。验收仍以运行结果和结构约束为准。

`enemy_melee_timing_test.gd` 通过真实 Fire 与身体执行核对挥击和射击冷却并行、重新反应／稳枪、取消换弹和支援点射退出；预测仍由原 `enemy_tactics.gd` 消费 Fire 的只读时间查询。该合同不替代原 `enemy_melee_approach_test.gd` 的自主挥击验证，不增加近战动作或改变统一评分。

`enemy_route_evaluation_batch_test.gd` 核对共同路线／暴露／风险的同步只读批次边界、同帧真实环境变更和返回值隔离，以及掩体候选在旋转、缩放、尺寸变化后的全部点位与顺序。对应优化继续位于 Context、Spatial 和原 `world/cover_region.gd`。Spatial 另在队列准备时按完整当前输入保留最多一份纯掩体坐标表，深复制给消费者，复位与离场释放；不保存路径、射界或评分。该坐标缓存与已接入的区域共享静态地图索引分别维护。

Spatial 的路线样本层仅在同步候选比较中复用同路径已实际观察的点与曝光值，保留原半米采样及逐样本累计顺序；空间预算扫描不建立该层，仍复用原完整结果／曝光缓存。速度、换弹与火控等待按每个候选重新计算，外层批次返回即清空。原换弹动作同时省去已经换弹时不会产生候选的 `after_cover` 路线计算，不增加独立路线或评分模块。

`enemy/services/enemy_local_motion.gd` 是身体私有的局部移动辅助，负责基础友军间距、近距让行，以及实际撞静态墙角且偏离导航走廊后的有限返回。通过原移动入口消费当前方向，使用实际胶囊与所属导航区域检查有限短路段；不接管 AI 目标、任务或动作进度。Context 接入导航区域与关系服务，即使关闭高级“团队协作”也启用基础间距，默认身体间额外余量 `cooperation.spacing_margin=0.45` 米；暂停／复位等由身体清理局部移动意图。间距修正只处理真实附近友军，不承担全队目的地分配。`enemy_navigation_corner_recovery_test.gd` 在内存中复刻现场掩体碰撞体与导航边界，覆盖单近战在协作开关两种情况下从范围外自主恢复并实际命中，不修改用户场景或烘焙资源。压制记忆将调查脚底点与真实可射身体采样分开，出口射击方案已移除；旧资源与脚本保留加载兼容。

无法通过友军的持续物理阻塞由本地辅助观察，经身体的 `ally_path_blocked` 信号交给 Context 保存有限期堵点；跨动作的路线过滤位于 `enemy_cover_selection._path_to()`，在原导航缓存之后复核堵点的当前有效性。队友移开即可恢复路线，复位和离场清理记忆；身体仍只报告执行事实，不决定替代战术或目的地。`enemy_ally_route_recovery_test.gd` 使用真实窄口和身体碰撞验证跨终点过滤、原选择器的替代目的地、恢复通行与生命周期。

堵点默认需累计1.25秒真实受阻才报告，Context 最多保留6处、每处4秒。同一堵点的报告经过4秒后，仍须重新发生真实失败并从零累计1.25秒才能再次报告；停等和过期本身不会续报，也不能拿旧累计立即恢复封堵。动作切换不清空或延长有限路线记忆。

`enemy_ally_route_autonomous_test.gd` 通过真实玩家声音、听觉和完整 AI 更新复现搜索短段反复尝试同一窄口，要求在搜索阶段登记堵点并在队友移开后自主通过；保留原搜索卡住期限，不手动选中动作。身体观察允许有限间隔内累计同一堵点的真实失败，避免每次短段退出都清空证据，等待时间本身不算阻塞。

空间评估的重复物理查询由 Context、Selection、Fire 各自管理同步只读批次缓存：选择器和空间扫描成对开启／结束，嵌套批次共用结果，最外层返回即清除。动作提交、身体移动及实际开火恢复实时查询，不用整帧缓存代替执行检查。团队服务的友军射线检查只读取必要的成员位置，不构建完整任务快照。

`docs/enemy-ai.md` 是敌人结构、维护和使用部署说明；`docs/gameplay/` 保留移动、武器、掩体等专项说明，`docs/TODO.md` 记录后续方向，`docs/superpowers/` 保存仍有价值的设计与验收记录。第三方插件自带文档留在插件目录，以保留其使用说明和许可。

敌人配置与扩展见 [敌人 AI](enemy-ai.md)，统一清单和运行方式见 [测试维护](testing.md)，敌人验收结果见 [敌人测试](enemy-tests.md)，未完成方向见 [待办](TODO.md)。`tests/` 中的编辑器脚本、场景辅助与导航写入工具按清单区分；日志副本由 `logs/.gdignore` 排除，Dialogue Manager 的本地扫描补丁见 [插件维护记录](../movement_demo/addons/dialogue_manager/LOCAL_CHANGES.md)。

玩家、敌人和 NPC 的表现适配器放在各自脚本目录，掩体复用公共表现组件。美术素材接入与空配置回退见 [模型动画与命中特效](gameplay/PRESENTATION.md)。外部模型可按用途放入 `resources/models/`，不改玩法碰撞或导航几何。

整理目录只改文件位置和引用，不重设场景布局、武器数值或训练参数。`player_combat_v3.gd` 是当前玩家战斗实现，保留原文件名；已无引用的更早版本已删除。

半身掩体沿用 `scripts/world/cover_region.gd` 与原掩体节点，预设为 `scenes/world/low_cover.tscn`。`world/low_cover_geometry.gd` 提供低墙、翻越轨迹及近距关系的只读查询；`systems/character_geometry.gd` 只校验假定胶囊的占位与扫掠，不管理玩家或敌人的动作、攻击、生命和计时。角色各自身体执行及适配器消费这些查询和共享表现快照。对应设计与实施记录在 `docs/superpowers/`。

主场景保留原相机节点，通过新增的 `CameraGroundAnchor`（`systems/camera_ground_anchor.gd`）跟随玩家地面高度，过滤翻越抬升；不修改第三方相机插件。Arena 增加一个独立低掩体实例，原高掩体和行为资源保留。玩家、敌人、NPC 与示例胶囊站高为 1.75 米，导航资源同步这一尺度。

原 `Camera3D` 挂 `systems/player_camera.gd`，只订阅现有 Combat 装备通知，将 WeaponData 中的视野大小／过渡时间应用到正交 Size；`systems/camera_occlusion.gd` 是该相机私有的模型遮挡查询与材质还原辅助对象，仅处理 `camera_fadeable` 标记的天花板／装饰，保留掩体不透明。主场景增加 `scenes/world/camera_occlusion_demo.tscn` 纯视觉试玩实例，不增加物理或导航几何。位置仍由 Phantom Camera 和原地面锚点控制，不把视野或透明状态放进武器槽、角色动作或 AI。共享材质、物理与导航资源保持独立，配置与限制见 [相机说明](gameplay/CAMERA.md)。

玩家 V 近战直接扩展 `scripts/player/player_combat_v3.gd`，不另建玩家近战执行文件。纯表现剑光放在 `scripts/systems/effects/` 与 `scenes/effects/`；参数仍在 WeaponData。敌人由 `services/enemy_melee_controller.gd` 管请求与阶段，`enemy_actor.gd` 管实际命中、冷却及独立受击。近战与射击同属底层执行；现有 `actions/enemy_tactics.gd` 在远程接敌中提供近战推开方案，不新增独立挥击脚本／行为资源，不改默认行为、战术目录和训练选择。本轮不移动原模块，不与玩家共用攻击或受击函数，见 [近战说明](gameplay/MELEE.md)。

近战命中减速与击退同放在原 WeaponData 的“近战参数”中，玩家从 WeaponSlots 内编辑，敌人仍从自身 Weapon 编辑。双方攻击入口各自保存本次参数快照；受击倍率和剩余时间分别属于 `player.gd`、`enemy_actor.gd` 实例，沿用原移动入口与生命周期清理。武器槽、共享资源和 AI 行为不保存受击进度，不新增状态管理节点或共用双方受击实现。

敌人基础执行的条件查询与互斥规则继续放在身体／服务中；行为不读取近战控制器的阶段枚举，表现适配器读取状态快照。两种压制共同使用的环境推断参数属于 `config/selection_settings.gd`，由 `services/enemy_cover_selection.gd` 读取，不放在某个可选动作的专用配置中。接口见 [敌人 AI](enemy-ai.md#基础执行接口与冲突规则)。

团队指挥下的基础近战请求统一放在 `actions/enemy_action.gd` 的命令执行入口，使用 Context 的本场装备资格与原近战服务查询；各岗位不另复制挥击判断。原 `enemy_melee_controller.gd` 和身体继续负责时序、命中及取消。挥击仅占用当前任务；被打断的换弹仍由 `enemy_reload_action.gd` 重新请求实际换弹。个人 Utility 接敌与退让逻辑保持独立。

2026-10-07 近战兵接敌扩展继续使用原三层装配：`actions/enemy_melee_cover_action.gd` 和 `enemy_melee_rush_action.gd` 是独立可选战术，定义在 `resources/enemy/actions/`，由近战兵目录提供、Training 解锁。共用只读路径与结果估计放在 `services/enemy_melee_approach.gd`；换弹观察属于原感知／记忆服务。`config/melee_tactics_settings.gd` 经训练的 `action_overrides` 配置，示例为 `resources/enemy/training/melee_assault.tres`。原协调器、选择器、评分公式、场景节点及基础挥击执行职责保持不变；完整规则见 [近战说明](gameplay/MELEE.md)。

`enemy/services/enemy_tactical_map.gd` 由 `shooting_range.gd` 持有并通过环境接口提供给 Context。同区域共用一份静态模板；Spatial 在原预算内推进地图与增量搜索准备，coverage 保存个人覆盖数据。地图模板不替代身体与路线验证；玩家线索与实际观察账本归区域管理，岗位、建议和计划期限归小队协调器管理。
