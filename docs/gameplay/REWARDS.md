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
| `Effect` | `ADD_MEDKIT` 增加医疗包库存、`REFILL_AMMO` 补满弹匣与备弹、`SET_FLAG` 获得商品并设置旗标、`WEAPON` 覆盖武器槽 |
| `Amount` | 医疗包购买数量；其他效果忽略 |
| `Medkit Data` | `ADD_MEDKIT` 商品引用的现有 `MedkitData .tres`，疗效和使用时间由此资源配置 |
| `Flag Key` | `SET_FLAG` 商品购买后置为 true 的旗标键，不能为空 |
| `Weapon Data` | `WEAPON` 商品必须引用现有 `WeaponData` |
| `One Time` | 购买成功后隐藏；`WEAPON` 与 `SET_FLAG` 必须为真，医疗包／补弹可关闭以重复购买 |

初始目录只有三个商品，均 `unlock_level = 0`。急救包与弹药补给可重复购买；思维接入装置为一次性商品：

| 商品 | ID | 价格 | 效果 | 效果参数 |
| --- | --- | ---: | --- | ---: |
| 急救包 | `first_aid` | 40 | `ADD_MEDKIT` | `default_medkit.tres`，数量 1 |
| 弹药补给 | `ammo` | 30 | `REFILL_AMMO` | 无 |
| 思维接入装置 | `mind_access_device` | 500 | `SET_FLAG` | `has_mind_access_device = true` |

装置商品一次付清 500，单次购买调用 `GameState.grant_shop_flag(&"has_mind_access_device")`，将拥有旗标置为 true。
购买成功后记录一次性购买并隐藏商品，不能重复购买。死亡选择返回酒馆时，恢复上次通关返程的状态，
货币、商品旗标与购买资格一起回到该恢复点；不是另做一笔退款。检查点只恢复商店登记的旗标，唱片机等其他玩法旗标不受影响。

目录读取时过滤无效项：空项、空 ID、负价格、未知效果、医疗包商品的非正数量、缺失或无效的 `Medkit Data`、旗标商品缺少 `Flag Key` 或未开 `One Time`、武器商品缺少
`WeaponData` 或未开 `One Time`。

## 可见性与购买

打开／关闭由本场 SceneDirector 批准并记账，ShopController 保留商品校验与购买结算。NPC 提交 shop 请求；原 `open_shop_for_player(player)`、`close_shop()` 为兼容转发入口。关闭、死亡或来源离场会结束本次商店流程，不解除其他暂停拥有者；空目录仍不暂停。接线见[导演教程](SCENE_DIRECTOR.md)。

检查器按 `Effect` 显示配置：`ADD_MEDKIT` 只显示 `Medkit Data` 与 `Amount`；`WEAPON` 只显示
`Weapon Data`；`SET_FLAG` 只显示 `Flag Key`；补弹隐藏这些无关字段。切换效果只隐藏字段，不清空已拖入的资源。

新增医疗包商品时，选择 `ADD_MEDKIT`，把现有 `resources/player/default_medkit.tres` 或其他有效的
`MedkitData .tres` 拖入 `Medkit Data`，再填 `Amount` 数量。默认商品为 40 货币购买 1 个包。
当前 Equipment 共用一种医疗包资源：同一资源直接叠加；库存清空后可接收另一种资源。
还有库存时不覆盖成另一种医疗包，拒绝购买且不扣款。死亡返回酒馆时，资源、库存数量与货币随检查点一起恢复。

商品区使用可滚动网格：默认 3 列，行数随可见商品自动增长；窗口变窄时按卡片最小宽度自动降为 2 列或 1 列。
商店面板默认尺寸为 1040×680，随游戏窗口缩小并在四周各留 24 像素；标题、商品文字和购买／关闭按钮使用较大字号。
锁定和已购买的一次性商品不创建卡片，也不占网格位置。

商品可见条件：

```text
item.unlock_level <= GameState.completed_level
and not (item.one_time and GameState.has_purchased_shop_item(item.id))
and not (item.effect == SET_FLAG and GameState.get_flag(item.flag_key))
```

不满足可见条件的商品不创建可见行，也不占空位；目录全部不可见时商店显示“暂无商品”且不暂停游戏。
面板按 `ShopController` 给出的可用状态显示／禁用购买按钮：余额不足、没有可接收的医疗包库存、弹药已满或已拥有旗标商品时，
对应按钮不可点击，控制器在购买时仍会再次复核，不扣款、不改变状态。

