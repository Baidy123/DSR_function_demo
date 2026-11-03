# 项目文档导航

[项目总览](../README.md)介绍已实现功能、常用配置和扩展入口。本目录的现行说明按用途组织；场景路径以 `movement_demo/` 为根，检查器数值以实际保存配置为准。

## 玩法与玩家配置

| 文档 | 解决的问题 |
| --- | --- |
| [游玩说明](gameplay/PLAY_GUIDE.md) | 操作、两种锁定模式、五关流程 |
| [移动](gameplay/MOVEMENT.md) | 加减速、耐力、蹲姿、翻越及移动接口 |
| [战斗](gameplay/COMBAT.md) | 锁定、鼠标辅助、弹道算法、精度与爆头 |
| [开火方式](gameplay/PLAYER_FIRE_MODES.md) | 单发、自动、霰弹及输入边界 |
| [装备](gameplay/WEAPON_SLOTS.md) | 主副槽、配置归属、切枪状态 |
| [弹药](gameplay/AMMO.md) | 弹种、备弹、换弹与缺弹掉落 |
| [霰弹](gameplay/SHOTGUN.md) | 图样编辑、散布标定与逐发装填 |
| [近战](gameplay/MELEE.md) | 玩家近战、眩晕破绽、近战兵及命中反馈 |
| [生命与医疗包](gameplay/PLAYER_HEALTH.md) | 伤害、治疗、重开与 Debug |

## 敌人与关卡

| 文档 | 解决的问题 |
| --- | --- |
| [敌人 AI](enemy-ai.md) | 身体、训练、感知、动作、小队职责与接入 |
| [竞技场](gameplay/ARENA.md) | 区域激活、离场与复位 |
| [关卡地图](gameplay/LEVEL_MAPS.md) | 保存关卡、部署与导航维护 |
| [敌人波次](gameplay/ENEMY_WAVES.md) | 编排小队、延迟、出生搜索与排错 |
| [场景总调度教程](gameplay/SCENE_DIRECTOR.md) | SceneEvent节点接线、Wave事件、手摆镜头目标、死亡与通关控制 |
| [敌人武器](gameplay/ENEMY_WEAPON.md) | 武器绑定、射击与换弹 |
| [敌人命中概率](gameplay/ENEMY_PROBABILITY.md) | 敌人瞄准与精度恢复 |
| [听觉](gameplay/HEARING.md) | 声源、遮挡、听觉响应与显示 |
| [攻击位置](gameplay/ATTACK_POINTS.md) | 掩体、射击站位与路径选择 |

## 内容接入与维护

| 文档 | 解决的问题 |
| --- | --- |
| [相机](gameplay/CAMERA.md) | 玩家绑定、武器视野与遮挡透明 |
| [模型、动画与特效](gameplay/PRESENTATION.md) | 表现资源契约及接入流程 |
| [交互物](gameplay/INTERACTION.md) | 条件、效果与可复用对象 |
| [阶段与任务](gameplay/STAGE_STATE.md) | 配置表、任务条件及 NPC 状态 |
| [项目结构](project-layout.md) | 模块职责、目录与维护约束 |
| [测试入口](testing.md) | 查询清单、选择专项及结果判断 |
| [敌人验证](enemy-tests.md) | AI 运行验证、故障场景与已知限制 |
| [当前待办](TODO.md) | 项目进度及后续工作 |

## 当前说明与历史依据

现行文档说明当前用法，后续应直接更新对应章节，不在文件开头持续堆叠逐日更新。历史参数、实施过程与旧验证结果保存在[整理前记录目录](history/2026-10-28/index.md)，引用历史结果时保留当时的范围和失败项。

`superpowers/plans/` 与 `superpowers/specs/` 是已有计划和设计依据，本轮不修改、迁移或重排其中内容。它们与当前代码有差异时，应依据用户要求和实际实现核对，不能以文档整理重新定义功能。
