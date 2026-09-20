# 敌人行为板块拆分（2026-09-20）

用户已确认：兵种主要决定战术逻辑；训练水平调整各板块参数，并限制高级动作是否可用。高级动作必须先具备能力，之后才按场景和概率选择。本轮迁移已有行为，不创建尚未讨论的兵种/训练预设，不接入 WeaponData。

## 节点与边界

```text
Enemy                         基础身体、武器执行、伤害与复位
└─ AI                         唯一物理更新入口、共享目击记忆、行为切换
   ├─ Perception              真实视野、近身警戒与遮挡
   ├─ Tactics                 交战选位、射击节奏、战术动作能力
   │  └─ CoverAction          转移、躲藏、探头、绕行等已有动作
   ├─ Search                  丢失目标后的追踪、调查、区域搜索
   └─ Cover                   选择/评估躲藏与探头位置，不驱动动作
```

AI 顺序调用板块，避免多个节点分别移动同一身体。板块保存自身参数与运行状态；最后目击位置、警戒和主状态属于 AI 的共享信息。空间查询共用 AI 的基础检查，搜寻不依赖战术选位。Cover 返回 hide/peek/body 的选择结果，动作状态留在 Tactics/CoverAction。

Tactics 新增 can_covering_retreat（掌握撤退射击），默认开启以保留当前敌人的行为。未掌握时，即使 covering_retreat_chance=1 也只普通转移；开枪授权也核实能力。暂不创建“小混混/雇佣兵/公司特工”的枚举或配置资源。

## 执行计划

- [x] 固定测试夹具的射击参数，记录当前导出参数与场景值，取得现有行为基线；测试不依赖用户正在调整的数值。
- [x] 新建 tests/enemy_modules_test.gd，确认旧结构缺少5个板块的预期失败，再验证新结构和能力。
- [x] 从 enemy_ai.gd 迁出 Tactics、Search、Perception 的参数、状态与实现；AI 只保留协调及共享基础查询，更新调用方。
- [x] 从原 Cover v9 拆出 enemy_cover_selection.gd 与 enemy_cover_action.gd；旧脚本留作历史。更新 arena.tscn 节点及参数归属，所有当前值不变。
- [x] 能力门槛同时应用于动作选择与开火授权，验证关闭、开启、100%概率、普通跑打、刷新和实例独立性。
- [x] 迁移现行回归测试引用，运行原157项AI行为、41项射击、36项时序、13项撤退和玩家生命重开检查。
- [x] 查看实际节点/检查器、运行与日志；独立代码审查无阻碍，更新说明。

主要文件：enemy_ai.gd、enemy_tactics.gd、enemy_search.gd、enemy_perception.gd、enemy_cover_selection.gd、enemy_cover_action.gd、arena.tscn，及对应测试。保留 main.tscn、test_pistol.tres 的用户修改。

检查命令（项目根 E:/Godot）：
```powershell
& './Godot_v4.7.2-stable_win64_console.exe' --headless --fixed-fps 60 --path './movement_demo' --script res://tests/enemy_modules_test.gd
& './Godot_v4.7.2-stable_win64_console.exe' --headless --fixed-fps 60 --path './movement_demo' --script res://tests/enemy_ai_regression_test.gd
```

## 当前结果与查看方法

- 新板块/能力17项、原AI157项、结构与基础身体20项、射击41项、时序36项、撤退13项、玩家生命27项通过，共311项。早期旧版本测试未列为本轮通过范围。
- 独立审查逐函数比较迁移前后，核实全部旧导出参数、默认值和场景覆盖值。真实编辑器也读取核对了分块后的参数。
- 主场景实际运行正常；保留反应1.4秒、停顿2.1秒、视距8米、射程30.1米和移动散布23.9度。实机撤退约1.97米并射击1枪，关闭能力时100%概率仍不启用。最终正常权限运行无脚本错误/警告，游戏已停止。
- 打开 arena.tscn，展开 Enemy/AI。Tactics 的 Action Capabilities → Can Covering Retreat 是当前能力开关；默认开启是为了保留当前敌人的行为，不代表已经赋予某个训练等级。
- Tactics/CoverAction 的 Covering Retreat Chance 仍是“已经会这个动作后，本次是否选择”的概率。可临时调为1方便比较开关，测试后改回自己的值。F5进入竞技场射击触发掩体反应。
- 兵种（近战、手枪、霰弹枪、步枪）与训练水平（小混混、雇佣兵、公司特工）是两条已确认的分类方向；具体配置资源、能力分配和各兵种差异尚未实现。当前 Combat Type 仍是原来的近战/远程。
