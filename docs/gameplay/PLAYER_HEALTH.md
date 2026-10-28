# 玩家生命、医疗包与重开

Health 保存玩家生命，Player 保存耐力；Equipment 保存医疗包库存，Medkit 执行治疗。Health归零后只结算自身失能并发died；[SceneDirector](SCENE_DIRECTOR.md)收到后暂停、取消场景动作并显示原死亡UI，再接收按钮请求重开当前关。对话和剧情状态仍遵循GameState原生命周期。

## 配置入口

| 位置 | 字段 | 用途 |
| --- | --- | --- |
| Player → Health | Max Health | 最大生命，出生时满血，脚本默认100 |
| Player → Equipment | Medkit Count | 出生医疗包数量，默认3；运行时为该实例余量 |
| Player → Equipment → Medkit | Heal Amount / Use Seconds | 完整治疗回血量／时间，默认50／2秒 |
| Player → Health | Debug Mode | Debug 总开关的检查器入口 |

医疗资源默认为 `resources/player/default_medkit.tres`，也可另建 MedkitData；留空禁用治疗。共享资源只保存效果与时间，不共享库存和治疗进度。重开读取场景保存的装备、生命和数量。

## 治疗条件与操作

按 **H** 开始，站立或蹲下、实际落地、生命未满且有包时可用，场内外均可。松开动作键后可以立即使用，不用等待残余惯性完全停止。

| 情况 | 结果 |
| --- | --- |
| 仍按住动作键、瞄准、换弹或保留半程、近战、蹲起过渡、翻越 | 不能开始 |
| 完整计时结束 | 扣一个包并回血，不超过最大生命 |
| 中断 | 清零进度，不回血、不耗包，下次从头计时 |
| 满血、无包、配置为空或无效 | 不开始 |
| 暂停 | 冻结计时 |
| 对话、死亡、卸载 | 取消治疗；医疗不能复活 |

移动、奔跑、瞄准、开火、换弹、近战、蹲站、翻越、交互、切枪和再次按 H 都会打断，即使对应动作当时不能执行；取消后动作继续处理。单纯移动鼠标、松开 H 与按键重复事件不取消。治疗判断逐个动作键，反向键相抵不等于没有输入。

有效受击通过 `Health.hit_received` 打断；Debug 无敌也打断但不扣血。零、负数或非有限伤害不是有效命中。一次治疗冻结开始时的效果参数，运行时改资源影响下一次。

头顶显示真实进度环，右下装备栏显示数量；两者不驱动角色动作或碰撞。

## 伤害、死亡与 Debug

`receive_hit(damage)` 检查有效伤害并结算，致死时实际扣血不超过剩余生命；重复打击死亡玩家不重复处理。`restore_health(amount)` 返回恢复量且不能复活。`hit_received`、`damage_applied`、`died` 分别服务命中、中断／实际扣血与死亡通知。

Debug 总开关控制玩家无敌及诊断显示；右上“测试受伤”使用统一入口。带武器来源的真实命中仍按攻击武器与受方倍率结算精度／速度损失；无来源的测试伤害不伪造武器惩罚。无敌不回血、不复活，release 构建不接受该调试开关。

普通生命、体力、弹药、换弹与准星不依赖 Debug。声音圈和攻击位置诊断采用各自开关；日志设置与可见性分开。具体显示见[表现](PRESENTATION.md)与[敌人验证](../enemy-tests.md)。

## 文件与接口

| 文件／组件 | 职责 |
| --- | --- |
| `player_health.gd` / Health | 生命、有效命中、治疗结算与死亡通知，不自行暂停或重载 |
| `scene_director.gd` / `scene_result_view.gd` | 调度死亡、取消、重开及加载失败；视图复用原Health死亡UI节点 |
| `player_weapon_slots.gd` / Equipment | Medkit 资源与唯一库存 `medkit_count` |
| `player_medkit.gd` / Equipment/Medkit | 输入守卫、条件复核、冻结参数、计时和耗包 |
| `medkit_indicator.gd`、`medkit_stock_label.gd` | 进度与库存显示 |
| `medkit_data.gd` | 医疗效果和时间配置 |

新增动作输入时同步检查治疗的中断列表。日志默认位于 `movement_demo/logs/`，不提交；导出版本的日志位置需按实际运行环境核对。

## 验证

`player_medkit_test` 验证输入与结算，`player_medkit_lifecycle_test` 验证实例、保存、暂停、受击和重开，配合 `player_health_test`。历史渲染首轮曾出现未复现的治疗取消，原始失败及随后通过结果均保留在历史记录；本次文档整理不算重新运行这些专项。

## 历史记录

早期配置、实施过程及当时的验证结果保存在[整理前记录](../history/2026-10-28/gameplay/PLAYER_HEALTH.md)。历史通过数不代表当前本地配置已重新验证。
