# 五张关卡地图

F5从第1关开始连续五关。每关先显示可关闭的2D游玩说明并暂停；清空所有波次后点击按钮进入下一关，第5关显示通关。死亡重开当前关，换关使用下一关保存的生命与装备。操作见[五关游玩说明](PLAY_GUIDE.md)，早期地图构建、缩放及加载验证见[历史记录](../history/2026-10-28/gameplay/LEVEL_MAPS.md)。

## 文件与当前配置

以下路径相对 `movement_demo/`：

| 关卡 | 场景 | 导航资源 | 本关兵种预设 |
| --- | --- | --- | --- |
| 1 | `scenes/world/levels/lvl_1.tscn` | `resources/navigation/lvl_1_navigation.tres` | `scenes/enemy/levels/lvl_1/melee.tscn` |
| 2 | `scenes/world/levels/lvl_2.tscn` | `resources/navigation/lvl_2_navigation.tres` | lvl_2下的melee／pistol／smg |
| 3 | `scenes/world/levels/lvl_3.tscn` | `resources/navigation/lvl_3_navigation.tres` | lvl_3下的melee／pistol／smg |
| 4 | `scenes/world/levels/lvl_4.tscn` | `resources/navigation/lvl_4_navigation.tres` | lvl_4下的melee／pistol／smg／shotgun |
| 5 | `scenes/world/levels/lvl_5.tscn` | `resources/navigation/lvl_5_navigation.tres` | lvl_5下的melee／pistol／smg／shotgun |

五关均已保存玩家、相机、灯光、小队与敌人波次，可打开各关按F6单独试玩；不再是早期空Squad或仅地图状态。实际人数、装备、出生点与波次以用户当前保存场景为准，不将早期示例数值写成固定难度。

本关预设引用 `resources/enemy/training/levels/lvl_N/` 下同名训练，同关同兵种通常共享。复制／继承敌人场景不会自动分离外部训练或武器资源。仅修改单关／单实例时先另存训练与武器再替换引用；地图里已有跨关引用保留，不自动按地图名重配。完整配置见[敌人AI](../enemy-ai.md)。

## 场景结构与维护

关卡根继续使用scripts/world/shooting_range.gd，CombatZone、NavigationRegion3D、Player、Camera3D及Squad路径保持；原EnemyWaves仅改名SceneDirector并更新必要引用，子层级不动。总调度统一开场、死亡、完成与加载，LevelFlow保留五关表和结果视图；区域与波次执行各自业务。新配置见[教程](SCENE_DIRECTOR.md)。

地形位于 `NavigationRegion3D/Environment` 下，按FullCover、HalfCover、Walls、Boundary、Ground组织。高低掩体沿用原预制与区域脚本，普通墙和边界不能只因外形相似就加上战术掩体标签。修改大小时同时检查Mesh与碰撞Shape，保持底面落地和原导航辅助；详见[竞技场与掩体](ARENA.md)。

源图为 `scenes/Lvl_1.svg` 至 `Lvl_5.svg`。原第4、5张SVG内部标题与文件编号有交叉，关联以文件名为准。场景中 `source_svg`、`source_rect`、`interior_size` 等metadata用于编辑追溯，不是运行时自动重建地图的接口；历史比例与缩放步骤见归档，不能据此再次缩放用户已调整的地图。

## 修改波次和装备

第一关首波通过 `SceneDirector/Wave1.existing_squads` 引用原根目录Squad，第二波使用 `SceneDirector/Wave2/Squad`。修改第一波仍选原Squad；复制新波优先复制独立部署的Wave，避免复制外部引用造成重复。其他关卡先展开已有SceneDirector，再调整小队与成员，不重复添加控制器。

波次树序决定出场顺序。Wait For Previous Clear决定在紧邻前波全灭或实际出场后开始计时，Start Delay Seconds决定延时。后续波默认在实际出生时获得一次有误差的玩家位置并持续搜索，树序首波排除。操作、重叠波和不刷怪排查见[波次配置](ENEMY_WAVES.md)。

玩家装备通过场景原Equipment／武器槽配置，敌人通过各自Weapon配置；切关不会自动继承上一关临时装备。共享资源改动会跨场景生效，保存前检查引用对象。

## 导航与验证边界

移动墙、掩体或边界后重新烘焙对应关卡导航，并保存外部 `lvl_N_navigation.tres` 与场景。保留UID及导航障碍配置，不能只保存场景或仅修改可见Mesh。站立身体高1.75米；原批量烘焙工具设置cell_height与agent_max_climb为0.25米，并排除平面地图中实体箱体的内部与顶面。

`tests/bake_levels.gd` 会重新写入五关导航资源，是明确的维护操作，不属于回归测试；本次文档整理没有运行它。普通导航可达不能替代完整身体通道、友军间距、低墙翻越入口与落点检查，也不构成多层地图支持承诺。

历史五关短时headless加载记录只证明当时资源可加载；卸载出现的成员移除警告亦保留在历史中。完整验收需分别核对加载、实际波次战斗、全部清场、过关／死亡复位及导航行为；单个关卡流程测试不等于难度与手感验收。测试入口与未解决限制见[敌人测试](../enemy-tests.md)。

## 旧章节引用

<a id="区域导航与空小队"></a>

区域、导航与空小队：[整理前对应章节](../history/2026-10-28/gameplay/LEVEL_MAPS.md#区域导航与空小队)。

<a id="敌人波次快速上手"></a>

敌人波次快速上手：[整理前对应章节](../history/2026-10-28/gameplay/LEVEL_MAPS.md#敌人波次快速上手)。

<a id="本阶段核对"></a>

本阶段核对：[整理前对应章节](../history/2026-10-28/gameplay/LEVEL_MAPS.md#本阶段核对)。
