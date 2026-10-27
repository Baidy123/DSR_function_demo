# DSR_function_demo

基于 **Godot 4.7.2 与 GDScript** 的 3D 俯视角战斗功能原型。项目围绕锁定射击、精度损耗、近战破绽和敌人小队协作构建，包含连续五关、独立任务演示，以及可复用的玩家、武器、敌人、波次和表现组件。

[功能](#已实现的功能) · [操作](#玩家操作) · [配置接口](#配置接口) · [脚本接口](#常用脚本接口) · [扩展方法](#如何扩展) · [完整文档](docs/README.md)

## 已实现的功能

| 模块 | 当前能力 |
| --- | --- |
| 玩家移动 | 转向、加减速、奔跑与耐力、蹲姿、半身掩体与翻越 |
| 锁定与射击 | 方向键转向锁定、可开关的鼠标辅助选敌／换锁、平滑转身、单发／自动／霰弹、真实射线与遮挡 |
| 精度与爆头 | 移动、跟枪、开火和受击损耗；三种收敛公式；按准度线性增加的爆头率 |
| 近战 | 枪械附带近战、专用近战兵、击退与眩晕反馈；玩家近战为受击敌人提供一次爆头门槛优惠 |
| 装备与补给 | 主副武器槽、按弹种共享备弹、整匣／逐发装填、缺弹掉落、医疗包与死亡重开 |
| 敌人 AI | 巡逻、视觉／听觉、追踪与搜索、掩体、近远程攻击；个人决策与三档小队配合 |
| 关卡流程 | 场景节点配置敌人波次、连续五关、入场说明、通关按钮与当前关重开 |
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
| EnemyWaves → Wave | 顺序、等待前波、延迟、出生搜索；Wave 下的小队与敌人决定部署 | [波次](docs/gameplay/ENEMY_WAVES.md) |
| `scenes/world/levels/` | 地形、导航、出生点、玩家装备和敌人部署；LevelFlow 保存关卡编号 | [关卡](docs/gameplay/LEVEL_MAPS.md) |
| Interactable、StageStateController | 交互条件与效果、Stage Table、任务及 NPC 状态 | [交互](docs/gameplay/INTERACTION.md)、[任务](docs/gameplay/STAGE_STATE.md) |
| Presentation、武器外观、ImpactProfile | 模型、动画映射与命中特效 | [表现接入](docs/gameplay/PRESENTATION.md) |

## 常用脚本接口

下表是扩展时常用的调用或订阅入口，详细职责见[项目结构](docs/project-layout.md)。资源保存配置，组件保存各实例运行状态。

| 所属组件 | 接口 | 用途 |
| --- | --- | --- |
| Equipment | `select_slot(slot)`、`ammo_snapshot()`、`add_ammo(definition, amount)` | 切槽、只读弹药快照、增加共享备弹 |
| Combat | `get_effective_accuracy()`、`get_target_headshot_chance(target)`、`is_turning_to_target()` | UI 读取基础准度、目标爆头率和转身状态 |
| Combat | `weapon_changed`、`shot_fired`、`headshot_resolved` 信号 | 相机、表现或统计订阅真实装备／射击结果 |
| Health | `receive_hit(damage)`、`restore_health(amount)`、`died` 信号 | 伤害、治疗与死亡通知 |
| EnemyWaves | `start_encounter()`、`reset_encounter()`；`wave_started`、`wave_cleared`、`encounter_completed` | 波次控制及完成通知；日常部署用场景节点 |
| Interactable / InteractionEffect | `can_interact(player)`、`interact(player)`、`apply(context)` | 查询与执行交互、扩展单一效果 |
| StageStateController | `reload_table()`、`get_snapshot()`、`snapshot_changed` | 重新装配任务配置及只读状态展示 |

## 如何扩展

- **新增武器**：新建或复制 WeaponData，配置开火、弹药、精度与近战参数，保存到 `resources/weapons/`，拖入 Equipment 的槽位。玩家槽不接受专用近战武器；玩家近战使用手持枪械的附带参数。
- **新增弹种**：创建 AmmoDefinition，填写唯一 ID；让武器引用它，并在 Equipment 的 `Initial Ammo` 中添加 AmmoSupply。掉落开关、数量和模型在弹种资源内设置。
- **新增敌人或波次**：选择兵种场景，按需另存训练资源；将敌人放入 Squad，再放到 Wave 下。配合等级由 Squad 决定，先后顺序由 Wave 的树序决定。
- **接入新战斗地图**：复用带区域控制器的关卡结构，保留 CombatZone 与导航；放入玩家、独立相机及 EnemyWaves，设置相机 `Player Path`，部署并烘焙导航。完整步骤见[关卡](docs/gameplay/LEVEL_MAPS.md)和[波次](docs/gameplay/ENEMY_WAVES.md)。
- **新增交互或表现**：交互物组合已有 InteractionEffect，新增效果通过 InteractionContext 使用注入的状态；模型、动画与特效通过表现组件接入。具体资源契约见对应专项说明。

## 文档与维护

[文档总目录](docs/README.md)按玩法、配置、结构和验证分类。[项目结构](docs/project-layout.md)说明文件职责与维护约束；[测试说明](docs/testing.md)列出运行器和验证方式；[敌人测试](docs/enemy-tests.md)记录 AI 专项与已知限制；[当前待办](docs/TODO.md)跟踪进度。

`movement_demo/scenes/` 保存场景，`scripts/` 保存运行代码，`resources/` 保存配置，`tests/` 保存验证，`logs/` 保存不提交的运行输出。Dialogue Manager、Phantom Camera、Godot AI 及项目自有检查器插件位于 `addons/`，第三方许可证随插件保留。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](docs/history/2026-10-28/README.md)。历史通过数不代表当前本地配置已重新验证。
