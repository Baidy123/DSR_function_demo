# 阶段、任务与 NPC 状态

该系统服务独立任务演示，按配置表表达接任务、进入场地、返回结算和 NPC 状态。连续五关的 LevelFlow 只消费波次完成信号，使用单独的[关卡流程](PLAY_GUIDE.md)，不读写本页三个控制器的任务状态。

2026-11-02 的本地五关接入把两套职责同时保留：工程默认 F5 进入酒馆，五关都通过返程门回到酒馆，再由 A 解锁下一关并从门口传送门出发。关卡进度由 `GameState` 的 `completed_level`／`available_level` 管理；酒馆主线任务仍由任务控制器读取这些状态来标记“通关第N关”。独立任务演示继续按配置表表达接任务、进入场地、返回结算和 NPC 状态；连续五关的 `LevelFlow` 只消费波次信号并启用返程门，不自行切换下一关。详见[五关说明](PLAY_GUIDE.md)。

配置入口为 **StageStateController → Stage Table**，资源模板是 `resources/stages/stage_table_template.tres`。普通玩法改配置表，扩展条件或状态类型才改对应资源／控制器。

## 三个控制器

| 控制器 | 脚本 | 职责 |
| --- | --- | --- |
| 阶段控制器 `StageController` | `scripts/systems/stage/stage_controller.gd` | 判定“现在第几阶段 + 哪个环节”，变化时广播 |
| 任务控制器 `QuestController` | `scripts/systems/stage/quest_controller.gd` | 任务状态的唯一权威：未接／进行中／已拒绝／已完成／已失效 |
| 状态控制器 `StageStateController` | `scripts/systems/stage/stage_state_controller.gd` | 按配置表解析各 NPC 该有的状态，记录快照，按开关下发到场景 |

三者是 `main.tscn` 下的普通节点（`StageController`、`QuestController`、`StageStateController`），
通过 group 互相查找，不新增全局单例。场景里还需要一个 `TavernZone`（Area3D）表示酒馆范围；
任务场地直接用竞技场已有的 `Arena/CombatZone`。两者都挂 `scripts/world/zone_volume.gd` 并填 `zone_id`。

## 配置表用法

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
   `StageStateController.stage_table`（多份表的分发规则见[待办](../TODO.md)）。

- 任务控制器不监听 `phase_changed`；五关通关任务都由 `completed_level` 的整数下限条件驱动，不是靠阶段变化触发。
- 任务控制器订阅阶段控制器的只读广播 `stage_changed` 来重算窗口；阶段控制器订阅 `quest_changed` 来重推阶段。
  两边都只读值、不调用对方的行为，重算幂等且只在值变化时广播，所以不会来回震荡。
- `StageStateController` 只负责把同一张配置表分发给两个控制器，不再做「任务监听阶段」这类接线。

独立任务示例中的唱片机支线仍由同一张表表达：`task_music` 在阶段一内不占阶段序号，接取条件为
`music_quest_choice == accepted`，完成要求 `music_quest_turnin == done` **且** `music_playing` 为真。
因此交差时关掉唱片机不会完成，重新打开后再交差才完成；未接取时完成条件不参与评估。唱片机在接取前后都能操作，
接取前开关音乐只写旗标。该任务没有拒绝条件，B 对话里的“现在不行”只写 `music_quest_choice = refused`
供对话分支使用，任务状态保持未接，再找 B 可以重新接取。

### 开关：先检测，再决定是否落地

`StageStateController.apply_enabled` 默认关闭。关闭时只检测、只记录，游戏表现和接入前完全一致；
表填好、确认无误后再打开，NPC 的在场、站位与对话才会真正按表变化。

本地合并基线还把五条关卡主线登记在同一张表中：`task_a` 与 `task_level_2` 至 `task_level_5` 分别按 `available_level >= N` 接取、`completed_level >= N` 完成。该扩展不改变上面独立任务演示与五关流程的职责边界。

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
新增任务阶段时，阶段序号会自动落到“第一个尚未完成的阶段”；五关表全部完成则停在最后一个阶段。

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
| `STATE_INT_AT_LEAST` | 状态字段整数值 ≥ 下限 | `key`、`min_value` |
| `FLAG` | 旗标等于给定真假 | `key`、`flag_value` |
| `ITEM` | 持有物品数量 ≥ 给定值 | `key`、`min_count` |
| `INTERACTED` | 曾与 `key` 标识的交互物交互过 | `key` |
| `ZONE_ENTERED` | 曾进入 `key` 标识的区域 | `key` |
| `ZONE_LEFT` | 曾离开 `key` 标识的区域 | `key` |

