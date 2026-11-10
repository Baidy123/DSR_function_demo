# 货币商店与任务奖励

酒馆东侧房间的蓝色 NPC 标签为“商店”，交互时打开货币商店。商品由 `resources/shop/shop_catalog.tres`
配置，任务金额由 `resources/stages/stage_table_template.tres` 里的 `money_reward` 配置。旧的三选一奖励
组件保留为兼容代码，不再接入主流程。

## 商品目录

目录资源是 `resources/shop/shop_catalog.tres`（`ShopCatalog`），`Items` 数组按检查器顺序保存
`ShopItemDefinition`，显示顺序即数组顺序。每个商品字段：

| 字段 | 含义 |
| --- | --- |
| `Id` | 稳定商品 ID，目录内唯一；重复 ID 只保留第一项并给出诊断 |
| `Display Name` / `Description` | 商店名称与说明 |
| `Price` | 价格，至少 0；余额不足或效果当前不可用时，由控制器复核并拒绝，不扣款、不改变状态 |
| `Unlock Level` | 0 始终可见；大于 0 时要求 `completed_level >= unlock_level`，否则完全隐藏 |
| `Effect` | `HEAL` 回血、`REFILL_AMMO` 补满弹匣与备弹、`SYSTEM_PROGRESS` 增加系统进度、`WEAPON` 覆盖武器槽 |
| `Amount` | 回血量或系统进度增量；弹药补给与武器忽略 |
| `Weapon Data` | `WEAPON` 商品必须引用现有 `WeaponData` |
| `One Time` | 购买成功后永久隐藏；`WEAPON` 必须为真，普通商品可关闭以重复购买 |

初始目录只有三个商品，均 `unlock_level = 0` 且可重复购买：

| 商品 | ID | 价格 | 效果 | 数值 |
| --- | --- | ---: | --- | ---: |
| 急救包 | `first_aid` | 40 | `HEAL` | 35 |
| 弹药补给 | `ammo` | 30 | `REFILL_AMMO` | 无 |
| 系统进度 | `system_progress` | 50 | `SYSTEM_PROGRESS` | 20 |

目录读取时过滤无效项：空项、空 ID、负价格、未知效果、回血／系统进度商品的非正数值、武器商品缺少
`WeaponData` 或未开 `One Time`。

## 可见性与购买

商品区使用可滚动网格：默认 3 列，行数随可见商品自动增长；窗口变窄时按卡片最小宽度自动降为 2 列或 1 列。
锁定和已购买的一次性商品不创建卡片，也不占网格位置。

商品可见条件：

```text
item.unlock_level <= GameState.completed_level
and not (item.one_time and GameState.has_purchased_shop_item(item.id))
```

不满足可见条件的商品不创建可见行，也不占空位；目录全部不可见时商店显示“暂无商品”且不暂停游戏。
面板按 `ShopController` 给出的可用状态显示／禁用购买按钮：余额不足、满血、弹药已满或系统进度已满时，
对应按钮不可点击，控制器在购买时仍会再次复核，不扣款、不改变状态。

- 急救包：生命未满时购买成功，立即恢复 `Amount` 点生命；满血时购买被拒绝。
- 弹药补给：补满两把已装备武器的弹匣，并把 `initial_ammo` 中已配置的共享备弹恢复到至少初始数量，
  同时保留其他备弹类型；已经全满时购买被拒绝。
- 系统进度：按 `Amount` 增加，不超过 100；已满时购买被拒绝。
- 购买成功后扣款、刷新余额和商品可用状态，面板保持打开。

## 武器商品

把现有 `resources/weapons/*.tres` 拖入新建 `WEAPON` 商品的 `Weapon Data` 即可扩展目录，不需要复制枪械配置。
武器商品行显示名称、说明、价格，以及“覆盖主武器”“覆盖副武器”两个按钮；任一按钮直接购买并覆盖对应槽位，
没有二次弹窗。购买前会验证槽位有效、当前阵营可装备且 `WeaponData` 不是专用近战武器；失败不扣款、不写购买记录、
不改变装备。成功后写入一次性购买 ID，并通过 `Equipment.replace_weapon_slot(slot, weapon)` 覆盖目标槽：
保留医疗包、另一把武器、共享备弹和玩家生命，目标槽以满弹匣出生。一次性武器商品购买后立即隐藏，不能重复购买。

## 任务金额

`QuestDefinition.money_reward` 默认 100。任务控制器在任务首次进入 `COMPLETED` 时调用
`GameState.claim_task_reward(task_id, amount, completed_level)` 发放一次；`GameState.rewarded_task_ids`
和任务完成终态共同防止重复发放。五个主线任务（`task_a`、`task_level_2` 至 `task_level_5`）均为 100，
唱片机支线 `task_music` 保持 0，只有在其资源上配置金额后才发钱。

任务完成发生在返程门记录检查点之后、酒馆任务控制器重新评估时，因此 `claim_task_reward()` 会把该任务 ID
和新增金额补写进当前 `completed_level` 对应的检查点，不依赖任务自身的 `stage_index`；返回酒店恢复检查点时
`rewarded_task_ids` 让新的任务控制器只显示已完成，
不会第二次发钱。

## 当前关重试与酒店退款

- 进入关卡时，`QuestPortal` 除一次性 `pending_player_state` 外，还保存 `level_entry_player_state`。
- 重新挑战当前关卡：`SceneDirector.request_restart()` 重载前把 `level_entry_player_state` 设为
  `pending_player_state`，因此进入本关前已付费的武器、弹药、医疗包和货币不会因重试丢失；没有入口快照的
  独立场景继续使用场景保存配置。
- 返回酒店：沿用 `GameState.restore_campaign_checkpoint()`，恢复检查点货币（退还检查点之后的花费）、
  检查点 `purchased_shop_item_ids`（撤销之后的一次性购买）、检查点玩家快照（移除之后购买的武器并恢复被覆盖的
  旧武器、消耗品和系统进度）。已发任务奖励已在检查点中，不会因返回酒店丢失。

## 兼容组件

旧三选一组件保留文件与脚本 UID，不再接入主流程：`scripts/rewards/reward_level.gd`／`reward_option.gd`／
`reward_table.gd`、`scripts/systems/stage/encounter_controller.gd`、`scripts/ui/reward_board.gd` 与
`scenes/ui/reward_board.tscn`、`resources/rewards/level_rewards.tres`。`tests/reward_board_test.gd` 仍作为
兼容组件测试验证旧面板；旧逐关奖励验收测试已退役，商店与任务金额测试进入统一 systems 清单。

## 测试

`shop_catalog_test`、`shop_state_test`、`shop_weapon_test`、`shop_board_test`、`shop_flow_test`、
`quest_money_reward_test` 分别覆盖目录过滤、货币与检查点状态、武器槽覆盖、面板回传、购买流程与任务金额。
入口见[测试说明](../testing.md)。
