# 阶段、任务与 NPC 状态

这份文档说明“酒馆接任务 → 前往场地 → 战斗 → 返回结算”这条循环现在由谁掌控、配置表怎么填，
以及它和现有对话、竞技场、物品旗标的关系。设计稿在 `docs/superpowers/specs/`（仅本地保留）。

## 三个控制器

| 控制器 | 脚本 | 职责 |
| --- | --- | --- |
| 阶段控制器 `StageController` | `scripts/systems/stage/stage_controller.gd` | 判定“现在第几阶段 + 哪个环节”，变化时广播 |
| 任务控制器 `QuestController` | `scripts/systems/stage/quest_controller.gd` | 任务状态的唯一权威：未接／进行中／已拒绝／已完成 |
| 状态控制器 `StageStateController` | `scripts/systems/stage/stage_state_controller.gd` | 按配置表解析各 NPC 该有的状态，记录快照，按开关下发到场景 |

三者是 `main.tscn` 下的普通节点（`StageController`、`QuestController`、`StageStateController`），
通过 group 互相查找，不新增全局单例。场景里还需要一个 `TavernZone`（Area3D）表示酒馆范围；
任务场地直接用竞技场已有的 `Arena/CombatZone`。

## 阶段与环节

阶段 = “第几个任务”（`StageDefinition.index`，从 1 开始）。环节是同一个任务内固定循环的五步，
取值见 `scripts/systems/stage/stage_phase.gd`：

| 环节 | 含义 | 判定依据 |
| --- | --- | --- |
| 酒馆待命 | 还没接本阶段任务 | 任务为未接／已拒绝 |
| 已接任务 | 任务进行中，玩家还在酒馆 | 任务进行中且没有离开过酒馆 |
| 前往场地 | 已离开酒馆，还没进场地 | 任务进行中、离开过酒馆、未到过场地 |
| 场地战斗 | 玩家在任务场地内 | 任务进行中且玩家在 `CombatZone` 内 |
| 返回结算 | 已离开场地 | 任务已完成，或到过场地后离开 |

判定只读现有信号：`GameState` 的对话字段、酒馆区域与竞技场的玩家进出，不改写对话、移动与战斗。
任务二接入时，阶段序号会自动落到“第一个尚未完成的阶段”；表里全部完成则停在最后一个阶段。

## 任务状态

`QuestDefinition` 声明判定来源，运行状态由任务控制器持有：

- 接取：`accept_source` 指定读哪个状态字段（现在用对话写入的 `help_choice`），
  `accept_value` 是“进行中”的值，`refuse_values` 里的值记为“已拒绝”。
- 完成：`complete_on_return` 打开时，玩家离开任务场地即完成；`required_flags` 可以附加条件。
- 对话剧本不改写：`npc_a.dialogue` 仍然自己写 `GameState.help_choice`，任务控制器监听
  `GameState.value_changed` 同步成任务状态。

`GameState` 为此增加了一个通用信号 `value_changed(key, value)`，值没有变化时不重复发出，
现有 `talked_to_a`、`help_choice` 的用法与语义不变。

## 记录

阶段或任务变化时，状态控制器会输出一行结构化记录并追加写入文件；阶段序号、环节、任务状态、
玩家所在区域与坐标、每个 NPC 的在场／位置／对话／命中规则都会带上，便于排查“为什么这个 NPC
现在是这样”。

```text
[阶段记录] 2026-10-07T20:40:14 阶段1(任务一) 环节=酒馆待命 任务=task_a/未接 玩家=other(0.0, 0.0, 3.4231) npc_a{在场=是,位置=(-7.88, 0.0, 3.79),对话=res://resources/dialogue/npc_a.dialogue,规则=default_a} 原因=初始化
```

默认写入 `res://logs/stage_state.log`（`logs/` 已被 Git 忽略），可用 `log_to_file`、`print_log`、
`log_path` 调整。

## 怎么配置配置表

配置表是 `StageTable` 资源，模板在 `resources/stages/stage_table_template.tres`，已在
`main.tscn` 的 `StageStateController` 上引用。做法：

1. 在编辑器里双击该 `.tres`，在检查器里展开 `Stages`、`Quests`、`Rules` 三个数组。
2. `Stages` 每项填 `index`（第几个任务）、`display_name`（如“任务一”）、`quest_id`（对应任务 id）、
   `target_area`（目标场地标识，如 `arena`）、`note`（给自己看的备注）。
3. `Quests` 每项填 `id`、`stage_index`、`accept_source`／`accept_value`／`refuse_values`，
   以及完成方式（`complete_on_return` 或 `required_flags`）。
4. `Rules` 是 NPC 状态规则，按数组顺序生效，**后面的覆盖前面的**。每项填三段：
   - 条件：`stage_index`（0 表示不限）、`phase`（-1 表示不限）、`quest_id` + `quest_status`
     （`not_started`／`in_progress`／`refused`／`completed`）、`required_flags`、`required_items`。
   - 目标：`target_npc` 填 NPC 的 `npc_id`，留空表示应用到全部 NPC。
   - 状态：`present`（是否在场）、`position_set` + `position`（站位）、`facing_set` + `facing`
     （朝向点）、`dialogue`（换成哪份 `.dialogue` 资源，留空表示不改）。
5. NPC 一侧要填 `npc_id`：`main.tscn` 里两个 NPC 已填好 `npc_a`、`npc_b`；新增 NPC 时在
   `npc.gd` 的 `npc_id` 里填一个稳定名字，规则表的 `target_npc` 就写这个名字。
6. 想新增一个任务阶段时，复制整份 `.tres`，改阶段序号、任务 id 与规则，再把新表赋给
   `StageStateController.stage_table`（多份表的分发规则尚未定稿，见 `docs/TODO.md`）。

模板里已按现状填了示例：`default_a`／`default_b` 是两个 NPC 的默认站位与对话，
`done_a`（任务一完成后 NPC A 挪位置）、`done_b`（任务一完成后 NPC B 退场）演示“NPC 随任务状态变化”。

### 开关：先检测，再决定是否落地

`StageStateController.apply_enabled` 默认关闭。关闭时只检测、只记录，游戏表现和接入前完全一致；
表填好、确认无误后再打开，NPC 的在场、站位与对话才会真正按表变化。

## 验证

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path movement_demo --script res://tests/stage_system_test.gd
```

`tests/stage_system_test.gd` 覆盖：阶段判定的全部转移与次序、拒绝与接取的区分、任务完成判定、
规则匹配与覆盖顺序、未指定字段的回退、开关关闭时场景不被改动、打开后按表落地、快照字段、
记录内容与去重信号，并在最后加载真实 `main.tscn` 检查三个控制器、区域绑定、
`npc_id` 对应和“默认不落表现”。

## 后续

多份配置表的分发、任务二的场地与内容、酒馆场景整体变化、真正的场景切换都还没做，
记录在 [待办](../TODO.md)。本阶段只提供检测、控制接口与一份可复制的模板。
