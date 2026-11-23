# 远程交叉火力与远近混编协同设计

状态：**用户已在后续对话指示按本文实施，三个生产阶段已落实。** 需求与建议保留原文；实际完成范围、验证及未通过的旧断言见[实施记录](../plans/2026-10-24-ranged-melee-cooperation.md)和[敌人测试](../../enemy-tests.md)。下方“当前交付范围”及交接状态是实施前历史快照，不代表最新代码状态。

依据：[团队战术与连续搜索设计](2026-10-23-squad-tactical-search-design.md)、[当前敌人 AI 接口](../../enemy-ai.md)，以及用户本轮关于远近配合、近战停步和先写文档的反馈。保留现有统一协调器、能力装配、信息权限和真实身体执行边界。

## 1. 用户已经明确的方向

1. 重点是搜索和交战时近战与远程如何互相配合，不能只优化近战自己的移动或增加几个岗位名称。
2. 全远程队伍尽量形成交叉火力；混编时远程尽量在近战后方进行射击。这是基本方向，具体交战、搜索和突袭规则需要进一步设计。
3. 双侧突袭不能把近战当成远程使用同一种站位和完成条件。近战应能够接近并实际攻击，不能停在刚好打不到玩家的位置。
4. 不把兵种比例作为本轮设计和测试重点，按实际成员能力安排配合。
5. 保留此前要求：一人或两人检查，其余可提供掩护；空间不足时减少同侧人数；侧绕、突袭和赶到队友等待位置时合理奔跑；转角前后关注对应的藏身区。
6. 先形成可审阅的设计文档，再实施生产代码。

普通和强配合都适用。仅视野共享档保持原个人决策，单人幸存者继续由协调器指挥。

## 2. 已检查的实现与证据边界

| 当前代码事实 | 对本次工作的影响 |
| --- | --- |
| `enemy_search_formation.gd` 的接敌候选主要来自通用环形点，近战再把点收缩到武器范围附近。 | 缺少根据近战通道、远程后方射界共同生成和比较方案的明确职责。不能仅缩短远程站位距离来实现混编协同。 |
| `squad_coordination.gd` 在接敌位置变化超过约1米时更换目标；已有近战岗位没有与远程枪线失效对应的攻击可达性重排检查。 | 玩家较小位移也可能令近战站点失效，需要按攻击几何而非统一位移阈值判断。此处是代码支持的风险，尚未确认它是用户全部卡住现象的唯一原因。 |
| 已有搜索 `overwatch_for`、同期支援需求、真实火控、通行和关键入口屏障。 | 应复用并补足实际有效性，不另建一套身体、射击或团队循环。 |
| 既有远程搜索、侧翼和近战执行测试分别验证过部分能力。 | 这些结果不能自动证明“近战接近时远程有效掩护”，也不能证明搜索支援实际到位。 |

本轮曾运行旧 `--mixed --search` 入口，得到27/29；保存场景的兵种/装备变化影响了该夹具，两个失败涉及掩体观察断言，不能据此确认用户描述的近战停步原因。随后编写的混编诊断初稿把部分出生点放到当前地板范围外，成员下落，整组结果无效。该初稿与日志仅保存在 `movement_demo/logs/`，不进入正式回归或生产实现；实施时先校验地面、导航、装配和真实目击，再进行行为断言。

## 3. 推荐结构及取舍

采用 **一个协调器统一指挥，战术候选按能力区分，支援关系显式关联** 的结构。

- 继续由 `squad_coordination.gd` 唯一拥有目标、任务、成员生命周期和原子提交。
- 将远程射界分布、混编前后关系、近战攻击位置和联合方案评价集中到一个战术规划模块；根据实际武器与装配动作分类，不能仅判断兵种名称。
- 将检查者/接近者与掩护者的关联、就绪检查和有限等待集中到协调器持有的支援组件。组件返回事实和调整建议，不独立下发任务。
- 原动作执行器沿路线移动并上报反馈；原感知、火控和近战控制器继续决定本人是否能开火、挥击及实际命中。

其他方案的取舍：直接把所有分支堆进协调器，改动入口少但难以独立核对合作条件；分别建立远程和近战协调器，会拆散共同通行、掩护和换弹交接。因此推荐保留一个任务所有者，在其内部按职责拆分。

