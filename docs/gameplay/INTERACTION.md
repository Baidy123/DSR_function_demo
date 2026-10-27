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
scripts/world/interactions/interaction_context.gd   一次交互的注入上下文
scripts/world/interactions/interaction_effect.gd    效果基类
scripts/world/interactions/*_effect.gd              具体效果
scripts/world/sliding_barrier.gd              纯位移屏障，由交互物通过方法调用驱动
scenes/world/interactable.tscn                可复用交互物场景
scenes/world/access_gate.tscn                 门禁读卡器 + 屏障
scenes/world/objects/                         各个具体交互物场景
scenes/ui/game_state_debug.tscn               调试面板
```

## 配置和扩展接口

`Interactable` 的 `display_name`／`verb` 控制提示，`interact_id` 提供任务稳定标识，`one_shot`／`hide_on_interact` 控制重复和隐藏，`required_items`／`required_flags` 表达条件，`effects` 数组按顺序执行。

`can_interact(player)` 查询资格，`interact(player)` 执行并返回结果；`interacted`／`blocked` 通知成功或受阻。效果继承 `InteractionEffect.apply(context)`，通过 InteractionContext 获取注入的状态及目标，不直接依赖全局节点或其他系统内部实现。

## 验证

`interactable_test` 核对输入、条件、效果和注入替身，任务联动由任务及交互专项覆盖。运行结果同时看断言、进程和脚本／资源诊断；已有退出资源问题单独记录，不用“断言通过”覆盖它们。统一入口见[测试说明](../testing.md)。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](../history/2026-10-28/gameplay/INTERACTION.md)。历史通过数不代表当前本地配置已重新验证。
