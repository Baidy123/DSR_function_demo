# 场景交互物

交互物让玩家在场景里按 E 查看、拾取或使用物体，并把结果交给物品栏、对话、听觉事件或场景里的其他节点。设计与解耦约定见 [设计记录](../superpowers/specs/2026-09-29-scene-interactable-design.md)。

## 使用

- 靠近物体时显示“E 动词 物体名”提示；条件不满足时改为显示阻断提示。
- 对话进行中不抢按键，`DialogueUI` 仍然负责推进对话。
- 长按不会重复触发；`one_shot` 物体用过一次后显示 `used_hint`，`hide_on_interact` 物体拾取后隐藏。

## 目录

```text
scripts/world/interactable.gd                 交互物节点（范围、提示、输入、条件、效果派发）
scripts/world/quest_portal.gd                 任务状态传送门，接取 A 任务后才允许操作
scripts/world/interactions/change_scene_effect.gd  交互后切换目标场景
scripts/world/interactions/interaction_context.gd   一次交互的注入上下文
scripts/world/interactions/interaction_effect.gd    效果基类
scripts/world/interactions/*_effect.gd              具体效果
scenes/world/interactable.tscn                可复用交互物场景
scenes/world/objects/quest_portal.tscn        酒馆门口的任务传送门
scenes/world/objects/tavern_return_portal.tscn 第一关完成后的返回传送门
scenes/world/objects/                         各个具体交互物场景
scenes/ui/game_state_debug.tscn               调试面板
```

## 可复用示例

2026-10-27 按用户要求，主场景删除门禁卡和对应门禁屏障，改为酒馆门口的任务传送门。酒杯、终端和唱片机继续保留。

| 实例 | 位置 | 交互 | 结果 |
| --- | --- | --- | --- |
| 酒杯 | 主房间南侧 | 查看 | 打开线索对话，置 `saw_wine_clue` |
| 终端 | 主房间东侧 | 使用一次 | 打开通道信息对话，置 `terminal_read` |
| 唱片机 | 主房间东南 | 使用，可重复 | 开／关音乐，写入 `music_playing`；接取任务前后都能操作，接取前操作不会推进任务状态 |
| 关卡传送门 | 酒馆东侧门口 | 进入 | 未接 A 任务时提示并拒绝；任务进行中后按 E 切换到第1关 |
| 酒馆返回传送门 | 第一关出生点附近 | 返回 | 第一关清空后出现；交互写入 `task_a_returned=returned` 并返回酒馆 |
| 结算奖励 NPC | 酒馆东侧房间 | 交互 | 第一关完成并回到酒馆后按 E 打开三选一；未完成或已领取时只显示提示 |

关卡传送门读取 `QuestController.status_of("task_a")`，不读取物品或自行修改任务状态。目标场景由
`ChangeSceneEffect.scene_path` 配置，`quest_portal.tscn` 指向第1关。效果通过共享 `SceneTransition` 切换，
切换前恢复中性 `World3D` 回退环境，防止目标关卡沿用酒馆的环境光。

第一关返回传送门默认隐藏，由 `LevelFlow` 在本关波次全部完成后启用。效果依次用 `SetStateValueEffect` 写入任务交差字段，
再用 `ChangeSceneEffect` 返回酒馆；酒馆的任务控制器据此把任务 A 判为已完成。

结算奖励 NPC 由 `scripts/world/reward_npc.gd` 扩展普通 NPC。普通对话前，NPC 会发出
`interaction_requested(player)`；专用 NPC 可接管本次输入。奖励 NPC 在任务完成且
`GameState.task_a_reward_claimed` 尚未置位时调用 `EncounterController`，否则继续普通对话。

对话影响是打开交互物自己的对话资源，不动 NPC 对话；音乐声音事件继续进入既有听觉系统。

## 新增交互物

1. 实例化 `scenes/world/interactable.tscn`，或复制 `scenes/world/objects/` 下的一个物体场景。
2. 设置 `display_name`、`verb` 与外观网格；需要条件时填 `required_items`、`required_flags` 和 `blocked_hint`。
3. 在 `effects` 里加效果资源。常用组合：拾取用 `GiveItemEffect`，信息用 `ShowDialogueEffect`，
   旗标用 `SetFlagEffect`，状态字段用 `SetStateValueEffect`，开／关切换用 `ToggleFlagEffect`，
   切换场景用 `ChangeSceneEffect`，声音用 `EmitNoiseEffect`。
4. 需要驱动门、机关或生成器时用 `CallMethodEffect` 指向目标节点与方法，交互物本身不需要认识目标类型。
5. 把物体场景放进关卡场景，放入需要交互演示的独立场景。

新增玩法优先新增一个效果子类；只有确实需要交互物感知新概念时才扩展 `Interactable`。

## 状态与调试

`GameState` 保存 `items` 与 `flags`，提供 `add_item`、`has_item`、`get_item_count`、`item_display_name`、`set_flag`、`get_flag`、`is_flag_set`，并在变化时发出 `item_gained`、`flag_changed`。与对话选择一样，死亡重开场景不清空，重新运行游戏才重置。

交互物还有稳定标识 `interact_id`（留空回退节点名），与 NPC 的 `npc_id` 同一套思路：任务条件用
`INTERACTED` 来源按它记录“曾经交互过”，所以场景里换节点名不会打断配置表。见
[阶段、任务与 NPC 状态](STAGE_STATE.md)。

游戏内 Debug 总开关打开时，左上角面板列出当前物品与旗标。状态节点可以替换：把交互物的 `state_path` 指向任意实现同样方法的节点即可，测试就用这种方式验证效果不依赖 `GameState`。

## 验证

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path movement_demo --script res://tests/interactable_test.gd
```

该检查覆盖输入守卫、条件与阻断提示、各实例结果、一次性与可重复行为，以及把 `state_path` 换成测试替身后的写入结果。

`quest_portal_test.gd` 使用真实酒馆与 `QuestController` 检查未接任务时阻断、接取后进入第1关，并确认门禁卡和旧门禁实例已删除。

Godot 4.7.2 下，只要进程里打开过对话，退出时就会报告 Dialogue Manager 的少量资源未释放（`resources still in use at exit`），与本功能无关；判断通过与否看 `FAIL` 与 `SCRIPT ERROR` 行。