| 拟涉及位置 | 职责 |
| --- | --- |
| 新 `squad_combat_tactics.gd` | 从能力档案、合法目标和静态几何准备不同作战方式的候选；提供整队射界、前后关系和路线冲突的评价。无任务所有权。 |
| 新 `squad_support.gd` | 管理与当前任务绑定的掩护关系、就绪/失效事实和等待期限；复位、减员、换任务时清理。无独立更新循环。 |
| `enemy_team_planner.gd` | 在共同候选集合中比较全员组合，保持能力、空间和完整分工约束。 |
| `enemy_search_formation.gd` / `squad_search.gd` | 继续提供检查入口、藏身区、地图覆盖和连续调查路线。 |
| `squad_coordination.gd` / `squad_contract.gd` | 组织上述职责，定义任务关联字段、有效性与重排规则；所有任务一起验证和提交。 |
| 原命令动作、Context | 执行阶段朝向、速度和等待，报告攻击岗位失效；不自行选择另一套战术。 |

文件名和接口细节在设计确认后的实施计划中落实。只拆分与本次配合直接有关的职责，保留场景节点、资源路径、脚本 UID 和用户已有修改。

## 4. 交战规则

### 4.1 全远程：有持续火力的交叉射界

先保留已经具有合法射界的射手，再比较其他成员从侧方建立第二条射界的收益。对射向相同目标、角度过度重叠且身体集中在同一通道的组合提高代价；优先选择可达、可射击且彼此不挡枪的位置。

交叉火力是空间允许时的偏好，不能要求每次都绕到目标两边。窄通道只有一条射界时，其他成员可以等待可用射位、负责另一出口或执行短段转移；不能为摆出夹角让全队同时停火。候选仍比较实际行程、暴露、弹药、受压和改派成本，保留稳定岗位，避免频繁左右互换。

侧翼者长距离转移合理奔跑，移动中保持合法威胁朝向。有人因换弹或受压失去持续火力时，优先由具备实际射界的队友接替，再决定是否继续原机动。

### 4.2 混编：近战接近，远程在后方偏侧射击

“后方”以已知威胁和当前接近路线为参照，随战斗方向变化。远程通常比近战离目标更远，并保留侧向偏移，使枪线避开近战身体和即将经过的通道；不把两人排成一条直线。

联合比较一组近战接近路线和远程射位：

1. 近战最终位置能满足实际攻击距离、高差、遮挡与身体空间，路径能到达。
2. 远程有合法射程和可用枪线，能够从后方或后侧方覆盖接近中的暴露方向。
3. 近战当前及短期路线不会长期封住远程枪线；无法避免的短暂穿越由原火控停火和通行次序处理。
4. 路线互挡持续发生时，比较远程侧移、近战换入口或分段通过，不让双方重复等待同一个不变方案。

远程是否提供“支援”按实际视野、弹药、身体可用性和火控状态核对。普通射击者可以继续合法射击；专门的支援岗位及长点射仍要求已有训练资格，不能因为混编自动解锁。

近战已经具有合法攻击机会时及时攻击，不为等待远程换弹或队形外观错过出手。多人近战接近时分配不同可攻击位置；空间只够一人时，其他成员选择可继续接近的侧向路线或有限等待位置，不把所有人停到同一个攻击圈边缘。

### 4.3 停点和小幅移动修正

近战岗位的有效性同时包含“能到达”和“到达后能攻击”。规划停点应给导航到达容差留出余量，不能把理论射程边缘直接当作安全停止点。

收到新的合法目击后，按现有岗位是否仍满足距离、高差和遮挡判断是否需要调整，不等待玩家移动超过统一的1米阈值。优先保留仍有效的远程火力和其他成员任务，只重排失效职责及其直接冲突。

实际到位后，近战若持续无法攻击，应区分距离不足、墙体/队友遮挡、朝向尚未转好和正常冷却。距离或遮挡失效上报协调器重新规划；转向、冷却和收招保留合理等待，不能为了更快攻击跳过身体执行条件。新的合法目标位置才允许更新接近点，隐藏目标移动不能直接驱动修正。

## 5. 搜索规则

### 5.1 形成有对应对象的检查与掩护

搜索仍先调查最后合法线索，再扩展地图覆盖。根据入口空间、路径和成员能力选择检查者：混编时近战可承担近处和转角检查，远程优先利用后侧方可观察的位置掩护；明显绕远、不具备掩护资格或视线不成立时允许其他合理分工。

每个掩护任务关联具体检查组及其暴露区域，明确“在掩护谁、能覆盖哪段、何时失效”。位置必须能实际观察所负责的藏身区或出口，不能只看得到检查者就算有效掩护。隐藏阶段的任务是观察与待机，不能凭支援标签穿墙或向隐藏玩家开火。

全远程搜索也采用检查与掩护的组合；有可行几何时从不同方向观察可能暴露的区域。人数与入口关系由现场决定，不规定每次必须一人、两人或全员一起行动。

