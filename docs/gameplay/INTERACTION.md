# 场景交互物与效果

交互物提供按 E 查看、拾取或使用物体的入口，把结果交给物品、对话、声音或目标节点。默认主场景不放置早期五个交互演示物；组件和对象场景仍可独立接入。

## 使用

- 靠近物体时显示“E 动词 物体名”提示；条件不满足时改为显示阻断提示。
- 对话进行中不抢按键，`DialogueUI` 仍然负责推进对话。
- 长按不会重复触发；`one_shot` 物体用过一次后显示 `used_hint`，`hide_on_interact` 物体拾取后隐藏。

## 新增交互物

1. 实例化 `scenes/world/interactable.tscn`，或复制 `scenes/world/objects/` 下的一个物体场景。
2. 设置 `display_name`、`verb` 与外观网格；需要条件时填 `required_items`、`required_flags` 和 `blocked_hint`。
3. 在 `effects` 里加效果资源。常用组合：拾取用 `GiveItemEffect`，信息用 `ShowDialogueEffect`，
   单次写入用 `SetFlagEffect`，开／关切换用 `ToggleFlagEffect`，声音用 `EmitNoiseEffect`。
4. 需要驱动门、机关或生成器时用 `CallMethodEffect` 指向目标节点与方法，交互物本身不需要认识目标类型。
5. 把物体实例放入需要交互的关卡或独立演示场景。

新增玩法优先新增一个效果子类；只有确实需要交互物感知新概念时才扩展 `Interactable`。

## 状态与调试

`GameState` 保存 `items` 与 `flags`，提供 `add_item`、`has_item`、`get_item_count`、`item_display_name`、`set_flag`、`get_flag`、`is_flag_set`，并在变化时发出 `item_gained`、`flag_changed`。与对话选择一样，死亡重开场景不清空，重新运行游戏才重置。

交互物还有稳定标识 `interact_id`（留空回退节点名），与 NPC 的 `npc_id` 同一套思路：任务条件用
`INTERACTED` 来源按它记录“曾经交互过”。显式填写稳定 ID 后，修改节点名不会打断配置表；依赖空值回退时则需同步维护引用。见
[阶段、任务与 NPC 状态](STAGE_STATE.md)。

`scenes/ui/game_state_debug.tscn` 可另行装配为状态面板，当前主场景没有挂载该面板。状态节点可以替换：把交互物的 `state_path` 指向任意实现同样方法的节点即可，测试就用这种方式验证效果不依赖 `GameState`。

## 目录

```text
scripts/world/interactable.gd                 交互物节点（范围、提示、输入、条件、效果派发）
scripts/world/quest_portal.gd                 按任务和 A 解锁进度更新目标的酒馆关卡门
scripts/world/tavern_return_portal.gd         记录关卡完成与玩家状态并返回酒馆
scripts/world/reward_npc.gd                   酒馆蓝色商店 NPC，交互时打开货币商店
scripts/world/interactions/change_scene_effect.gd  交互后切换目标场景
scripts/world/interactions/interaction_context.gd   一次交互的注入上下文
scripts/world/interactions/interaction_effect.gd    效果基类
scripts/world/interactions/*_effect.gd              具体效果
scenes/world/interactable.tscn                可复用交互物场景
scenes/world/objects/quest_portal.tscn        酒馆门口的任务传送门
scenes/world/objects/tavern_return_portal.tscn 五关共用的返回酒馆传送门
scenes/world/objects/                         各个具体交互物场景
scenes/ui/game_state_debug.tscn               调试面板
scripts/shop/shop_controller.gd              货币商店控制器（目录、可见性、购买、暂停所有权）
scripts/ui/shop_board.gd                    商店面板，只回传购买意图，不写状态
scenes/ui/shop_board.tscn                   货币商店界面
```

## 配置和扩展接口

`Interactable` 的 `display_name`／`verb` 控制提示，`interact_id` 提供任务稳定标识，`one_shot`／`hide_on_interact` 控制重复和隐藏，`required_items`／`required_flags` 表达条件，`effects` 数组按顺序执行。

