# 酒馆编辑与调试

## 场景入口和生命值

按 **F5** 运行 `project.godot` 中的 Main Scene，当前为 `scenes/access_denied/hub/tavern_exterior.tscn`。外景的 `Player/Health` 设置 **Max Health = 100**，开局满血。打开 `scenes/main.tscn` 按 **F6** 可直接测试酒馆。酒馆、战斗关卡与共享玩家预制体的生命值仍可分别在各自场景的 **Player → Health** 调整。

在 Main 展开 `BarEnvironment` 就能直接编辑墙、地板、吧台、桌椅位置和灯光。单件家具仍引用可复用的模板。如果要调整某个实例内部的座位点，右键它开启 **Editable Children**。正式入口使用 Main 内的节点。原 `svg_tavern_environment.tscn` 可用于查阅旧布景。

带门帘卡座的 `Booth4/Seating/Sofa` 默认由 `curved_booth_sofa.gd` 在编辑器预览和运行时生成沙发网格。底座、坐垫和靠背的材质在 `privacy_booth_seating.tscn` 的 `Sofa` 节点上配置。保存场景时跳过生成的网格数据。要使用自制网格，将其存为外部资源后赋给 `Sofa` 的 **Mesh** 字段。

吧台北端在 `BarEnvironment/BarCounter/NorthReturn` 向内拐，占原开口约三分之二。`NorthPartition` 是接到墙边的齐台面木隔门，两段各有碰撞体。调整这两处时，让柜体、隔门与墙面在地面一侧连续，并给北面通往员工门的路线留出空间。

开场的 **E 询问酒保** 提示跟随 `BarEnvironment/BarCounter/Bartender`。移动酒保后，可交谈范围会沿吧台一起移动。柜体 `Long/Collision` 的本地 **+X** 侧是客人侧。

## 开场发放装备