### 5.2 入口前准备、入口后检查

沿用现有转角观察顺序：接近拐点时看近侧可能藏人的位置，到达后再转向后续藏身区。近战需要检查与接近空间，远程需要有效射界，不能把所有人停到同一种远程射击站点。

当一个检查方案明确依赖某名远程提供掩护时，检查者可以先到准备点；在进入对应暴露段前核对掩护者实际到位、朝向/观察、弹药和身体状态。普通档按具体关联协调，强档在此基础上保留关键入口参与者的同步；掩护者不被错误加入要求其一起突入的屏障。

等待必须有期限和恢复动作。掩护迟迟不到、换弹、遮挡、受压或减员时，重新选掩护位、换人、改变入口或缩短本次检查段；没有可用掩护时允许重新评估独立短段检查。不能因为旧关系无限站住，也不能超时后仍宣称已经受到掩护。

### 5.3 不空守、不扎堆

同一入口空间不足时减少当前检查人数，其他成员尝试另一侧或更远的可用观察位。掩护位置不能挡住检查者离开路线；相互等待关系在完整方案验证时排除。

检查者完成、换入口或转为交战后，旧掩护责任随之结束或更新。看不到任何负责区域的成员需要调整位置或接受其他有用职责。真实转身、视野和遮挡仍是面积观察的依据，预约和“站岗”标签不算已经搜索。

## 6. 从搜索转入交战及突袭

突袭是一段有条件的共同执行过程，复用现有接敌/侧翼、搜索和支援执行器。

| 阶段 | 近战或机动成员 | 掩护成员 | 结束或变更条件 |
| --- | --- | --- | --- |
| 接近准备 | 前往可达的入口或侧向路线，保留正确观察方向。 | 移动到能够观察责任区域的射位。 | 必要成员真实就绪，或原支援方案失效。 |
| 检查/暴露 | 检查近处藏身区；只有合法信息支持时继续接近。 | 观察相应区域，个人重新目击后才实际开火。 | 重新目击、观察完成、受阻或超时。 |
| 接敌推进 | 以可攻击位置为终点，按已有能力使用奔跑和绕侧。 | 从后侧方保留火力，适时调整枪线。 | 真实进入攻击范围，或路线/支援条件改变。 |
| 接替/恢复 | 保留有效进度，换入口、短暂停留或接受新的接近任务。 | 换弹/受压时由有资格队友接替；无接替则明确失效。 | 新的完整方案被协调器提交。 |

一名成员重新目击后，协调器及时更新队级阶段。近战可根据共享的合法位置接近，但实际挥击仍要求本人视野和真实命中几何；不能为了走完旧检查路线错过已经确认的目标。若再次失视，调查最后位置及其遮挡，不继续追踪隐藏玩家。

合理使用奔跑，仍尊重本场训练、移动能力、身体占用和临近拐点/终点的减速。没有空间的正面通道不强行叫作侧翼；没有有效火力时也不把冲入标成“受掩护突袭”。

## 7. 关联、失效与信息边界

支援关系需要包含参与任务身份、检查/接近对象、责任区域、当前阶段和等待期限；以同一组当前任务为准。实际就绪每次由当前位置、视野、身体与装备状态复核，预测射位可用不能替代当前火力可用。

任务替换、死亡、离区、换队、复位或关联检查完成时清理对应依赖。旧反馈不能重新激活关系；短暂点射停顿不自动取消一条仍有用的掩护任务，长时间无视野、枪线失效及换弹则必须影响当前推进决策。

所有新规划只读取冻结能力、合法情报、公共地图以及当前成员状态。原 hint 采样权限不扩大；不能为了判断“这边能不能偷袭”读取隐藏玩家位置、未来行为或未观测的换弹状态。

## 8. 验证方案

先确认夹具在当前地面和导航内，兵种/装备装配正确，真实目击成立，再检查以下行为。测试不以固定兵种比例作为功能要求，不注入任务、接受、就绪、观察完成或开火结果。

