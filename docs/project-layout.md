# 项目目录结构

爆头结算与被爆头状态（2026-10-25）：原 `scripts/weapons/weapon_data.gd` 导出开关、概率、秒杀选项、兜底倍率、状态时长及刷新规则。`scripts/weapons/headshot_resolver.gd` 仅处理已完成射线的命中统计，每枪每目标一次抽样，在受击回调前冻结本枪所有结果；`player_combat_v3.gd` 仍拥有弹药、后坐与实际射击。原 `headshot_hit(world_position, pellets, shotgun)` 保留，新增 `headshot_resolved(world_position, outcome)` 通知准星显示实际结果。

敌人身体拥有独立 `scripts/enemy/services/enemy_headshot_state.gd` 状态，保存本次攻击武器的效果快照与剩余时间；不加节点／Timer／AI循环。复用近战／枪击的 `apply_aim_penalty()` 与 `get_hit_movement_multiplier()` 出口执行精度和减速，不禁止射击，不取消AI动作、不新增协调器占用。`EnemyContext` 只沿原训练查询注入爆头防护，`tactics_settings.gd` 直接保存布尔字段，检查器仅将原 `Profile.tactics` 显示为“作战能力”。原资源键、场景路径和UID保留。`enemy_ai.gd`、火控决策和协调器逻辑未因本状态修改。设计与接口见[爆头设计](superpowers/specs/2026-10-25-headshot-stagger-execution-design.md)。

霰弹标定与独立预览（2026-10-25）：原 `ShotgunSettings` 保存标定距离并集中换算／校验，继续用原角度驱动弹道；`addons/weapon_mode_inspector/shotgun_coverage_property.gd` 在原检查器中供武器配置与预览节点复用，负责距离、面积和整体撤销，不另建插件入口。原 `scripts/debug/shotgun_pattern_preview.gd` 保存三个图样槽、独立标定距离／角度及偏移等数值，内部构造专用配置并调用原采样；观察距离可超过 1000 米，三栏共用可自动扩展的米制比例尺。同名场景只保存根节点的引用和参数，不保存生成的 UI；除图样引用外不读取武器 `.tres`。武器随机偏移、图样格式、运行时射击和原 UID 保留，见[霰弹说明](gameplay/SHOTGUN.md)。

方向跟枪（2026-10-25）：原 `scripts/player/player_combat_v3.gd` 内部按目标水平位移相对瞄准连线计算有效横向距离／速度，同时决定跟枪损失和恢复限制；`tracking_parallel_tolerance_degrees` 只在玩家 Combat 配置。继续读取原 `WeaponData.get_aim_settings()`，不增加跟枪组件、不修改节点／资源引用或敌人 AI。暂停／恢复清理位置样本，真实玩家帧流程由 `tests/directional_tracking_test.gd` 验证。完成记录见[方向跟枪设计](superpowers/specs/2026-10-25-directional-tracking-accuracy-design.md)。

霰弹编辑与装填补充（2026-10-25）：原 `addons/weapon_mode_inspector/` 插件增加 `shotgun_pattern_property.gd`（检查器、原生撤销、保存／另存）和 `shotgun_pattern_canvas.gd`（点选／拖动画板），仍写入原 `ShotgunPattern.points`，运行时不依赖编辑插件。原图样预览脚本使用 `@tool`，其生成的界面不序列化到场景。逐发开关和每发耗时归 `ShotgunSettings`；原 `weapon_ammo.gd` 统一计时与弹量守恒，并提供只读 `reload_remaining_seconds()` 供 UI、原 AI 估时及协调快照使用。玩家输入中断仍归 Combat，敌人选择权仍归原 AI。旧资源、节点路径和 UID 保留。

霰弹扩展（2026-10-25）：沿用 `WeaponData` 和原 `Fire Mode`，追加霰弹选项；可选 `ShotgunSettings` 与 `ShotgunPattern` 分别位于 `scripts/weapons/shotgun_settings.gd`、`shotgun_pattern.gd`。`shotgun_ballistics.gd` 仅提供弹丸采样／物理射线／近弹几何，双方原射击脚本各自结算。图样与示例放在原 `resources/weapons/` 下，预览脚本位于 `scripts/debug/`，两个独立预览场景位于 `scenes/presentation/`。不迁移原资源、不改变玩家／敌人节点或 AI 接口，见[霰弹说明](gameplay/SHOTGUN.md)。

