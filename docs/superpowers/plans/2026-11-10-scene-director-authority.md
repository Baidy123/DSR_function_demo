# SceneDirector 统一场景调度 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 用户已选择 Native，由当前执行者连续实施，六阶段完成后进行一次独立整体审阅。

**Goal:** 对话、商店、传送、脚本演出、镜头、波次及出口启用统一经过本场 SceneDirector，原组件继续执行业务。

**Architecture:** 在现有导演核心内加入请求身份与控制权调度；交互、脚本和加载使用小型执行适配，SceneFlowRunner 复用同一入口。保留原场景入口兼容脚本与部署，按请求真正取消持续工作，并把跨关状态准备与加载成功提交分开。

**Tech Stack:** Godot 4.7.2、GDScript、现有 SceneRules／SceneEvent、ScenePauseCoordinator、Python 回归运行器。

**Spec:** [已批准设计](../specs/2026-11-10-scene-director-authority-design.md)。用户已批准书面计划并授权实施；六阶段实现与定向验收已完成，最终审阅状态见下方记录。

## Global Constraints

- “以当前本地工程为基线，保留节点路径、资源引用、脚本 UID、五关部署与用户保存参数；敌人血量保持本地配置。”
- “伤害、库存、扣款、任务奖励等结算仍属于原业务模块。”
- “普通等待与后台逻辑仍可并行。”
- “正式场景明确装配一个 SceneDirector，不增加跨场景 AutoLoad 导演。”
- “不重排地图、不迁移部署层、不替换原玩家相机跟随框架。”
- “只提交本任务修改，不 pull 或带入其他远端内容。”
- 实施前阅读 README、项目结构及各任务专项；波次／区域修改同时遵守 enemy-ai.md、enemy-tests.md。已有失败、断言和时间／性能门槛保持。
- 沿用当前空商店“暂无商品”且不暂停的行为；装置一次付清 500、旗标拥有、医疗包资源入库及检查点退款保持。

下述类名、签名、排队规则与分文件安排是本计划的实施选择，区别于用户直接指定的玩法要求。相邻阶段可共同修改同一文件，每阶段交付时同步现行教程及职责说明，明确尚未接管的范围。

## Review Focus

1. 对话第一句尚在异步加载时死亡／来源离场，也要结束请求，不能只等待 dialogue_ended；任务2覆盖。
2. 同步完成后才拿到请求的调用者仍能读取终态，重复或迟到信号不重入；任务1、3覆盖。
3. 复合交互中“先发物品再对话”不能自锁，忙碌拒绝不能提前发物品或记 one_shot；任务4覆盖。
4. 返程状态准备不能提前触发任务金额；真实目标场景 _ready 必须能读到成功提交的状态；任务4覆盖。
5. 两个区域共享一名玩家，区域复位只取消本区域；一个出生点受阻不拖住另一波；任务5、6覆盖。

## 文件职责与统一接口

以下路径以 `movement_demo/` 为根。新增 .gd 需生成并提交配套 .uid；保留现有 UID。新增测试同步登记 tests/run_regressions.py，不建立第二套运行器。

| 新文件 | 单一职责 |
| --- | --- |
| scripts/systems/scene_request.gd | SceneRequest（RefCounted）：身份、弱节点引用、状态与一次性结果 |
| scripts/systems/scene_request_scheduler.gd | 导演内部调度：排队、去重、控制占用与取消；不是公开调度入口 |
| scripts/systems/scene_interaction_executor.gd | NPC 转身、对话／商店生命周期及交互效果顺序适配 |
| scripts/systems/scene_script_executor.gd | 普通方法与可取消脚本提供者的适配 |
| scripts/systems/scene_transition_executor.gd | 加载请求、准备数据、调用 SceneTransition、提交／失败与重试 |

导演新增公开入口：

```gdscript
static func for_node(node: Node) -> Node
func request_action(kind: StringName, context: Dictionary = {}) -> SceneRequest
func cancel_request(id: int, reason: StringName = &"cancelled") -> void
```

`for_node` 按所属场景根的弱引用注册查找，不使用全树第一个 group 成员；重复注册报错，缺失时不临时创建。现有 configure(host, bindings) 保留，允许夹具显式传入 scene_root；正式场景从当前所属根绑定。初始化尚未完成的入口拒绝请求，不默默记录为成功。

`context` 固定字段：`source: Node`、`player: Node3D`、`target: Node`、`parameters: Dictionary`、`scope: int`（沿用 SCENE=0／REGION=1）、`scope_owner: Node`、`origin: StringName`（interaction／rule／system）、`dedupe_key: StringName`、`parent_id: int`（默认0）。必要字段按 kind 验证；节点字段转弱引用，嵌套参数不得藏入强节点引用。父请求只允许同一导演、代次及有效执行链的内部适配继承，外部不能靠填写 parent_id 越过忙碌检查。