`key` 留空的条件视为不满足。区域与交互用“曾经”语义：一次进入或交互即长期成立；因为任务状态不回退，
效果上等于“首次触发”。条件每次在下列事件后重新评估：状态字段变化、拾取物品、旗标变化、
交互物报告交互、区域进出、阶段变化、换表。

## 关卡返回与货币商店闭环

每关由 `ShopController`（`scripts/shop/shop_controller.gd`）配合关卡完成状态和酒馆
`RewardNPC` 串起“清场 → 返回酒馆 → 找商店 NPC 购买商品”的闭环：

1. A 的对话说明逐关解锁目标。接受后 `help_choice` 写为 `accepted`、`available_level = 1`，任务进入进行中；
   酒馆门口 `Interactables/LevelPortal` 随后解锁，按 E 可切换到 `scenes/world/levels/lvl_1.tscn`。
   旧门禁卡与门禁屏障已删除。
   第一关清空后，出生点附近的 `TavernReturnPortal` 出现；交互写入 `task_a_returned = returned`、
   `completed_level`、一次性玩家快照和酒店检查点并返回酒馆。
2. 酒馆重新加载后，任务控制器按 `completed_level >= 1` 把“通关第1关”任务判为已完成，
   并在首次进入完成态时发放 `QuestDefinition.money_reward`（主线任务各 100）。
   `task_a_returned == returned` 继续写入供旧任务逻辑兼容。酒馆内的蓝色商店 NPC 使用 `scripts/world/reward_npc.gd`，
   标签为“商店”。
3. 玩家靠近商店 NPC 按 E 时，NPC 调用 `ShopController.open_shop_for_player(player)`。
   控制器解析 `resources/shop/shop_catalog.tres`，按“已解锁且未购买的一次性商品”过滤可见项，
   取得暂停所有权后显示 `scenes/ui/shop_board.tscn`（`CanvasLayer.process_mode = ALWAYS`）。
4. 初始商品为急救包（40，回血35）、弹药补给（30，补满弹匣与备弹）、系统进度（50，+20），
   均可重复购买；`unlock_level` 大于 0 的商品在 `completed_level` 达标前完全隐藏。
5. 购买成功后控制器扣款、刷新余额与商品可用状态，面板保持打开；一次性商品（武器）购买后永久隐藏。
   面板只回传 `purchase_requested(item_id, slot)`，不直接修改 `GameState`、玩家或装备。
6. 货币与一次性购买记录跨场景保留，重新运行游戏才重置；死亡返回酒店时由酒店检查点恢复。

旧三选一奖励组件（`EncounterController`、`RewardBoard`、`resources/rewards/level_rewards.tres`）
保留为兼容代码，不再接入主流程；`Arena.combat_cleared` 不打开商店，也没有旧的 `Arena/CombatZone/ReturnPortal`。
`system_progress` 目前只累计并显示在任务面板上，尚未用于章节解锁或后续内容门槛。

## 五关进度与跨关玩家状态

五关共用 `LevelFlow`、`TavernReturnPortal` 和酒馆 `QuestPortal`：

1. 任意关卡清空后，`LevelFlow` 只启用本关 `TavernReturnPortal`，不显示按钮切关，也不暂停。
2. 返程门把本关编号写入 `GameState.completed_level`，并用 `PlayerCampaignState.capture()`
   保存一次待恢复状态；第1关同时写入 `task_a_returned = returned`。同一快照还会写入
   `GameState.campaign_checkpoint`，连同当前 `available_level`、系统进度、货币、
   已发放任务奖励和一次性购买记录保存为酒店检查点。
3. 新玩家实例在 `player.gd::_ready()` 中消费一次 `pending_player_state`。因此回酒馆时，
   同一个角色逻辑上的生命、当前槽位、双武器、各自弹匣、共享备弹和医疗包会出现在新 Player 节点上；
   瞄准、换弹进度、受击减速、体力和蹲姿等临时过程不跨场景。
4. 关卡刚完成时 `available_level == completed_level`，门口传送门保持锁定。A 对话把
   `available_level` 改为已完成关卡 +1 后，`QuestPortal` 才更新 `ChangeSceneEffect` 的目标并允许进入。
