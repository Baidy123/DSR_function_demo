# 货币商店、任务金额与检查点回滚设计

日期：2026-11-04

状态：用户已确认方向，等待书面设计复核

## 目标

- 用货币商店取代主场景中的关卡三选一奖励。
- 保留原三种商品能力：急救包、弹药补给、系统进度。
- 商品由 `.tres` 资源组成，可在 Godot 检查器中直接新增，例如绑定现有 `WeaponData` 作为新枪商品。
- 商品按已完成关卡逐级解锁；未解锁商品完全隐藏。
- 五个主线任务各自配置固定金额，首次完成时发放一次。
- 死亡返回酒店时恢复最近完成关卡检查点，退还检查点之后的商店花费，并同步撤销购置记录和装备变化。

## 非目标

- 不实现退出游戏后的正式存档。
- 不实现完整武器库存或独立换装菜单。
- 不扩展任务面板为商店界面。
- 不修改现有武器数值、敌人、关卡部署或导航。
- 不恢复被舍弃的三选一主流程。

## 用户确认的规则

- 蓝色结算奖励 NPC 继续复用，但职责改为进入商店。
- 舍弃三选一。
- 初始只有急救包、弹药补给、系统进度三个商品。
- 后续通过商品 `.tres` 手动添加新商品，包括现有枪械。
- 每关首次完成发放固定金额；未指定时默认 100。
- 消耗品可重复购买；武器购买永久保留于当前运行，但同一商品只可购买一次。
- 购买武器时由玩家选择覆盖主武器槽或副武器槽。
- 未解锁商品完全隐藏。
- 死亡返回酒店时恢复上一轮商店花费，并重置检查点之后购买的一次性武器及其装备状态。

## 资源设计

### ShopItemDefinition

新增 `scripts/shop/shop_item_definition.gd`，`class_name ShopItemDefinition extends Resource`。

字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `id` | `StringName` | 稳定商品 ID；目录内唯一 |
| `display_name` | `String` | 商店名称 |
| `description` | `String` | 商品说明 |
| `price` | `int` | 购买价格，至少 0 |
| `unlock_level` | `int` | 0 始终可见；大于 0 时要求 `completed_level >= unlock_level` |
| `effect` | 枚举 | `HEAL`、`REFILL_AMMO`、`SYSTEM_PROGRESS`、`WEAPON` |
| `amount` | `int` | 回血量或系统进度增量；其他效果可忽略 |
| `weapon_data` | `WeaponData` | `WEAPON` 商品的现有枪械资源引用 |
| `one_time` | `bool` | 购买成功后永久隐藏；武器商品必须为真 |

检查器提示需要说明：`WEAPON` 必须挂 `WeaponData`，且买入后覆盖所选槽位；普通商品可重复购买。

### ShopCatalog

新增 `scripts/shop/shop_catalog.gd`，`class_name ShopCatalog extends Resource`，包含按检查器顺序保存的 `items: Array[ShopItemDefinition]`。

新增 `resources/shop/shop_catalog.tres`：

| 商品 | ID | 价格 | 解锁等级 | 效果 | 参数 |
| --- | --- | ---: | ---: | --- | --- |
| 急救包 | `first_aid` | 40 | 0 | `HEAL` | 35 |
| 弹药补给 | `ammo` | 30 | 0 | `REFILL_AMMO` | 无 |
| 系统进度 | `system_progress` | 50 | 0 | `SYSTEM_PROGRESS` | 20 |

初始目录不加入武器条目。现有 `resources/weapons/*.tres` 可直接拖入新建 `WEAPON` 商品，不需要复制枪械配置。

目录读取时过滤无效项：空项、空 ID、负价格、未知效果、武器商品缺少 `WeaponData`。同一 ID 只接受第一项并给出诊断。

## 任务金额

`QuestDefinition` 新增 `money_reward: int = 100`。

`resources/stages/stage_table_template.tres` 的五条主线任务分别配置 `money_reward = 100`。支线任务保持显式 0，只有在其资源上配置金额后才发钱。