打开酒馆场景，展开 **Opening → EquipmentGrant**。在检查器调整 **Weapon**、**Weapon Slot**、**Ammo Supplies** 和 **Medkit Amount**。这里的实例来自 `scenes/world/opening_equipment_grant.tscn`，只保存“发什么”；何时发放由 **SceneDirector → Event Sequences → opening_delivery_equipment** 的 `GiveEquipmentAction` 决定。预制场景默认是主武器槽的测试冲锋枪、60 发备弹和 1 个医疗包；`main.tscn` 中的实例可以保存自己的覆盖值，实际测试和调参应以当前实例检查器显示值为准，不要用预制默认值覆盖实例。发放接线与其他场景复用方式见[导演教程](SCENE_DIRECTOR.md#用导演发放装备)。

## 在检查器编辑开场事件

开场跨节点流程不再写成 `opening_sequence.gd` 里的一长串直接调用。选中每个场景自己的 **SceneDirector**，在 **Event Sequences** 队列添加、删除、排序并展开编辑 `SceneEventDefinition` 与其 `SceneAction`：

- 外景 `tavern_exterior.tscn` 保存 `opening_arrival` 和 `opening_scene_transition`，负责车内对白、下车、入口镜头以及进入酒馆。
- 酒馆 `main.tscn` 保存酒保指引、访客出帘／移动／镜头／对白／离场、敲门帘、大姐头委托、商人目录、送货、伙计离场和装备发放。访客移动单列为 `opening_visitor_motion`，并排在镜头事件之前，使移动请求先提交、镜头暂停世界后仍能继续。主要入口 ID 包括 `opening_visitor_entrance`、`opening_visitor_motion`、`opening_commissioner_seating`、`opening_merchant_catalog`、`opening_delivery_equipment` 与 `opening_runner_departure`。
- `Opening` 节点仍负责当前阶段、交互距离、目标提示和少量场景本地机械适配；对白、镜头、座位、NPC 定向移动、装备和转场的先后顺序以 Event Sequences 为准。

新增步骤时先选最具体的动作类型，例如 `DialogueAction`、`CameraAction`、`MoveActorAction`、`SeatActorAction`、`GiveEquipmentAction` 或 `ChangeSceneAction`。只有目标组件已经提供导演 provider 契约、但目录中没有更具体动作时，才用 `RunProviderAction`。它的 **Request Kind** 可选 Script 或 Shop；开场只读目录直接在动作中填写 Shop、`ShopController`、Player Path 和 `browse_only`，不再由 `Opening` 子请求商店。事件的 NodePath 都相对当前 SceneDirector 宿主填写；`DialogueAction` 会把 Camera/Seat Cue 的宿主相对路径转换成 DialogueUI 可用路径，外景对象不要跨场引用 Main 对象。

## 放 NPC 和设置坐席

1. 在 Main 实例化 `scenes/access_denied/hub/tavern_npc.tscn`，命名并摆好站位。仅当需要阶段状态、对话或商店时，勾选 **Special NPC** 并填写相应资源。
2. 在对应家具展开 `SeatPoint` 或 `Seats`，选中一个挂载 `TavernSeat` 的 `Marker3D`，把 NPC 本体拖入 **Initial Occupant Path**。开场坐姿由座位的初始占用触发。NPC 站在坐垫上时，先选中座位检查此字段，然后重新打开 Main 确认绑定已经保存。
3. 拖动座位点到坐垫上方。座位点的本地 **-Z** 是角色入座后的固定朝向。圆凳的座位点沿用凳子自身的朝向，摆放时绕 Y 轴旋转凳子根节点，使它面向相邻的桌子、吧台或终端。其他家具可直接旋转座位标记。**Reach** 控制入座距离，**Npc Exit Distance** 控制 NPC 离席时向前寻找落脚点的距离。座位已占用时其他人不能使用。
4. 玩家可以自由按 F 入座、起身。开场大姐头和商人段落由对话行的 `[#sit=commissioner]`、`[#sit=merchant]` 触发入座。座位 cue 与路径分别保存在 `opening_commissioner_seating`、`opening_merchant_catalog` 的 `DialogueAction → Seat Cues`，对白后的离席由同一事件里的 `SeatActorAction` 配置。剧情会先找可站立的落脚点，沿可通行路线走近，再按座位的固定朝向忽略碰撞落座。无通路或途中受阻时，玩家直接坐到指定空座。对话或交付结束后，导演检查站立落脚点并安排起身。返程通道受阻时，原站位有地面和站立空间即可直接回到原处。给玩家胶囊留出通道有助于保留完整走位演出。离席点被占时可等通道清空后按 F。
5. 商人对话固定使用 `Tables/Setting1/SouthSofa/Seats/Center`，与商人隔桌正对。大姐头对话若开始时玩家已经坐在同桌另一座位，会保留实际座位；事件结束时 `SeatActorAction` 读取并离开玩家当前座位，而不是强制操作 cue 的候选座位。`Setting1/Table` 向商人侧偏移 0.24 米，给主角一侧留了入座通道。调整桌椅后，可在开场实际走一遍，核对胶囊能通过且两人仍面对面。

## 用鼠标摆行走路线

1. 在 Main 的 `TavernRoutes` 下新建一个 **Node3D**，挂载 `scripts/world/tavern_route.gd`。
2. 给它添加 **Marker3D** 子节点。选中标记，用 3D 视口的移动工具拖到想经过的地方。角色按场景树从上往下经过各点，可以在场景树拖动顺序；点名仅用于识别。贴地高度由 NPC 的地板配置修正。
3. 在 NPC 的 **Route Path** 拖入该路线节点。勾选 **Patrol On Ready** 表示 NPC 入场后自行循环或执行这条本地日常路线；它不属于剧情事件队列。剧情中的固定移动在 **SceneDirector → Event Sequences** 添加 `MoveActorAction`，分别选择 **Actor Path** 和一个 **Target Path** 或 **Route Path**。因此“NPC 自己巡逻”和“事件导演让 NPC 去某处”不会混在同一个开关里。
4. 在路线节点选 **Finish Mode**。**Stay** 到终点后停留，**Loop** 到终点后等待 **Loop Interval** 秒再从第一个点重走，**Despawn** 到终点才离场。`MoveActorAction` 默认继承路线自己的 Finish Mode；勾选动作的 **Vanish At End** 才会强制本次移动在终点隐藏。NPC 上的 **Waypoint Pause** 控制循环途中停留，**Walk Speed** 控制速度。拖拉时预留足够的过道，运行时 NPC 会尝试绕过临时挡路的角色。镜头暂停世界时仍要继续走位的专用演出，可在该动作开启 **Process While Paused**；普通移动不要开启。
5. **Sit** 会请求终点入座。把座位点拖进 **Finish Seat Path**，并把最后一个路点放在空座位附近的地面上。座位会检查 **Reach**、遮挡和碰撞空间。**Activity** 会请求终点动作。把动作节点拖进 **Finish Activity Path**。**Finish Activity Method** 可填该节点的无参公开方法。留空时节点提供 `begin_scene_action(request)` 和 `cancel_scene_action(request, reason)`，由 `request.node(&"source")` 取得 NPC，演出结束时调用 `request.complete()` 或 `request.fail(...)`。
6. 员工门路线的 **Exit Gate Path** 指向 `BarEnvironment/Architecture/StaffDoor`。最后两点分别放在门前与门后。伙计路线是 `RunnerToStaffDoor`，访客从正门离开的路线是 `VisitorToEntrance`。
7. 伙计的送货点是 `BarEnvironment/SouthLounge/Tables/Setting1/Table/RunnerDeliveryPoint`。点位沿桌面短边居中，标记的本地 **-Z** 指向桌子。伙计经 `RunnerToStaffDoor/Point01` 进入，在桌前放下箱子，然后立即原路走出桌边过道并继续去员工门。商人交付对白和伙计离场同时进行。主角在对白结束且伙计走出桌边过道后才起身，给双方留出通行空间。

## 货币和以后新增掉落

余额在自动加载的 `GameState.money`，玩家角色跨场景更换时继续读取同一余额。入账用 `GameState.add_money(amount)`，扣费用 `GameState.spend_money(amount)`，界面可订阅 `money_changed`。任务奖励和商店恢复规则见[货币系统](REWARDS.md)。

后续加死亡金币掉落时，可让场景掉落组件接敌人真实死亡事件，生成一件可拾取物。地面位置检查可参考 `ammo_drop_position.gd`，拾取防重复可参考 `ammo_pickup.gd`。只有拾取成功才调用 `add_money`。当前重新挑战只恢复玩家入关快照，余额仍保留。新增掉钱前需要选定同一波敌人重试能否重复产出，或者将掉落入账纳入相应检查点的恢复策略。