- 急救包：购买后将 `Medkit Data` 对应的医疗包加入 Equipment，数量增加 `Amount`；满血也可购买，当前生命不变。之后按 H 使用，疗效与使用时间读取该医疗包资源。
- 弹药补给：补满两把已装备武器的弹匣，并把 `initial_ammo` 中已配置的共享备弹恢复到至少初始数量，
  同时保留其他备弹类型；已经全满时购买被拒绝。
- 旗标商品：装置售价 500、`Flag Key = has_mind_access_device`、`One Time = true`；购买后旗标变为 true。已拥有时隐藏并拒绝再次购买，即使购买记录被清空也以旗标为准。
- 购买成功后扣款、刷新余额和商品可用状态，面板保持打开。

## 拥有类商品与旗标查询

新增拥有类商品时选 `SET_FLAG`，填写不重复的 `Flag Key` 并打开 `One Time`；无需填写 `Amount`。
思维接入装置的商品 ID 为 `mind_access_device`，拥有旗标为 `has_mind_access_device`。

```gdscript
if GameState.get_flag(&"has_mind_access_device"):
    # 玩家已拥有装置，可在这里判断后续玩法条件。
    pass
```

任务表可用 `QuestCondition.flag(&"has_mind_access_device")` 作为条件，沿用原 FLAG 条件与 `flag_changed` 通知。
商店商品旗标的值唯一保存在 `GameState.flags`；`shop_flags` 仅是检查点快照，不是另一份运行时状态。
原数值进度、累加方法和任务面板进度条已移除。

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
和新增金额补写进当前 `completed_level` 对应的检查点，不依赖任务自身的 `stage_index`；返回酒馆恢复检查点时
`rewarded_task_ids` 让新的任务控制器只显示已完成，
不会第二次发钱。

## 死亡后的重新挑战与返回酒馆

平时没有手动重试入口。**只有死亡界面**提供两个选择，分别对应一近一远两个恢复点：

- **本关入场恢复点 → 重新挑战当前关卡**：回到进入当前关卡时的状态，所以进关前在酒馆买好的装备和补给保留。
- **上次通关返程恢复点 → 返回酒馆**：回到上一关刚完成并返回酒馆时的状态，更早于本关入场。货币、装备、医疗包、商品旗标和购买记录一起恢复；之后的消费和购买不保留。

例如完成第1关回酒馆后买装备，再进入第2关死亡：重新挑战回到第2关入场时；返回酒馆回到第1关结束、刚返程时。不是返回第1关地图，也不是单独退钱。已完成的关卡及对应任务奖励保留，返回酒馆后仍由 A 解锁下一关。

内部实现会在入关时保存一次性玩家快照及本关入场快照，死亡重开时使用本关入场快照；`request_restart()` 本身也只接受 dead 状态。酒馆恢复使用返程检查点。它们都在引擎接受加载后提交；加载失败时只允许重新尝试这次切换，不表示新增了平时重试关卡的功能。没有入场快照的独立场景死亡重开仍用场景保存配置。

这两个恢复点会随手动游戏存档写入单槽 `user://campaign_save.cfg`。启动读取有效存档后进入酒馆；未手动保存就退出游戏时，本次运行中的恢复点不会保留。

## 兼容组件

旧三选一组件保留文件与脚本 UID，不再接入主流程：`scripts/rewards/reward_level.gd`／`reward_option.gd`／
`reward_table.gd`、`scripts/systems/stage/encounter_controller.gd`、`scripts/ui/reward_board.gd` 与
`scenes/ui/reward_board.tscn`、`resources/rewards/level_rewards.tres`。`tests/reward_board_test.gd` 仍作为
兼容组件测试验证旧面板；旧逐关奖励验收测试已退役，商店与任务金额测试进入统一 systems 清单。

## 测试

`shop_catalog_test`、`shop_state_test`、`shop_weapon_test`、`shop_board_test`、`shop_flow_test`、
`quest_money_reward_test` 分别覆盖目录过滤、货币与检查点状态、武器槽覆盖、面板回传、购买流程与任务金额。
入口见[测试说明](../testing.md)。