`QuestController` 在任务从非完成状态进入 `COMPLETED` 时调用 `GameState.claim_task_reward(task_id, amount, completed_level)`。任务已完成终态和 `GameState.rewarded_task_ids` 共同防止重复发放。

任务完成发生在返程门记录检查点之后、酒馆任务控制器重新评估时。因此 `claim_task_reward()` 还要把该任务 ID 和新增金额同步补写进匹配当前完成关卡的检查点。恢复检查点时，`rewarded_task_ids` 会让新酒馆任务控制器只显示已完成，不再发第二次钱。

## GameState 扩展

新增运行状态：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `money` | `int` | 当前货币，永不为负 |
| `rewarded_task_ids` | `Dictionary` | 已发放金额的任务 ID 集合 |
| `purchased_shop_item_ids` | `Dictionary` | 当前运行中已购买的一次性商品 ID 集合 |
| `level_entry_player_state` | `Dictionary` | 最近从酒馆进入关卡的玩家快照，仅用于当前关重试 |

接口：

- `add_money(amount)`：增加有效正整数并广播 `money_changed`。
- `spend_money(amount)`：余额足够时原子扣款；不足时返回 `false`。
- `claim_task_reward(task_id, amount, completion_level)`：首次发奖并同步当前完成检查点。
- `has_task_reward(task_id)`。
- `mark_shop_item_purchased(item_id)` / `has_purchased_shop_item(item_id)`。

酒店检查点新增 `money`、`rewarded_task_ids`、`purchased_shop_item_ids`。现有任务、奖励兼容字段和玩家快照保留，避免破坏旧资源接口。

旧 `claimed_reward_levels` 与三选一组件保留为兼容数据，但不再参与主场景商品资格。

## 商店流程

### 入口

保留主场景节点路径 `RewardNPC`，其显示名称改为“商店”，继续使用现有脚本 UID。交互不再打开三选一，而是调用新的 `ShopController.open_shop_for_player(player)`。

主场景移除旧 `RewardBoard`/`EncounterController` 的启用接线，新增 `ShopBoard` 与 `ShopController`。旧组件文件保留，避免破坏独立复用和原脚本 UID。

### 可见性

商品可见条件：

```text
item.unlock_level <= GameState.completed_level
and not (item.one_time and GameState.has_purchased_shop_item(item.id))
```

不满足条件的商品不创建可见行，也不占用空位。

### 普通商品

- 急救包：生命未满时可直接购买，选择后立即恢复配置的 35 点生命。
- 弹药补给：补满两把已装备武器的弹匣，并恢复各弹种初始共享备弹。
- 系统进度：按配置增加，不超过 100。
- 余额不足或效果当前不可用（满血、进度已满等）时禁用购买。
- 购买成功后扣款、刷新余额和商品可用状态，面板保持打开。

### 武器商品

- 商品行显示名称、说明、价格，以及“覆盖主武器”“覆盖副武器”两个按钮。
- 任一槽位按钮都会直接购买并覆盖对应槽位；没有二次弹窗。
- 购买前验证当前阵营可装备、槽位有效且 `WeaponData` 不是专用近战武器。
- 扣款成功后写入一次性购买 ID，并把新枪装备到所选槽位。
- 新枪使用完整弹匣和当前共享备弹池，不修改其他槽或共享备弹总量。
- 购买失败不扣款、不写购买记录、不改变装备。

`Equipment` 新增 `replace_weapon_slot(slot, weapon)`：保留医疗包、另一把枪、当前共享备弹和玩家生命等状态，只替换目标槽、初始化该槽弹匣并更新显示/战斗绑定。

## 当前关重试与酒店回退

### 从酒馆进入关卡

`QuestPortal` 除一次性 `pending_player_state` 外，同时保存一份 `level_entry_player_state`。新玩家实例照常消费一次性快照，但进入状态副本保留到本关结束。

### 重新挑战当前关卡

`SceneDirector.request_restart()` 在重载前把 `level_entry_player_state` 设为 `pending_player_state`。因此已购买的枪械、弹药、医疗包和当前槽位会保留，不会因重试丢失已付款物品。没有入口快照的独立场景继续使用场景保存配置。

