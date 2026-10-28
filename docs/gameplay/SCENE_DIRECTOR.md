# 场景总调度：节点接线教程

`SceneDirector` 是原 `EnemyWaves` 升级后的场景入口，负责可选引导、事件动作、敌人出场、演出镜头、死亡重开及通关切关。现有五关只改入口名称和必要引用；CombatZone、Player、Camera3D、Wave → Squad → Enemy 的分工和摆放保持，第一关根上的原 Squad 仍由 Wave1 引用。

新场景使用 `scenes/world/scene_director.tscn`。旧 `enemy_waves.tscn` 和 `enemy_wave_controller.gd` 保留兼容与原脚本 UID，不要在同一区域同时放两套调度器。五关装备、训练、导航和地图数值未由本功能重配。

## 编辑器里主要操作什么

| 对象 | 怎么创建 | 配置内容 |
| --- | --- | --- |
| SceneDirector | 五关已有；新场景拖入 `scene_director.tscn` | 玩家/UI绑定、可选引导、场景规则 |
| SceneEvent | 拖入 `scenes/world/scene_event.tscn`，自行改名 | 来源节点、来源信号、可选过滤；也可手动触发 |
| Wave | 原 `enemy_wave.tscn`，部署方式不变 | 出场模式、事件节点列表、延迟、出场镜头 |
| Marker3D | 在3D编辑器创建并手动摆放 | 镜头画面中心；也可直接绑定已有 Node3D |

例如需要事件增援时，可以增加两个普通容器。它们是可选命名，不要求改造现有关卡：

```text
Lvl1
├─ CombatZone
├─ SceneDirector
│  ├─ Wave1
│  └─ Wave2
│     └─ Squad
│        └─ Enemy...
├─ Squad                         第一关原第一波，保留位置
├─ SceneEvents                   普通 Node，可自行命名
│  └─ CallReinforcements          scene_event.tscn 实例
├─ CameraPoints                  普通 Node3D，可自行命名
│  └─ ReinforcementLookAt         手摆 Marker3D
├─ Player
├─ Camera3D                      原跟随相机及 Phantom 链
└─ LevelFlow
   └─ PlayGuide                  临时、可移除的说明
```

**Wave 下仍只放 Squad，事件节点和标记不要塞进部署层。**检查器悬停属性名可看中文说明；动作类型与过滤类型切换后，只显示需要填写的参数。

## 一、绑定事件节点，让指定 Wave 出场

以项目现有 CombatZone 的玩家进入信号演示。你也可以换成自己放置的 Area3D、Timer 或交互节点。

1. 在关卡根下创建普通 Node `SceneEvents`，拖入 `scene_event.tscn`，改名 `CallReinforcements`。
2. 选中事件节点，把 **Source Path** 选为 CombatZone；按上图结构是 `../../CombatZone`。
3. **Signal Name** 下拉选择 `body_entered`。先选来源，再选信号，列表来自实际节点。
4. **Filters** 加一项并新建 `SceneEventFilter`：`Parameter Index = 0`，`Operator = NODE_IN_GROUP`，`Group Name = player`。这样敌人进入不算事件。
5. 选中 Wave2，将 **Start Mode** 改为 `EVENTS`。
6. Wave2 的 **Event Nodes** 加一项，选择 CallReinforcements；按上图是 `../../SceneEvents/CallReinforcements`。不用再填信号名，Wave 监听标准 `triggered`。
7. 保留原小队、敌人和出生点，调整 **Start Delay Seconds** 后试玩。

这个示例在玩家入区时触发 Wave2，可与 Wave1 独立等待；它是接线示例，并未替现有关卡开启。三种模式如下：

| Start Mode | 条件 |
| --- | --- |
| SEQUENCE | 保留原相邻上一波出场/全灭后等待 |
| EVENTS | Event Nodes 与高级 Triggers 按 ANY/ALL 满足后等待 |
| REQUEST | 由场景动作 REQUEST_WAVE 或公开请求接口启动 |

同一个事件可以被多个 Wave 选择。一个 Wave 也可选多个事件：**ANY** 任意一个发生即可，**ALL** 本轮每个都发生过。每波每轮只生成一次，重复通知不重复刷新。

事件先发生、玩家随后入区也能衔接；刷新仍检查区域资格、暂停、死亡、对话、完整身体空间和导航。某波出生点被占，不阻塞其他独立合法请求；每个物理步最多成功提交一波。离区复位重新等待本轮事件，暂停不替来源伪造信号，默认 Timer 在暂停中也不计时。

## 二、让自己的脚本发事件

原节点已经声明信号时，通常只需绑定 Source Path / Signal Name，无需改脚本。例如 `Interactable.interacted` 表示交互真正成功，`blocked` 不算成功。

也可让 SceneEvent 的 **Source Path 留空**，在你自己的成功回调里直接触发：

```gdscript
# 本脚本位于上图的关卡根。在真实交互成功、机关完成等位置调用。
$SceneEvents/CallReinforcements.trigger()
```