| 情形 | 必须取得的实际证据 |
| --- | --- |
| 全远程开阔交战 | 有可用侧向射位时形成不同方向的真实射击；机动期间保留队友火力。窄口不可行对照不要求强行展开。 |
| 混编接近 | 近战实际缩短距离并命中；同期远程从后方或后侧方实际射击；核对身体与枪线，不能只统计岗位名称。 |
| 搜索检查与掩护 | 检查者真正检查藏身区；关联远程实际到位、朝向正确并观察对应区域；等待期间不伪造就绪。 |
| 转角重新目击 | 从检查转为接近攻击，保留原转角朝向要求；远程继续或恢复有效火力。 |
| 范围外停步 | 玩家小幅后退、贴墙或转角后，近战及时调整并重新命中；明确区分正常冷却、转向和路线失败。 |
| 掩护失效 | 换弹、挡枪、受压或支援者死亡后，依赖被更新，有接替或新的可执行方案，不能无限等待或全队一起失去行动。 |
| 信息与能力 | 隐藏移动不直接更新攻击点，未训练职责不解锁，近战不会领远程支援/换弹任务。 |
| 普通/强配合及减员 | 同一套配合原则适用，强档保留真实入口同步；单人继续指挥并执行。 |

自动运行还需保留现有碰撞、个人开火权限、原地图重新接敌8秒以及整队 AI/区域 P99 <16毫秒、峰值 <50毫秒的适用门槛。记录关键时段的真实位置、朝向、射击/命中和等待原因，并用独立图形实例核对观感。失败时先核实夹具与现场几何，不修改用户场景来迁就测试，不把失败样本静默移出统计。

## 9. 实施顺序与当前交付范围

设计确认后，再落实文件接口和实施计划。建议按以下顺序独立验收：

1. 修正并建立有效的近战停点/小位移复现；补齐攻击岗位生成和失效反馈。
2. 加入全远程交叉射界与混编后侧方支援的联合评价，验证真实同期火力和接近。
3. 补足搜索掩护关联、入口前就绪、搜索转交战及有限恢复，验证换弹/受阻/减员。
4. 汇总独立实机验证，维护接口说明、测试登记和待办，按已验证阶段提交并正常推送。

当前只交付本设计草案及待办索引。生产代码、保存场景、训练、武器、导航资源均未因本方案修改；此前未完成的诊断不构成上述阶段已经完成。

## 10. 新对话交接（2026-10-24）

### 10.1 接续状态

- 工作目录 `E:\godot`，Godot 工程 `E:\godot\movement_demo`，PowerShell；Godot 程序为 `E:\Godot\Godot_v4.7.2-stable_win64_console.exe`。
- 分支 `main`，远端 `origin` 为 `https://github.com/Baidy123/DSR_function_demo.git`。设计草案及 TODO 索引已在 `f4e9146` 提交并推送；此前生产修复 `d190256` 是转角前后观察切换，`5af8265` 是搜索分工及机动速度。
- **本轮远近配合生产实现尚未开始。** 上文两个新模块尚不存在，不能在新对话中当作现有接口调用。用户已经明确的行为方向见第1节；本文其余设计仍待审阅。用户本次要求把代码和状态写入文档以便换对话。
- 两次后台诊断进程都已结束，不存在需要继续等待的测试进程。没有完成有效的混编专项验收，也没有修正并重跑下方无效夹具。
- 当前没有正式的 `tests/enemy/squad_mixed_cooperation_test.gd`；诊断初稿已移到 Git 忽略的日志目录。本节末尾保存其完整原文，防止换机器或缺少本地日志时丢失上下文。
- 文档链接/草案状态、`git diff --check`、`python movement_demo/tests/run_regressions.py --check` 已检查通过。这些仅是文档与登记检查，不是配合行为通过的证据。

先阅读根目录 `AGENTS.md`、`README.md`、`docs/project-layout.md`、`docs/enemy-ai.md`、`docs/enemy-tests.md`。保留用户当前本地工程；不执行 pull，不合并/变基远端，不覆盖已有修改。独立完成并验证的阶段按项目规则提交、普通推送。需要观察用户正在运行的游戏时只读采样；独立测试使用独立实例，不重启或移动用户现场来适配夹具。

### 10.2 必须保留的工作区改动

交接时已有约50项用户或此前任务的未提交修改，不能当成本轮成果一起提交。新对话先重新执行 `git status --short`，以当时实际状态为准。

重点包括 `.gitignore`、`docs/superpowers/specs/2026-10-13-squad-node-coordinator-design.md`、大量 `movement_demo/addons/godot_ai/` 文件、`project.godot`、`scenes/arena.tscn`、`resources/enemy/cooperation/coordinated.tres`、`resources/enemy/training/arena.tres`、`resources/weapons/enemy_test_melee.tres`、导入元数据，以及下列脚本：

- `scripts/enemy/actions/enemy_attack_position_action.gd`
- `scripts/enemy/actions/enemy_melee_cover_action.gd`
- `scripts/enemy/actions/enemy_route_motion.gd`
- `scripts/enemy/services/enemy_perception.gd`
- 多份 `tests/enemy/` 个人行为和预算测试。

