# 项目结构与模块职责

本页说明当前目录、场景与代码归属。功能和常用接口见[项目总览](../README.md)，专项用法见[文档导航](README.md)。路径以 `movement_demo/` 为根；现有节点路径、资源引用和脚本 UID 是复用边界，文档整理不迁移它们。

## 目录

```text
movement_demo/
├── project.godot                 工程与输入配置，主入口为 world/levels/lvl_1.tscn
├── scenes/
│   ├── main.tscn                 独立功能／任务演示
│   ├── arena.tscn                独立战斗区域
│   ├── player/                   玩家、独立相机及战斗／装备／生命子场景
│   ├── enemy/                    公共身体、兵种继承与各关预设
│   ├── world/levels/             五关地图与已保存部署
│   ├── world/                    波次、小队、掩体、交互物及区域
│   ├── presentation/             模型包装与独立预览
│   ├── effects/                  表现特效场景
│   └── ui/                       游玩说明、关卡流程、对话与状态界面
├── scripts/
│   ├── player/                   移动、Combat、Equipment、Health、医疗
│   ├── weapons/                  武器配置、弹药状态、弹道与爆头结算
│   ├── enemy/                    身体、AI、训练、动作与私有服务
│   ├── world/                    区域、波次、小队、导航、对象与交互效果
│   ├── systems/                  相机、状态、任务、表现与特效
│   ├── ui/                       只读界面与操作界面
│   └── debug/                    Debug 开关与诊断视图
├── resources/                    武器、弹药、训练、声音、动画、任务等静态配置
├── tests/                        玩家／系统专项、enemy/ 专项与统一运行器
├── addons/                       第三方插件与项目检查器扩展
└── logs/                         运行输出、截图与临时验证，Git 忽略
```

仓库根的 `docs/gameplay/` 保存现行使用说明，`docs/history/` 保存整理前的实施和验证记录；`docs/superpowers/plans/`、`specs/` 保持原计划／设计依据。

## 玩家与武器

| 文件／组件 | 职责与接口边界 |
| --- | --- |
| `player/player.gd` | 真实移动、碰撞、耐力、姿态和翻越；移动前后调用 Combat 的帧入口 |
| `player/player_combat_v3.gd` | 锁定、鼠标辅助、转身、准度、扳机、当前枪弹药、射击和玩家近战 |
| `player/target_switch_gesture.gd` | 仅累计鼠标净位移、时间和新输入标记，不持有目标或场景 |
| `player/player_weapon_slots.gd` / Equipment | 装备配置、槽位、每槽运行状态、共享备弹和唯一医疗包库存 |
| `player/player_health.gd` | 生命、伤害、治疗结算、死亡通知及重开 |
| `player/player_medkit.gd` | 治疗资格、输入中断、冻结参数与计时，向 Health 交付回血 |
| `weapons/weapon_data.gd` | 静态枪械参数、收敛和爆头等纯数值规则；不保存角色运行进度 |
| `weapons/weapon_ammo.gd` | 每枪弹匣与装填计时，玩家／敌人共用；策略由调用方决定 |
| `weapons/shotgun_ballistics.gd` | 弹丸采样、物理射线与近弹几何，伤害归各方射击入口 |
| `weapons/headshot_resolver.gd` | 按实际目标冻结每枪结果与一次破绽消费，再交付受击 |
| `ui/lock_reticle.gd` | 只读准度、目标概率和转身状态，显示准星／菱形／转向标记 |

Equipment 交接当前枪给 Combat；相机订阅 `weapon_changed`，表现订阅真实射击结果。鼠标辅助沿原 Combat 执行，不新增第二份锁定或自由瞄准状态。主动转身固定读取当前武器低速跟枪项，真实目标移动仍独立按原速度插值，两项损耗取较大者。

## 敌人、区域与小队