### 返回酒店

继续使用 `restore_campaign_checkpoint()`：

- 恢复检查点货币，退还检查点之后的花费。
- 恢复检查点 `purchased_shop_item_ids`，撤销之后的一次性购买记录。
- 恢复检查点玩家快照，移除之后购买的武器并恢复被覆盖的旧武器、消耗品和系统进度。
- 已发任务奖励仍在检查点中，不会因回酒店丢失。
- 加载失败时继续使用现有事务回滚，避免污染“重新挑战当前关卡”。

## 商店界面

新增 `scenes/ui/shop_board.tscn` 与 `scripts/ui/shop_board.gd`：

- `CanvasLayer.process_mode = ALWAYS`，暂停时可用。
- 顶部显示标题和当前货币。
- 中部为可滚动动态商品列表。
- 底部为关闭按钮。
- 行按钮发出 `purchase_requested(item_id, slot)`；`slot=-1` 表示普通商品，0/1 表示主/副武器。
- 面板只显示与回传意图，不直接修改 `GameState`、玩家或装备。

`ShopController` 负责目录解析、可见性、余额、效果复核、玩家修改、扣款、一次性记录和购买结果广播。打开商店时取得暂停所有权，关闭或离树时只释放自己的暂停。

## 错误处理

- 目录为空：商店显示“暂无商品”，游戏不暂停。
- 无玩家、面板缺失、目录缺失：拒绝打开并报告诊断。
- 商品无效：跳过并诊断，不阻塞其他商品。
- 余额不足：按钮禁用；控制器再次校验，防止过期 UI 购买。
- 武器槽无效、资源为专用近战或玩家不允许装备：拒绝购买，不扣款。
- 重复一次性购买：拒绝并刷新列表。
- 商店打开期间玩家死亡或场景卸载：取消商店并释放暂停。

## 兼容与迁移

- 保留 `RewardNPC` 节点路径、脚本 UID、`WeaponData`、武器资源和关卡场景引用。
- 旧 `RewardBoard`、`RewardOption`、`RewardLevel`、`RewardTable`、`EncounterController` 保留文件接口，但不挂在主流程中。
- 旧的逐关奖励测试改为兼容组件测试，不再作为主场景玩法验收。
- 新增商店测试进入统一 systems 清单。
- README、项目结构、交互、任务奖励、游玩说明和测试文档同步更新。

## 验证

### 资源与状态

- 商品目录加载、顺序、唯一 ID、无效项过滤。
- `unlock_level` 隐藏与逐级开放。
- 货币增加、扣款、不足拒绝、不出现负数。
- 任务金额只发一次，检查点补写后恢复不重复发奖。
- 酒店检查点恢复货币、一次性购买 ID 和玩家装备。

### 商店行为

- 三个初始商品按配置价格购买。
- 急救包、弹药、系统进度实际生效。
- 新增 `WEAPON` 商品引用现有 `WeaponData` 后可见并可购买。
- 主/副槽覆盖正确，旧武器在检查点恢复时回来。
- 一次性武器购买后隐藏且不能重复购买。
- 未解锁和已购商品完全隐藏。

### 五关集成

- 第 1 关完成返酒店获得 100。
- 商店购买急救包或其他消耗品后进入第 2 关，死亡重试保留已购状态。
- 进入第 2 关后死亡返回酒店，货币恢复、消费撤销、一次性武器购买记录和装备槽同时回滚。
- 更早检查点之前的购买和任务奖励保留。

## 验收标准

- 主场景不再打开三选一。
- 蓝色 NPC 可稳定打开货币商店。
- 编辑器添加 `.tres` 商品即可扩展目录，新枪可绑定现有 `WeaponData`。
- 任务固定金额与商店消费均纳入检查点语义。
- 死亡返回酒店不会出现“退款但枪还在”或“枪消失但钱没退”的不一致。
- 当前关重试不会丢失已付款装备。
- 相关自动化、场景结构和文档检查通过。
