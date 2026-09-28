# 竞技场配置与试玩

`scenes/main.tscn` 实例化 `scenes/arena.tscn`。敌人在 `Arena/Enemy`，玩家进入区域后启用 AI，离场按区域规则复位。当前敌人结构与战术勾选见 [敌人模块化 AI](../enemy-ai.md)。

## 编辑场景

- 敌人身体、生命与武器在 `Enemy`；兵种资源在 `Enemy/UnitType`，训练资源和战术勾选在 `Enemy/Training`。
- `Enemy/AI` 协调运行，`Perception` 和 `Cover` 子节点提供感知与空间查询。动作按资源装配，无需逐个添加动作节点。
- 掩体位于 `NavigationRegion3D/Environment`，可以实例化 `scenes/world/cover.tscn` 添加。改动墙体、地板或掩体布局后，应重新烘焙导航。

## 掩体与站位

掩体碰撞盒提供四面躲藏区域和墙角攻击区域。编辑器显示候选范围，运行时再检查身体空间、导航可达性、遮挡和真实射界，并非线框内每一点都能站立。

墙角区域几何与参数见 [ATTACK_POINTS.md](ATTACK_POINTS.md)。攻击占位在训练中开放后参与统一评分，旧版本的目击触发概率和固定优先级已被替代。

## 试玩

按 F5 进入竞技场，观察交战、换弹、绕掩体、失视搜索及重新目击。游戏内 Debug 总开关可显示攻击候选、声音范围和敌人状态；需要时启用无敌。

当前验证入口见 [敌人测试](../enemy-tests.md)。CoverB 东北侧偶发卡住、视野边缘切换和整体手感仍按真实复现处理。