5. 由酒馆进入下一关前，门口传送门再次捕获当前玩家状态，所以酒馆商店购买的治疗、弹药和武器会带入下一关。
   快照被新玩家实例消费后立即清空。
6. 第5关完成后 `completed_level == available_level == 5`，A 显示五关完成，不再提供下一关。

死亡不写入跨关快照。`PlayerHealth` 只报告死亡，`SceneDirector` 提供两种重生：

- **重新挑战当前关卡**：重载当前场景，按进入本关时的 `level_entry_player_state` 恢复生命、
  武器、弹药、医疗包与货币，不消费酒店检查点。
- **返回酒店**：调用 `GameState.restore_campaign_checkpoint()`，恢复最近完成关卡时的
  `completed_level`、`available_level`、货币、已发放任务奖励、一次性购买记录、系统进度和
  装备／玩家快照，再加载酒馆。

检查点固定在任务完成并返程、尚未在商店消费、尚未由 A 解锁下一关的时刻。因此返回酒店后，
货币恢复为检查点余额，退还之后的花费；检查点之后的一次性购买记录被清除，被覆盖的武器、
消耗品和系统进度随玩家快照一并回退；任务奖励已写进检查点，不会因返回酒店丢失或重复发放。
第1关尚未完成时没有检查点，返回酒店会保留当前任务接取状态，以酒馆初始关卡状态重新加载。
正常跨关、重新挑战和返回酒店使用不同状态来源。

主线任务表现在有五关条目：

- `task_a` 显示“通关第1关”，由 `help_choice == accepted` 接取，`completed_level >= 1` 完成。
- `task_level_2` 至 `task_level_5` 显示“通关第2关”至“通关第5关”；分别在
  `available_level >= N` 时接取、`completed_level >= N` 时完成。
- 五条主线任务的 `money_reward` 均为 100，首次进入完成态时由任务控制器一次性发放；
  唱片机支线 `task_music` 的 `money_reward` 保持 0。
- 任务完成是终态；A 后一次解锁不会回退已完成任务。任务面板按同一任务表更新。

整数下限条件使用 `QuestCondition.int_at_least(key, value)`；手写 `.tres` 时
`source=6`、`min_value=N`。该来源追加在枚举末尾，原有字段、旗标、物品、交互和区域条件的整数索引保持不变。

货币商店按 `completed_level` 与 `GameState.money` 展示商品：`unlock_level <= completed_level`
且“一次性商品尚未购买”的条目才可见，购买由 `ShopController` 复核并执行，`GameState.money`
与 `purchased_shop_item_ids` 同步进酒店检查点。任务金额由 `QuestDefinition.money_reward`
在首次进入完成态时一次性发放，并补写进匹配完成关卡的检查点。具体配置与回滚规则见
[货币商店与任务奖励](REWARDS.md)。

正式切场景统一经过 `SceneTransition`。切换前先把 `World3D` 的环境恢复为中性回退值，避免酒馆环境光残留到没有
自己的 `WorldEnvironment` 的关卡；传送门、关卡按钮和死亡重开不会各自复制渲染清理代码。

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
  唱片机支线另有 `music_quest_choice`、`music_quest_turnin` 两个对话字段，以及只读镜像
  `music_playing`（读同名旗标，供对话剧本按属性名判断）。
- `Interactable`：`interact_id`（留空回退节点名，见 [场景交互物](INTERACTION.md)）与 `interacted` 信号。
- `ZoneVolume`（`scripts/world/zone_volume.gd`）：`zone_id` + `zone_volume` 组，提供区域进出；
  阶段控制器按自己的 `node_paths` 绑定同一批区域，两者互不认识。

## 任务面板

当前合并基线在 `main.tscn` 挂载 `scenes/ui/quest_panel.tscn` 与 `scripts/ui/quest_panel.gd`，默认隐藏，按 Tab 显示或隐藏；五关场景不挂载这套酒馆任务界面。上游保留的“可独立装配组件”能力仍有效，组件测试可显式挂载。面板半透明、鼠标事件忽略，不抢对话与交互按键；Tab 使用运行时输入动作绑定，不依赖 `project.godot` 中的输入条目。面板只读任务控制器和状态节点：

