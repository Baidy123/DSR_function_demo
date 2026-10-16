# 阶段、任务与 NPC 状态

这份文档说明“酒馆接任务 → 前往场地 → 战斗 → 返回结算”这条循环现在由谁掌控、任务条件怎么配、
任务状态怎么看，以及它和对话、交互物、竞技场的关系。设计稿在 `docs/superpowers/specs/`（仅本地保留）。

## 三个控制器

| 控制器 | 脚本 | 职责 |
| --- | --- | --- |
| 阶段控制器 `StageController` | `scripts/systems/stage/stage_controller.gd` | 判定“现在第几阶段 + 哪个环节”，变化时广播 |
| 任务控制器 `QuestController` | `scripts/systems/stage/quest_controller.gd` | 任务状态的唯一权威：未接／进行中／已拒绝／已完成／已失效 |
| 状态控制器 `StageStateController` | `scripts/systems/stage/stage_state_controller.gd` | 按配置表解析各 NPC 该有的状态，记录快照，按开关下发到场景 |

三者是 `main.tscn` 下的普通节点（`StageController`、`QuestController`、`StageStateController`），
通过 group 互相查找，不新增全局单例。场景里还需要一个 `TavernZone`（Area3D）表示酒馆范围；
任务场地直接用竞技场已有的 `Arena/CombatZone`。两者都挂 `scripts/world/zone_volume.gd` 并填 `zone_id`。

## 解耦约定

两个控制器互不触发对方行为，只读对方的查询接口；各自的数据只有一个写入者：

| 数据 | 唯一写入者 | 另一方的用法 |
| --- | --- | --- |
| 每个任务的运行状态 | `QuestController` | `StageController` 只调用 `status_of(quest_id)` |
| 阶段序号与环节 | `StageController` | `QuestController` 只调用 `get_stage_index()`，用来判解锁／失效窗口 |

- 任务控制器不监听 `phase_changed`，「离开场地即完成」由任务自己的区域条件表达，不是靠阶段变化触发。
- 任务控制器订阅阶段控制器的只读广播 `stage_changed` 来重算窗口；阶段控制器订阅 `quest_changed` 来重推阶段。
  两边都只读值、不调用对方的行为，重算幂等且只在值变化时广播，所以不会来回震荡。
- `StageStateController` 只负责把同一张配置表分发给两个控制器，不再做「任务监听阶段」这类接线。

## 阶段与环节

阶段 = “第几个任务”（`StageDefinition.index`，从 1 开始）。环节是同一个任务内固定循环的五步，
取值见 `scripts/systems/stage/stage_phase.gd`：

| 环节 | 含义 | 判定依据 |
| --- | --- | --- |
| 酒馆待命 | 还没接本阶段任务 | 任务为未接／已拒绝／已失效 |
| 已接任务 | 任务进行中，玩家还在酒馆 | 任务进行中且没有离开过酒馆 |
| 前往场地 | 已离开酒馆，还没进场地 | 任务进行中、离开过酒馆、未到过场地 |
| 场地战斗 | 玩家在任务场地内 | 任务进行中且玩家在 `CombatZone` 内 |
| 返回结算 | 已离开场地 | 任务已完成／已失效，或到过场地后离开 |

阶段序号是“第一个尚未完成的阶段”，本阶段任务处于**已完成或已失效**都算结束，不会因为任务失效卡在原处。
任务二接入时，阶段序号会自动落到“第一个尚未完成的阶段”；表里全部完成则停在最后一个阶段。

## 任务条件

任务状态由条件驱动，条件资源是 `scripts/systems/stage/quest_condition.gd`（`QuestCondition`），
`QuestDefinition` 用三组条件声明判定；数组内的条件必须**全部满足**，空数组表示该判定不由条件驱动：

| 字段 | 全部满足时 |
| --- | --- |
| `accept_conditions` | 任务进入进行中 |
| `refuse_conditions` | 任务记为已拒绝 |
| `complete_conditions` | 任务完成（只在已接取之后判断） |

条件来源与写法：

| `source` | 判定 | 用到的字段 |
| --- | --- | --- |
| `STATE_FIELD` | 状态字段的字符串值相等 | `key`、`state_value` |
| `FLAG` | 旗标等于给定真假 | `key`、`flag_value` |
| `ITEM` | 持有物品数量 ≥ 给定值 | `key`、`min_count` |
| `INTERACTED` | 曾与 `key` 标识的交互物交互过 | `key` |
| `ZONE_ENTERED` | 曾进入 `key` 标识的区域 | `key` |
| `ZONE_LEFT` | 曾离开 `key` 标识的区域 | `key` |