kind 使用 `dialogue`、`shop`、`interact`、`script`、`presentation`、`guide`、`wave`、`completion`、`transition`。关闭、跳过和死亡按钮由现有公开方法转成导演对相应请求的结束／取消命令，不新开与原请求竞争的前台任务。所有保留的公开入口只转发请求，内部执行使用单独的授权方法，不能从适配器再次调用转发入口造成递归。

SceneRequest 提供只读 `id: int`、`generation: int`、`status: StringName`、`reason: StringName`，`finished(request: SceneRequest)` 信号，以及：

```gdscript
func is_terminal() -> bool
func is_current() -> bool
func has_started() -> bool
func get_result() -> Dictionary
func wait_result() -> Dictionary
func complete(result: Dictionary = {}) -> void
func fail(message: String) -> void
```

状态为 queued／running／completed／failed／cancelled／rejected；wait_result 先查终态，再等待，处理同步结束。complete／fail 仅给已绑定的执行者使用，终态后无效果。导演取消时先失效身份，再调用执行者取消，清理后只报告一次 finished。

普通交互忙碌即拒绝；规则演出进入仅存于当前场景生命周期的 FIFO，重复 dedupe_key 返回原活动请求。每帧先选候选、后执行，避免信号回调递归开演。前台占用与暂停分别记录，计时／波次等后台请求独立推进；优先级为死亡、已获准加载、当前前台、等待普通演出。局部门动画的已注册适配可声明后台执行；受击、死亡消散等原业务表现继续由原组件完成，不逐帧上交导演。

## 验证命令约定

在仓库根目录执行。每阶段用下面模板，将 names 换成该阶段明确列出的专项；新建时间戳日志目录，结果必须同时满足退出0和 output_errors 为空。

```powershell
@'
from datetime import datetime
from pathlib import Path
import sys
sys.path.insert(0, str(Path('movement_demo/tests').resolve()))
from regression_runner import run_tests
project = Path('movement_demo').resolve()
names = ['scene_request_test']
logs = project / 'logs' / 'director-authority' / datetime.now().strftime('%Y%m%d_%H%M%S_%f')
raise SystemExit(run_tests('E:/Godot/Godot_v4.7.2-stable_win64_console.exe', project, project / 'tests', names, logs, 'director-authority'))
'@ | python -
python movement_demo/tests/run_regressions.py --check
```

敌人目录的三个波次专项使用已有选择入口：

```powershell
python movement_demo/tests/enemy/run_enemy_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe enemy_wave_test enemy_wave_search_test enemy_wave_events_test
```

提交步骤共用：审查阶段 diff 与状态，明确列出本阶段文件并暂存，git diff --cached --check，普通 commit／push origin main，再核对远端 SHA。不把提交前已有整文件改动顺带暂存；冲突文件按本任务改动单独构建暂存内容，核对索引和工作区两个版本。日志、导入缓存和本地撤回误同步的变更不上传。

## Task 1：请求生命周期与明确的场景入口

**Files:** 新建 scene_request.gd、scene_request_scheduler.gd；修改 scripts/systems/scene_director.gd、scripts/world/enemy_wave_controller.gd、scenes/main.tscn；新建 tests/scene_request_test.gd；修改 tests/scene_director_test.gd、tests/run_regressions.py、docs/gameplay/SCENE_DIRECTOR.md、docs/project-layout.md（docs 路径在仓库根）。

**Interfaces:** 产出上述 SceneRequest、for_node／request_action／cancel_request。scheduler 为 RefCounted，`_init(director: Node)`、`submit(request: SceneRequest) -> void`、`advance(delta: float) -> void`、`cancel_all(reason: StringName) -> void`、`cancel_scope(owner: Node, reason: StringName) -> void`、`snapshot() -> Dictionary`，只由导演持有。请求分派先接入现有 presentation／guide／completion，其他 kind 在对应阶段实现前明确拒绝。