无参信号也能通过编辑器“节点 → 信号 → 连接 → 高级”连到 SceneEvent 的 `trigger()`。有参数的信号推荐使用来源绑定，由 SceneEvent 适配和过滤，避免回调参数不匹配。项目已有 `CallMethodEffect` 也可以调用目标事件节点的公开 `trigger` 方法。

如果你的脚本节点本身声明 **无参 `signal triggered`**，可以直接让 Wave 选择该节点，不必再套 SceneEvent。带参原信号则使用适配节点或高级 Triggers。

事件节点不保存某个 Wave 的引用，是 Wave 选择监听谁；同一个事件还可被场景规则使用。不要循环接线。已经有效发出事件的拾取物随后删除是允许的；先离树再发出的过期信号不会推进流程。

## 三、手摆目标，展示真实增援

只需要增援镜头时，直接配 Wave，不必先建场景规则：

1. 在 CameraPoints 下创建 `Marker3D`，改名 `ReinforcementLookAt`，在3D视图摆到想关注的地方。
2. 选中对应 Wave，展开 **出场镜头**，开启 **Show Spawn Presentation**。
3. **Presentation Target Path** 选择这个标记；按上图是 `../../CameraPoints/ReinforcementLookAt`。也可选已有 Node3D。
4. 配置 **Presentation Move Seconds / Hold Seconds / Return Seconds**，分别为移过去、停留、返回的秒数。
5. **Presentation Size** 为0时保留玩家当前正交视野；大于0可指定这次展示范围，不改玩家武器参数。

标记表示 **画面看哪里**，不是把相机机身放在这里；保留原俯视倾角。不会自动替你选敌人中心或摆锚点。未绑定、目标删除或不在树内时，诊断并跳过镜头，不重刷已生成敌人。

执行顺序：真实生成成功 → 在公开出场通知前冻结战斗 → 第二台相机复制玩家当前画面并切入 → 移到手选目标 → 返回玩家最新画面并切回 → 释放本次暂停。出生点受阻时不提前看空位置。原玩家相机仍由 Phantom 和武器视野组件控制。

**不用手放第二台相机。**默认首次需要时创建内部 PresentationCamera；想手动装配，可拖入 `scenes/player/presentation_camera.tscn` 并在 SceneDirector 的 **Presentation Camera Path** 选择它。不要选原玩家 Camera3D。

SceneDirector 另有可选“统一出场镜头”，适合所有波使用同一手动目标。优先级：场景动作专属请求 → Wave 自己开启的镜头 → 整场默认。当前五关镜头开关默认关闭，目标由你摆放后开启。

## 四、事件之后安排多个动作

单纯刷怪及出场展示用前三节即可。需要顺序流程时，配置 SceneDirector 的 **Scene Rules**：

1. 添加 `SceneFlowRule`，写 **Label**，例如“交互后增援”。
2. **Event Nodes** 选择事件节点。这里路径相对 **SceneDirector**，如 `../SceneEvents/CallReinforcements`。
3. **Scope = REGION**：本轮区域战斗一次，复位可重播；**SCENE**：本场一次，出入区域不重播。
4. **Actions** 按顺序添加 `SceneFlowAction`，先选 **Kind**，再填相关字段。

例如“事件 → 等1秒 → 请求Wave2 → 等清空 → 调已有公开方法”：

| 顺序 | Kind | 配置 |
| --- | --- | --- |
| 1 | WAIT | Seconds = 1 |
| 2 | REQUEST_WAVE | Target Path = `Wave2`；Wave2 设成 REQUEST 模式 |
| 3 | WAIT_WAVE_CLEARED | Target Path = `Wave2` |
| 4 | CALL_METHOD | Target Path 选已有对象，Method 写公开方法名，Arguments 按真实签名填 |

REQUEST_WAVE 等真实生成才继续；若勾选 **Present Spawn**，动作的 **Presentation Target Path** 手选标记（相对 SceneDirector），留空则使用 Wave 自己绑定的目标。两处都没有目标时跳过镜头并诊断。不要让同一部署由两份无约束配置反复请求。

| 其他动作 | 用途 |
| --- | --- |
| PRESENT_TARGET | 单独展示 Target Path 指向的 Marker3D/Node3D，不要求刷怪 |
| GUIDE | 调用 begin() 并等待无参 finished，可选择是否暂停 |
| WAIT_SIGNAL | 等待 Completed Trigger 的来源信号及过滤结果 |
| COMPLETE_SCENE | 请求完成，必要镜头结束后显示结果，同帧死亡优先 |
| RESTART | 请求重载当前场景 |
| CHANGE_SCENE | 请求 Scene Path 指定场景，失败可重试原目标 |

CALL_METHOD 不接受以下划线开头的私有方法，并检查参数数量和基础类型。需要等动画或异步执行结束时配 **Completed Trigger**，订阅先于方法调用；留空只表示调用返回。例如现有滑门的状态改变不等于 Tween 已经结束，不能当作移动完成。