| 层 | 责任 |
| --- | --- |
| Enemy 身体 | 实际移动、碰撞、枪械、近战、生命及受击；报告执行事实 |
| `enemy/enemy_ai.gd` | 个人决策或团队任务执行，交接原动作、身体与火控 |
| Training / Profile | 感知、搜索、战术参数与动作能力；本场装配按现有冻结规则应用 |
| `enemy/actions/` | 各动作的候选、执行和共同命令提案，沿原生命周期调用 |
| `enemy/services/` | 感知、记忆、路线、规划与有限私有值记录，各服务保持单一职责 |
| `world/squad_controller.gd` | Squad 配置、区域注册与生命周期；Profile 独占团队等级 |
| 小队协调器 | 1／2级团队任务、规划与公共约束；0级及无绑定个人沿原个人决策 |
| `world/shooting_range.gd` | 区域激活、注册、时钟、导航／公共查询及离场复位 |

只有个人分支运行个人 Utility；团队成员即使暂时失败、占用或只剩一人，仍按团队指挥边界执行。身体不选择战术，私有值记录服务不另建调度循环。详细服务契约、训练适用范围和故障处理见[敌人 AI](enemy-ai.md)。

## 波次、关卡与补给

- `world/enemy_wave_controller.gd` 在区域中捕获部署模板、推进波次、处理完成与重置；`enemy_wave_definition.gd` 保存等待、延迟、出生搜索和已有小队引用。
- `systems/level_flow.gd` 消费 `encounter_completed`，显示下一关／通关界面；`ui/play_guide.gd` 管理入场说明期间的暂停与鼠标恢复。任务系统不参与五关按钮流程。
- `world/ammo_drop_controller.gd` 管理区域掉落选择、数量与生命周期，`ammo_drop_position.gd` 检查合法落点，`ammo_pickup.gd` 显示并执行一次领取。
- `scenes/enemy/levels/lvl_N/` 与 `resources/enemy/training/levels/lvl_N/` 保存各关兵种／训练。共享资源仍可能被跨关引用，修改前核对实际使用者。
- 导航烘焙命令会写资源，属于维护工具；不能作为普通游戏加载流程或默认回归一起执行。

## 相机、表现与内容

相机根 `systems/player_camera.gd` 统一绑定玩家、读取武器 Aim Range、控制视野过渡；`camera_occlusion.gd` 仅处理显式标记装饰的材质副本与还原。CameraGroundAnchor 过滤翻越抬升。保持原 Phantom Camera 跟随和更新关系。

`systems/presentation/` 读取实际状态驱动模型／动画，`systems/effects/` 管理命中快照、表面配置与特效生命周期。表现不改变伤害、枪口、碰撞或 AI；UI 不替代业务状态的唯一写入者。

`world/interactions/` 的效果只通过 InteractionContext 使用注入引用。`systems/stage/` 中阶段、任务和 NPC 状态控制器各自拥有数据，通过只读查询和变化信号协作；普通节点按组绑定，NPC 只按稳定 ID 接收状态。

## 文件与文档维护约束

1. 修改前阅读 README、本页及涉及的专项说明；敌人任务同时检查敌人说明与验证要求。
2. 按既有职责扩展，保留节点路径、资源引用、脚本 UID 和用户配置；新增脚本放入对应职责目录，不把临时诊断放入运行目录。
3. 用户确认的方向是实现依据。不能为了迁就实现改写原设计、放宽测试，或把默认值／建议写成用户逐项确认要求。
4. 功能、接口或职责变化时更新相应当前章节和使用说明。README 保持项目入口，详细参数放专项文档，逐次验证和历史过程单独记录，避免再次堆积成更新流水。
5. 资源只保存配置，实例组件保存运行状态；同一状态只保留一个权威写入入口，UI、相机和诊断读取或订阅。
6. 验证覆盖实际行为及结构约束；历史通过数、运行无错误或一次成功不能替代完整验收。
7. 普通阶段提交、推送及本地修改保护遵循仓库 [AGENTS.md](../AGENTS.md)；不得借文档整理同步远端、覆盖其他任务或改写历史计划。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](history/2026-10-28/project-layout.md)。历史通过数不代表当前本地配置已重新验证。

## 旧章节引用

<a id="文档维护约束"></a>

文档维护约束：[整理前对应章节](history/2026-10-28/project-layout.md#文档维护约束)。
