# 关卡奖励配置

每关返回酒馆后，可与蓝色“结算奖励”NPC 交互打开该关三选一。领取记录按关卡独立保存：

- 同一关只能领取一次；
- 第1关领取后仍可领取第2关；
- 第2～5关同理，互不覆盖；
- 领取状态随 `GameState` 跨场景保留，退出游戏后重置。

## 配置入口

默认奖励表位于 `resources/rewards/level_rewards.tres`。在 Godot 文件系统中双击打开，
在 **Levels** 数组里选择关卡，每关的 **Options** 必须配置恰好三项：

| 字段 | 含义 |
| --- | --- |
| `Id` | 选项稳定 ID，在当前关三项中唯一；运行时回传该 ID |
| `Display Name` | 面板按钮标题 |
| `Description` | 按钮下方说明 |
| `Effect` | `HEAL` 回血、`REFILL_AMMO` 补满弹匣与初始备弹、`SYSTEM_PROGRESS` 增加系统进度 |
| `Amount` | 回血量或系统进度增量；弹药补给类型忽略该字段 |

五关的条目是独立资源，可以分别设置奖励名称和数值，也可新增其他已有效果的组合。
新增效果类型时需同步扩展 `RewardOption.Effect` 和 `EncounterController.select_reward()`。

## 结算流程

`EncounterController` 读取 `GameState.completed_level`，取得对应 `RewardLevel`，将三项配置传给
`RewardBoard.configure()`。面板只回传用户选择的选项 ID；控制器按该选项配置执行效果，
最后调用 `GameState.mark_reward_claimed(level)`。因此面板不保存玩家状态，也不会把某一关的选择写到其他关。

`task_a_reward_claimed` 仅为第1关旧接口保留镜像；逐关规则以 `claimed_reward_levels` 和
`GameState.has_claimed_reward(level)` 为准。

## 测试

`tests/reward_per_level_test.gd` 验证：

- 第1～5关分别开放三选一并分别记录领取；
- 已领取某关后不能重复领取，但不影响下一关；
- 修改第2关按钮标题、说明和回血数值后，实际面板与结算使用新配置。
