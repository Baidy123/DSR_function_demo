# DSR_function_demo

基于 **Godot 4.7.2 与 GDScript** 的 3D 俯视角战斗功能原型。项目围绕锁定射击、精度损耗、近战破绽和敌人小队协作构建，包含连续五关、独立任务演示，以及可复用的玩家、武器、敌人、波次和表现组件。

[功能](#已实现的功能) · [操作](#玩家操作) · [配置接口](#配置接口) · [脚本接口](#常用脚本接口) · [扩展方法](#如何扩展) · [完整文档](docs/README.md)

直接运行工程或按 **F5** 即进入酒馆。接取 A 的任务后，酒馆门口的传送门会解锁，按 E 进入第1关。任务面板依次记录“通关第1关”至“通关第5关”：A 解锁关卡时对应任务进入进行中，清场返回酒馆后完成任务。每关清空都会先返回酒馆，再次与 A 交互后才解锁下一关。每次返回后都可与酒馆东侧房间的蓝色“商店”NPC 交互打开货币商店；初始三个商品为急救包（40，回血35）、弹药补给（30，补满弹匣与备弹）、系统进度（50，+20），均可重复购买。跨关保留生命、当前武器、两把枪的弹匣与共享备弹、医疗包、货币。五个主线任务各固定发放 100 货币，首次完成时发放一次。死亡后可选重新挑战当前关（保留进入本关时已付费的装备），或回到最近一次完成关卡的酒店检查点（退还检查点之后的商店花费、撤销之后的一次性购买并恢复装备）；检查点仍尚未由 A 解锁下一关。Debug 总开关开启后可一键完成当前关。完整操作见[五关游玩说明](docs/gameplay/PLAY_GUIDE.md)，商店与任务金额见[货币商店与任务奖励](docs/gameplay/REWARDS.md)。

## 已实现的功能

| 模块 | 当前能力 |
| --- | --- |
| 玩家移动 | 转向、加减速、奔跑与耐力、蹲姿、半身掩体与翻越 |
| 锁定与射击 | 方向键转向锁定、可开关的鼠标辅助选敌／换锁、平滑转身、单发／自动／霰弹、真实射线与遮挡 |
| 精度与爆头 | 移动、跟枪、开火和受击损耗；三种收敛公式；按准度线性增加的爆头率 |
| 近战 | 枪械附带近战、专用近战兵、击退与眩晕反馈；玩家近战为受击敌人提供一次爆头门槛优惠 |
| 装备与补给 | 主副武器槽、按弹种共享备弹、整匣／逐发装填、缺弹掉落、医疗包与二选一重生 |
| 货币商店与任务金额 | 蓝色商店 NPC 打开货币商店；初始急救包／弹药补给／系统进度按价格购买，`.tres` 商品按关卡逐级解锁，一次性武器商品可覆盖主副槽；五个主线任务各发 100 货币一次 |
| 敌人 AI | 巡逻、视觉／听觉、追踪与搜索、掩体、近远程攻击；个人决策与三档小队配合 |
| 场景调度 | SceneDirector统一可选引导、节点事件、波次出场、手选目标的独立镜头、死亡重开／回酒店与连续五关 |
| 交互与任务 | 对话、场景交互效果、条件驱动任务、阶段与 NPC 状态；任务演示与五关流程各自独立 |
| 表现与诊断 | 可替换模型／动画、命中特效、血条与尸体、准星／状态提示、相机遮挡透明和调试视图 |

具体数值由场景及资源保存，文档中的默认值用于解释参数，不替代当前武器和关卡配置。

## 玩家操作

| 输入 | 作用 |
| --- | --- |
| W / A / S / D、Shift | 按画面方向移动；按住 Shift 奔跑 |
| C、空格 | 蹲下／站起；翻越半身掩体 |
| 按住右键、左键 | 瞄准；瞄准时开火，自动武器可按住连射 |
| 右键按住时拨动鼠标 | 鼠标辅助开启时选敌、换锁 |
| V | 使用当前枪械的近战攻击 |
| 1 / 2、滚轮 | 切换主副武器 |
| R | 主动换弹，打空不会自动装填 |
| H | 使用医疗包；动作输入或受击会打断 |
| E | 与附近可交互物或 NPC 交互 |

**方向键转向锁定**：用方向键调整朝向，再按住右键自动锁定；更换方向时松开瞄准后重新转向。**鼠标辅助锁定（默认）**：保留上述方式，增加鼠标方向选敌；无目标时以玩家的画面位置为参照，有目标时以当前目标为参照。击杀后可继续按住右键拨向下一人。

锁定、近战与射击使用战斗区域的许可；锁定仍需满足可见性、距离与遮挡条件。转身中开枪沿当时朝向并使用实际发射时的准度。完整规则见[游玩说明](docs/gameplay/PLAY_GUIDE.md)。

## 配置接口

以下是 **Godot 检查器入口**。资源路径均相对 `movement_demo/`；修改实例子节点时可启用“可编辑子节点”。共享 `.tres` 会影响所有引用者，只调整一处时先设为唯一或另存副本。

### 玩家与相机

| 位置 | 可以配置 | 说明 |
| --- | --- | --- |
| Player | 移速、转速、加减速、耐力、蹲姿与翻越 | [移动](docs/gameplay/MOVEMENT.md) |
| Player → Combat → 目标切换 | `Mouse Target Assist Enabled` 开关、鼠标行程、方向半角、转身速度 | [锁定与精度](docs/gameplay/COMBAT.md) |
| Player → Combat | `Aim Mode` 弹道算法、蹲姿散布缩减、受击反应倍率 | [战斗配置](docs/gameplay/COMBAT.md) |
| Player → Equipment | 主副武器、初始槽、初始共享备弹、医疗包资源与数量 | [装备](docs/gameplay/WEAPON_SLOTS.md) |
| Player → Health | 最大生命、Debug 入口 | [生命与治疗](docs/gameplay/PLAYER_HEALTH.md) |
| Camera3D | `Player Path`、视野过渡、遮挡透明；视野范围跟随武器 `Aim Range` | [相机](docs/gameplay/CAMERA.md) |

### 武器与补给

武器统一由 Equipment 的 `Primary Weapon / Secondary Weapon` 引用，也可直接编辑 `resources/weapons/` 下的 WeaponData。

| 武器分组／资源 | 可以配置 | 说明 |
| --- | --- | --- |
| 基本信息、射击与弹药 | Fire Mode、伤害、射击间隔、射程、弹种、弹匣与换弹 | [开火方式](docs/gameplay/PLAYER_FIRE_MODES.md)、[弹药](docs/gameplay/AMMO.md) |
| 瞄准与散布 | 锁定距离／锥角、收敛公式与时间、散布、移动及跟枪损耗；玩家与敌人恢复入口独立 | [战斗](docs/gameplay/COMBAT.md) |
| 命中效果 → 精准爆头 | 起始准度、秒杀开关、伤害倍率、被爆头状态 | [爆头](docs/gameplay/COMBAT.md) |
| 近战 → 命中反馈 | 眩晕时间、保留移速、精度损失、击退、爆头破绽门槛倍率 | [近战](docs/gameplay/MELEE.md) |
| Shotgun | 弹丸图样、散布标定、随机偏移、逐发装填 | [霰弹](docs/gameplay/SHOTGUN.md) |
| `resources/ammo/types/` | 弹种 ID、掉落开关、每包数量与模型 | [补给](docs/gameplay/AMMO.md) |

爆头率在起始准度处为 0，之后线性升至满准度的 100%，仍须实际命中。近战破绽调整受击敌人的门槛，例如普通 80% × 0.8 = 64%；它不直接增加玩家准度。

### 敌人、关卡与内容

| 位置 | 可以配置 | 说明 |
| --- | --- | --- |
| Enemy 根节点 | 生命、速度、Weapon、屏外开火概率 | [敌人武器](docs/gameplay/ENEMY_WEAPON.md) |
| Enemy → Training → Profile | 感知、搜索、射击及战术解锁；修改后重新加载战斗 | [敌人 AI](docs/enemy-ai.md) |
| Squad → Profile | 仅视野共享、战术配合、强配合三档及队级参数 | [小队与 AI](docs/enemy-ai.md) |
| SceneDirector → Wave | 顺序/事件节点/请求出场、延迟、出生搜索、手动镜头目标；原小队部署保持 | [波次](docs/gameplay/ENEMY_WAVES.md) |
| SceneEvent、SceneDirector → Scene Rules | 选择来源信号或手动trigger；Wave/规则直接选择事件节点，配置动作 | [节点接线教程](docs/gameplay/SCENE_DIRECTOR.md) |
| `scenes/world/levels/` | 地形、导航、出生点、玩家装备和敌人部署；LevelFlow 保存关卡编号 | [关卡](docs/gameplay/LEVEL_MAPS.md) |
| Interactable、StageStateController | 交互条件与效果、Stage Table、任务及 NPC 状态 | [交互](docs/gameplay/INTERACTION.md)、[任务](docs/gameplay/STAGE_STATE.md) |
| Presentation、武器外观、ImpactProfile | 模型、动画映射与命中特效 | [表现接入](docs/gameplay/PRESENTATION.md) |

### 货币商店与任务金额

| 位置 | 可以配置 | 说明 |
| --- | --- | --- |
| `resources/shop/shop_catalog.tres` | 商品列表（顺序即显示顺序） | [货币商店](docs/gameplay/REWARDS.md) |
| ShopItemDefinition | 商品 ID、名称、说明、价格、解锁等级、效果、数值、武器引用、一次性 | 商品条目资源 |
| ShopCatalog → Items | 拖入／新建 `ShopItemDefinition` | 目录读取时过滤空项、空 ID、负价格、未知效果、缺 `WeaponData` 的武器商品与重复 ID |
| QuestDefinition → Money Reward | 完成时固定货币 | 默认 100；五个主线任务为 100，不奖励的任务显式设为 0 |
| Equipment | 主副武器槽 | 商店 `WEAPON` 商品购买时覆盖所选槽位 |

## 常用脚本接口

下表是扩展时常用的调用或订阅入口，详细职责见[项目结构](docs/project-layout.md)。资源保存配置，组件保存各实例运行状态。

| 所属组件 | 接口 | 用途 |
| --- | --- | --- |
| Equipment | `select_slot(slot)`、`ammo_snapshot()`、`add_ammo(definition, amount)` | 切槽、只读弹药快照、增加共享备弹 |
| Combat | `get_effective_accuracy()`、`get_target_headshot_chance(target)`、`is_turning_to_target()` | UI 读取基础准度、目标爆头率和转身状态 |
| Combat | `weapon_changed`、`shot_fired`、`headshot_resolved` 信号 | 相机、表现或统计订阅真实装备／射击结果 |
| Health | `receive_hit(damage)`、`restore_health(amount)`、`died` 信号 | 伤害、治疗与死亡通知 |
| GameState | `record_campaign_checkpoint(level, player_snapshot)`、`restore_campaign_checkpoint()` | 保存并恢复最近完成关卡时的酒店进度与玩家快照 |
| GameState | `add_money(amount)`、`spend_money(amount)`、`claim_task_reward(id, amount, level)`、`has_purchased_shop_item(id)` | 货币增减、一次性任务发奖与商店购买记录 |
| ShopController | `open_shop_for_player(player)`、`purchase(item_id, slot)`、`close_shop()` | 打开／关闭货币商店、复核并执行购买；面板只回传意图 |
| SceneDirector | `start_encounter()`、`request_wave(wave)`、`reset_encounter()`、`debug_snapshot()`；原波次信号保留 | 场景调度入口与波次兼容接口；核心通过director访问 |
| SceneEvent | `trigger()`、无参`triggered`；来源节点/信号/过滤由检查器配置 | 统一通知Wave或场景规则，不要求每种事件重写刷怪代码 |
| Interactable / InteractionEffect | `can_interact(player)`、`interact(player)`、`apply(context)` | 查询与执行交互、扩展单一效果 |
| StageStateController | `reload_table()`、`get_snapshot()`、`snapshot_changed` | 重新装配任务配置及只读状态展示 |

## 如何扩展

- **新增武器**：新建或复制 WeaponData，配置开火、弹药、精度与近战参数，保存到 `resources/weapons/`，拖入 Equipment 的槽位。玩家槽不接受专用近战武器；玩家近战使用手持枪械的附带参数。
- **新增弹种**：创建 AmmoDefinition，填写唯一 ID；让武器引用它，并在 Equipment 的 `Initial Ammo` 中添加 AmmoSupply。掉落开关、数量和模型在弹种资源内设置。
- **新增商店商品**：在 `ShopCatalog` 的 `Items` 数组里新建 `ShopItemDefinition`，填稳定 `Id`、名称、说明、价格与解锁等级；普通商品选 `HEAL`／`REFILL_AMMO`／`SYSTEM_PROGRESS` 并填数值，武器商品选 `WEAPON`、拖入现有 `WeaponData` 并把 `One Time` 打开。武器商品会覆盖玩家所选主／副槽，不复制枪械配置。
- **新增敌人或波次**：兵种放入Squad，再放到Wave；选择原顺序模式、事件节点模式或显式请求。事件和手摆镜头按[SceneDirector教程](docs/gameplay/SCENE_DIRECTOR.md)配置，无需迁移部署层。
- **接入新战斗地图**：复用带区域控制器的结构，保留CombatZone与导航；放入玩家、独立相机及SceneDirector，设置相机Player Path、部署并烘焙导航。见[关卡](docs/gameplay/LEVEL_MAPS.md)和[波次](docs/gameplay/ENEMY_WAVES.md)。
- **新增交互或表现**：交互物组合已有 InteractionEffect，新增效果通过 InteractionContext 使用注入的状态；模型、动画与特效通过表现组件接入。具体资源契约见对应专项说明。

## 文档与维护

[文档总目录](docs/README.md)按玩法、配置、结构和验证分类。[项目结构](docs/project-layout.md)说明文件职责与维护约束；[测试说明](docs/testing.md)列出运行器和验证方式；[敌人测试](docs/enemy-tests.md)记录 AI 专项与已知限制；[当前待办](docs/TODO.md)跟踪进度。

`movement_demo/scenes/` 保存场景，`scripts/` 保存运行代码，`resources/` 保存配置，`tests/` 保存验证，`logs/` 保存不提交的运行输出。Dialogue Manager、Phantom Camera、Godot AI 及项目自有检查器插件位于 `addons/`，第三方许可证随插件保留。

## 当前实现补充

医疗包操作：松开动作键后按 **H** 治疗，无需等待惯性停稳；默认两秒完成、恢复50生命，初始3个。动作输入或受击立即打断，中断不消耗。选中 `Player → Equipment`，在“医疗包”分组配置 **Medkit Count** 与 **Medkit** 资源，展开资源调整回血量／时间；Equipment（装备）为原 WeaponSlots 节点，统一管理武器与医疗包，见 [生命与医疗包](docs/gameplay/PLAYER_HEALTH.md)。

攻击武器可配置命中／压制精度损失（百分比）、擦过范围和击中速度损失。玩家 `Combat → 受击反应倍率`、敌人 `Training → Profile → tactics → 受击反应倍率` 各有三个可在检查器修改的倍率，射击与附带近战共用对应倍率；字段提示解释公式和关闭方式，见 [命中效果与倍率](docs/gameplay/COMBAT.md#命中压制与击中减速2026-10-24)。

酒馆门口现在串联五关流程：首次接取 A 任务后进入第1关；每关清场后先返回酒馆，再次与 A 对话才解锁下一关，门口传送门随解锁进度更新目标。跨关状态由 `GameState` 的一次性快照携带，酒馆商店购买的治疗、弹药和武器会继续带入下一关。死亡界面提供“重新挑战当前关卡”和“返回酒店”两项：前者按进入本关时的付费装备重开；后者恢复最近完成关卡的检查点，包括当时的玩家状态、货币、任务奖励和一次性购买记录、A 尚未解锁下一关的状态，并退还检查点之后的花费。任务面板默认隐藏，按 Tab 显示。

## 打开工程

1. 使用本工程已验证的 Godot 4.7.2 标准版。
2. 在 Godot 项目管理器中导入 `movement_demo/project.godot`。
3. 等待资源和插件首次导入完成，按 F5 进入酒馆；接取 A 的任务后，从门口传送门进入第1关。也可打开任意 `scenes/world/levels/lvl_N.tscn` 按 F6 单独试玩。

所需的 Dialogue Manager、Phantom Camera 和 Godot AI 插件源码及各自许可证随工程保存。Godot 可执行程序、导入缓存和临时文件不纳入仓库。

## 项目说明

- [后续总待办](docs/TODO.md)
- [五关游玩说明与连续闯关](docs/gameplay/PLAY_GUIDE.md)
- [操作与移动说明](docs/gameplay/MOVEMENT.md)
- [战斗说明](docs/gameplay/COMBAT.md)
- [玩家近战、近战兵战术与武器参数](docs/gameplay/MELEE.md)
- [竞技场说明](docs/gameplay/ARENA.md)
- [五张关卡地图与导航](docs/gameplay/LEVEL_MAPS.md)
- [场景交互物说明](docs/gameplay/INTERACTION.md)
- [货币商店与任务奖励](docs/gameplay/REWARDS.md)
- [阶段、任务与 NPC 状态](docs/gameplay/STAGE_STATE.md)
- [模型、动画与命中特效接入](docs/gameplay/PRESENTATION.md)
- [相机视野、武器绑定与遮挡透明](docs/gameplay/CAMERA.md)
- [敌人 AI 结构、维护与使用部署](docs/enemy-ai.md)
- [项目目录结构](docs/project-layout.md)
- [统一测试入口与维护](docs/testing.md)

运行脚本按职责位于 `movement_demo/scripts/`，敌人测试集中在 `movement_demo/tests/enemy/`。旧敌人实现和未引用的玩家射击原型已清理。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](docs/history/2026-10-28/README.md)。历史通过数不代表当前本地配置已重新验证。