- [x] **1. 写失败测试。** scene_request_test 的 test_synchronous_result／test_cancel_reentrancy／test_duplicate_and_generation／test_scene_local_lookup 分别断言：同步 complete 后 `status == &"completed"` 且 await wait_result 不挂起；取消过程中执行者再次 complete 仍只 finished 一次且 status cancelled；重复来源不二次开始，旧代次无效；两个根的查找互不串场，重复导演被拒绝，准备中请求 rejected。测试注册后首先证明失败在缺失接口。
- [x] **2. 跑红测试。** 用模板运行 scene_request_test，预期缺少 SceneRequest／入口而失败；记录输出，不把解析失败视为行为测试完成。
- [x] **3. 实现请求与调度。** 在上述签名下实现弱引用与终态读取，死亡／加载先关请求资格再取消；完成清理回调不能依赖 can_run_actions 或 tree.paused 为 false。debug_snapshot 添加 requests／foreground／controls，保留旧键。
- [x] **4. 装配酒馆入口。** main 增加 SceneDirector 预制实例，清空 guide_path／result_view_path，设置 complete_when_all_waves_cleared=false、auto_start_on_enter=false；不改变原节点位置和玩家配置。无 Wave 时跳过区域模板依赖，绑定 Player/Health；五关现有入口仍只创建一个内部核心。区域旧回退暂留，到任务6移除，并在文档标明迁移范围。
- [x] **5. 验证交付。** names：scene_request_test、scene_director_test、scene_event_node_test、campaign_flow_test、shop_flow_test；新入口不改变无 Wave 不自动完成和商店行为。清单检查必须 Catalog OK；本地已知失败独立报告，不修改玩法参数换绿。
- [x] **6. 同步文档并提交推送。** 说明新增请求合同和唯一入口，标明其余旁路仍待迁移；提交建议 `feat: add scene director request lifecycle`。

## Task 2：导演接管普通对话与商店

**Files:** 新建 scripts/systems/scene_interaction_executor.gd、tests/scene_interaction_test.gd；修改 scripts/systems/scene_director.gd、scripts/systems/scene_request_scheduler.gd、scripts/systems/scene_pause_coordinator.gd、scripts/world/npc.gd、scripts/world/reward_npc.gd、scripts/ui/dialogue_ui.gd、scripts/shop/shop_controller.gd；修改 tests/dialogue_cache_test.gd、tests/shop_flow_test.gd、tests/run_regressions.py；同步 docs/gameplay/INTERACTION.md、REWARDS.md、SCENE_DIRECTOR.md 与 docs/project-layout.md。

**Interfaces:** 消费任务1入口。执行适配统一 `begin_scene_action(request: SceneRequest) -> void`、`cancel_scene_action(request: SceneRequest, reason: StringName) -> void`。DialogueUI 和 ShopController 实现这两个方法，另加 `scene_action_finished(id: int, result: StringName)`，覆盖尚未显示即结束的情况。旧 open_dialogue(...) -> void、open_shop_for_player(player: Node3D) -> bool、close_shop() -> void 保留为导演请求／结束转发；executor 调用执行方法，不能递归调用转发入口。

- [x] **1. 写失败测试。** test_dialogue_before_camera：启动对话后提交 presentation，断言 queued、关闭对话后只开始一次；test_death_before_first_line：首句 await 期间死亡，断言请求 cancelled、玩家不再受对话控制、迟到行不显示；test_busy_npc：拒绝时 pending_player 为空且没有 face_npc／set_dialogue_active；test_shop_ownership：死亡只留下死亡控制，外部暂停仍保留；test_empty_shop：空目录显示“暂无商品”、tree.paused=false、关闭可结束前台。另测空对话同步结束、UI／来源离树。
- [x] **2. 跑红测试。** names：scene_interaction_test，预期当前直开窗口、早锁玩家或缺少结束回报断言失败。
- [x] **3. 调整控制记账。** 将 Pauses.acquire 扩为 `acquire(owner: Node, reason: StringName, visible_mouse: bool = false, pause_world: bool = true) -> int`，保留默认语义。账本分别统计暂停和鼠标需求；最后一个暂停令牌释放可恢复世界，即使还有非暂停令牌。输入限制由导演持有，结束时不能覆盖死亡造成的失能。覆盖 mixed pause／mouse-only／既有外部 pause，can_advance_presentation 按实际暂停拥有者检查。
- [x] **4. 接管 NPC 与界面。** NPC 的转身和移动限制在导演批准后开始，期间取消也收尾；普通 NPC 与 RewardNPC 不直接打开 UI。商店空目录仍占前台但不冻结世界；有效商品商店沿原规则暂停。购买 purchase(...)、资源拖入、一次扣款与库存保持原业务。RewardNPC 因忙碌被拒绝时消费本次 E，不回落再发对话；缺商店配置时仍可走获准的普通对话。
- [x] **5. 验证交付。** names：scene_interaction_test、scene_request_test、dialogue_cache_test、shop_catalog_test、shop_flow_test、shop_board_test、shop_weapon_test、quest_money_reward_test、scene_director_test；确认 close_shop／dialogue 结束无暂停死锁，同步完成不漏信号。
- [x] **6. 同步文档并提交推送。** 教程给出 NPC／商店请求示例，明确 business 与控制权归属；建议提交 `feat: route dialogue and shop through scene director`。

## Task 3：脚本演出真实取消，规则复用请求入口

**Files:** 新建 scripts/systems/scene_script_executor.gd、tests/scene_script_cancellation_test.gd；修改 scripts/systems/scene_flow_runner.gd、scene_flow_action.gd、scene_director.gd、scene_request_scheduler.gd、presentation_camera.gd、scripts/world/range_door.gd；修改 tests/scene_director_test.gd、scene_event_node_test.gd、run_regressions.py；同步 docs/gameplay/SCENE_DIRECTOR.md、INTERACTION.md、docs/project-layout.md。

