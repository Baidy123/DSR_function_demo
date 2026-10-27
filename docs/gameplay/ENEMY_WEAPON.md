# 敌人武器配置

敌人与玩家共用 `WeaponData` 资源，射击控制与运行状态各自独立。普通敌人枪械使用中心概率；霰弹使用固定图样加随机偏移。武器不会替敌人寻找目标或决定战术。本文按当前代码整理，旧实现与旧测试结果见[历史记录](../history/2026-10-28/gameplay/ENEMY_WEAPON.md)。

## 配置入口

| 目的 | 检查器入口 | 作用 |
| --- | --- | --- |
| 装备枪械 | 敌人根节点 → Shooting → Weapon | 拖入枪械资源；空装备合法 |
| 禁止射击 | Shooting → Shooting Enabled | 关闭身体开火入口，不能替代兵种配置 |
| 枪口跟转速度 | Shooting → Aim Turn Speed Degrees | 默认90°/秒，区别于身体转身速度 |
| 屏外开火机会 | Shooting → Offscreen Fire Chance | 0～100%，默认50%；只影响原本合法的开火尝试 |
| 射击诊断 | Shooting → Debug Shooting | 输出中心概率、实际命中或遮挡 |
| 普通枪准度 | Weapon → 瞄准与散布 → 概率模式（百分比） | 初始概率、每枪损失、移动与目标跟踪损失 |
| 敌人恢复 | Weapon → 瞄准与散布 → 敌人恢复（原算法） | `stabilize_seconds`；玩家收敛公式不覆盖此项 |
| 射击节奏 | Training → Profile → Tactics | 反应时间、稳枪目标、点射数量、间隔倍率、停顿 |
| 感知距离 | Training → Profile → Perception | 默认启用武器锁定距离加感知余量；可切回独立视距 |

表中数值是脚本默认值，保存的武器、训练和场景覆盖优先。编辑共享 `.tres` 会影响所有引用者；只改一个敌人时先设为唯一或另存资源。

远程兵种必须具备枪械能力并装备兼容武器，纯近战武器不能靠勾选 Shooting Enabled 变成枪械。霰弹也是合法枪械，配置见[霰弹](SHOTGUN.md)。兵种、训练与装备分别配置，更换兵种不会自动替换 Weapon。

## 实际射击规则

普通枪调用 `weapon.get_aim_settings(false)`。中心概率成功时沿**当前枪口方向**发射，否则在8°～20°偏离范围内取样；最终伤害仍由真实射线的第一处碰撞决定。因此100%中心概率也可能因枪口尚未跟上或障碍遮挡而未命中，详见[敌人概率](ENEMY_PROBABILITY.md)。

每名敌人拥有独立弹匣、精度、恢复等待和冷却。敌人使用有限弹匣及原换弹流程，备弹采用敌人原无限补充策略。运行时装备应走身体的 `equip_weapon(data)`，不能直接把共享资源当作运行状态容器；装备变更不应绕过已有开火冷却。

屏外机会在真实开火尝试时才抽样。失败跳过整枪，不耗弹、不发送实际发射事件，但仍消耗射击间隔和对应火控配额；霰弹按整枪处理。屏内仍按正常射击条件执行，屏外机会不授予目击、穿墙射击或超射程权限。

玩家专用的收敛公式、蹲姿精度、跟枪免罚半角不改变敌人算法。`tracking_parallel_tolerance_degrees` 默认25°，只在玩家持枪时读取；敌人内嵌武器检查器隐藏这些玩家专用项。

命中与擦过的基础效果来自攻击方武器，受方训练中的精度／速度损失倍率再参与计算。身体负责伤害、减速和执行互斥，AI决定何时提交射击、换弹或近战请求。

## 结构与验证

身体执行在 `scripts/enemy/enemy_actor.gd`，射击节奏在 `services/enemy_fire_controller.gd` 与 `enemy_fire_decision.gd`，参数结构在 `scripts/weapons/weapon_data.gd` 和 `scripts/enemy/config/tactics_settings.gd`。代码路径均相对 `movement_demo/`。

相关入口包括 `enemy_probability_test`、`enemy_firing_cadence_test`、`enemy_offscreen_fire_test`、`enemy_reload_test` 和霰弹测试。概率、射线、节奏与自主战斗是不同验证层次；历史中存在资源预期、节奏及性能失败，不能以某个专项通过代表全量通过。运行方法与已知限制见[敌人测试](../enemy-tests.md)。
