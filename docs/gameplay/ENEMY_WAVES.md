# 敌人波次配置

每波仍在场景中摆好小队和敌人，支持原顺序、多波同场，以及事件节点/显式请求出场。原EnemyWaves入口已改名SceneDirector，内部敌人执行部分报告真实结果，总调度显示过关按钮、处理死亡和镜头。五关部署与F5/F6流程保持。事件接线和手摆目标见[中文教程](SCENE_DIRECTOR.md)，旧部署见[历史记录](../history/2026-10-28/gameplay/ENEMY_WAVES.md)。

## 第一关在哪里改

第一关保留原 `Lvl1/Squad` 作为第一波，`SceneDirector/Wave1` 的 **兼容已有场景 → Existing Squads** 保存相对路径 `../../Squad`。Wave1下面没有子小队是正常的。第二波在 `SceneDirector/Wave2/Squad`。人数、装备和出生位置以当前保存场景为准，不按早期示例固定。

| 修改内容 | 操作 |
| --- | --- |
| 第一波敌人 | 修改根节点下原 Squad 及其成员 |
| 第二波敌人 | 修改 SceneDirector/Wave2/Squad |
| 增加成员 | 将敌人／兵种预制拖到所属 Squad 下，移开重叠位置 |
| 改血量、移速、武器 | 敌人根节点 |
| 改个人训练 | Training → Profile／战术解锁 |
| 改团队配合 | Squad → Profile → Level |
| 增加小队 | 在同一 Wave 下放入 `scenes/world/squad.tscn` |
| 增加波次 | 复制独立部署的 Wave2，或添加 `scenes/world/enemy_wave.tscn` |
| 改顺序模式的先后 | 调整SceneDirector下同一层Wave的顺序；事件/请求模式各自等待 |
| 删除一波 | 删除对应 Wave，保留有效部署并核对引用 |

复制Wave1会复制同一个外部Squad引用。创建独立新波时，应清空新副本的 Existing Squads 并放入独立小队；同一小队只能属于一波。移动敌人时拖到目标波的Squad下，再改3D位置。节点属性可单实例覆盖，武器／训练／Profile资源则可能共享，单独修改前先设为唯一或另存。

## 时间与出生搜索

| Wave字段 | 默认值 | 语义 |
| --- | --- | --- |
| Start Mode | SEQUENCE | 原顺序；EVENTS监听事件；REQUEST由场景动作/接口请求 |
| Event Nodes | 空 | 推荐：选择SceneEvent或有无参triggered的节点，路径相对Wave |
| Triggers / Trigger Combination | 空 / ANY | 高级原信号绑定；与Event Nodes合并，ANY任一、ALL全部 |
| Wait For Previous Clear | 开启 | 等紧邻上一波全灭并完成清理后开始等待 |
| Start Delay Seconds | 0秒 | 条件满足后的等待时间 |
| Search On Spawn | 开启 | 后续波实际出生时取得一次玩家大概位置并进入搜索 |
| Spawn Search Error Radius | 3米 | 该一次性提示的最大水平误差，0为精确快照 |

SEQUENCE模式关闭Wait For Previous Clear时，从紧邻上一波实际出场起计时；开启则等全灭清理。其首波从战斗开始计时，后波不越过未出场的前波。EVENTS/REQUEST独立满足条件后才开始自己的延时，不受这项前波条件约束；暂停、对话、死亡等区域不可运行期间不累计时间。

“上一波”只指树序紧邻的那一波；第二波先死时，等待第二波的第三波可以加入，即使第一波尚存活。最终完成要求所有波次已出场且全部敌人死亡。清场信号可能按第二波、第一波的顺序发出。

树序最前的初始波（内部第0波）始终忽略出生搜索。公开信号从1计数，初始波对应 `wave_started(1)`；波名不决定顺序。提示在刷新点真正可用、实际生成时才采样，同波共享一次快照，只发给新波成员，不重置旧波。

出生搜索复用原TRACK／SEARCH与团队搜索：先快速追查，再持续警戒搜索。**Training → Profile → Search** 的 `combat_pursuit_seconds` 默认4秒、`combat_pursuit_speed_multiplier` 默认1.8，前者为0关闭快速阶段。按提示原始捕获时刻计算，换轮、重排、到点或暂停恢复不续期。它不是目击、压制或开火许可，不跟踪玩家后续隐蔽移动，也不推断其速度。