**Interfaces:** 消费 SceneRequest 及任务2的 begin_scene_action／cancel_scene_action 合同。SceneFlowAction 在原枚举末尾追加 RUN_SCRIPT（原0～9值不变），target_path 指向实现该合同的节点；参数仍用 arguments。旧 CALL_METHOD 保留即时调用；若配置 completed_trigger，必须新增 `cancel_method: StringName` 指定公开取消方法（无参），或把目标接成 RUN_SCRIPT。完成订阅仍先于开始；RUN_SCRIPT 用 request.complete／fail，无需第二份完成触发器。range_door 实现同一提供者合同，parameters.open: bool 指定方向，动画结束才 complete。

- [x] **1. 写失败测试。** test_timer_and_tween_stop：真实 Timer、Tween 启动后取消，超过原完成时长仍不修改计数；test_late_completion：旧 request.complete 不推进新轮；test_scope_cancel：区域演出取消不动无关 SCENE 规则；test_sync_script：同步完成只推进一步；test_uncancellable_async_rejected：带完成触发器但缺取消合同，在开始前拒绝并定位规则／动作；test_waits_parallel：两条独立等待能各自推进；test_real_door_cancel_and_reverse：原滑门中途死亡确实停 Tween，关门折返由新请求取消旧请求，保留防夹行为且不生成重复动画。
- [x] **2. 跑红测试。** names：scene_script_cancellation_test，确认当前 cancel_all 仅断开信号、持续动作仍执行的行为确实被捕获。
- [x] **3. 实现脚本适配。** begin／cancel 接入同一调度与身份；取消先失效请求，执行者 stop Timer、kill Tween 并在 await 后检查 request.is_current。runner 的每个已启动动作保存请求句柄；_fail、reset_region、cancel_all、release 都通知执行者后清订阅，不能仅 entry.wait.clear。
- [x] **4. 接管资源动作和滑门。** GUIDE、PRESENT_TARGET、CALL_METHOD、RUN_SCRIPT、COMPLETE_SCENE、RESTART、CHANGE_SCENE 均转成同一入口；纯 WAIT／WAIT_SIGNAL／WAIT_WAVE_CLEARED 保留轻量并行等待。等待期间的完成／取消可在暂停中记账，普通计时仍按原规则冻结。滑门按 E、离开自动关闭及折返请求导演，保持原距离与时长；局部门动画不占全场前台，死亡／卸载能取消。现有异步测试提供者接入真实取消合同，保留所有原顺序／同步／参数校验断言。
- [x] **5. 验证交付。** names：scene_script_cancellation_test、scene_request_test、scene_interaction_test、scene_director_test、scene_event_node_test、presentation_camera_test、scene_reinforcement_test；检查新增枚举与检查器字段显示，不改原资源枚举编号。
- [x] **6. 同步文档并提交推送。** 增加可取消 Timer／Tween 提供者的短例子，说明即时调用和持续演出的配置区别；建议提交 `feat: cancel scene script executions through director`。

## Task 4：交互效果与传送事务统一接入

**Files:** 新建 scripts/systems/scene_transition_executor.gd、tests/scene_transition_request_test.gd；修改 scripts/world/interactable.gd、quest_portal.gd、tavern_return_portal.gd、interactions/interaction_context.gd、interaction_effect.gd、show_dialogue_effect.gd、change_scene_effect.gd、call_method_effect.gd；修改 scripts/systems/scene_interaction_executor.gd、scene_director.gd、scene_request_scheduler.gd、scene_transition.gd、game_state.gd；修改 tests/interaction_fixture.gd、interaction_test.gd、quest_portal_test.gd、campaign_flow_test.gd、campaign_checkpoint_test.gd、scene_director_test.gd、run_regressions.py。同步 docs/gameplay/INTERACTION.md、PLAY_GUIDE.md、SCENE_DIRECTOR.md 与 docs/project-layout.md。

**Interfaces:** Interactable.interact(player: Node3D) -> bool 保留，只在请求本次获准并开始时返回 true；新增 `execute_scene_interaction(context: InteractionContext) -> SceneRequest` 供导演适配调用，返回 context.execution 对应的本次请求。InteractionContext 追加 director: Node、execution: SceneRequest；InteractionEffect 追加可等待的 `execute(context: InteractionContext) -> Dictionary`，结果键为 status: StringName（completed／failed／cancelled）、reason: StringName。默认实现只调用原同步业务 apply 并返回同步结果；ShowDialogue／ChangeScene／CallMethod 重写 execute，使用受验证 parent_id 继承控制并等待子请求结果。后三者旧 apply(context) 保留为请求转发，不能直开 UI／加载；无导演的默认上下文也不能绕过授权。

