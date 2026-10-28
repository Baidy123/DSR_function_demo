# 竞技场与掩体编辑

项目 F5 默认进入连续五关。要单独测试竞技场，打开 `movement_demo/scenes/main.tscn` 后按 F6；竞技场本体为 `scenes/arena.tscn`，在 Main 中以 Arena 实例接入。五关另见[关卡地图](LEVEL_MAPS.md)。旧场景布局和阶段记录见[历史记录](../history/2026-10-28/gameplay/ARENA.md)。

## 场景与日常配置

竞技场通过 `scripts/world/shooting_range.gd` 管理区域激活、敌人、共享地图与复位。玩家进入战斗区后运行，离场后按原区域流程刷新并等待再次进入。敌人部署在所属 Squad 下；不要按旧示例假定固定存在 `Arena/Enemy`，实际路径以当前保存场景树为准。

| 修改内容 | 入口 |
| --- | --- |
| 个人生命、移动、装备 | 对应敌人根节点 |
| 兵种与训练 | 敌人 UnitType／Training 节点 |
| 小队配合 | Squad → Profile → Level |
| 多波部署 | SceneDirector → Wave → Squad，见[波次说明](ENEMY_WAVES.md) |
| 掩体大小 | 掩体 MeshInstance3D 的 Mesh Size 与 CollisionShape3D 的 Shape Size |
| 掩体候选区域 | 掩体根节点的 Wall Gap、Hide Depth、攻击区参数 |
| 导航 | NavigationRegion3D 的外部 NavigationMesh 资源 |

单个实例调参前注意资源共享：Mesh、Shape、武器、训练和小队 Profile 可能被多个实例引用；需要独立修改时先设为唯一或另存。

## 掩体尺寸与候选区域

高掩体由碰撞盒生成四面躲藏带与四角攻击扇环，每个角保留墙外270°、排除墙内90°。低掩体站姿与蹲姿共用一圈外围矩形带，不使用高墙角内圈排除或高墙 Peek 区。颜色只是有限候选预览，实际仍需身体、路线、占位和射界检查，见[攻击位置](ATTACK_POINTS.md)。

标准低掩体预制尺寸为3×1.1×0.6米，根节点Y为0.55以落地；这是预制初值，不限制关卡实例。优先保持根节点 Scale 为1，同时修改可见Mesh和碰撞Shape尺寸，并让底面落地。只缩放可见模型会使AI看到的几何与画面不符；根节点缩放还会改变区域宽度与采样间距。

低墙须开启 Low Cover，且碰撞盒满足运行时高度与直立限制；Vault Enabled 仅允许尝试翻越，入口、完整身体通道和落点仍需检查。保留预制原节点路径、NavigationBakeObstacle等导航辅助与资源UID，不手工删除以“放开”导航。

## 导航与验证限制

竞技场使用外部 `resources/navigation/arena_navigation.tres`。改墙体或可行走范围后重新烘焙，并同时保存场景与外部导航资源；`tests/bake_arena.gd` 是会写入导航的维护工具，不是只读测试。角色站高按1.75米维护，不能只凭导航线穿过就认定完整胶囊可通过。

候选带不保证在地图边界处自动裁成全部合法区域。有限采样或绿色预览不能代替实际通行、转角、射线与翻越验证。验证方法见[敌人测试](../enemy-tests.md)；本次文档整理未重新运行场景或烘焙导航。
