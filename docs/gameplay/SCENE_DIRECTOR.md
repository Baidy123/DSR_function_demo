# 场景导演使用指南

`SceneDirector` 统一安排本场的对话、商店、交互、脚本演出、镜头、波次、出口和切场景。日常交互直接请求，复杂演出使用 **Scene Rules → Actions**。伤害、库存、扣款、任务和刷怪细节仍由原组件执行。

## 新场景先这样接入

酒吧外、酒馆和五关已经装配，无需重复添加。新场景按以下步骤配置：

1. 把 `scenes/world/scene_director.tscn` 拖到场景根下，保留一份入口。
2. 在 **Health Path** 选择本场玩家的 Health；同级 Player 的路径是 `../Player/Health`。
3. 有 LevelFlow 时设置 **Result View Path**。**Guide Path** 默认留空，操作说明统一从 **Esc → 设置** 手动打开；只有另需开场教程时才显式绑定。没有 Wave 也能运行，不会自动通关。
4. 战斗场景沿用 CombatZone、Player、Camera3D 和 Wave → Squad → Enemy。Wave 放在导演入口下，第一关原根节点 Squad 仍由 Wave1 引用，无需移动。
5. 事件、动作和手摆镜头按后文配置。不要把整个区域或敌人设成 Always；内部调度器会处理暂停期间的 UI 和取消。

导演入口的 `director` 属性指向内部核心；代码用 `SceneDirector.for_node(self)` 查找本场核心。区域不会再暗中创建导演，缺少入口时会给出节点路径诊断。旧 `enemy_waves.tscn` 与脚本 UID 保留兼容，不要和新入口同时放置。

## NPC 对话与商店

普通 NPC 沿用现有 `npc.tscn`，配置对话资源与起点，并让其既有 `../DialogueUI` 路径指向本场对话界面。调用 `npc.request_dialogue(player)` 即可；获准后才转身和限制玩家。交互物自己的对话仍用 **ShowDialogueEffect** 拖入资源，见[交互说明](INTERACTION.md)。

商店沿用 RewardNPC、ShopController、ShopBoard：NPC 绑定本场控制器，控制器绑定面板和 ShopCatalog；商品添加方式见[商店配置](REWARDS.md)。`open_shop_for_player(player)`、`close_shop()` 会转交导演，购买仍用 `purchase(item_id, slot)`。有可见商品时暂停，空目录显示“暂无商品”且不暂停。

## 开场接线

`Opening` 节点负责阶段、交互范围与目标提示。剧情文本保存于 `resources/dialogue/opening.dialogue`。对话中的 `[#camera=booth]` 和 `[#camera=merchant]` 通过 `camera_cues` 选择镜头目标，镜头是对话的子请求。镜头返回后显示当前页回复。对话记录保留台词、内心独白和已选回复。

门帘默认有物理阻挡。开场敲隔断后，导演授权玩家穿过门帘，之后可双向感应开合。访客出卡座由演出短暂开帘，随后用后台移动请求沿路线走到酒馆正门再隐藏。直接 F6 运行酒馆时可在门帘前按 E 授权通行。

酒馆角色共用 `TavernNPC`。检查器中的 **Special NPC** 开关启用阶段状态和对话／商店，两种模式共用身体、坐姿和移动。初始角色填在座位节点的 **Initial Occupant Path** 中。拖入 **Route Path** 并开启 **Patrol On Ready** 可起动可见路线。访客走正门，送货伙计从吧台上方的员工门离场。

`TavernSeat` 是家具上的独立 `Marker3D`，记录位置、朝向和占用者。圆凳单点，普通沙发三点，两侧有座位的卡座每侧两点。玩家通过 **F** 向导演请求入座和离席。可在检查器调整点位、互动距离及 NPC 离席距离。

对白的 `sit` 标签向 SceneDirector 提交以座位为目标的 `script` 子请求。入座和对话后的离席都由座位执行碰撞检查、姿态和行走。商人对话绑定其正对面的座位。NPC 路线可在抵达后向导演请求座位或活动作为子动作。布景、座位和路线的编辑步骤见[酒馆编辑与调试](TAVERN_AUTHORING.md)。

`shop` 请求传入 `browse_only = true` 时，面板禁用购买按钮，`ShopController.purchase()` 同时拒绝交易。目录关闭后继续价格对话和交付。伙计以 `script` 子请求到桌前，放下箱子后立即提交后台离场请求，商人继续交付对白。装备通过现有装备快照一次性发放，仓库门沿用 QuestPortal 以及导演的跨关装备搬运。大姐头和商人的位置直接保存在主场景，`keep_authored_position` 使阶段刷新继续使用保存的位置。

两场通过 GameState 的 `opening_active` / `opening_complete` 交接。直接 F6 运行酒馆或完成开场后返程，使用酒馆的常规任务和商店入口。首次流程的付款、人物原则、接入制度和供应信息旗标由对应选项设置，活跃于本次运行。

默认先结束当前对话／商店，再播放事件镜头；忙碌时再次按 E 不会排队弹出另一个窗口。死亡立即取消当前演出与界面。关闭按钮、来源离场和场景卸载只释放本次控制，不解除其他拥有者的暂停。