保存场景的兵种和武器也已被用户修改，不能假设仍是三名远程。检查实际 UnitType、Training、Weapon 组合及运行时能力档案；诊断所需调整只作用于独立场景实例，不保存回用户资源。不需要为了本任务建立固定兵种比例矩阵。

### 10.3 相关生产代码入口

下表行号是本次交接快照，仅用于定位；后续以函数名搜索为准。路径相对 `movement_demo/`。

| 文件与入口 | 需要理解的内容 |
| --- | --- |
| `scripts/enemy/services/squad_coordination.gd:260` `_update_objective()` | 合法目击、接敌/搜索转换、约1米位置更新阈值；未变化时仅更新瞄准点。 |
| 同文件 `:324` `_plan()`、`:458` `_member_work()` | 重排条件、预算内逐成员候选准备、任务保留和整队提交。 |
| 同文件 `:513` `_contact_role()` | 默认岗位及队友换弹/避险时的支援选择。 |
| 同文件 `:697` `motion_permission()`、`:772` `support_demand()` | 交通、关键入口等待、赶路许可，以及真实队友需求下的支援点射。 |
| `scripts/enemy/services/enemy_search_formation.gd:10` `sites()`、`:178` `_candidate()` | 搜索入口和远侧掩护、通用接敌环形候选、近战点位收缩、路线/枪线验证。 |
| `scripts/enemy/services/enemy_team_planner.gd:58` `_team_cost()`、`:92` `_eligible()` | 完整组合代价、能力资格、同入口排重、身体与最终枪线冲突。 |
| `scripts/enemy/services/squad_contract.gd` | 任务身份、步骤字段、冻结能力默认模板，单人仍归协调器。 |
| `scripts/enemy/actions/enemy_action.gd:229` `execute_command()` | 共用近战请求、实际路线游标、转角前后关注点、机动奔跑与身体占用。 |
| `scripts/enemy/actions/enemy_melee_action.gd:45` `command_roles()` | 指挥模式提供 engage/guard/move；个人 `tick()` 不是指挥模式的接近执行入口。 |
| `scripts/enemy/actions/enemy_cooperation_action.gd` | 训练允许的 flank 执行器；远程提交射击，近战仍走共用近战请求。 |
| `scripts/enemy/services/enemy_melee_controller.gd:35` `can_request()` | 本人视野、身体能力和真实攻击几何；冷却不能被当作路线失效。 |
| `scripts/enemy/enemy_actor.gd:590` `melee_target_reachable()` | 距离、高差、角度和真实射线命中；`melee_struck` 的非空目标才能证明命中。 |
| `scripts/enemy/services/enemy_melee_approach.gd` | 原个人近战的路径、导航边缘停靠与距离估计，可参考几何；不能据此重新启用个人选优。 |
| `scripts/enemy/services/enemy_context.gd`、`scripts/enemy/enemy_ai.gd` | 能力快照、运行时状态、命令验证/执行分流及实际动作装配。 |

当前关键片段如下，**这是待修改的现状，不能直接当作新设计实现**：

```gdscript
# squad_coordination.gd::_update_objective()
if phase == &"contact" and not newest.is_empty():
	changed = changed or _objective.get("position", Vector3.INF).distance_to(newest.position) > 1.0
if phase == &"search" and not newest.is_empty():
	changed = changed or float(newest.captured_at) > float(_objective.get("captured_at", -INF)) + 0.01
if not changed:
	if phase == &"contact" and not newest.is_empty():
		_objective.aim_position = newest.get("aim_position", Vector3.INF)
	return

# enemy_search_formation.gd::_candidate() 的非枪械接敌分支
var away: Vector3 = (point - objective.position).normalized()
point = objective.position + away * maxf(0.5, float(profile.weapon.get("melee_range", 1.3)) * 0.8)
```

方向上的改进是验证“当前近战岗位是否仍可攻击”，而非直接把全队目击位移阈值调小、每帧重排所有人。双方协同还需联合判断后侧方射界与接近通道，不能只修上面两行就宣称完成远近配合。

### 10.4 日志与运行命令

| 本地路径（相对 `movement_demo/`） | 结果及限制 |
| --- | --- |
| `logs/mixed_cooperation_level1_20261024.log` | 原 `squad_command_runtime_test.gd --level=1 --mixed --search`，退出码1、27/29。两个失败是掩体观察断言；当前场景装配影响夹具，不能当作近战停步的独立证明。 |
| `logs/mixed_cooperation_before_20261024.log` | 新诊断初稿，退出码1、6/11，但成员从错误出生点下落，**整组行为与性能结果无效**。例如120帧时 y 已约-22.8，所谓近战小步后退前距离达到约504米。 |
| `logs/mixed_cooperation_20261024/squad_mixed_cooperation_probe.gd` | 下方代码的本地副本。仅加过无效诊断说明，错误出生点及后续夹具逻辑尚未修正。 |

