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

`docs/enemy-ai.md` 是敌人结构、维护和使用部署说明；`docs/gameplay/` 保留移动、武器、掩体等专项说明，`docs/TODO.md` 记录后续方向，`docs/superpowers/` 保存仍有价值的设计与验收记录。第三方插件自带文档留在插件目录，以保留其使用说明和许可。

敌人配置与扩展见 [敌人 AI](enemy-ai.md)，验证入口见 [敌人测试](enemy-tests.md)，未完成方向见 [待办](TODO.md)。

玩家、敌人和 NPC 的表现适配器放在各自脚本目录，掩体复用公共表现组件。美术素材接入与空配置回退见 [模型动画与命中特效](gameplay/PRESENTATION.md)。外部模型可按用途放入 `resources/models/`，不改玩法碰撞或导航几何。

整理目录只改文件位置和引用，不重设场景布局、武器数值或训练参数。`player_combat_v3.gd` 是当前玩家战斗实现，保留原文件名；已无引用的更早版本已删除。

半身掩体沿用 `scripts/world/cover_region.gd` 与原掩体节点，预设为 `scenes/world/low_cover.tscn`。`world/low_cover_geometry.gd` 提供低墙、翻越轨迹及近距关系的只读查询；`systems/character_geometry.gd` 只校验假定胶囊的占位与扫掠，不管理玩家或敌人的动作、攻击、生命和计时。角色各自身体执行及适配器消费这些查询和共享表现快照。对应设计与实施记录在 `docs/superpowers/`。

主场景保留原相机节点，通过新增的 `CameraGroundAnchor`（`systems/camera_ground_anchor.gd`）跟随玩家地面高度，过滤翻越抬升；不修改第三方相机插件。Arena 增加一个独立低掩体实例，原高掩体和行为资源保留。玩家、敌人、NPC 与示例胶囊站高为 1.75 米，导航资源同步这一尺度。

原 `Camera3D` 挂 `systems/player_camera.gd`，只订阅现有 Combat 装备通知，将 WeaponData 中的视野大小／过渡时间应用到正交 Size；`systems/camera_occlusion.gd` 是该相机私有的模型遮挡查询与材质还原辅助对象，仅处理 `camera_fadeable` 标记的天花板／装饰，保留掩体不透明。主场景增加 `scenes/world/camera_occlusion_demo.tscn` 纯视觉试玩实例，不增加物理或导航几何。位置仍由 Phantom Camera 和原地面锚点控制，不把视野或透明状态放进武器槽、角色动作或 AI。共享材质、物理与导航资源保持独立，配置与限制见 [相机说明](gameplay/CAMERA.md)。

玩家 V 近战直接扩展 `scripts/player/player_combat_v3.gd`，不另建玩家近战执行文件。纯表现剑光放在 `scripts/systems/effects/` 与 `scenes/effects/`；参数仍在 WeaponData。敌人由 `services/enemy_melee_controller.gd` 管请求与阶段，`enemy_actor.gd` 管实际命中、冷却及独立受击。近战与射击同属底层执行；现有 `actions/enemy_tactics.gd` 在远程接敌中提供近战推开方案，不新增独立挥击脚本／行为资源，不改默认行为、战术目录和训练选择。本轮不移动原模块，不与玩家共用攻击或受击函数，见 [近战说明](gameplay/MELEE.md)。

敌人基础执行的条件查询与互斥规则继续放在身体／服务中；行为不读取近战控制器的阶段枚举，表现适配器读取状态快照。两种压制共同使用的环境推断参数属于 `config/selection_settings.gd`，由 `services/enemy_cover_selection.gd` 读取，不放在某个可选动作的专用配置中。接口见 [敌人 AI](enemy-ai.md#基础执行接口与冲突规则)。

2026-10-07 近战兵接敌扩展继续使用原三层装配：`actions/enemy_melee_cover_action.gd` 和 `enemy_melee_rush_action.gd` 是独立可选战术，定义在 `resources/enemy/actions/`，由近战兵目录提供、Training 解锁。共用只读路径与结果估计放在 `services/enemy_melee_approach.gd`；换弹观察属于原感知／记忆服务。`config/melee_tactics_settings.gd` 经训练的 `action_overrides` 配置，示例为 `resources/enemy/training/melee_assault.tres`。原协调器、选择器、评分公式、场景节点及基础挥击执行职责保持不变；完整规则见 [近战说明](gameplay/MELEE.md)。