Event Nodes 和高级 Triggers 都为空表示准备好后自动运行一次。不同规则可独立等待，事件回调只记录事实，动作在调度边界推进。普通等待在暂停时冻结，资源不保存本场执行进度。

## 路径和过滤速查

| 配置位置 | 路径相对谁 | 上图例子 |
| --- | --- | --- |
| Wave 的 Event Nodes / Triggers / 镜头 | 此 Wave | `../../SceneEvents/CallReinforcements` |
| SceneFlowRule / SceneFlowAction | SceneDirector | `../CameraPoints/ReinforcementLookAt` |
| SceneEvent.Source Path | 此事件节点 | `../../CombatZone` |
| 全局状态来源 | 可用绝对路径 | `/root/GameState` |

高级 **Triggers** 可直接新建 `SceneEventTrigger`，填写来源路径、信号名、过滤；与 Event Nodes 一起按 ANY/ALL 组合。信号支持0～8个参数，索引从0开始，同一事件的 Filters 必须全部满足。

| 项目实际信号 | 常用过滤 |
| --- | --- |
| Area3D.body_entered(body) | 参数0：NODE_IN_GROUP / player |
| Interactable.interacted(interactable, player) | 参数1：NODE_IN_GROUP / player |
| GameState.item_gained(item_id: StringName, display_name: String, total: int) | 参数0：EQUALS / STRING_NAME，填写实际物品ID |
| GameState.flag_changed(flag: StringName, value: bool) | 参数0：STRING_NAME旗标名；参数1：BOOL=true |
| Timer.timeout、Wave.spawned、Wave.cleared | 无参，不填过滤 |

String 不等于 StringName，整数1不等于布尔true。需要“事件发生过，且当前旗标仍成立”时可用规则的可选 Condition：目标 `/root/GameState`、方法 `has_flag`、参数为实际 StringName ID；查询必须返回 bool。

## 开场、死亡、完成和取消

- 清空 **Guide Path** 或移除 PlayGuide 即可跳过临时说明。未来教程适配 `begin()/cancel()/finished`；允许走动的教程关闭 Guide Pauses World。核心不依赖 PlayGuide 类型。
- Health 只结算生命、停止玩家自身动作并发 `died`。调度器先取得死亡暂停，再取消镜头/动作，独立视图控制原 `Player/Health/DeathScreen`；按钮只报告重开请求。
- 当前五关仍按全部波次完成显示原按钮，第5关回第1关。无结果UI的旧独立波次场景只报告完成，不强制通关暂停；没有任何 Wave 不自动通关。
- 离区仍由区域服务清理敌人、掉落与协同，调度器取消 REGION 规则和镜头。SCENE 开场和结果不重播；若 SCENE 规则正等旧轮波次，该等待明确取消诊断，不自动跨轮重投。
- 关闭说明、结束镜头、旧场景卸载只释放自己的暂停，不清除别的拥有者。重开不清空 GameState。
- 加载失败保留暂停并恢复重试按钮；事件切场景失败重试原路径，不误用五关路径表。自定义无UI流程可读核心诊断并调用 `request_load_retry()`。

入口的 `director` 属性指向内部核心，`debug_snapshot().scene` 提供场景状态、暂停原因、规则进度与最近错误。原波次接口仍可用：`start_encounter()`、`request_wave(wave)`、`reset_encounter()`、`wave_started`、`wave_cleared`、`encounter_completed`。

旧 Main 没有波次入口时，区域为场景玩家装配同一个核心处理死亡，并防止多区域重复接管。单独复用 Player 不再自行暂停/重开，应由所在场景接入调度。

## 排错

| 现象 | 检查 |
| --- | --- |
| 选了事件不刷怪 | EVENTS模式、事件路径、过滤、是否真实触发、玩家是否在有效区域、是否暂停 |
| 事件节点没有信号下拉项 | 先选有效Source Path，来源脚本必须真实声明信号 |
| ALL永远等 | 是否包含不会发生的条件或依赖自己的出场/清空；检查诊断 |
| 占位时镜头不动 | 正常，必须先真实生成；不要单独播放镜头冒充增援已到 |
| 已刷敌人却无镜头 | 检查开关、手动目标、目标是否在树内及最近诊断 |
| 构图不合意 | 移动Marker3D的世界位置，调整Size；不要移动玩家相机 |
| 说明关闭后仍暂停 | 检查pause.reasons是否还有死亡、结果或其他拥有者 |
| 换关没继承装备 | 当前仍按各关保存配置；PlayerSession/角色绑定属于后续连续模式，不擅自更改携带规则 |

使用依据见[设计](../superpowers/specs/2026-10-25-enemy-wave-event-triggers-design_todo.md)，验证见[实施计划](../superpowers/plans/2026-10-28-scene-director-implementation.md)。实际地图的锚点位置与镜头手感由你调整，自动测试不替你决定构图。