原诊断初稿运行时位于 `tests/enemy/squad_mixed_cooperation_test.gd`，此路径现已移除。修正夹具后可从仓库根目录使用下列入口；**移动后的路径尚未重新运行验证，直接运行当前原文仍会复现夹具错误**：

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path movement_demo --script res://logs/mixed_cooperation_20261024/squad_mixed_cooperation_probe.gd -- --level=1 *> movement_demo/logs/mixed_cooperation_probe_next.log
```

该脚本继承 `res://tests/enemy/squad_command_runtime_test.gd`，依赖其 `SceneTree` 初始化入口、成员变量、`check()` 与 `_trace()`；不能脱离当前工程当作独立 Godot 项目运行。原父脚本及 `squad_command_contract_test.gd` 仍保留在正式测试目录。

PowerShell `*>` 产生的本轮原始日志为 UTF-16；可用 `Get-Content` 读取，Python 读取时先确认编码。日志和初稿均不提交。正式化测试时再移到 `tests/enemy/` 并登记 `run_enemy_regressions.py`，不能留下未登记的正式 `.gd` 文件。

### 10.5 下一步应先处理什么

1. 接受用户在新对话中的最新指示，核对本文设计审阅状态；不要把已写草案或已提交文档当作行为已实现。
2. 修复诊断起点：从当前场景的真实地面/导航选择站位，并在开始接敌断言前确认角色站稳、没有掉出地板、武器/动作资格正确、成员已接受真实任务。
3. 小幅后退用例必须先证明同一近战成员已经命中过、站点有效，再让玩家移动小于1米并检查重新命中；若前提失败应明确报夹具/前置失败，不能继续把后续结果当成卡住复现。
4. 搜索用例须先核实合法最后目击和实际遮挡，再检查掩护到位及观察。减员后的新目标位置也要先验证可达性；记录真实命中，不仅是挥击次数。
5. 形成有效的失败轨迹后，在用户认可的设计范围内实施，并用实际同期射击、命中、视野、等待与恢复验证。不要先改生产代码来迁就下方失效夹具。

### 10.6 诊断初稿完整代码（已知无效，待修正）

以下代码为本地诊断副本的完整快照，保留错误以便定位原始过程，不属于生产实现或已通过的测试。