无法取得有效玩家或合法误差点时仍生成本波，保留原出生行为并输出诊断，不无限等待或退回无误差坐标。未建立交战警戒的普通声音调查仍可能结束回巡逻，与出生搜索不同。

## 给新战斗区域接入

1. 保留区域的 `shooting_range.gd`、战斗区、玩家和导航。在该区域下放一个 `scenes/world/scene_director.tscn`，一个区域只放一个控制器。
2. 在SceneDirector下放Wave，在Wave下放Squad，在Squad下放敌人／兵种预制。日常无需填写成员名单。
3. 在有效导航面上摆好完整身体位置；不要缩放角色。同波成员不能重叠；允许不同波共用刷新位置，但被占时会等待。
4. 保存场景与引用资源后试玩。已有五关先检查现有SceneDirector，不能重复添加第二套控制器。

已有小队不便移动时，用Wave的Existing Squads引用。需要修改继承场景子节点时开启“可编辑子节点”，保留原路径与UID。关卡入口和导航维护见[关卡地图](LEVEL_MAPS.md)。

## 不刷怪时检查

| 现象 | 核对项 |
| --- | --- |
| 第一波未开始 | 玩家是否在区域内、场景是否暂停／对话／死亡、区域是否正常激活 |
| 提示配置错误 | 控制器数量、空波、无敌人小队、非法子节点、重复或无效小队引用 |
| 一直等待刷新 | 原出生点是否被玩家、存活敌人或可移动物体占据 |
| 编辑后位置不可用 | 完整身体空间、静态墙体、导航烘焙与场景保存 |
| 后续波不搜索 | 是否变成树序首波、开关是否关闭、是否取得有效出生提示 |
| 不显示过关 | 是否仍有其他波存活／未生成，以及关卡流程是否接入完成信号 |

静态部署错误停止本轮并报告；动态占位按控制器 `spawn_retry_seconds` 重试，默认0.25秒。不会换到随机位置、强推角色或跳过错误波来掩盖部署问题。

## 代码接口与验证

入口仍使用enemy_wave_controller.gd原脚本UID；执行部分提取为enemy_wave_runtime.gd，定义与合法性检查继续由enemy_wave_definition.gd及enemy_wave_spawn_check.gd负责。区域在子节点ready前捕获模板并统一驱动战斗时钟，场景核心独立处理死亡/引导/镜头，不另起敌人AI循环。

| 入口 | 用途 |
| --- | --- |
| `capture_templates(region)` | 收集并校验部署，建立本轮模板 |
| `start_encounter()` | 请求启动；仍受原区域激活条件限制 |
| `request_wave(wave)` / `wave_status(wave)` | 请求指定REQUEST波、查询其独立状态；不会绕过区域和出生校验 |
| Wave的`spawned` / `cleared` | 稳定无参事件，来源节点可直接绑定 |
| `advance_from_region(delta)` | 仅由区域统一推进，其他脚本不要重复每帧调用 |
| `reset_encounter()` | 清理运行实例并复位；清理完成前不生成新轮 |
| `owns_runtime_enemy(enemy)` | 判断受管运行成员 |
| `debug_snapshot()` | 只读状态；alive是总人数，active_waves是仍存活波次，wave不是唯一在场波 |
| `wave_started(index)`／`wave_cleared(index)` | 从1计数的波次事件 |
| `encounter_completed` | 全部波次完成，由关卡流程接后续界面 |

拾取/交互/区域/脚本信号可用SceneEvent或高级Triggers接入，不需重写刷新代码。Wave的“出场镜头”可直接绑定手摆Marker3D/Node3D，未绑定不自动猜目的地；出生成功时才冻结和展示。配置步骤见[教程](SCENE_DIRECTOR.md)。专项为enemy_wave_test、enemy_wave_search_test、enemy_wave_events_test及scene_reinforcement_test；五关流程由level_flow_test验证。

## 旧章节引用

<a id="后续波出生即搜索"></a>

后续波出生即搜索：[整理前对应章节](../history/2026-10-28/gameplay/ENEMY_WAVES.md#后续波出生即搜索)。