`can_interact(player)` 查询资格，`interact(player)` 执行并返回结果；`interacted`／`blocked` 通知成功或受阻。效果继承 `InteractionEffect.apply(context)`，通过 InteractionContext 获取注入的状态及目标，不直接依赖全局节点或其他系统内部实现。

酒馆主场景已按用户要求删除门禁卡和对应门禁屏障，改为门口任务传送门；酒杯、终端和唱片机继续保留。

| 实例 | 位置 | 交互 | 结果 |
| --- | --- | --- | --- |
| 酒杯 | 主房间南侧 | 查看 | 打开线索对话，置 `saw_wine_clue` |
| 终端 | 主房间东侧 | 使用一次 | 打开通道信息对话，置 `terminal_read` |
| 唱片机 | 主房间东南 | 使用，可重复 | 开／关音乐，写入 `music_playing`；接取任务前后都能操作，接取前操作不会推进任务状态 |
| 关卡传送门 | 酒馆东侧门口 | 进入 | 未接 A 任务时提示并拒绝；A 每次解锁下一关后，按 E 切换到对应关卡 |
| 酒馆返回传送门 | 各关出生点附近 | 返回 | 本关清空后出现；记录完成关卡与玩家状态并返回酒馆 |
| 商店 NPC | 酒馆东侧房间 | 交互 | 靠近按 E 打开货币商店；显示“商店”标签，可购买商品按自适应网格排列 |

关卡传送门在首次进入时读取 `QuestController.status_of("task_a")`；后续按
`GameState.completed_level` 与 `available_level` 判定是否已由 A 解锁。目标场景由
`ChangeSceneEffect.scene_path` 按可用关卡动态更新。交互前会把当前玩家状态写入一次性快照，
再由共享 `SceneTransition` 切换并恢复中性 `World3D` 回退环境。

五关返回传送门默认隐藏，由 `LevelFlow` 在本关波次全部完成后启用。`TavernReturnPortal`
写入本关 `level_number`、保存生命/武器/弹匣/备弹/医疗包快照；第1关还写入
`task_a_returned=returned`。随后 `ChangeSceneEffect` 返回酒馆，新玩家实例只消费一次快照。

商店 NPC 由 `scripts/world/reward_npc.gd` 扩展普通 NPC，保留 `RewardNPC` 节点路径和脚本 UID，
标签改为“商店”。普通对话前，NPC 会发出 `interaction_requested(player)`；该 NPC 直接调用
`ShopController.open_shop_for_player(player)`，成功打开商店后吞掉本次输入；目录为空、缺面板、
缺玩家或商店拒绝打开时才回退普通对话。可见商品、价格、余额和一次性购买记录由 `ShopController`
与 `GameState` 共同决定；`ShopBoard` 默认每行 3 张商品卡，窄窗口自动降为 2 或 1 列并保持纵向滚动，
见[货币商店与任务奖励](REWARDS.md)。

对话影响是打开交互物自己的对话资源，不动 NPC 对话；音乐声音事件继续进入既有听觉系统。

## 验证

`interactable_test` 核对输入、条件、效果和注入替身，任务联动由任务及交互专项覆盖。运行结果同时看断言、进程和脚本／资源诊断；已有退出资源问题单独记录，不用“断言通过”覆盖它们。统一入口见[测试说明](../testing.md)。

## 历史记录

`quest_portal_test.gd` 使用真实酒馆与 `QuestController` 检查未接任务时阻断、接取后进入第1关，并确认门禁卡和旧门禁实例已删除。

Godot 4.7.2 下，只要进程里打开过对话，退出时就会报告 Dialogue Manager 的少量资源未释放（`resources still in use at exit`），与本功能无关；判断通过与否看 `FAIL` 与 `SCRIPT ERROR` 行。

早期配置、实施过程及当时的验证结果保存在[整理前记录](../history/2026-10-28/gameplay/INTERACTION.md)。历史通过数不代表当前本地配置已重新验证。