```gdscript
extends "res://tests/enemy/squad_command_runtime_test.gd"

## UNVALIDATED DIAGNOSTIC DRAFT: initial z=-7 starts are outside the saved
## floor. The 2026-10-24 run is invalid and is not a regression result.
## Kept only for traceability while the cooperation design is reviewed.
var melee_members: Array = []
var shooters: Array = []
var hits := {}
var costs: Array[int] = []
var clearance := INF
var ownership := true

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): level = int(arg.trim_prefix("--level="))
	seed(20261024)
	await _setup_mixed()
	await _contact_cooperation()
	await _small_retreat()
	await _dispose()
	await _setup_mixed()
	await _search_cooperation()
	check(ownership, "Mixed members retain squad authority and installed weapon-qualified roles")
	check(clearance >= 0.64, "Cooperating bodies preserve physical collision clearance")
	costs.sort()
	check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Mixed cooperation preserves full-frame P99 <16ms / maximum <50ms")
	print("MIXED METRICS clearance=", clearance, " p99_usec=", costs[int(costs.size() * 0.99)], " peak_usec=", costs[-1])
	await _dispose()
	print("SQUAD MIXED COOPERATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _setup_mixed() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	var squad = scene.get_node("Arena/Squad")
	squad.profile = squad.profile.duplicate(true)
	squad.profile.level = level
	actors = scene.get_node("Arena").find_children("*", "CharacterBody3D", true, false).filter(func(actor): return actor.has_node("AI"))
	melee_members.clear()
	shooters.clear()
	hits.clear()
	for index in actors.size():
		var actor = actors[index]
		var close := index > 0
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/%s.tres" % ("melee" if close else "ranged"))
		actor.weapon = load("res://resources/weapons/enemy_test_%s.tres" % ("melee" if close else "pistol")).duplicate(true)
		var training = load("res://resources/enemy/training/arena.tres").duplicate(true)
		training.selected_tactics.clear()
		training.selected_tactics.append(&"cooperate" if close else &"suppression")
		training.search.tracking_cheat_enabled = false
		actor.get_node("Training").profile = training
		if close: melee_members.append(actor)
		else: shooters.append(actor)
		hits[actor.get_instance_id()] = 0
		actor.melee_struck.connect(func(target, _settings, _direction):
			if target == player: hits[actor.get_instance_id()] += 1)
	root.add_child(scene)
	current_scene = scene
	arena = scene.get_node("Arena")
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get("combat").set_physics_process(false)
	player.get("health").debug_invincible = true
	player.global_position = arena.to_global(Vector3(0, 0, -3))
	var starts := [Vector3(-1, 0, -7), Vector3(3, 0, -7), Vector3(5, 0, -4)]
	for index in actors.size():
		actors[index].global_position = arena.to_global(starts[index])
		actors[index].look_at(player.global_position)
	for frame in 10: await physics_frame

func _dispose() -> void:
	scene.queue_free()
	await physics_frame

func _sample() -> void:
	var total: int = arena.cooperation.last_advance_usec
	for index in actors.size():
		var actor = actors[index]
		if actor.is_dead: continue
		var ai = actor.get_node("AI")
		var task: Dictionary = ai.context.coordination_assignment()
		ownership = ownership and not task.is_empty() and ai.utility_decision_count == 0
		ownership = ownership and ai.actions.has(task.get("action", &""))
		if not actor.can_use_firearms(): ownership = ownership and not task.get("role") in [&"support", &"reload"]
		for cost in ai.frame_costs.values(): total += int(cost)
		for other in actors.slice(index + 1):
			if not other.is_dead: clearance = minf(clearance, actor.global_position.distance_to(other.global_position))
	costs.append(total)

func _contact_cooperation() -> void:
	var concurrent_shots := 0
	var pressure_shots := 0
	var previous: int = shooters[0].shot_count
	for frame in 600:
		await physics_frame
		_sample()
		var approaching: bool = melee_members.any(func(actor): return actor.velocity.length() > 0.2 and actor.global_position.distance_to(player.global_position) > actor.weapon.melee_range)
		if shooters[0].shot_count > previous and approaching:
			concurrent_shots += shooters[0].shot_count - previous
			if shooters[0].get_node("AI").context.command_support_pressure() > 0.0: pressure_shots += 1
		previous = shooters[0].shot_count
		if frame % 120 == 0: print("MIXED CONTACT ", frame, " ", JSON.stringify(actors.map(_trace)), " hits=", hits)
	check(melee_members.all(func(actor): return hits[actor.get_instance_id()] > 0), "Each melee member actually reaches and hits the player")
	check(concurrent_shots > 0 and pressure_shots > 0, "Ranged fire actually supports a simultaneously advancing melee teammate")
	print("MIXED FIRE concurrent=", concurrent_shots, " pressure=", pressure_shots, " hits=", hits)

func _small_retreat() -> void:
	var actor = melee_members[0]
	var start_hits: int = hits[actor.get_instance_id()]
	var away: Vector3 = player.global_position - actor.global_position
	away.y = 0.0
	var before: Vector3 = player.global_position
	player.global_position += away.normalized() * 0.7
	var recovered := -1
	var initial_distance: float = actor.global_position.distance_to(player.global_position)
	for frame in 240:
		await physics_frame
		_sample()
		if hits[actor.get_instance_id()] > start_hits and recovered < 0: recovered = frame
	check(initial_distance > actor.weapon.melee_range and before.distance_to(player.global_position) < 1.0, "A real sub-metre player retreat invalidates the previous melee attack distance")
	check(recovered >= 0 and recovered <= 180, "The stranded melee member adjusts and actually hits again within three seconds")
	print("MIXED RETREAT distance=", initial_distance, " recovered=", recovered, " ", JSON.stringify(actors.map(_trace)))

func _search_cooperation() -> void:
	for frame in 40: await physics_frame
	check(actors.any(func(actor): return actor.get_node("AI").context.sees_player), "Mixed search starts from real personal contact")
	var screen := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 3.0, 8.0)
	collision.shape = shape
	screen.add_child(collision)
	arena.add_child(screen)
	screen.global_position = arena.to_global(Vector3(-7.0, 1.5, 1.5))
	# Establish a legal last sight next to the saved tall wall, then hide behind
	# it and the second screen. No search clue, readiness or task is injected.
	player.global_position = arena.to_global(Vector3(-2.0, 0, 0.5))
	for frame in 30: await physics_frame
	player.global_position = arena.to_global(Vector3(-7.6, 0, 1.5))
	var paired := 0
	var watching := 0
	var waiting := 0
	var blind_shots := 0
	var previous: int = shooters[0].shot_count
	for frame in 720:
		await physics_frame
		_sample()
		var shooter = shooters[0]
		var ctx = shooter.get_node("AI").context
		var watch: Dictionary = ctx.coordination_assignment()
		if not ctx.sees_player and shooter.shot_count > previous: blind_shots += shooter.shot_count - previous
		previous = shooter.shot_count
		var inspectors: Array = melee_members.filter(func(actor):
			var task: Dictionary = actor.get_node("AI").context.coordination_assignment()
			return task.get("role") == &"search" and task.get("sync_key", "!") == watch.get("overwatch_for", ""))
		if not inspectors.is_empty():
			paired += 1
			if shooter.global_position.distance_to(watch.position) < 0.18 and preload("res://scripts/enemy/services/enemy_visual_observation.gd").visible(ctx, watch.look_position): watching += 1
		for actor in melee_members:
			if actor.get_node("AI").context.coordination_assignment().get("reason") == &"support_preparing": waiting += 1
		if frame % 180 == 0: print("MIXED SEARCH ", frame, " ", JSON.stringify(actors.map(_trace)))
	check(paired > 0 and watching > 0, "Melee investigation receives ranged overwatch that physically arrives and observes its hiding area")
	check(blind_shots == 0, "Search support never fires without personal sight")
	print("MIXED SEARCH PAIR assigned=", paired, " actual_watch=", watching, " waits=", waiting)
	# The supporting member is lost while the player emerges. Surviving melee
	# members must abandon orphaned support dependencies and actually engage.
	shooters[0].receive_hit(shooters[0].health + 1.0)
	var before_hits := hits.duplicate()
	player.global_position = arena.to_global(Vector3(-4.8, 0, -3.5))
	var stale := false
	for frame in 600:
		await physics_frame
		_sample()
		if frame > 120:
			for actor in melee_members:
				var task: Dictionary = actor.get_node("AI").context.coordination_assignment()
				stale = stale or task.get("waiting_for", []).has(shooters[0].get_instance_id())
	check(not stale and melee_members.all(func(actor): return hits[actor.get_instance_id()] > before_hits[actor.get_instance_id()]), "Loss of the ranged supporter leaves no stale wait and both melee survivors actually hit")
```

