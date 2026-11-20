# 酒馆编辑与调试

## 场景入口和生命值

按 **F5** 运行 `project.godot` 中的 Main Scene，当前为 `scenes/access_denied/hub/tavern_exterior.tscn`。外景的 `Player/Health` 设置 **Max Health = 100**，开局满血。打开 `scenes/main.tscn` 按 **F6** 可直接测试酒馆。酒馆、战斗关卡与共享玩家预制体的生命值仍可分别在各自场景的 **Player → Health** 调整。

在 Main 展开 `BarEnvironment` 就能直接编辑墙、地板、吧台、桌椅位置和灯光。单件家具仍引用可复用的模板。如果要调整某个实例内部的座位点，右键它开启 **Editable Children**。正式入口使用 Main 内的节点。原 `svg_tavern_environment.tscn` 可用于查阅旧布景。

## 放 NPC 和设置坐席

1. 在 Main 实例化 `scenes/access_denied/hub/tavern_npc.tscn`，命名并摆好站位。仅当需要阶段状态、对话或商店时，勾选 **Special NPC** 并填写相应资源。
2. 在对应家具展开 `SeatPoint` 或 `Seats`，选中一个挂载 `TavernSeat` 的 `Marker3D`，把 NPC 本体拖入 **Initial Occupant Path**。初始占用归座位配置。运行时 NPC 只保存自己当前所坐的座位引用。
3. 拖动座位点到坐垫上方。绕 Y 轴旋转标记，标记的本地 **-Z** 就是角色入座后的固定朝向。**Reach** 控制玩家按 F 入座的距离，**Npc Exit Distance** 控制 NPC 离席时向前寻找落脚点的距离。座位已占用时其他人不能使用。
4. 玩家可以自由按 F 入座、起身。开场大姐头和商人段落由对话行的 `[#sit=commissioner]`、`[#sit=merchant]` 触发入座。按优先级把座位路径填入 `opening_sequence.gd` 的 `SEAT_CUES`，首选座位受阻时导演会试下一个。对话结束或装备交付后，导演会请求释放剧本安排的座位。离席点被占时仍可等通道清空后按 F。

## 用鼠标摆行走路线

1. 在 Main 的 `TavernRoutes` 下新建一个 **Node3D**，挂载 `scripts/world/tavern_route.gd`。
2. 给它添加 **Marker3D** 子节点。选中标记，用 3D 视口的移动工具拖到想经过的地方。角色按场景树从上往下经过各点，可以在场景树拖动顺序；点名仅用于识别。贴地高度由 NPC 的地板配置修正。
3. 在 NPC 的 **Route Path** 拖入该路线节点。勾选 **Patrol On Ready** 可让 NPC 入场自行提交路线请求。剧情角色可以保留此项关闭，等 Scene Director 的 `script` 请求启动。
4. 在路线节点选 **Finish Mode**。**Stay** 到终点后停留，**Loop** 到终点后等待 **Loop Interval** 秒再从第一个点重走，**Despawn** 到终点才离场。NPC 上的 **Waypoint Pause** 控制循环途中停留，**Walk Speed** 控制速度。拖拉时预留足够的过道，运行时 NPC 会尝试绕过临时挡路的角色。
5. 员工门路线的 **Exit Gate Path** 指向 `BarEnvironment/Architecture/StaffDoor`。最后两点分别放在门前与门后。伙计路线是 `RunnerToStaffDoor`，访客从正门离开的路线是 `VisitorToEntrance`。

## 货币和以后新增掉落

余额在自动加载的 `GameState.money`，玩家角色跨场景更换时继续读取同一余额。入账用 `GameState.add_money(amount)`，扣费用 `GameState.spend_money(amount)`，界面可订阅 `money_changed`。任务奖励和商店恢复规则见[货币系统](REWARDS.md)。

后续加死亡金币掉落时，可让场景掉落组件接敌人真实死亡事件，生成一件可拾取物。地面位置检查可参考 `ammo_drop_position.gd`，拾取防重复可参考 `ammo_pickup.gd`。只有拾取成功才调用 `add_money`。当前重新挑战只恢复玩家入关快照，余额仍保留。新增掉钱前需要选定同一波敌人重试能否重复产出，或者将掉落入账纳入相应检查点的恢复策略。