`key` 留空的条件视为不满足。区域与交互用“曾经”语义：一次进入或交互即长期成立；因为任务状态不回退，
效果上等于“首次触发”。条件每次在下列事件后重新评估：状态字段变化、拾取物品、旗标变化、
交互物报告交互、区域进出、阶段变化、换表。

## 阶段窗口

| 字段 | 含义 |
| --- | --- |
| `unlock_stage` | 阶段序号小于该值时任务未解锁，不参与条件评估；0 表示不限 |
| `expire_stage` | 阶段序号大于等于该值时任务失效，转为已失效；0 表示不限 |

到达失效阶段时，除“已完成”“已失效”外的任务都转为已失效。**已完成与已失效都是终态**，
之后条件字段怎么变都不回退，只有显式 `reset_progress()`／重开场景才会清空。

## 任务状态与查询

状态枚举在 `QuestController.Status`，中文名见 `STATUS_NAMES`：
未接、进行中、已拒绝、已完成、已失效。“未解锁”不进状态枚举，只是评估门槛与面板显示。

供界面与测试使用的只读接口：

| 接口 | 说明 |
| --- | --- |
| `status_of(quest_id)` | 取状态枚举 |
| `status_name(quest_id)` | 取中文状态名 |
| `is_locked(quest_id)` | 是否还没到解锁阶段 |
| `get_quest_entries()` | 按阶段升序返回全部任务：`id`、`name`、`status`、`status_name`、`stage_index`、`target_area`、`locked` |
| `quest_changed(quest_id, previous, current)` | 状态变化信号，面板据此刷新 |

显式接口 `accept`／`refuse`／`complete`／`fail`／`set_status`／`reset_progress` 保留，供调试与测试直接改状态。

## 中立事件来源

- `GameState`：对话字段与物品、旗标信号（`value_changed`、`item_gained`、`flag_changed`）。
  唱片机支线另有 `music_quest_choice`、`music_quest_turnin` 两个对话字段，以及两个镜像属性：
  只读的 `music_playing`（读同名旗标，供对话剧本按属性名判断）与可读写的 `music_quest_open`
  （读写同名旗标，供对话置位、交互物用 `required_flags` 做门禁）。
- `Interactable`：`interact_id`（留空回退节点名，见 [场景交互物](INTERACTION.md)）与 `interacted` 信号。
- `ZoneVolume`（`scripts/world/zone_volume.gd`）：`zone_id` + `zone_volume` 组，提供区域进出；
  阶段控制器按自己的 `node_paths` 绑定同一批区域，两者互不认识。

## 任务面板

`scenes/ui/quest_panel.tscn` + `scripts/ui/quest_panel.gd` 挂在 `main.tscn` 上，屏幕左上角常驻显示，
半透明样式与调试面板一致，鼠标事件忽略、不抢对话与交互按键。面板只读任务控制器：

- 一行一个任务，格式“任务名：状态”，`target_area` 非空时附“（场地 xxx）”；
- 未解锁显示“未解锁”，配置表为空时显示“暂无任务”；
- 监听 `quest_changed` 刷新，并在启动时延迟补刷一次，兜住控制器晚接线。

左侧调试面板（`GameStateDebug`）已下移，避免与任务面板重叠。

## 记录

阶段或任务变化时，状态控制器会输出一行结构化记录并追加写入文件；阶段序号、环节、任务状态、
玩家所在区域与坐标、每个 NPC 的在场／位置／对话／命中规则都会带上。

```text
[阶段记录] 2026-10-16T18:40:35 阶段1(任务一) 环节=酒馆待命 任务=task_a/未接 玩家=other(0.0, 0.0, 3.423183) npc_a{在场=是,位置=(-7.88, 0.0, 3.79),对话=res://resources/dialogue/npc_a.dialogue,规则=default_a} 原因=初始化
```

默认写入 `res://logs/stage_state.log`（`logs/` 已被 Git 忽略），可用 `log_to_file`、`print_log`、
`log_path` 调整。

## 怎么配置配置表

配置表是 `StageTable` 资源，模板在 `resources/stages/stage_table_template.tres`，已在
`main.tscn` 的 `StageStateController` 上引用。做法：

1. 在编辑器里双击该 `.tres`，在检查器里展开 `Stages`、`Quests`、`Rules` 三个数组。
2. `Stages` 每项填 `index`（第几个任务）、`display_name`、`quest_id`（对应任务 id）、
   `target_area`（目标场地标识，如 `arena`）、`note`。