## 11. 个人训练能力的接入审计（2026-10-24）

用户后续追问协调器是否读取并使用个人训练。原设计已经要求按实际装配能力分工，但“读取资源/冻结参数”“为动作提供团队岗位”“让该战术完整执行”是三个需要分别核实的环节。不能因为档案里保存了动作名称和参数，就宣称所有个人训练都已在指挥模式生效。

当前已核实的链路：`EnemyActionLibrary.resolve()` 消费兵种能力和 `Training.selected_tactics`，AI 装配成功的动作通过 `freeze_command_capability()` 发布岗位与参数，协调器使用成员档案进行资格约束和候选准备。抗压阈值、成员搜索移动/停留、掩体执行和支援资格都有实际消费者；小队 `cooperation` 参数按原设计覆盖个人同名模块。个人 Utility 评分仅在0级/无绑定分支运行，不应将其关闭误认为训练完全未读取。

本轮只修复检查器资源类型并记录审计结果，未修改其他对话的战术执行代码。以下分别记录接入缺口与同步进展：

- 攻击占位动作没有声明团队执行岗位，不能靠装配结果证明其个人占位逻辑被协调器使用。
- 近战掩体接近继承基础掩体命令入口，不能把基础躲藏的接入算作整个近战掩体接近、出口选择、恢复观察和后续接敌已实现。
- 近战短程突进的命令入口、冻结参数和运行状态已由另一轮维护在 `6c1d2f4` 提交；对应验证见敌人测试的“团队突进、连续追击与真实支援点射”，本次检查器专项不重复认领该行为验收。
- 队级搜索公共参数的成员来源、各成员动作参数的优先级应明确记录；不能把首个可搜索成员的队级配置说成每名成员都按各自配置独立调度。

后续设计/实施要求逐项建立“训练资格 → 生效参数 → 团队候选 → 命令执行 → 实际结果”的对应表。角色缺失时明确标注未接入，不静默以同名岗位代替战术；训练未解锁时不得由小队等级代为授予。验证应比较启用/禁用训练以及参数变化后的真实执行，保持本场能力冻结、重载生效、原身体/火控条件和唯一协调器所有权。

这份审计补充不把上述未完成能力列为已实现；准确操作说明与当前消费边界见[敌人 AI](../../enemy-ai.md#个人训练如何参与团队决策)。
