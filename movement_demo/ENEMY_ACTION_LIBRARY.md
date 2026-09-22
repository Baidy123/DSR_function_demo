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

## 怎样配置和调用

1. 打开`arena.tscn`，选Enemy/UnitType：`available_actions`决定兵种拥有哪些动作。`action_overrides`按动作ID替换实现，替换脚本须继承对应公共动作脚本；无效继承会警告并退回默认实现。
2. 选Enemy/Training：`allowed_actions`决定训练允许哪些动作。原有Can类能力开关也继续生效；例如出口压制还须开启`tactics_can_suppress_exits`。新Training默认关闭它，现有测试场景保留用户已开启的值。
3. 原AI、战术、搜索、掩体等训练参数集中在Training，保留中文说明和原值。身体和武器参数仍在Enemy。原动作属性转发到Training，不再保存第二套绑定配置。
4. AI通过UnitType创建实例，绑定上下文，再以`can_use_action(id)`检查兵种与训练两层门槛；还须满足导航、视线等现场条件。AI调用动作，动作调用Enemy执行。Training不更新计时器、不启动或执行动作。
5. 运行中撤销权限会取消相应活动动作；恢复搜索权限会按已有记忆继续。死亡、刷新、场外停用由AI统一清理。动作内部的既有流程保留，尚未改成新的总体评分系统。

按F5运行Main，进入竞技场观察巡逻、接敌、架枪、掩体和射击；离场再进检查刷新。可在远程检查器关闭对应UnitType/Training权限观察取消。编辑器已刷新为新结构，当前选中Training，游戏已停止。人工手感仍待用户试玩。

## 验证记录（2026-09-22）

- 动作库77、配置迁移90、结构17、原AI回归157、架枪接口15、架枪32、受击28、保持6、普通压制39、出口压制30、概率8，共499项通过。
- 编辑器保存后配置迁移90项再次通过；与迁移前快照比较地图节点、变换、碰撞盒、网格和导航资源，138项通过。
- 实际Main运行确认新节点树、独立动作对象、敌人移动与10次开火；运行日志无本次错误，独立审查完成。
- 4组旧测试仍有18项失败：fire_timing 14、fire_decision 1、enemy_weapon 1、covering_retreat_fire 2。用迁移前脚本与同一份用户调参复测，失败一致；这些固定旧参数的断言不能代表本次迁移回归。未为通过旧断言改动用户调参，也未宣称旧全套测试通过。

现有动作迁移、权限门槛、实例独立、替换实现、运行中撤权、死亡/刷新和配置保存均已验证。没有新增兵种等级、训练预设、声音或弹匣玩法。后续具体玩法仍由用户指定。
