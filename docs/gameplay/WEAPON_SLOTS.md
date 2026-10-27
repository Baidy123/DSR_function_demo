# 玩家装备与武器槽

Equipment 是玩家装备的配置入口，管理主副武器、共享备弹和医疗包库存。Combat 负责当前枪械的战斗执行。场景节点名为 Equipment，文件仍为 `player_weapon_slots.gd/.tscn`。

## 在哪里配置

选中关卡中的 **Player → Equipment**；实例需要时启用可编辑子节点。展开槽内资源时，检查器根据同级 Combat 的 Aim Mode 显示相应参数。

| 字段 | 用法 |
| --- | --- |
| Primary Weapon / Secondary Weapon | 引用 WeaponData；副槽可为空，专用近战武器不接受 |
| Starting Slot | 出生默认槽，0 主武器、1 副武器；为空时选择另一有效槽 |
| Initial Ammo | AmmoSupply 列表，配置每种弹药的共享初始备弹 |
| Medkit / Medkit Count | 医疗效果资源与初始数量，见[医疗包](PLAYER_HEALTH.md) |

武器资源位于 `resources/weapons/`，引用以各关当前保存配置为准。修改共享资源影响所有引用者；只调整一把枪或一关时先设为唯一或另存。Combat 没有第二个用于配置武器的 Weapon 槽。

## 怎么使用

按 **1 / 2** 选择主副武器，滚轮在有效槽间切换；重复选择当前槽不重置状态，空槽跳过。场外也能切枪；射击和近战仍需战斗区域许可。对话、死亡、暂停与近战动作占用时禁止切槽。

| 状态 | 切枪后的处理 |
| --- | --- |
| 锁定与扳机 | 取消旧锁定和待发请求；按住右键可用新枪重新索敌，左键需重新扣扳机 |
| 射击冷却 | 沿用上一枪剩余冷却，不能用切枪绕过射速 |
| 精度 | 各槽保存惩罚与等待；收起时不自动恢复，切回至多到初始精度，较差精度保留 |
| 整匣换弹 | 未到半程取消；达到半程保存 50%，切回后续换，收起时不计时 |
| 逐发装填 | 已装入的子弹保留，未完成的本发取消，不保存半程 |
| 同资源双槽 | 配置可共享，弹匣／恢复／换弹状态仍各槽独立 |

右下角显示两槽、当前武器、备弹与医疗包数量。重开恢复场景保存的装备及库存。近战读取手持枪械的附带参数，不需要为玩家另装专用近战武器。

## 代码接口

| 接口 | 契约 |
| --- | --- |
| `select_slot(slot) -> bool` | 检查合法性并切槽；0 主、1 副 |
| `ammo_snapshot() -> Array[Dictionary]` | 只读合并携带枪械的同类备弹和匣内数量；不创建或切换武器状态 |
| `add_ammo(definition, amount) -> int` | 增加共享备弹并返回入账数，不补弹匣、不开始换弹 |
| `Combat.equip_weapon(data, preserve_cooldown, ammo_state, resume_slow_reload)` | 装备组件向 Combat 交接当前枪及实例状态；切槽优先调用 Equipment |
| `Combat.weapon_changed` | 通知相机与表现装备变化 |

配置保存在 WeaponData，运行进度由 Equipment／WeaponAmmo／Combat 按职责持有。现有资源与节点 UID 不迁移。更多规则见[开火方式](PLAYER_FIRE_MODES.md)、[弹药](AMMO.md)、[近战](MELEE.md)及[相机](CAMERA.md)。

## 验证

相关入口为 `weapon_slots_test`、`player_scene_reuse_test` 及弹药／换弹专项。部分旧夹具仍引用本地已删除的 `test_sidearm.tres`，须区分资源假设失败与运行机制错误；详细状态见[测试说明](../testing.md)。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](../history/2026-10-28/gameplay/WEAPON_SLOTS.md)。历史通过数不代表当前本地配置已重新验证。