## 脚本请求速查

已有 NPC、商店和 Interactable 接口都已转交导演。自定义入口可以直接提交请求：

```gdscript
const SceneDirector = preload("res://scripts/systems/scene_director.gd")

var director := SceneDirector.for_node(self)
if director == null:
    push_warning("当前场景缺少 SceneDirector")
    return
var request = director.request_action(&"dialogue", {
    "source": self, "target": dialogue_ui, "player": player,
    "origin": &"interaction",
    "parameters": {"resource": dialogue_resource, "start": "start", "face_source": true}
})
var result: Dictionary = await request.wait_result()
if result.status == &"completed":
    print("对话已结束")
```

`origin = interaction` 忙碌时拒绝，`rule` 排队。`parameters` 只放数据，节点分别放在 source／target／player／scope_owner；跨场节点和参数中藏入的节点会被拒绝。请求状态为 queued／running／completed／failed／cancelled／rejected；`wait_result()` 也可读取已同步完成的结果。用 `director.cancel_request(request.id, &"reason")` 取消；自定义持续逻辑见第五节，不要在批准前自行锁住玩家。

## 编辑器里主要操作什么

| 对象 | 怎么创建 | 配置内容 |
| --- | --- | --- |
| SceneDirector | 酒馆与五关已有；新场景拖入 `scene_director.tscn` | 玩家/UI绑定、可选引导、场景规则 |
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

三种 Start Mode 都在物理调度边界向导演申请部署，实际生成前再读取当前许可；回调只记录事件，不在信号栈中直接生成。原模板、导航、二次空间检查和每步最多提交一波保持。普通等待或另一波占位不会占住整场队列；需要前台镜头的增援会等当前对话／商店结束，再真实生成与展示。

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

将鼠标悬停在 **Kind** 属性名上查看用途与必填参数；新增 RUN_SCRIPT 后共有11种动作，旧资源编号保持。

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
| RESTART | 编排者配置的重载动作；当前五关未配置，不是玩家平时的重试入口 |
| CHANGE_SCENE | 请求 Scene Path 指定场景，失败可重试原目标 |

CALL_METHOD 不接受以下划线开头的私有方法，并检查参数数量和基础类型。即时方法留空 Completed Trigger；需要等待异步完成时，必须同时配置 **Completed Trigger** 与 **Cancel Method**（公开、无参停止方法），缺少取消契约会在执行前拒绝。订阅先于方法调用，不遗漏同步完成；滑门状态改变不等于 Tween 已经结束。

规则请求排队后，真正开始前会重新检查 **Condition**。条件已经失效时取消本次动作，原因是 `condition_changed`，不会先执行副作用。本次规则已触发，不自动重投；REGION 规则在所属区域复位后可以重新触发，SCENE 规则本场不重播。

## 五、接入可取消的脚本演出

复杂演出优先用 **RUN_SCRIPT**，Target Path 选实现 `begin_scene_action(request)` 与 `cancel_scene_action(request, reason)` 的节点。Arguments 保存在 request.parameters.arguments，执行者用 `request.complete()` 或 `request.fail(reason)` 报告实际结果。每次 await 后先检查 `request.is_current()`；取消时停止自己持有的 Timer、Tween 与动画，不能只断开完成通知。

例如节点下添加一次性 Timer，按下面的合同接入；持续逻辑仍留在自己的脚本中：

```gdscript
var active: SceneRequest

func _ready() -> void:
    $Timer.timeout.connect(_finished)

func begin_scene_action(request: SceneRequest) -> void:
    active = request
    $Timer.start()

func cancel_scene_action(request: SceneRequest, _reason: StringName) -> void:
    if active != request: return
    $Timer.stop()
    active = null

func _finished() -> void:
    if active != null and active.is_current(): active.complete()
    active = null
```

默认脚本演出占前台。只做局部背景动画的适配可提供 `scene_action_is_background() -> bool` 并返回 true，仍受死亡、区域复位与卸载取消管理。原滑门已这样接入：按 E、离开自动关门和防夹折返都通过导演，反向请求先取消旧 Tween。普通 WAIT／WAIT_SIGNAL／WAIT_WAVE_CLEARED 保持独立等待，不占全场前台。

## 六、交互与传送怎么接入

普通交互物继续用 Interactable 的 Effects 数组。`interact(player)` 先请求导演，忙碌拒绝不执行效果；返回 true 表示本次获准开始，`interacted` 表示全部效果真正完成。一次性记录和隐藏也在完成后提交。含对话的组合继承本次前台控制，不会把自己的子对话排队到自己结束之后。

切场景仍配置 **ChangeSceneEffect → Scene Path**。普通交互默认 plain；QuestPortal 自动准备入关快照，TavernReturnPortal 按原 Level Number 准备完成级别、返程快照与检查点，无需重配资源。准备不改变 GameState；引擎接受切换后才提交，目标 `_ready()` 已能读取，且快照仍只消费一次。切场成功后旧来源已离树，不补发旧节点的交互信号；跨场结果查询 transition 请求与业务状态。