GameState 新增纯准备 `prepare_scene_transition(mode: StringName, player_snapshot: Dictionary = {}, level_number: int = 0) -> Dictionary` 与 `commit_scene_transition(prepared: Dictionary) -> bool`；mode 为 enter_level／return_tavern／retry_level／death_return／plain。prepared 包含唯一事务编号、目标状态、原状态身份，不把可写 GameState 引用交给调用者。快照包含原 capture_campaign_state 内容及 campaign_checkpoint、level_entry_player_state；只处理原商店旗标集合，不动其他旗标。旧 checkpoint API 保留用于业务与兼容调用。

- [x] **1. 写失败测试。** test_busy_interaction_no_effect：被拒绝不发物品、不记 has_interacted、不隐藏、不发 interacted；test_composed_dialogue：同步物品效果一次后可打开子对话，不因自己占用前台而排队死锁；test_portal_rejected：完成级别、money、rewarded_task_ids、pending／entry／checkpoint 均与原值相同；test_failed_load_retry：注入加载失败，不发奖、不消费快照，重试仍原目标；test_target_ready_state：真实最小目标场景 _ready 读到新快照且仅消费一次；test_duplicate_load：快速两次按 E 只提交一次。夹具只放 tests 内并登记，不修改正式目标内容制造失败。
- [x] **2. 跑红测试。** names：scene_transition_request_test，明确捕获现有传送门提前写状态及加载失败残留；保留失败现场日志。
- [x] **3. 接管复合交互。** 先 director 批准再逐项 await effect.execute；parent_id 只由内部执行链赋值，同根子动作共享控制且父动作可等待，每次恢复先检查 context.execution.is_current。effects 顺序保留；已发生业务不由通用取消自动倒退。同步全部成功才发 interacted；含异步效果时在全部成功后发，取消／失败不伪造成功。has_interacted／隐藏在成功时提交，运行中单独防重；interact 返回值只表示本次真正开始，文档同步区分两者。切场成功后原来源已离树，不补发旧节点 interacted 或操作隐藏状态；跨场结果由请求 completed 与 GameState 提交报告，旧场景规则不得被重新激活。异步 ShowDialogue／ChangeScene 的失败不能被默认 apply 当成成功。
- [x] **4. 把传送准备改为纯数据。** QuestPortal／TavernReturnPortal 不在 interact 前写 GameState；准备函数不触发 value_changed／money_changed／任务发奖。引擎调用前最后校验身份和准备数据；返回 OK 后在同一调用栈内完成已验证的数据提交，必须早于目标 _ready，不能此时才执行可失败的业务校验。用真实切场夹具证明。执行器用 RefCounted 承接预期旧场景退出，为当前加载请求及其父交互保留一次终态收尾，其他旧执行均取消；正常退出不能丢弃成功提交或把本次成功标为 cancelled。失败不提交准备数据，重试重建当前数据。若这一时序验证不成立，本阶段不得交付，须回到已批准事务边界修正加载适配。
- [x] **5. 统一所有加载。** director 的死亡重开、回酒馆、规则 CHANGE_SCENE 和门的加载都经执行器，生产加载最终只调用 `await SceneTransition.change_scene(tree, path)`／reload_scene(tree)。保留 scene_loader(path: String, reload: bool) -> Error 注入兼容并支持 await；每次 await 后核对身份，加载期间只允许一个请求。死亡／结果失败保持可用重试 UI，普通门失败归还控制、显示原因并可再交互；不把普通失败留成永久暂停。
- [x] **6. 验证交付。** names：scene_transition_request_test、scene_interaction_test、scene_director_test、campaign_checkpoint_test、campaign_flow_test、campaign_quest_task_test、quest_portal_test、shop_state_test、shop_flow_test、dialogue_cache_test；interaction_test 同时与原基线比较，原已知离场 E 失败单独记录。真实最小目标测试用例与夹具登记 SPECIAL 或专项内嵌，Catalog OK。
- [x] **7. 同步文档并提交推送。** 说明“准备 ≠ 完成”和失败策略，保留原业务 API 语义；建议提交 `feat: coordinate interaction and scene transition transactions`。

## Task 5：波次、镜头与出口服从同一授权

**Files:** 修改 scripts/world/enemy_wave_controller.gd、enemy_wave_runtime.gd、shooting_range.gd、scripts/systems/scene_director.gd、scene_request_scheduler.gd、scene_flow_runner.gd、level_flow.gd、presentation_camera.gd；修改 tests/scene_reinforcement_test.gd、scene_director_test.gd、scene_request_test.gd、enemy/enemy_wave_events_test.gd、enemy/enemy_wave_test.gd、enemy/enemy_wave_search_test.gd、level_flow_test.gd、debug_complete_level_test.gd。同步 docs/gameplay/SCENE_DIRECTOR.md、ENEMY_WAVES.md、docs/project-layout.md、docs/enemy-tests.md。