- 一行一个任务，格式“任务名：状态”，`target_area` 非空时附“（场地 xxx）”；
- 未解锁显示“未解锁”，配置表为空时显示“暂无任务”；
- 系统进度使用最大值 100 的 `ProgressBar`，并显示“当前值 / 100”；
- 监听 `quest_changed` 刷新，并在启动时延迟补刷一次，兜住控制器晚接线。

当前 `main.tscn` 不再挂载 `GameStateDebug`；任务控制器与配置表接口保持原归属。

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

## 记录

阶段或任务变化时，状态控制器会输出一行结构化记录并追加写入文件；阶段序号、环节、任务状态、
玩家所在区域与坐标、每个 NPC 的在场／位置／对话／命中规则都会带上。

```text
[阶段记录] 2026-10-16T18:40:35 阶段1(任务一) 环节=酒馆待命 任务=task_a/未接 玩家=other(0.0, 0.0, 3.423183) npc_a{在场=是,位置=(-7.88, 0.0, 3.79),对话=res://resources/dialogue/npc_a.dialogue,规则=default_a} 原因=初始化
```

默认写入 `res://logs/stage_state.log`（`logs/` 已被 Git 忽略），可用 `log_to_file`、`print_log`、
`log_path` 调整。

## 维护与验证

配置资源与控制器位于 `scripts/systems/stage/`，场景控制器是普通节点，通过组查找；NPC 通过稳定 `npc_id` 与状态接口接入。`StageStateController.reload_table()` 重新分发表，`get_snapshot()`／`snapshot_changed` 提供只读状态；调试接口不能替代运行时真实事件验证。

## 当前模板条目

模板已按现状填了五条主线和一个支线：

- `task_a`（通关第1关）：接取 `help_choice == accepted`，拒绝 `help_choice == refused`，
  完成＝`completed_level >= 1`，`money_reward = 100`。
- `task_level_2` 至 `task_level_5`：分别在 `available_level >= N` 时接取、
  `completed_level >= N` 时完成，`money_reward = 100`。
- `task_music`（打开唱片机，阶段一内的支线，不占阶段序号）：接取 `music_quest_choice == accepted`，
  完成＝`music_quest_turnin == done` **且** `music_playing` 为真。所以交差时唱片机被关掉就不会完成，
  重新打开再交差才会完成；没接取时完成条件根本不参与评估。
  唱片机在接取前后都能操作，接取前开关音乐只是写旗标，不会推进任务状态。
  这个任务**没有拒绝条件**：B 对话里的“现在不行”只把 `music_quest_choice` 写成 `refused` 供对话分支使用，
  任务状态保持未接；再找 B 会看到拒绝台词，并可以直接“我改主意了”重新接取。

## 验证

对应条件、任务状态、阶段接线、面板和交互支线测试列于[测试说明](../testing.md)。本地五关与商店新增记录包括：

- `campaign_quest_task_test`：五条关卡任务随 A 解锁与通关更新、任务面板名称，以及每关任务奖励累计发放到 500。
- `campaign_checkpoint_test`：酒店检查点恢复货币、已发任务奖励、一次性购买记录和完成时玩家快照，并退款检查点之后的花费。
- `campaign_flow_test`：五关返程门、A 逐关解锁、动态传送门、跨关状态，以及购买商品进入第2关后死亡，返回酒店退款并回滚一次性武器与装备。
- `shop_catalog_test`、`shop_state_test`、`shop_weapon_test`、`shop_board_test`、`shop_flow_test`：商品目录过滤、货币与检查点状态、武器槽覆盖、面板回传与购买流程。
- `quest_money_reward_test`：默认／主线金额、一次性发放、无奖励支线为 0，以及付费支线同步当前关卡检查点。
- `debug_complete_level_test`：Debug 总开关、一键完成当前关、单次完成信号和返程门流程。

任务面板、交互物和 NPC 的独立夹具仍可用于隔离测试，但不能把夹具中的旧演示位置当成当前主场景配置；当前 `main.tscn` 已挂载任务面板。

## 后续

多份配置表的分发、任务二的场地与内容、酒馆场景整体变化还没做；
五关已经使用真实场景往返酒馆，并由 A 控制逐关解锁。
跨场景运行状态已保留，但退出游戏后的进度持久化仍未做；`system_progress` 只累计并显示、未用于章节门槛，
都记录在 [待办](../TODO.md)。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](../history/2026-10-28/gameplay/STAGE_STATE.md)。历史通过数不代表当前本地配置已重新验证。