战斗可读性（2026-10-25）：`enemy/enemy_health_bar.gd` 挂在公共敌人的 `HealthBar`，仅显示原身体生命比例；`enemy/enemy_corpse_visual.gd` 由波次控制器在整波回收前创建静态网格快照，内部 `Corpses` 容器随本轮复位／卸载清理，不保留身体与AI。`systems/combat_view.gd` 是无状态的实际相机画面查询，玩家锁定及敌人火控／身体执行共用；原射线继续负责遮挡。`systems/player_camera.gd` 通过已有装备信号按武器锁定距离计算正交 Size，保留手动视野模式与跟随链。感知服务读取自身远程武器范围和原训练资源，不增加独立感知循环。入口见[相机](gameplay/CAMERA.md)、[敌人](enemy-ai.md)和[表现](gameplay/PRESENTATION.md)。

波次系统（2026-10-25）：`world/enemy_wave_controller.gd` 在区域子树入树前捕获小队为内存场景快照，按波分别持有出场、死亡集合与清理状态，支持多波同时在场；`enemy_wave_definition.gd` 保存等待上一波全灭开关、等待秒数和可选已有小队引用；私有无循环辅助 `enemy_wave_spawn_check.gd` 只读检查本区导航、实际胶囊与同波占位。对应 `scenes/world/enemy_waves.tscn`／`enemy_wave.tscn` 提供编辑入口，第一关保留原 `Squad` 为首波并新增第二波示例。区域仍独占玩家进出检测和物理时钟，不改变 Squad、身体或 AI 职责。见[波次实施记录](superpowers/plans/2026-10-25-level-enemy-waves.md)。

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
│   ├── enemy/             公共 enemy.tscn，types/兵种继承场景，levels/lvl_N/关卡预设
│   ├── player/            独立 player.tscn、player_camera_rig.tscn 与战斗／生命／装备子场景
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
│   ├── player/            玩家移动、战斗、生命和装备
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
│   │   └── training/      训练配置 .tres；levels/lvl_N/保存关卡独立训练
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

