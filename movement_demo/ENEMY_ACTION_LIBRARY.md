# 敌人动作库与节点结构

已完成现有敌人结构迁移。UnitType管“有没有”，Training管“允不允许”，AI统一选择、启动、更新与取消；Enemy负责身体执行。

```text
Enemy                 移动、转向、瞄准、开火、生命与复位
├─ UnitType           动作清单、单项实现替换、近战/远程类型
├─ Training           动作权限与训练参数
└─ AI                 决策、动作实例与生命周期
   ├─ Perception      感知辅助
   └─ Cover           空间查询与选点评估辅助
```

## 动作在哪里

`enemy_action_library.gd`集中登记实现；`enemy_action.gd`提供上下文与参数访问。动作继承RefCounted，是普通对象，不挂场景节点。代码按用途分文件，不合成一个大脚本。

| 动作ID | 实现 |
| --- | --- |
| patrol | enemy_patrol_action.gd：巡逻 |
| search | enemy_search.gd：追踪、调查与搜索 |
| engage | enemy_tactics.gd：接敌移动与射击 |
| cover | enemy_cover_action.gd：转移、躲藏、探头 |
| attack_position | enemy_attack_position_action.gd：寻找攻击位置并架枪 |
| suppression | enemy_suppression_action.gd：普通压制 |
| exit_suppression | enemy_exit_suppression_action.gd：出口压制 |

`covering_retreat`是cover内的掩护撤退能力，单独受权限控制。FireDecision也是AI持有的普通辅助对象。每个敌人创建自己的动作实例、计时器和进度；当前工厂创建全套实例，清单限制参与选择的动作，不用于减少实例分配。

## 怎样拖入动作

动作资源位于Godot文件系统的`res://enemy_actions/`。默认已在UnitType和Training各填好8项；保存重开仍能显示，不再手填动作ID。

1. 打开`arena.tscn`，选Enemy/UnitType，展开Available Actions。
2. 添加数组元素（或把Size增加1），将文件系统里的`.tres`拖到新增的空槽。删除某项表示兵种没有该动作。空槽不提供权限，同ID只放一项。
3. 选Enemy/Training，展开Allowed Actions，同样拖入训练允许的动作资源。两个清单都含该动作才可使用，仍需满足原能力开关和现场条件。
4. 例如`attack_position.tres`表示“寻找墙角并架枪”。从Training移除它表示未掌握；重新拖入且开启Can Use Attack Positions即可恢复资格。
5. 按Ctrl+S保存，按F5运行Main进入竞技场测试。运行中撤销权限会取消对应活动动作。

文件名与上表动作ID一致。资源显示中文名称，展开后可看Action Id、Display Name和Implementation。`.tres`描述动作，Implementation引用的`.gd`执行动作；计时器、执行阶段仍在每个敌人独立创建的普通对象中。

## 怎样替换特殊兵种动作

复制一份对应`.tres`，保留Action Id，修改名称，并把继承原动作脚本的自定义`.gd`拖入Implementation。用这份资源替换UnitType列表里的原条目。Training按ID匹配，可继续使用公共资源；Training中的Implementation不参与选择执行脚本。

原Action Overrides字典已移除。资源实现脚本不符合继承要求时，警告并使用公共实现。`covering_retreat.tres`是掩护撤退权限条目，执行仍在cover动作内，Implementation留空；它不提供独立动作替换。

训练参数仍集中在Training，身体和武器参数仍在Enemy。Training不启动或更新动作，AI通过UnitType创建实例并统一调度。清单权限运行中生效，替换Implementation需重启运行才能重建动作对象。公共`.tres`会被多个敌人引用，需要单独调整时先复制资源。

## 验证记录（2026-09-22）

- 动作库77、配置迁移90、结构17、原AI回归157、架枪接口15、架枪32、受击28、保持6、普通压制39、出口压制30、概率8，共499项通过。
- 编辑器保存后配置迁移90项再次通过；与迁移前快照比较地图节点、变换、碰撞盒、网格和导航资源，138项通过。
- 实际Main运行确认新节点树、独立动作对象、敌人移动与10次开火；运行日志无本次错误，独立审查完成。
- 迁移当时4组旧测试有18项失败（后续已修复测试配置，见下节）：fire_timing 14、fire_decision 1、enemy_weapon 1、covering_retreat_fire 2。用迁移前脚本与同一份用户调参复测，失败一致；这些固定旧参数的断言不能代表本次迁移回归。未为通过旧断言改动用户调参，也未宣称旧全套测试通过。

现有动作迁移、权限门槛、实例独立、替换实现、运行中撤权、死亡/刷新和配置保存均已验证。没有新增兵种等级、训练预设、声音或弹匣玩法。后续具体玩法仍由用户指定。

## 可拖拽资源验证（2026-09-22）

资源加载、同ID授权、空槽、实际脚本替换、独立实例及修改后的场景保存重载41项通过，原动作库77项及配置迁移90项通过，共208项。实际编辑器保存并重载后两个列表各有8个资源；Main启动成功，运行中移除与恢复训练资源的权限变化符合预期。游戏已停止，当前选中UnitType。

本次未改动UnitType/Training以外的场景节点、训练数值或武器。命令行运行有既有武器资源UID失配后按文件路径加载的警告；实际Main运行无本次错误。没有重跑上一节全部旧行为测试。

## 旧测试配置修正（2026-09-22）

此前18项失败现已消除。`tests/enemy_fire_fixture.gd`为时序和开火决策测试新建独立武器，并配置测试敌人的权限及训练参数，避免依赖检查器中的当前试玩值。时序测试固定0.5秒反应、三枪一组、1秒停顿和0.8秒射击间隔；决策测试使用明确的低概率跟枪条件。资源只在测试进程内创建，不写回用户`.tres`。

武器测试仍检查实际场景引用正确资源及按当前初始概率初始化；后续使用独立武器验证真实射线、伤害、射程、冷却、换枪和状态独立。保留原射速、停顿、真实移动及禁射断言，修正一处误设散布参数的测试。

4组结果：enemy_fire_timing 36/36、enemy_fire_decision 17/17、enemy_weapon 21/21、covering_retreat_fire 13/13，共87项通过。游戏逻辑、场景与用户调参均未修改。本轮只运行这4组，不代表全部历史测试均通过。