3. `Quests` 每项填 `id`、`display_name`、`stage_index`、`target_area`，
   再填阶段窗口 `unlock_stage`／`expire_stage`（0 表示不限），最后加三组条件。
   手写 `.tres` 时 `source` 用整数：`STATE_FIELD=0`、`FLAG=1`、`ITEM=2`、`INTERACTED=3`、
   `ZONE_ENTERED=4`、`ZONE_LEFT=5`。
4. 条件示例：
   - 对话接取：`source=0`、`key=help_choice`、`state_value=accepted`；
   - 交互开关：`source=1`、`key=music_playing`（`flag_value` 默认真）；
   - 拾取物品：`source=2`、`key=keycard`、`min_count=1`；
   - 去过竞技场又离开：`source=4` + `source=5`、`key=arena` 两条都要填。
5. 区域要挂 `scripts/world/zone_volume.gd` 并填 `zone_id`（现成：酒馆 `tavern`、竞技场 `arena`）；
   交互物要填 `interact_id`（留空会回退节点名）；NPC 要填 `npc_id`（`npc_a`、`npc_b`）。
6. `Rules` 是 NPC 状态规则，按数组顺序生效，**后面的覆盖前面的**。每项填三段：
   - 条件：`stage_index`（0 表示不限）、`phase`（-1 表示不限）、`quest_id` + `quest_status`
     （`not_started`／`in_progress`／`refused`／`completed`／`missed`）、`required_flags`、`required_items`。
   - 目标：`target_npc` 填 NPC 的 `npc_id`，留空表示应用到全部 NPC。
   - 状态：`present`、`position_set` + `position`、`facing_set` + `facing`、`dialogue`。
7. 想新增一个任务阶段时，复制整份 `.tres`，改阶段序号、任务 id 与规则，再把新表赋给
   `StageStateController.stage_table`（多份表的分发规则尚未定稿，见 `docs/TODO.md`）。

模板里已按现状填了两个任务：

- `task_a`（帮 A 的忙）：接取 `help_choice == accepted`，拒绝 `help_choice == refused`，
  完成＝曾进入 `arena` 且曾离开 `arena`（等价于原来的“离开场地返回结算”）。
- `task_music`（打开唱片机，阶段一内的支线，不占阶段序号）：接取 `music_quest_choice == accepted`，
  完成＝`music_quest_turnin == done` **且** `music_playing` 为真。所以交差时唱片机被关掉就不会完成，
  重新打开再交差才会完成；没接取时完成条件根本不参与评估。
  这个任务**没有拒绝条件**：B 对话里的“现在不行”不写任何字段，任务保持未接，可以再找 B 重新接取。
  接取时对话顺带置位 `music_quest_open` 旗标，唱片机用 `required_flags` 读它，未接取时不可交互。

### 开关：先检测，再决定是否落地

`StageStateController.apply_enabled` 默认关闭。关闭时只检测、只记录，游戏表现和接入前完全一致；
表填好、确认无误后再打开，NPC 的在场、站位与对话才会真正按表变化。

## 验证

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path movement_demo --script res://tests/quest_conditions_test.gd
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path movement_demo --script res://tests/quest_system_test.gd
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path movement_demo --script res://tests/stage_system_test.gd
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path movement_demo --script res://tests/quest_panel_test.gd
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path movement_demo --script res://tests/record_player_quest_test.gd
```

macOS 上用 `Godot.app/Contents/MacOS/Godot` 替换可执行文件路径。

- `quest_conditions_test.gd`：六种条件的构造与描述文本。
- `quest_system_test.gd`：阶段窗口（未解锁不评估、到阶段失效、终态不回退）、条件驱动的接取／拒绝／完成、
  `get_quest_entries()` 的内容与排序，以及任务状态变化不会推进阶段序号。
- `stage_system_test.gd`：阶段判定的全部转移与次序、拒绝与接取的区分、失效处理、规则匹配与覆盖顺序、
  开关关闭／打开的行为差异、快照字段、记录内容与去重信号，并在最后加载真实 `main.tscn` 检查控制器、
  区域绑定、`npc_id` 对应与“默认不落表现”。
- `quest_panel_test.gd`：面板列出全部任务与状态、随 `quest_changed` 刷新、空表占位、不接收鼠标、
  真实 `main.tscn` 里能找到面板与控制器。
- `record_player_quest_test.gd`：接取前与唱片机交互被阻断且音乐状态不变、接取后才能开关、
  关闭状态下交差失败、重新打开后点“交差”完成任务、拒绝后任务仍是未接并可重新接取，
  以及任务面板显示对应状态。

## 后续

多份配置表的分发、任务二的场地与内容、酒馆场景整体变化、真正的场景切换都还没做；
进度持久化本轮也未做（场景重开后已完成会退回），都记录在 [待办](../TODO.md)。