**Interfaces:** 消费 request_action(wave／presentation／completion)。runtime 增加 `authorize_deployment: Callable`，签名 `(wave: Node) -> bool`，由导演绑定；仅查询当前波次执行许可，不发信号或 await。所有 SEQUENCE／EVENTS／REQUEST 在 ready 阶段先提交同一 wave 请求，最终生成前再校验许可；请求在真实提交后才完成。展示沿既有 wave_committed → 导演回调安排，不能再增加一个重复播放入口；runtime 继续拥有空间、模板、活体与清空状态。旧 request_wave(wave) -> bool、start_encounter() -> void、reset_encounter() -> void 和原信号保持为导演适配入口。

- [x] **1. 写失败测试。** test_all_start_modes_authorized：三个模式失去资格都不能生成；test_spawn_barrier：真实提交成功之后、公开 spawned 回调之前已经取得展示控制，失败出生不播放；test_camera_after_dialogue：对话中记录有效事件，结束后仅一次合法生成／展示；test_independent_blocked_wave：A 占位时 B 可合法提交；test_completion_command：导演获准后才启用原出口，同帧死亡优先；test_two_region_reset：复位 A 不取消 B 的 SCENE 演出或占用。
- [x] **2. 跑红测试。** names：scene_reinforcement_test、scene_request_test；敌人选择入口跑 enemy_wave_events_test，确认检测的是授权／时序缺口。
- [x] **3. 收拢波次与镜头授权。** runtime 保留原每物理步最多提交一波、二次空间检查、成员准备、出生屏障与清空判断；身份与授权检查紧邻提交，不在空间检查和提交之间插入信号／await。事件事实记录不依赖来源仍存活。对话／商店占用时延后需要前台的出场展示，重新验证目标；不提前播放空出生点。
- [x] **4. 接管完成适配。** LevelFlow.show_completion 仅作为当前 completion 请求的执行端，原公开兼容入口转发至导演，内部执行方法避免递归。启用现有 TavernReturnPortal，不创建新出口、不改变清场返酒馆／A 解锁流程；调试通关仍通过正式完成路径。
- [x] **5. 验证交付。** names：scene_reinforcement_test、scene_director_test、scene_request_test、scene_interaction_test、presentation_camera_test、level_flow_test、debug_complete_level_test、campaign_flow_test；另跑全部三个敌人波次专项。核对 Wave／Squad 路径、原血量和训练资源 diff，保持本地原样。
- [x] **6. 同步文档并提交推送。** 描述波次事实与导演授权的界线、出场前台冲突与镜头清理；建议提交 `feat: authorize wave and completion flows through scene director`。

## Task 6：关闭旧回退，验收真实酒馆和五关

**Files:** 修改 scripts/world/shooting_range.gd、scripts/world/enemy_wave_controller.gd；如绑定验证确有需要才最小修改 scenes/world/scene_director.tscn、scenes/world/levels/lvl_1.tscn 至 lvl_5.tscn、scenes/main.tscn；新增 tests/scene_director_authority_test.gd；修改 tests/run_regressions.py 及使用旧隐式导演的对应夹具。同步 README.md、docs/README.md、docs/TODO.md、docs/project-layout.md、docs/testing.md、docs/gameplay/SCENE_DIRECTOR.md、INTERACTION.md、PLAY_GUIDE.md、ENEMY_WAVES.md，以及本计划验收状态。

**Interfaces:** 只消费前五任务接口；撤去 shooting_range._bind_standalone_director 的隐式创建，区域通过 for_node 取得本场导演，缺失时可定位诊断。孤立 Player／区域测试显式配置最小导演，不能在生产代码里留测试回退。

