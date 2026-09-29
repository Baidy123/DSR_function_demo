# 场景交互物

交互物让玩家在场景里按 E 查看、拾取或使用物体，并把结果交给物品栏、对话、听觉事件或场景里的其他节点。设计与解耦约定见 [设计记录](../superpowers/specs/2026-09-29-scene-interactable-design.md)。

## 使用

- 靠近物体时显示“E 动词 物体名”提示；条件不满足时改为显示阻断提示。
- 对话进行中不抢按键，`DialogueUI` 仍然负责推进对话。
- 长按不会重复触发；`one_shot` 物体用过一次后显示 `used_hint`，`hide_on_interact` 物体拾取后隐藏。

## 目录

```text
scripts/world/interactable.gd                 交互物节点（范围、提示、输入、条件、效果派发）
scripts/world/interactions/interaction_context.gd   一次交互的注入上下文
scripts/world/interactions/interaction_effect.gd    效果基类
scripts/world/interactions/*_effect.gd              具体效果
scripts/world/sliding_barrier.gd              纯位移屏障，由交互物通过方法调用驱动
scenes/world/interactable.tscn                可复用交互物场景
scenes/world/access_gate.tscn                 门禁读卡器 + 屏障
scenes/world/objects/                         各个具体交互物场景
scenes/ui/game_state_debug.tscn               调试面板
```

## 现有实例

| 实例 | 位置 | 交互 | 结果 |
| --- | --- | --- | --- |
| 门禁卡 | NPC 附近 | 拾取 | 写入 `keycard` 与 `has_keycard`，物体消失 |
| 酒杯 | 主房间南侧 | 查看 | 打开线索对话，置 `saw_wine_clue` |
| 终端 | 主房间东侧 | 使用一次 | 打开通道信息对话，置 `terminal_read` |
| 唱片机 | 主房间东南 | 使用，可重复 | 发出唱片音乐声音事件，置 `music_playing` |
| 门禁读卡器 | 通往竞技场的通道口 | 刷卡 | 缺门禁卡时提示并拒绝；持有后打开屏障并置 `arena_access` |

对话影响是打开交互物自己的对话资源，不动 NPC 对话；战斗影响是通道屏障决定能否进入竞技场，以及音乐声音事件进入既有听觉系统。

## 新增交互物

1. 实例化 `scenes/world/interactable.tscn`，或复制 `scenes/world/objects/` 下的一个物体场景。
2. 设置 `display_name`、`verb` 与外观网格；需要条件时填 `required_items`、`required_flags` 和 `blocked_hint`。
3. 在 `effects` 里加效果资源。常用组合：拾取用 `GiveItemEffect`，信息用 `ShowDialogueEffect`，状态用 `SetFlagEffect`，声音用 `EmitNoiseEffect`。
4. 需要驱动门、机关或生成器时用 `CallMethodEffect` 指向目标节点与方法，交互物本身不需要认识目标类型。
5. 把物体场景放进关卡场景，例如 `main.tscn` 的 `Interactables` 下。

新增玩法优先新增一个效果子类；只有确实需要交互物感知新概念时才扩展 `Interactable`。

## 状态与调试

`GameState` 保存 `items` 与 `flags`，提供 `add_item`、`has_item`、`get_item_count`、`item_display_name`、`set_flag`、`get_flag`、`is_flag_set`，并在变化时发出 `item_gained`、`flag_changed`。与对话选择一样，死亡重开场景不清空，重新运行游戏才重置。

游戏内 Debug 总开关打开时，左上角面板列出当前物品与旗标。状态节点可以替换：把交互物的 `state_path` 指向任意实现同样方法的节点即可，测试就用这种方式验证效果不依赖 `GameState`。

## 验证

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path movement_demo --script res://tests/interactable_test.gd
```

该检查覆盖输入守卫、条件与阻断提示、各实例结果、一次性与可重复行为，以及把 `state_path` 换成测试替身后的写入结果。

Godot 4.7.2 下，只要进程里打开过对话，退出时就会报告 Dialogue Manager 的少量资源未释放（`resources still in use at exit`），与本功能无关；判断通过与否看 `FAIL` 与 `SCRIPT ERROR` 行。
