# 项目目录结构

游戏工程在 `movement_demo/`，说明文档集中在仓库的 `docs/`；仓库根目录仅保留 README 作为入口。脚本、场景与资源已按用途分类，移动时保留脚本 `.gd.uid` 和场景资源内的 UID。

玩家医疗包沿用 `scenes/player/player_health.tscn`：Health/Medkit 挂 `scripts/player/player_medkit.gd`，只管理本实例数量与治疗进度；`scripts/player/medkit_data.gd` 和 `resources/player/default_medkit.tres` 保存静态效果／时长，生命结算仍在 Health。Health/MedkitIndicator 的 `scripts/ui/medkit_indicator.gd` 只做头顶投影和绘制；`scripts/ui/medkit_stock_label.gd` 挂在原武器栏内，只订阅并显示医疗库存。原移动、Combat、武器槽和敌人运行职责不变。配置及输入打断规则见 [生命与医疗包](gameplay/PLAYER_HEALTH.md)。

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
│   ├── debug/             调试开关、声音和攻击点预览
│   └── systems/           公共游戏状态与声音数据
│       ├── presentation/  模型挂载、动画配置与表现状态
│       └── effects/       命中快照、表面配置与特效生命周期
├── resources/
│   ├── enemy/
│   │   ├── actions/       可配置动作 .tres
│   │   ├── units/         兵种模板 .tres
│   │   └── training/      训练配置 .tres
│   ├── weapons/           玩家与敌人的武器 .tres
│   ├── player/            玩家医疗包效果与时间等静态配置
│   ├── noise/             移动声、枪声配置
│   ├── animations/        动画对应表
│   ├── effects/           表面命中特效配置
│   ├── navigation/        烘焙导航资源
│   └── dialogue/          NPC 对话、导入元数据与原有剧情源文件
├── tests/
│   ├── enemy/             敌人测试、公共辅助和回归运行器
│   └── 其他系统测试与测试资源
├── addons/                编辑器插件及第三方依赖
└── logs/                  运行日志与验证输出，Git 忽略
```

新增运行脚本按职责放入对应目录；新增敌人动作实现放 `scripts/enemy/actions/`，其定义资源放 `resources/enemy/actions/`。新增交互效果放 `scripts/world/interactions/`，具体交互物场景放 `scenes/world/objects/`；交互物与效果只通过 `InteractionContext` 使用注入的状态，不直接查找全局节点。测试或临时诊断不要放回工程根目录，也不要混入运行脚本目录。

敌人协作由 `world/shooting_range.gd` 持有每战斗区一份 `enemy/services/enemy_cooperation.gd`；Context 提供值快照与任务接口，服务不访问其他行为实例或执行身体命令。`actions/enemy_cooperation_action.gd` / `resources/enemy/actions/cooperate.tres` 是训练解锁的协作战术，内部提供有限侧移、另一侧包抄和原地掩护方案；分工搜索与主动补弹仍属于原搜索／换弹模块。统一压制保留旧出口脚本 UID 作为兼容入口，默认目录只装配一个压制实例。参数位于 `config/cooperation_settings.gd`，详见 [敌人协作](enemy-ai.md#敌人协作)。

2026-10-10 的两端检查、基础间距和射击节奏调整继续增强上述既有流程。[统一队伍规划器设计](superpowers/specs/2026-10-10-enemy-team-coordinator-design.md)所述“队伍提供互补岗位与候选位置、个人 Utility 选择执行”尚未接入运行；现有服务的局部认领、人数名额与身体避让不等于新规划器已接管动作选择。

统一规划器阶段1已新增 `enemy/services/enemy_team_planner.gd`：纯值输入输出的有界组合 helper，负责排除冲突并提议互补岗位，不访问场景、找路、控制身体或制造任务期限。`tests/enemy/enemy_team_planner_test.gd` 覆盖65项纯协议。当前运行中的 board 尚未调用它，实际站位预约和战术接入仍按后续阶段完成。

`enemy/services/enemy_cover_inspection_geometry.gd` 只从冻结的合法线索和直立盒形掩体生成两个可步行检查端点，复用原导航、胶囊扫掠和完整路径校验；不读取隐藏目标身体、不认领、不发射。原 `actions/enemy_search.gd` 消费分侧认领，执行接近、有限等待、绕端检查和真实观察；`enemy_cooperation.gd` 管理线索、端点互斥与完成事实。Context 接收的调查线索默认保留20秒，与5秒精确共享目击分离，不延长射击权限。两端任务默认16秒且受线索原期限限制，等候2秒、观察0.5秒均不续期；单人或不足两个合法端点时沿用普通搜索，不恢复出口压制。几何和路径候选有限缓存，提交及执行继续复核真实可行性。

`enemy/services/enemy_flank_route.gd` 是协作动作使用的只读几何辅助：由合法已知锚点生成有限带转向弧线、逐段检查点与严格步行路径，拒绝直穿目标附近；不认领岗位、不执行身体、不决定最终 Utility 分数。`enemy_cooperation.gd` 继续统一持有冻结的包抄轮次、人数名额及不可变最终目的地，使用真实友军身体位置计算占侧；动作自己保留短段进度、前线保持和有限支援恢复等待。Context 与 Fire 发布即时火力及正常连射暂停的恢复事实，位置预约与实际火力射界分开，不新增控制整个小队的执行框架。

远处的内收后绕行也属于 `enemy_flank_route.gd`：候选保存少量严格几何转折点，辅助查询实际导航折线，再产出不超过约2米的执行检查点和完整路线时长。近距原四种方向／半径组合保留；不会将场外点吸到导航边缘、改变冻结终点或扩大整轮期限。`tests/enemy/enemy_flank_route_test.gd` 检查纯候选边界、保存地图上的真实通路、有限时间及共享盲态的下一段观察预测；正常 Utility 实际绕行继续由 `enemy_cooperation_flank_runtime_test.gd` 的多人开关对照验证，运行器统一调度。身体减速和支援等候仍由原执行层与固定期限处理。

协作动作按现有武器能力分流几何候选：枪械使用另一侧弧线建立射界，近战保留受掩护接近并核对真实可攻击范围；不新增按兵种名称配对的模块。原地掩护和到位保持的只读预测也在该动作内，以实际剩余保持时间及真实火控等待为限；新原地掩护可容纳一轮长点射，但始终受实际请求剩余时间与任务固定期限裁剪，执行重评不延长保持。当前枪线的执行事实仍由 Context／Fire 发布。普通动作结束调用服务的 `clear_execution()`，仅释放本人认领与执行意图，保留其他成员对本人的有效支援认领和真实换弹请求；完整成员释放仍用于复位、死亡及离场。

`enemy/services/enemy_fire_controller.gd` 统一维护普通短点射、真实队友需求下的掩护长点射、轮间停顿及 AI 扳机间隔，参数在 `config/tactics_settings.gd`。当前默认普通3发、支援6发、停顿1.8秒、AI 间隔倍率1.5；竞技场训练保存的普通枪数／停顿同步为3／1.8。动作、空间预测和协作窗口消费 Fire 的统一时序查询，切换意图不重置已消耗的枪数与间隔；长点射不越过请求和枪线条件。`WeaponData`、身体机械最大射速及玩家开火保持独立，不因 AI 节奏调整而修改。

新增验证仍位于 `tests/enemy/`：`enemy_cooperation_flank_service_test.gd` 检查名额、冻结轮次和生命周期协议；`enemy_cooperation_support_test.gd` 检查真实连射、零火力暂停及枪线／身体门槛；`enemy_cooperation_flank_runtime_test.gd` 以原 AI 循环比较多人开关、实际绕到另一侧、正面实弹及不可达路线。这些文件的存在不代表验证已通过，结果以 [敌人测试](enemy-tests.md) 和实施记录为准。

本轮专项沿用同一回归运行器：`enemy_cover_inspection_test.gd` 覆盖两端检查、证据权限与回退；`enemy_firing_cadence_test.gd` 覆盖短长点射、有限窗口、自主实际掩护与单敌人开关对照；`enemy_ally_spacing_test.gd` / `enemy_ally_spacing_runtime_test.gd` 覆盖基础间距及实际多人移动。验收仍以运行结果和结构约束为准。

`enemy_melee_timing_test.gd` 通过真实 Fire 与身体执行核对挥击和射击冷却并行、重新反应／稳枪、取消换弹和支援点射退出；预测仍由原 `enemy_tactics.gd` 消费 Fire 的只读时间查询。该合同不替代原 `enemy_melee_approach_test.gd` 的自主挥击验证，不增加近战动作或改变统一评分。

`enemy_route_evaluation_batch_test.gd` 核对共同路线／暴露／风险的同步只读批次边界、同帧真实环境变更和返回值隔离，以及掩体候选在旋转、缩放、尺寸变化后的全部点位与顺序。对应优化继续位于 Context、Spatial 和原 `world/cover_region.gd`。Spatial 另在队列准备时按完整当前输入保留最多一份纯掩体坐标表，深复制给消费者，复位与离场释放；不保存路径、射界或评分，尚不是拟实施的区域共享地图索引。

Spatial 的路线样本层仅在同步候选比较中复用同路径已实际观察的点与曝光值，保留原半米采样及逐样本累计顺序；空间预算扫描不建立该层，仍复用原完整结果／曝光缓存。速度、换弹与火控等待按每个候选重新计算，外层批次返回即清空。原换弹动作同时省去已经换弹时不会产生候选的 `after_cover` 路线计算，不增加独立路线或评分模块。

`enemy/services/enemy_local_motion.gd` 是身体私有的局部移动辅助，负责基础友军间距、近距让行，以及实际撞静态墙角且偏离导航走廊后的有限返回。通过原移动入口消费当前方向，使用实际胶囊与所属导航区域检查有限短路段；不接管 AI 目标、任务或动作进度。Context 接入导航区域与关系服务，即使关闭高级“团队协作”也启用基础间距，默认身体间额外余量 `cooperation.spacing_margin=0.45` 米；暂停／复位等由身体清理局部移动意图。间距修正只处理真实附近友军，不承担全队目的地分配。`enemy_navigation_corner_recovery_test.gd` 在内存中复刻现场掩体碰撞体与导航边界，覆盖单近战在协作开关两种情况下从范围外自主恢复并实际命中，不修改用户场景或烘焙资源。压制记忆将调查脚底点与真实可射身体采样分开，出口射击方案已移除；旧资源与脚本保留加载兼容。

无法通过友军的持续物理阻塞由本地辅助观察，经身体的 `ally_path_blocked` 信号交给 Context 保存有限期堵点；跨动作的路线过滤位于 `enemy_cover_selection._path_to()`，在原导航缓存之后复核堵点的当前有效性。队友移开即可恢复路线，复位和离场清理记忆；身体仍只报告执行事实，不决定替代战术或目的地。`enemy_ally_route_recovery_test.gd` 使用真实窄口和身体碰撞验证跨终点过滤、原选择器的替代目的地、恢复通行与生命周期。

堵点默认需累计1.25秒真实受阻才报告，Context 最多保留6处、每处4秒。同一堵点的报告经过4秒后，仍须重新发生真实失败并从零累计1.25秒才能再次报告；停等和过期本身不会续报，也不能拿旧累计立即恢复封堵。动作切换不清空或延长有限路线记忆。

`enemy_ally_route_autonomous_test.gd` 通过真实玩家声音、听觉和完整 AI 更新复现搜索短段反复尝试同一窄口，要求在搜索阶段登记堵点并在队友移开后自主通过；保留原搜索卡住期限，不手动选中动作。身体观察允许有限间隔内累计同一堵点的真实失败，避免每次短段退出都清空证据，等待时间本身不算阻塞。

空间评估的重复物理查询由 Context、Selection、Fire 各自管理同步只读批次缓存：选择器和空间扫描成对开启／结束，嵌套批次共用结果，最外层返回即清除。动作提交、身体移动及实际开火恢复实时查询，不用整帧缓存代替执行检查。团队服务的友军射线检查只读取必要的成员位置，不构建完整任务快照。

`docs/enemy-ai.md` 是敌人结构、维护和使用部署说明；`docs/gameplay/` 保留移动、武器、掩体等专项说明，`docs/TODO.md` 记录后续方向，`docs/superpowers/` 保存仍有价值的设计与验收记录。第三方插件自带文档留在插件目录，以保留其使用说明和许可。

敌人配置与扩展见 [敌人 AI](enemy-ai.md)，验证入口见 [敌人测试](enemy-tests.md)，未完成方向见 [待办](TODO.md)。

玩家、敌人和 NPC 的表现适配器放在各自脚本目录，掩体复用公共表现组件。美术素材接入与空配置回退见 [模型动画与命中特效](gameplay/PRESENTATION.md)。外部模型可按用途放入 `resources/models/`，不改玩法碰撞或导航几何。

整理目录只改文件位置和引用，不重设场景布局、武器数值或训练参数。`player_combat_v3.gd` 是当前玩家战斗实现，保留原文件名；已无引用的更早版本已删除。

半身掩体沿用 `scripts/world/cover_region.gd` 与原掩体节点，预设为 `scenes/world/low_cover.tscn`。`world/low_cover_geometry.gd` 提供低墙、翻越轨迹及近距关系的只读查询；`systems/character_geometry.gd` 只校验假定胶囊的占位与扫掠，不管理玩家或敌人的动作、攻击、生命和计时。角色各自身体执行及适配器消费这些查询和共享表现快照。对应设计与实施记录在 `docs/superpowers/`。

主场景保留原相机节点，通过新增的 `CameraGroundAnchor`（`systems/camera_ground_anchor.gd`）跟随玩家地面高度，过滤翻越抬升；不修改第三方相机插件。Arena 增加一个独立低掩体实例，原高掩体和行为资源保留。玩家、敌人、NPC 与示例胶囊站高为 1.75 米，导航资源同步这一尺度。

原 `Camera3D` 挂 `systems/player_camera.gd`，只订阅现有 Combat 装备通知，将 WeaponData 中的视野大小／过渡时间应用到正交 Size；`systems/camera_occlusion.gd` 是该相机私有的模型遮挡查询与材质还原辅助对象，仅处理 `camera_fadeable` 标记的天花板／装饰，保留掩体不透明。主场景增加 `scenes/world/camera_occlusion_demo.tscn` 纯视觉试玩实例，不增加物理或导航几何。位置仍由 Phantom Camera 和原地面锚点控制，不把视野或透明状态放进武器槽、角色动作或 AI。共享材质、物理与导航资源保持独立，配置与限制见 [相机说明](gameplay/CAMERA.md)。

玩家 V 近战直接扩展 `scripts/player/player_combat_v3.gd`，不另建玩家近战执行文件。纯表现剑光放在 `scripts/systems/effects/` 与 `scenes/effects/`；参数仍在 WeaponData。敌人由 `services/enemy_melee_controller.gd` 管请求与阶段，`enemy_actor.gd` 管实际命中、冷却及独立受击。近战与射击同属底层执行；现有 `actions/enemy_tactics.gd` 在远程接敌中提供近战推开方案，不新增独立挥击脚本／行为资源，不改默认行为、战术目录和训练选择。本轮不移动原模块，不与玩家共用攻击或受击函数，见 [近战说明](gameplay/MELEE.md)。

近战命中减速与击退同放在原 WeaponData 的“近战参数”中，玩家从 WeaponSlots 内编辑，敌人仍从自身 Weapon 编辑。双方攻击入口各自保存本次参数快照；受击倍率和剩余时间分别属于 `player.gd`、`enemy_actor.gd` 实例，沿用原移动入口与生命周期清理。武器槽、共享资源和 AI 行为不保存受击进度，不新增状态管理节点或共用双方受击实现。

敌人基础执行的条件查询与互斥规则继续放在身体／服务中；行为不读取近战控制器的阶段枚举，表现适配器读取状态快照。两种压制共同使用的环境推断参数属于 `config/selection_settings.gd`，由 `services/enemy_cover_selection.gd` 读取，不放在某个可选动作的专用配置中。接口见 [敌人 AI](enemy-ai.md#基础执行接口与冲突规则)。

2026-10-07 近战兵接敌扩展继续使用原三层装配：`actions/enemy_melee_cover_action.gd` 和 `enemy_melee_rush_action.gd` 是独立可选战术，定义在 `resources/enemy/actions/`，由近战兵目录提供、Training 解锁。共用只读路径与结果估计放在 `services/enemy_melee_approach.gd`；换弹观察属于原感知／记忆服务。`config/melee_tactics_settings.gd` 经训练的 `action_overrides` 配置，示例为 `resources/enemy/training/melee_assault.tres`。原协调器、选择器、评分公式、场景节点及基础挥击执行职责保持不变；完整规则见 [近战说明](gameplay/MELEE.md)。