关卡兵种示范使用 `scenes/enemy/enemy.tscn → types/melee.tscn → levels/lvl_1/melee.tscn`／`lvl_2/melee.tscn` 的场景继承链，保持原公共节点、脚本和UID；每个关卡预设仅覆盖生命与独立训练引用。训练保存到既有资源目录的对应 `training/levels/lvl_N/melee.tres`。示例参数和维护入口见[敌人配置](enemy-ai.md#按关卡维护兵种示范2026-10-24)，用户原独立近战副本与地图实例保留。

`scenes/Lvl_1.svg` 至 `Lvl_5.svg` 是关卡俯视参考图；`scenes/world/levels/lvl_1.tscn` 至 `lvl_5.tscn` 是独立地图，根节点复用原区域控制器，含 CombatZone、空 Squad、NavigationRegion3D。地图实体在导航区域的 Environment 下，内部掩体继承原预制场景，外围墙和地板为普通静态碰撞体。各图独立引用 `resources/navigation/lvl_N_navigation.tres`。维护命令 `tests/bake_levels.gd` 解析完整碰撞并用盒体轮廓排除实体内部及顶部导航，不由游戏加载。尺寸、编号差异及重烘方式见 [关卡地图](gameplay/LEVEL_MAPS.md)。

2026-10-24 五张 `scenes/world/levels/lvl_N.tscn` 仅做水平0.75倍布局与尺寸调整，根节点比例和全部高度保持；CombatZone与五份独立导航同步。已有角色只调整出生点，不改玩家／相机／敌人预制尺寸或通用资源。具体尺寸与本地／提交导航差异见 [关卡地图](gameplay/LEVEL_MAPS.md)。

阶段、任务与 NPC 状态规则集中在 `scripts/systems/stage/`：阶段判定、任务状态与状态解析各一个控制器，配置表资源脚本与 `resources/stages/` 下的 `.tres` 配套维护。控制器挂在 `main.tscn`、按 group 互相查找，不新增全局单例；NPC 只按 `npc_id` 与接收接口被驱动，不反向依赖控制器。见 [阶段与任务](gameplay/STAGE_STATE.md)。

`scripts/debug/coordinator_paths.gd` 保留 DebugSettings 入口，使用世界空间 Mesh 绘制 RTS 路线、箭头和站位，以及面积观察状态、责任预约和未来路线。每秒最多十次读取公开副本，不调用导航、规划或补写观察；成员颜色在死亡减员后保持稳定。主场景不含任务面板和五个交互演示物，组件由 `tests/interaction_fixture.gd` 独立装配验证。

| 文件 | 当前职责 |
| --- | --- |
| `enemy/services/squad_combat_tactics.gd` | 按冻结武器与合法目标生成近战攻击点、远程交叉/后侧射位，评价整队射界及近战路线冲突，提交前刷新近战停点；不选择动作，无任务所有权或身体控制。 |
| `enemy/services/enemy_command_offers.gd` | AI 持有的统一提案适配器，按共同截止时间轮询已装配动作、保留不同执行器和空间方案；只返回纯值，不提交任务或执行身体。 |
| `enemy/services/squad_support.gd` | 协调器持有的任务身份关联、实际掩护观察核对、累计等待期限和短段独立恢复建议；清理完成/替换/减员关系，无独立循环或任务提交权。 |
| `world/squad_controller.gd` | Squad 配置、区域注册、单次区域时钟推进、销毁；不增加独立 AI 循环。 |
| `enemy/services/squad_coordination.gd` | 本场能力档案、默认模板、持续目标、全员任务表、反馈、成员轮询准备、接敌提前提交与共同续接、逐轮同步、原子提交与生命周期。 |
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

`world/vault_navigation.gd` 由原 `shooting_range.gd` 持有并提供给 Context，增量维护所属区域的原生 NavigationLink3D：步行层1，翻越连接层2。公共 `cover.tscn` 的 `NavigationBakeObstacle` 子节点使用 `world/navigation_bake_obstacle.gd`，按真实碰撞同步原生烘焙轮廓；维护命令复用它，运行时不重烘导航。

2026-10-25 个人区域选点仍使用这些原生连接定位低墙。区域服务的 `area_candidates()` 从真实盒体整段墙面提供最多两个纯值候选；`enemy_navigation_route.gd` 在实际起跳失败后分帧验证接近／落地步行段与翻越弧。分段可带 `crossing_key` 区分同一原生连接上的具体位置，原 `link_key/owner_id` 继续核对几何生命周期并保守串行预约；失败位置独立避让，不将整个低墙判成不可翻越。团队沿用原原生通道，烘焙辅助、保存导航和场景结构未变。

个人近战动作保留仍可出手的准确停靠点及对应合法观察位置，普通动作切换可保留这份准备依据；配置变化和复位清理。候选的可选 `route_priority` 只控制路线准备，当前追击及已启动的分段准备每显示帧最多推进一次，未开始的普通路线保持原四物理步间隔，仍共用24点／2毫秒截止时间；收集候选不直接同步准备翻越几何。

个人 `enemy_route_planner.gd` 保留有界优先队列、短时失败连接和原 Spatial 预算，调用 `enemy_navigation_route.gd`。同一查询也供团队提案读取，返回纯值 `route_plan`（版本、几何版本、摘要点列和 walk/vault 分段）。查询游标每次最多一次原生查询、四个验证单位，未完成的验证不会被结果缓存期限清空。普通 `_path_to()` 与 NavigationAgent3D 仍仅使用步行层；摘要点列不证明可步行。

动作各自持有 `enemy_route_motion.gd` 的分段进度，个人与团队共享执行器，原身体独占实际起跳、占位复核与安全落地。团队任务保留原 `route` 摘要并可带 `route_plan`，特化动作等待查询并按实际分段耗时估计；旧 before/vault/after 与纯步行任务继续兼容。通道占用由现有 `enemy_cooperation.gd` 管理，任务取消／死亡／退队不提前释放仍在空中的身体。近战备用接敌点也走同一准备入口。

无法通过友军的持续物理阻塞由本地辅助观察，经身体的 `ally_path_blocked` 信号交给 Context 保存有限期堵点；跨动作的路线过滤位于 `enemy_cover_selection._path_to()`，在原导航缓存之后复核堵点的当前有效性。队友移开即可恢复路线，复位和离场清理记忆；身体仍只报告执行事实，不决定替代战术或目的地。`enemy_ally_route_recovery_test.gd` 使用真实窄口和身体碰撞验证跨终点过滤、原选择器的替代目的地、恢复通行与生命周期。

堵点默认需累计1.25秒真实受阻才报告，Context 最多保留6处、每处4秒。同一堵点的报告经过4秒后，仍须重新发生真实失败并从零累计1.25秒才能再次报告；停等和过期本身不会续报，也不能拿旧累计立即恢复封堵。动作切换不清空或延长有限路线记忆。

`enemy_ally_route_autonomous_test.gd` 通过真实玩家声音、听觉和完整 AI 更新复现搜索短段反复尝试同一窄口，要求在搜索阶段登记堵点并在队友移开后自主通过；保留原搜索卡住期限，不手动选中动作。身体观察允许有限间隔内累计同一堵点的真实失败，避免每次短段退出都清空证据，等待时间本身不算阻塞。

空间评估的重复物理查询由 Context、Selection、Fire 各自管理同步只读批次缓存：选择器和空间扫描成对开启／结束，嵌套批次共用结果，最外层返回即清除。动作提交、身体移动及实际开火恢复实时查询，不用整帧缓存代替执行检查。团队服务的友军射线检查只读取必要的成员位置，不构建完整任务快照。

`docs/enemy-ai.md` 是敌人结构、维护和使用部署说明；`docs/gameplay/` 保留移动、武器、掩体等专项说明，`docs/TODO.md` 记录后续方向，`docs/superpowers/` 保存仍有价值的设计与验收记录。第三方插件自带文档留在插件目录，以保留其使用说明和许可。

`docs/gameplay/ENEMY_WAVES.md` 是波次的独立中文使用说明，包含第一关原路径引用、跨波移动成员、复制排序、其他地图接入与排错。共用 `enemy_waves.tscn` 只提供控制器空容器，每个 `enemy_wave.tscn` 在关卡中独立实例化，避免继承默认首波导致保存排序受限。

敌人配置与扩展见 [敌人 AI](enemy-ai.md)，统一清单和运行方式见 [测试维护](testing.md)，敌人验收结果见 [敌人测试](enemy-tests.md)，未完成方向见 [待办](TODO.md)。`tests/` 中的编辑器脚本、场景辅助与导航写入工具按清单区分；日志副本由 `logs/.gdignore` 排除，Dialogue Manager 的本地扫描补丁见 [插件维护记录](../movement_demo/addons/dialogue_manager/LOCAL_CHANGES.md)。

玩家、敌人和 NPC 的表现适配器放在各自脚本目录，掩体复用公共表现组件。美术素材接入与空配置回退见 [模型动画与命中特效](gameplay/PRESENTATION.md)。外部模型可按用途放入 `resources/models/`，不改玩法碰撞或导航几何。

整理目录只改文件位置和引用，不重设场景布局、武器数值或训练参数。`player_combat_v3.gd` 是当前玩家战斗实现，保留原文件名；已无引用的更早版本已删除。

半身掩体沿用 `scripts/world/cover_region.gd` 与原掩体节点，预设为 `scenes/world/low_cover.tscn`。`world/low_cover_geometry.gd` 提供低墙、翻越轨迹及近距关系的只读查询；`systems/character_geometry.gd` 只校验假定胶囊的占位与扫掠，不管理玩家或敌人的动作、攻击、生命和计时。角色各自身体执行及适配器消费这些查询和共享表现快照。对应设计与实施记录在 `docs/superpowers/`。

按用户后续要求，玩家和相机分为两个独立预制：`scenes/player/player.tscn` 的根仍是原 CharacterBody3D，保留 Combat、Equipment、Health、Visual 与表现／受击子节点；`scenes/player/player_camera_rig.tscn` 以原 Camera3D 为根，包含 PhantomCameraHost、CameraGroundAnchor、PhantomCamera3D。Main 与 lvl3 引用这两个实例，保留 Player、Camera3D 根路径与出生位置；地面锚点／虚拟镜头路径改为 Camera3D 的子路径，不新增角色总控或修改插件。

相机根脚本 `get_follow_actor()` 按唯一的 `player_path` 解析玩家，地面锚点共用该引用；相机先就绪时等待玩家 ready 后再读取初始装备，避免漏掉武器视野或出生缩放。锚点与虚拟镜头保持 top_level，在原50／300／400的物理更新顺序下过滤翻越抬升。独立组件仍使用项目既有输入与 autoload，单视口配置一套活动相机。玩家、敌人、NPC 与示例胶囊站高仍为1.75米。

2026-10-24 按用户要求将 WeaponSlots 节点改名为 Equipment（装备），保留 `player_weapon_slots.gd/.tscn` 路径、脚本 UID 和原节点 unique_id。Equipment 检查器像武器一样直接挂载 `medkit: MedkitData` 资源并保存 `medkit_count` 数量；资源保存回血量与时间，库存只属于装备实例。Medkit 与 MedkitIndicator 由 Health 迁入 Equipment，独立医疗组件访问装备的配置／库存并执行使用，Health 通过原 `restore_health()` 结算生命。Main、独立玩家和地图实例统一使用新路径，原武器槽内的 UI 相对路径、武器资源、弹药与准度保存机制保持。

半身掩体阶段在 Arena 增加一个独立低掩体实例，原高掩体和行为资源保留。

原 `Camera3D` 挂 `systems/player_camera.gd`，只订阅现有 Combat 装备通知，将 WeaponData 中的视野大小／过渡时间应用到正交 Size；`systems/camera_occlusion.gd` 是该相机私有的模型遮挡查询与材质还原辅助对象，仅处理 `camera_fadeable` 标记的天花板／装饰，保留掩体不透明。主场景增加 `scenes/world/camera_occlusion_demo.tscn` 纯视觉试玩实例，不增加物理或导航几何。位置仍由 Phantom Camera 和原地面锚点控制，不把视野或透明状态放进武器槽、角色动作或 AI。共享材质、物理与导航资源保持独立，配置与限制见 [相机说明](gameplay/CAMERA.md)。

玩家 V 近战直接扩展 `scripts/player/player_combat_v3.gd`，不另建玩家近战执行文件。纯表现剑光放在 `scripts/systems/effects/` 与 `scenes/effects/`；参数仍在 WeaponData。敌人由 `services/enemy_melee_controller.gd` 管请求与阶段，`enemy_actor.gd` 管实际命中、冷却及独立受击。近战与射击同属底层执行；现有 `actions/enemy_tactics.gd` 在远程接敌中提供近战推开方案，不新增独立挥击脚本／行为资源，不改默认行为、战术目录和训练选择。本轮不移动原模块，不与玩家共用攻击或受击函数，见 [近战说明](gameplay/MELEE.md)。

近战命中减速与击退同放在原 WeaponData 的“近战参数”中，玩家从 Equipment 内编辑，敌人仍从自身 Weapon 编辑。双方攻击入口各自保存本次参数快照；受击倍率和剩余时间分别属于 `player.gd`、`enemy_actor.gd` 实例，沿用原移动入口与生命周期清理。武器槽、共享资源和 AI 行为不保存受击进度，不新增状态管理节点或共用双方受击实现。

2026-10-24 命中／压制效果继续沿原模块扩展：`weapon_data.gd.get_attack_effects()` 提供纯值攻击快照，双方射击／近战入口传入真实角色的 `receive_weapon_hit`／`receive_melee_hit`，擦过通知同时携带快照。玩家 Combat 导出三个受方倍率，敌人只从 Training 的 tactics 读取同义倍率，由 Context 将计算结果交给身体执行；FireController 不再额外监听生命／近弹去叠加固定损失。双方身体复用原减速状态与物理时钟，接口统一为 `get_hit_movement_multiplier()`／`clear_hit_effects()`，不新增节点或共用双方执行函数。旧角色基础损失字段、Cover半径和资源覆盖键已清理，详情见 [实施与清理记录](superpowers/specs/2026-10-24-weapon-impact-accuracy-cleanup-design.md)。

敌人基础执行的条件查询与互斥规则继续放在身体／服务中；行为不读取近战控制器的阶段枚举，表现适配器读取状态快照。两种压制共同使用的环境推断参数属于 `config/selection_settings.gd`，由 `services/enemy_cover_selection.gd` 读取，不放在某个可选动作的专用配置中。接口见 [敌人 AI](enemy-ai.md#基础执行接口与冲突规则)。

团队指挥下的基础近战请求统一放在 `actions/enemy_action.gd` 的命令执行入口，使用 Context 的本场装备资格与原近战服务查询；各岗位不另复制挥击判断。原 `enemy_melee_controller.gd` 和身体继续负责时序、命中及取消。挥击仅占用当前任务；被打断的换弹仍由 `enemy_reload_action.gd` 重新请求实际换弹。个人 Utility 接敌与退让逻辑保持独立。

2026-10-07 近战兵接敌扩展继续使用原三层装配：`actions/enemy_melee_cover_action.gd` 和 `enemy_melee_rush_action.gd` 是独立可选战术，定义在 `resources/enemy/actions/`，由近战兵目录提供、Training 解锁。共用只读路径与结果估计放在 `services/enemy_melee_approach.gd`；换弹观察属于原感知／记忆服务。`config/melee_tactics_settings.gd` 经训练的 `action_overrides` 配置，示例为 `resources/enemy/training/melee_assault.tres`。原协调器、选择器、评分公式、场景节点及基础挥击执行职责保持不变；完整规则见 [近战说明](gameplay/MELEE.md)。

2026-10-24 个人近战占点冲突修复：`enemy_melee_approach.gd` 增加有限侧向接近路线与位置有效性查询；`enemy_melee_action.gd` 负责候选占用过滤、保持有效侧向点及执行目的地，`enemy_melee_rush_action.gd` 复用准备并保留原时限/冷却。`enemy_search_coverage.gd` 仅调整代价排序和实时占用检查的先后顺序。没有新增节点、资源格式、协调器决策入口或动作专用指挥接口。

2026-10-24 近战堵截继续按原训练目录扩展：`resources/enemy/actions/melee_intercept.tres` 登记到 `units/melee.tres`，`actions/enemy_melee_intercept_action.gd` 提供个人候选/执行和共同命令提案，`services/enemy_melee_interception.gd` 负责只读有限观察预测与路径准备。参数扩展原 `config/melee_tactics_settings.gd`，无新节点、协调器专用分支或训练自动勾选。专项 `tests/enemy/enemy_melee_intercept_test.gd` 注册原敌人运行器；设计与代码入口见[实施说明](superpowers/specs/2026-10-24-trained-melee-interception-design.md)。

`enemy/services/enemy_tactical_map.gd` 由 `shooting_range.gd` 持有并通过环境接口提供给 Context。同区域共用一份静态模板；Spatial 在原预算内推进地图与增量搜索准备，coverage 保存个人覆盖数据。地图模板不替代身体与路线验证；玩家线索与实际观察账本归区域管理，岗位、建议和计划期限归小队协调器管理。

统一提案阶段2继续在原动作内适配专用过程：`enemy_attack_position_action.gd` 按预算批次提供真实攻击区域；`enemy_melee_cover_action.gd` 提供接近/出口/有限接敌步骤；`enemy_suppression_action.gd` 提供支援、近距及本人失视的有限射击。AI 保留同一 `plan_key/stage` 的执行状态，Context 与 Fire 核对冻结本人事件权限。原 Cover 计时、身体、射击与近战执行器保持各自职责。无新增节点或动作专用协调器接口。