- [x] **1. 写失败测试。** authority_test 实例化真实 Main 和五关，断言每场唯一注册、无 Wave／无引导可运行；多区域共享绑定、reset 不串场。审查正式脚本与静态入口，保证 NPC／effects／portal 无 UI／SceneTree 加载旁路，核心加载只走 SceneTransition；子执行端只接受有效请求。增加 --capture 分支，真实渲染并保存对话→镜头、商店关闭、死亡中断与传送返回的记录。
- [x] **2. 跑红测试。** names：scene_director_authority_test，预期至少旧回退结构检查失败；不能靠改变正式地图、去掉测试断言取得通过。
- [x] **3. 移除回退并补齐装配。** 逐场验证明确绑定；没有实际缺口的五关文件不修改。保留原 main 玩家 Health、本地资源和预制参数；不批量编辑器重存或重新导入所有场景。夹具更新附带原断言保持说明。
- [x] **4. 做最终定向回归。** names：scene_request_test、scene_interaction_test、scene_script_cancellation_test、scene_transition_request_test、scene_director_authority_test、scene_director_test、scene_event_node_test、scene_reinforcement_test、level_flow_test、campaign_flow_test、campaign_checkpoint_test、campaign_quest_task_test、quest_portal_test、dialogue_cache_test、shop_catalog_test、shop_state_test、shop_board_test、shop_flow_test、shop_weapon_test、quest_money_reward_test、player_health_test、player_medkit_test、player_medkit_lifecycle_test、weapon_slots_test、presentation_camera_test；另跑三个敌人波次专项。若新改动触及额外责任再扩大测试，不默认全量。
- [x] **5. 真实画面与配置验证。** 执行 `& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --path movement_demo --script res://tests/scene_director_authority_test.gd -- --capture`，要求退出0、无脚本／资源错误，人工核对截图和状态记录；F5 酒馆、五关 F6、对话选项／鼠标、商店、手摆镜头目标与死亡二选一可操作。编辑器打开配置，检查新动作字段、旧路径和 .tres 引用可用；截图／日志仅入 logs。
- [x] **6. 核对结构与用户修改。** 用 rg 查所有 open_dialogue／open_shop_for_player／change_scene／reload_scene／SceneDirector.new 调用，逐项解释授权路径；比较实施开始时保存的节点路径、UID、敌人血量及用户未提交差异。所有发生实际职责变化的现行 MD 同步，未迁移项保留待办，不把历史通过数写作本轮证据。
- [x] **7. 关闭阶段并提交推送。** 更新测试结果、已知失败和未测项；只有结构及行为验收都通过才勾选整体统一调度待办。建议提交 `feat: enforce scene director authority in authored scenes`，普通 push 后核对 SHA；推送受阻则保留成果并说明。

## 计划自检与执行交接

设计§1～4由任务1／2／3落地，§5由任务1／2／3／5落地，§6的交互与加载由任务2／4落地、波次出口由任务5落地，§7～9由各阶段文档维护和任务6验收覆盖。五项 Review Focus 已放进所属任务的失败断言，新增接口的生产者与消费者在任务中列出。

采用 Native：六阶段共享请求身份、UI 控制与跨关状态接口，并且当前工作区存在用户已有改动，由同一执行者连续维护边界。任务由当前执行者完成，最终由一名独立审阅者检查整体变更。

executing-plans 及 TDD、验证、调试、最终审阅和收尾依赖已安装并用于实施；没有派发逐任务实现代理。项目要求的本地基线、普通阶段提交推送和定向验证优先，裁决见执行记录。

使用入口为[场景导演使用指南](../../gameplay/SCENE_DIRECTOR.md)，没有另建平行教程。实施日志与截图留在本地 logs，不作为运行资源提交。

## Implementation evidence

Task 1: scene_request_test 17 checks passed; scene_director_test, scene_event_node_test and shop_flow_test passed. campaign_flow_test retains exactly the three baseline dual-magazine failures; no new errors. Catalog OK. Logs: movement_demo/logs/director-authority-task1/.

Task 2: scene_interaction_test 22 checks passed; initial 9 named suites passed. Added authored NPC busy/UI exit coverage; final stage gate also compares campaign_flow_test against baseline. Existing guides updated; final user-facing guide consolidation remains Task 6.

Task 3: real Timer/Tween and sliding-door cancellation, stale/synchronous callbacks and SCENE/REGION isolation covered (9 checks). Earlier fixture assumptions corrected with explicit scene_root and the fourth pause argument; original assertions retained. Final seven-suite verification logged in movement_demo/logs/director-authority-task3-final/.

Task 4: transition requests 17 checks and request identity 19 checks passed; 11/12 final suites passed, campaign_flow_test retains exactly its 3 captured baseline magazine failures. Original interaction_test and successful retry/old-checkpoint restoration passed. Logs: movement_demo/logs/director-authority-task4-final/.

Task 5: final systems/enemy gate logs in movement_demo/logs/director-authority-task5-final/. 9/11 suites clean; original campaign_flow_test 3 magazine assertions and enemy_wave_test first-level completion assertion remain unchanged. New wave-mode permits, real dialogue-to-reinforcement barrier and region-owner cancellation pass. Authored enemy baseline files remain byte-identical.

Task 6: six authored scenes each resolve exactly one explicit director; missing-director and two-region checks pass (28 headless checks). Real OpenGL capture passes 47 checks; editor configuration 17/17 with a scan-aborted warning at exit. The 28-suite gate retains only the two original failing suites / four assertions documented in testing.md. Existing 27 purchased-weapon assertions remain, with the entry snapshot inspected after actual scene acceptance. At that stage, of 108 originally dirty paths, 107 remained byte-identical; Main retained its authored content plus the explicit director instance.