普通门加载失败会归还本次控制，显示“交互失败，请重试”，再次按 E 重试当前配置目标。死亡／结果按钮和规则切换失败保留原暂停与重试界面；`request_load_retry()` 保留原路径与 reload 方式。源场景卸载后返回的旧异步加载结果无权提交状态。原检查点规则继续恢复医疗包资源、武器、弹药、货币及商店旗标。

引擎尚未接受加载时，可用 `cancel_request()` 取消加载请求或其父交互；来源离场也会取消，并恢复本次状态、界面与暂停所有权，迟到结果不能再提交。引擎接受切换后进入提交边界，旧来源正常离场不会把成功切换误判为取消。

规则的 Event Nodes 和高级 Triggers 都为空表示准备好后自动运行一次。不同规则可独立等待，事件回调只记录事实，动作在调度边界推进。普通等待在暂停时冻结，资源不保存本场执行进度。

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

- **Guide Path** 默认留空，当前五关进入与死亡重开不自动弹出操作说明；保留 `LevelFlow/PlayGuide` 节点路径，显式绑定的独立教程仍适配 `begin()/cancel()/finished`。允许走动的教程关闭 Guide Pauses World，核心不依赖 PlayGuide 类型。
- 导演初始化时装配一个 `PauseMenu`，不改变地图的 Wave／Squad 层级。`request_pause_menu()` 仅在可游玩、无加载失败、世界未暂停且没有前台请求／其他控制拥有者时取得 `pause_menu` 暂停；`resume_from_pause_menu()` 只释放该令牌。菜单回传暂停、继续和确认退出意图，设置／说明子页不自行恢复世界。菜单打开时不推进导演排队请求、普通规则或演出计时；死亡／加载等状态变化及卸载关闭菜单并保留其他暂停所有权。
- 暂停设置中的瞄准方式写入 `GameState.player_aim_control_override`，由玩家 Combat 读取。该选择独立于场景请求、暂停令牌和关卡快照。
- Health 只结算生命、停止玩家自身动作并发 `died`。调度器先取得死亡暂停，再取消镜头/动作，独立视图控制原 `Player/Health/DeathScreen`；“重新挑战”准备入关状态并重载当前场景，“返回酒馆”准备恢复最近酒馆检查点，再通过 `LevelFlow.next_scene_path()` 加载酒馆。两者均在加载接受后提交。没有 `LevelFlow` 适配器的通用场景隐藏“返回酒馆”，保留当前场景重开。
- 配置了 `LevelFlow.return_portal_path` 的五关在全部波次完成后只开放本关 `TavernReturnPortal`，不暂停世界，也不显示直接进入下一关的按钮。没有返程门的结果界面仍可暂停并显示原按钮；没有任何 Wave 不自动通关。
- `LevelFlow.completion_pauses_world()` 决定完成时是否取得暂停所有权：有返程门时返回 false，保留结果按钮时返回 true。该接口只影响完成，不改变死亡暂停。
- 离区仍由区域服务清理敌人、掉落与协同，调度器取消 REGION 规则和镜头。SCENE 开场和结果不重播；若 SCENE 规则正等旧轮波次，该等待明确取消诊断，不自动跨轮重投。

- 区域请求的 scope_owner 标明所属区域，`reset_region(region)` 只取消该区域的执行；不传参数沿用当前部署区域。另一区域的引导、镜头与 SCENE 请求不会被全局收尾分支误停。LevelFlow.show_completion 是兼容请求入口，真实出口启用由导演完成边界调用执行端。
- 关闭说明、结束镜头、旧场景卸载只释放自己的暂停，不清除别的拥有者。重开不清空 GameState。
- 死亡／结果／规则加载失败保留暂停并恢复重试按钮；普通交互失败归还控制。重试沿用上一次选择的路径和重载方式，不误用五关路径表。自定义无 UI 流程可读核心诊断并调用 `request_load_retry()`。

入口的 `director` 属性指向内部核心，`debug_snapshot().scene` 提供场景状态、暂停原因、规则进度与最近错误。原波次接口仍可用：`start_encounter()`、`request_wave(wave)`、`reset_encounter()`、`wave_started`、`wave_cleared`、`encounter_completed`。

同场多个区域通过查找共享已装配的核心。单独复用 Player 或区域时也要显式装配导演；Player 不自行暂停／重开，区域不创建替代核心。

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
| 请求被拒绝／没有导演 | 检查本场唯一入口、Health Path、核心是否准备好、目标是否仍在本场；查看 request.reason |
| 换关没继承装备 | 检查是否通过 QuestPortal／TavernReturnPortal、加载是否成功、一次性快照是否已被消费；plain 切换不自动准备战役快照 |

统一调度的约束见[设计](../superpowers/specs/2026-11-10-scene-director-authority-design.md)，实施与验证记录见[计划](../superpowers/plans/2026-11-10-scene-director-authority.md)和[测试说明](../testing.md)。实际地图的锚点位置与镜头手感由你调整，自动测试不替你决定构图。