## 最终独立审阅与收尾（2026-11-11）

一次静态独立审阅提出三项 Important，无 Critical／Minor：

1. 加载父链过早从调度器分离，导致引擎接受前 `cancel_request` 和来源离场失效。新增独立取消入口及弱来源监听，取消会恢复状态／pending UI／本次暂停；原生成代次仍阻止迟到提交。
2. Runtime 实例化／出生检查失败，没有结束等待的 wave 请求。新增 `deployment_failed(reason)` 结果通知，导演使等待请求失败并清理记录，原因原样保留。
3. 排队动作没有重查规则条件。启动边界增加条件守卫，条件变化则取消为 `condition_changed`，本次规则不自动重投，REGION 复位后按原规则重新触发。

三项在一次修复阶段完成。定向复现先失败后通过（加载／条件 6 项、波次 3 项），原切场专项 23 项通过。用户明确要求减少无实际价值的测试，修复后没有重新运行先前的 28 套；旧失败仍未诊断根因。指南示例补齐 preload，现行配置说明及待办同步。

用户追加要求改变本地参数的提交范围：上传本地敌人血量／移速／武器／训练／波次配置，并把 Main 玩家生命设为 100。已提交 `f7bd2b8`，只加载核对相关暂存资源及本地 Main（6 项）；不上传插件、地形、其他本地文档或旧撤回记录。

用户再次明确：只有死亡界面可重新挑战当前关，不能返回上一关。现有 request_restart 已检查 dead，五关未配置常规重载规则；此处只纠正文档措辞，返回酒馆指酒馆和检查点恢复，不表示关卡回选或撤销已通关关卡。

审阅者未判断的事项逐项裁决：旧四条失败只保留对照，不推断游戏正常，代价是根因仍待定位；原有未提交修改仅按用户新授权上传敌人参数，其他继续保留，代价是远端与整个本地工作区仍有差异；取消不通用撤回已结算物品，遵循批准设计，代价是中途取消前已发物品仍保留；最终待办原先留待审阅完成，现已更新，没有未完成实现借此被标记完成。无延后 Minor。

## 执行裁决存档

以下为执行者的实施裁决，不冒充用户逐项指定的设计要求；每项保留依据和错误时的代价。

- Work in the existing main checkout with a byte-for-byte baseline backup — the user approved this plan's local baseline and ordinary main stage pushes; an isolated clean checkout would omit authored local configuration — incorrect attribution could upload unrelated edits, so construct staged changes against the saved baseline.
- Run the plan's targeted suites instead of the entire repository — project instructions explicitly require relevant checks without broadening absent new evidence — unrelated failures remain visible in recorded baseline results.
- Existing campaign_flow_test magazine failures are recorded baseline outcomes, not new regressions — stage gate requires other named suites clean and an exact match to the captured baseline errors, without modifying test assertions or authored resources — this does not claim campaign_flow_test passes.
- Move explicit scene_root fixture binding forward into Task 3 and update the adversarial pause subclass signature now - new authority validation and the Task 2 pause parameter expose these old fixture assumptions; all original behavior assertions stay intact - leaving this late would misclassify legitimate sibling action targets as foreign.
- Replace two legacy assertions requiring checkpoint/entry publication before a failed load with unchanged-on-failure assertions, and add successful acceptance coverage - the approved transactional spec forbids those old transient writes - success restoration, paid equipment and old-checkpoint defaults remain explicitly tested.
- Extend SceneTransition with optional final guard and accepted callbacks - they enforce generation validation after its environment-settling await and commit before target ready - an incorrect ordering would lose cross-scene state; real target-ready and cancelled async-loader tests cover the boundary.
- Submit automatic wave requests at the eligible physics candidate boundary, not inside raw event callbacks - the spec requires callbacks to record facts without recursive action execution - delay clocks remain business-owned and final permission stays adjacent to commit.
- Move the existing purchased-loadout assertion after real scene acceptance, preserving its content and all 27 checks - the approved transaction deliberately forbids early entry-state publication - a failed accepted transfer would still fail the original weapon assertion.
- Honor the latest user request to stop redundant broad tests; run only focused reproductions and the directly affected transition suite after fixes - repeated 28-suite runs are no longer authorized as useful work - unrelated regressions are not re-evaluated by the final fix pass.
- Baseline failure causes were outside static review - retain exact results without inferring gameplay health - a real old gameplay bug could remain unresolved.
- Pre-existing local files were outside reviewed range - latest user explicitly authorized enemy parameters and Main health100, handled in f7bd2b8; other files stay local - remote intentionally still differs from the full local workspace.
- Already-settled interaction grants survive cancellation - approved design leaves settlement and rollback to business owners - a player may keep an item granted before interruption.
- Final TODO was pending during review - mark complete only after important fixes and focused evidence - stale status could otherwise misstate delivery.
