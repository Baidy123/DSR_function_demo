# 测试入口与维护

2026-10-28 固定低速转身损耗：`target_switch_test` **196/196**、`directional_tracking_test` **56/56**通过。增加21项：三模式不同低速／高速系数、提高高速不影响主动转身、低速为0时允许恢复、真实目标横移仍按原速度插值且比较损耗而非位移，以及步枪67%下限的两帧对照。原175项保留，未放宽断言；本轮仅精度结算与测试变化，未重复UI截图或全量回归，详见[低速修订](superpowers/specs/2026-10-27-mouse-direction-target-switch-design.md#11-转身固定低速系数2026-10-28)。

2026-10-28 鼠标方向换锁初版（6ea24d0）：新增 `target_switch_test` 登记原战斗入口，真实玩家、相机、物理目标和视口输入覆盖原自动选敌、连续切换、屏幕间距行程、限速转身、三种射击模式即时弹道、逐帧复用枪械跟枪损耗、准星替代标记及输入清理，headless **175/175**。非headless OpenGL追加 `-- --capture` 后 **177/177**，已查看转向中及对准后的实际截图；多出的2项为PNG保存检查。原方向跟枪56/56、模式兼容77/77、视线19/19、近战破绽82/82、五关流程42/42通过；五关流程仍有原波次卸载警告。原切枪测试引用本地已删除的副武器资源而未完成，原自动射击18/21的3项仍假定保存场景主枪为单发；本地场景实际已改为自动步枪，配置和断言保持。命令、结构核对与边界见[实施记录](superpowers/specs/2026-10-27-mouse-direction-target-switch-design.md#10-实施记录2026-10-28)，不记作全量回归通过。

## 线性爆头与近战破绽（2026-10-27）

后续倍率修订：五套运行专项通过，破绽82/82、爆头64/64、执行63/63、近战效果57/57、敌人三档运行39/39。检查器倍率显示／撤销／保存／旧绝对字段清理40/40功能断言通过；原模式检查器仍43/44及原退出资源诊断。详细规则与验证见[倍率修订](superpowers/specs/2026-10-27-headshot-curve-melee-opening-design.md#11-破绽倍率修订2026-10-27)。以下保留初版验证记录。

新增战斗入口 `melee_headshot_opening_test` 已注册在 `run_combat_regressions.py`；原 `headshot_test`、`headshot_execution_test`、`ammo_drop_test` 及两个武器检查器测试迁移到准度门槛／启用开关，删除旧固定概率设置，不保留废弃运行属性。战斗目录检查通过，目标运行专项及三档敌人能力验证见[本次实施记录](superpowers/specs/2026-10-27-headshot-curve-melee-opening-design.md#10-实施与验证记录)。

编辑器验证单列：霰弹检查器39/39；武器模式检查器43/44，其中旧“缺少资源即时通知时，撤销也恢复远程字段”失败。在本地提交 `3de224b` 导出的独立工程中，未经修改的原测试同样42/43，仅同一项失败；本次新增敌人破绽字段隐藏检查通过。两种检查器退出仍有原 RID／PhantomCamera 资源诊断，不能记作严格无错误通过。保留原断言和门槛，未为本功能修改旧刷新实现。真实 OpenGL 另核对大小菱形、满准度亮边、敌人星环及遮挡；截图和诊断仅保存在忽略的日志目录。

补查方向跟枪44/44、命中干扰58/58、模式兼容77/77通过，共12套相关运行专项通过。旧霰弹40/43、散布29/30保留失败；`3de224b` 副本分别41/43、29/30，均衡图样零均值、固定5发余弹和资源随机模式假设在旧提交也失败，当前多出的纵向图样零均值失败对应开始前已有的本地编辑。用户2发弹匣、不向圆心偏移及图样调参保持；原断言未修改，详细数值见实施记录。不能据此声明全量战斗测试通过。

2026-10-27 接敌派发：`squad_dispatch_continuity_test` 使用保存第五关第二波六人队、原训练装备和持续移动玩家，检查完整玩家胶囊路径、首次整表派发／真实移动时间、全警戒和全员无实际动作窗口、实际移动／挥击及原P99／峰值门槛。`-- --contract-only` 单独运行14项目标更新、成员候选完成、提前事务拒绝及搜索隔离边界；`-- --trace` 追加前180帧准备／组合／提交记录。原始失败、最终结果与性能限制见[敌人测试](enemy-tests.md#接敌派发空窗2026-10-27)，不以“任务版本没变”单独认定全队停工。

2026-10-27 第五关近战：`squad_melee_contact_test` 已登记敌人运行器，使用真实第二波六人和小幅玩家移动，检查完整静态胶囊路径、攻击连线、实际命中、射程外静止时间、间距和近战提示。还检查合法终点微移时保持原路线，观察24秒并沿原入口清理。近战独立改动13/14，唯一失败是原整队P99性能；合法基线本来可以命中，不能宣称为修复前卡死现场。准确对照及废弃的入墙诊断见[敌人测试](enemy-tests.md#第五关近战落点与真实命中2026-10-27)。

2026-10-27 接敌警戒恢复：`squad_contact_recovery_test` 已登记敌人运行器。默认加载当前保存的第五关并真实推进到第二波，重建现场初始位置后观察24秒的真实感知、位移、射击、间距和整队性能；随后验证恢复记录生命周期。独立追加 `-- --passage` 检查附近站位被实体堵住时的联合让路，`-- --history-only` 单独检查值记录边界。均保留原P99<16毫秒／峰值<50毫秒门槛，结果和未通过项见[敌人测试](enemy-tests.md)。测试实例移除启动说明并使用原入口清理波次，不修改保存地图。

2026-10-27 第五关出生搜索：原 `squad_command_contract_test` 新增六人组合漏解与0权重检查，59/59；`enemy_wave_search_test` 原默认分支79/79，另以 `-- --saved-lvl5` 独立运行真实保存地图的第二、第三波，11/11。长地图用例不串入原默认分支，也不提高原75秒门槛。测试固定中央玩家位置、真实清波并观察身体推进，不改保存资源；原出生位置部分成员长期警戒的恢复另行处理。命令、失败对照与限制见[记录](superpowers/specs/2026-10-27-lvl5-wave-planner-stall-fix.md)。

2026-10-27 五关说明与按钮切关：新增 `level_flow_test` 登记到 combat。它加载真实保存五关、用原伤害入口逐波清敌，由原控制器自行发出完成信号；使用视口本地鼠标事件验证关闭、下一关、当前关死亡重开和通关重玩。运行实例临时无敌并加速波间等待，刷新点被占时通过正常移动输入让开，不修改保存场景、武器、训练或完成条件。42/42通过，清单检查通过；不代表完整战斗／敌人回归。死亡重开时仍有原波次卸载警告。

初始全屏渲染专项以非headless启动，参数 `--fullscreen --script res://tests/level_flow_test.gd -- --capture --fullscreen-proof`；在首次显示前不缩放窗口，验证背景全屏、关闭按钮可见和实际全屏模式，4/4通过。已检查真实OpenGL截图 `logs/play_guide_20261027/guide_initial_fullscreen.png`，正文可滚动，按钮完整。原生锚点取代启动时手工读取一次视口尺寸，避免必须缩小再全屏才刷新。

原 `enemy_wave_test` 的保存地图夹具在入树前移除测试实例的 `LevelFlow`，避免入场暂停与结果界面干预它原有的波次／跨区断言；全部原断言保持，80/80通过。新增流程专项单独覆盖真实说明和按钮，不改写保存地图以兼容旧夹具。

2026-10-27：`ammo_drop_test` 当前运行分支84项，新增两包名额与前景材质隔离检查；原波次80项通过。实际渲染分支在非headless模式追加 `-- --render-proof`，用普通模型确实被不透明物体挡住作为对照，检查同处掉落盒与标签仍可见，4项通过并保存截图到忽略目录 `logs/ammo_visibility_limit_20261027/`。按项目视口缩放换算截图像素，不以材质字段断言代替视觉验证。

2026-10-26 弹药资源与缺弹掉落：战斗组新增 `ammo_drop_test`（72项），使用真实 Equipment、物理区域、敌人死亡和两波流程；包含资源保存、场景继承覆盖、初始条目撤销／重做、同类共享、数量边界、自动拾取及模型隔离。`--editor --script res://tests/ammo_drop_test.gd` 另执行7项配置检查；编辑器退出日志与旧工程对照单独记录，不计为无错误退出。与弹药／双槽／换弹／半程／逐发／爆头／收敛／受击／玩家复用合计10套定向回归通过，原波次80项通过；已知旧失败及命令见[实施记录](superpowers/plans/2026-10-26-ammo-drops-and-types.md)。

2026-10-26 屏外开火默认50%：敌人专项 `enemy_offscreen_fire_test` 已登记，使用真实相机、感知与火控比较0／50／100%的实际发射、机会节奏、弹药及事件；24/24通过，原相机专项19/19。霰弹与支援点射的旧失败保留并与修改前隔离副本核对，见[验证记录](enemy-tests.md#屏外开火概率2026-10-26)。

2026-10-26 旧夹具修复：`enemy_weapon_test` 与 `aim_disruption_test` 复用 `Fixture.wait_for_camera()` 等待真实跟随镜头，保留屏幕外禁射与锁定限制；场景武器按实际保存引用校验，训练视距用例显式选择非武器绑定模式。当前分别29/29、58/58。掩体专项改用当前竞技场 `CoverD` 的真实碰撞尺寸／方向，节点失效时明确失败退出，新增完整交战阶段诊断；900帧打空、90帧开始换弹及恢复射击期限保持。全周期曾通过但复跑有两项不稳定，不能作为稳定绿灯。详见[原因与复验](enemy-tests.md#旧测试失败原因与当前地图复验2026-10-26)。

2026-10-26 瞄准收敛新增 `aim_convergence_test`，登记在原战斗回归清单；覆盖三公式、分帧一致性、玩家与敌人恢复参数隔离、默认时间、蹲姿端点、非线性换弹与真实弹道。原 `weapon_fire_mode_inspector_test` 增加公式／时间保存与撤销断言，仍用真实编辑器运行。已验证范围、既有失败与编辑器退出清理诊断分列于[实施记录](superpowers/specs/2026-10-26-aim-convergence-models-design.md#7-验证与试玩边界)，不将断言通过等同于无错误退出。

## 验证范围与试玩优先级

2026-10-26 用户补充：大体差不多且不影响游戏体验的差异无需继续处理。优先排查真实卡住、错误结算和功能失效；只有测试固定时间或战术过程存在小幅波动时，记录证据与限制，不为全绿强行改变游戏行为。

2026-10-23 用户明确要求：必要回归可以做，可有可无且耗时的检查不做。优化阶段以当前保存地图中的真实问题复现、修改前后对照及直接受影响的行为为主，不默认运行全量回归来建立基线。

- 开始验证前明确本次要回答的问题，优先使用已有现场入口。自动检查通过不能否定用户试玩发现的问题，也不能替代实际行动与手感验收。
- 修改执行行为时检查对应现场；修改跨模块协议时补查相关身份、预约或清理边界。仅新增或修改确实能捕获本次故障的断言，不为内部函数搬迁逐个补测试。
- 必要检查通过后结束验证。只有新修改、失败或明确的关联风险才扩大或重复检查；不为提高通过数量运行无关套件，不顺带修理无关旧夹具。
- 保留原断言、时间与性能门槛，原有失败仍如实记录；未运行项目不计作通过。下文全量与分组命令是可用入口，不是每次任务的必跑清单。

## 本次协调器定向入口

2026-10-24 远近协同新增已登记 `squad_mixed_cooperation_test.gd`。默认明确配置独立实例的实际枪械/近战模式，验证地面、导航、装配、目击和任务前提，再核对同期后侧射击、真实近战命中及玩家0.7米后退后的再次命中。这是代表性混编夹具，不规定游戏里的兵种比例。所有资源改动仅在实例中，不保存回场景或资源。

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path movement_demo --script res://tests/enemy/squad_mixed_cooperation_test.gd -- --level=2 --search
```

`--level=1/2` 检查两档；`--ranged` 检查实际交叉射击及机动期间队友火力；`--search` 检查真实遮挡后的关联掩护、入口等待、真实换弹、短段独立恢复、隐藏位移隔离和支援者死亡后近战实际命中；再加 `--pressure` 用真实受伤替换换弹触发。图形实例去掉 `--headless` 并加 `--capture`，保存 `logs/ranged_melee_support_20261024.png`，异步抓帧不跳过逐物理帧采样。

`--pursuit` 使用真实持续移动的玩家，核对已训练成员实际加速、后续真实近战命中、单次时限/跨任务冷却、暂停计时及无遮挡追击最长停顿。加 `--far` 检查先普通接近、进入距离后突进；加 `--crowded` 检查邻近队友条件；加 `--untrained` 做不自动解锁的对照。追击图形实例加 `--capture` 保存 `logs/command_melee_pursuit_20261024.png`。停顿断言排除近战占用和邻近身体让行，不能据此宣称消除所有正常停步。

`--support-burst` 使用实际接受的支援任务及队友真实换弹，验证超过普通配额的实射、只读停顿预测，以及真正转入近战后结束长点射。`enemy_melee_timing_test` 的相同三项精确时序断言保留，夹具显式装配训练与团队，手动时钟测试不替代前述完整运行验证。两种模式均不直接注入任务、支援需求或命中结果。

`--ranged --legacy-search --handoff --no-hints` 复用原搜索函数及全部断言，核对持续遮挡下的强档同步与转角朝向。`--saved-runtime --level=1/2 --search` 在原保存出生点运行原完整脚本，只在节点入树前纠正实例的枪械装备，含换弹、减员、单人及重载生命周期。当前提前重新目击场景的旧强档用例有3项未观测到同步放行的断言失败；不能把它记为全部通过，也不延迟真实接敌来凑放行。具体通过范围与保留失败见 [敌人测试](enemy-tests.md)。

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path movement_demo --script res://tests/enemy/squad_command_runtime_test.gd -- --level=1 --search
```

将 `--level=1` 改为 `2` 检查强协同实际屏障，`0` 检查个人 Utility；`--crowded` 复现三人墙角入口，`--blocked-exit` 用实例内实体封堵一端，`--mixed` 检查近战/远程及不同训练。运行中不注入任务接受、视野、到位或开火结果。图形模式追加 `--capture-debug` 保存当前路线画面到忽略目录。测试不写回保存场景、训练或武器资源。

`--level=1/2 --search-corners` 复现左侧高掩体单人幸存者的分段检查。先取得真实目击，再让玩家在墙的另一侧移动躲避；独立实例提高合法 hint 机会并关闭可选侧翼/掩体战术，以稳定执行本次搜索路线。用实际墙体几何、身体朝向和真实到达时刻分别核对拐点前后观察，不读取待测 `approach_look_position` 来生成期望值；最初未形成目标路线的试验不计作朝向验证。保留有意义的上下检查路线，同时检查提示多次更新后不立即重复已完成的同一检查、单人持续归队及原帧预算。图形模式加 `--capture-corners` 保存实际阶段截图至忽略目录 `logs/search_backtrack_20261024/`。该输入不向协调器注入任务、目击或完成结果，不写回用户场景与训练。

2026-10-24 分工/机动入口：`--level=1/2 --middle-right --no-hints` 在当前保存地图中先形成真实目击，再把玩家移到中间高掩体右侧，核对入口不重复、不同侧掩护候选、8秒内重新发现、碰撞和帧预算；图形模式加 `--capture-maneuver` 在真实搜索/掩护并存时保存 `logs/squad_maneuver_20261024/middle_right.png`。这是一组明确的复现输入，不声称捕获了用户难以复现的每一次三人排队。

`--level=1/2 --flank-motion --no-hints` 验证持续侧翼：实例里只给第三方包抄成员保留协作训练，两名射手保持真实接敌；该夹具关闭可选掩体战术，并让玩家在开阔处小幅移动，避免一直选择原地射击位而没有实际侧翼路段。检查真实身体移动速度、无遮挡时的身体朝向、间距和帧预算，不注入角色任务或目击。`--search --no-hints --handoff --maneuver` 另检查真实搜索/掩护组合、掩护者到位并看见目标区域，以及队友实际等待时赶路者奔跑。

2026-10-24 补充掩体背面朝向验收：`--level=1/2 --search --no-hints --handoff` 从实际墙体局部坐标核对观察目标位于背后的藏人空间，并在两端记录真实身体向内、独立背面采样点可见，以及抵达前仍沿入口方向移动的事实。不能仅比较任务朝向和执行输出，或以最后重新发现玩家代替此项验收。原代码会同时失败目标和身体检查。普通 `--search` 同样检查目标与双侧任务；封堵一端时仍检查目标，但不要求使用封死的入口。图形模式追加 `--capture-rear` 在突入阶段保存 `logs/tactical_search_20261023/cover_rear_facing.png`。

将 `--search` 换成 `--patrol`，配合 `--level=1` 或 `--level=2`，单独运行20秒未警戒巡逻。此分支检查前后两段真实移动、每人到达多个不同巡逻点、持续团队归属及身体间距，用于防止到第一个点后停住。

`--level=2 --contact-edge` 使用现场捕获的真实站位，验证一人看见玩家但枪口无合法瞄准点时，队伍能够换位并在8秒内实际射击；不注入无效瞄准、目击或任务结果。

`--level=1/2 --area --no-hints` 运行60秒真实失视地图搜索，检查本区导航边界、走出初始 `search_radius`、多段计划、移动中真实新增覆盖、30秒后推进及无全队长时间停滞。新增独立0.9米地面采样及站/蹲空间射线，不能用服务自身的已查标记证明覆盖。无提示用例在实例内以实体小围墙保持玩家真实隐藏，仍处于活跃战斗区；单面墙会被地图路线绕过，不能保证持续60秒失视。不可核实的围墙内部仍留在地图面积分母。原半径永久边界断言按指定设计改为地图权限边界，原时间与性能门槛不变。`--level=1 --area` 仍使用单面墙检查训练开启的 hint 确实触发并在8秒内通过个人视野重新目击。`--no-hints` 只修改测试实例的训练开关，冻结后不再改动。

强配合关键 `sync_key` 仍保留逐帧等齐、先到保持和后续放行检查；普通面积路段不以逐格同步为验收对象，合同专项另外检查前员调速、后员跟进后释放及换弹不加入队列屏障。`--search --no-hints --handoff` 在装配前将三名成员的实际检查时长设为0.6/0.9/1.2秒，使任意两名实际检查者都有先后完成，即使第三人被派去掩护。按用户允许一人/两人检查的新要求，后续可以再次同步两名检查者，也可以在前组完成后实际开始单人步骤；所有多人关键步骤仍必须等齐，先完成者仍必须留守。同速成员同时到位不能替代此项证据。`squad_map_observation_test` 使用真实实体墙、低墙和独立区域检查严格视角、部分面积、提示历史、重复时间、局部地图失效及死亡/离队监视清理；它与真实运行入口互补，不注入运行场景的命令或目击结果。

`--level=2 --defense` 使用真实受击比较低/高抗压成员和未训练掩体能力的成员，检查实际蹲藏、起身射击、撤回、恢复分工及队友本人目击下的实际支援射击；`--level=1 --defense --tall` 检查高墙绕角，以及探出后再次受击在30帧内改派躲藏。两者检查 Training 保存重载及本场参数冻结、全程零个人 Utility、身体间距与原16/50毫秒帧预算。只修改实例并把训练保存到忽略的 `logs/coordinator_repair_20261023/`，不修改场景、原武器或训练资产。

受压用例在导航就绪后设置初始身体位置，启用正常 AI 后即注入真实伤害，避免伤害前已完成正常掩体循环。高抗压只要求不被同等压力强制避险，正常掩体战术仍允许。`--level=1 --normal-cover` 单独验证无伤害时实际躲藏、探出射击和撤回。`--capture-debug` 使用独立图形实例，图片保存到 `logs/tactical_search_20261023/map_observation_routes.png`；运行用例同时核对调试副本不能改变任务/观察记录或增加射线查询。

将 `--search` 换成 `--melee`，配合等级1或2检查远程兵贴身自卫：保存地图中玩家逐一接近三名成员，统计实际命中、击退、非零前摇与正常收招，检查挥击期间任务保持、移动/射击/换弹互斥、收招后任务恢复，以及真实换弹被打断后的续换。最后在实例中关闭武器近战并再次贴近，检查禁止挥击。角色由协调器正常分配，贴身后可能从侧翼变为警戒等岗位；测试核对模板的三种分工及三名成员实际命中，不伪造固定岗位或命中结果。

`--level=2 --search` 逐帧核对每轮实际检查参与者的真实准备位置、放行及先完成者保持岗位，不只累计“出现过等待”。追加 `--handoff` 会在实例里放置第二道墙，将玩家移到墙后，专门验证真实完成后的等待和后续步骤；该用例不承诺发现被第二道墙遮挡的玩家。全员“都必须执行搜索”的旧断言按新分工要求改为实际执行检查或有资格的掩护，并单独核实掩护观察；不是仅给原地等待改名。原保存地图及入口封堵用例仍检查8秒内重新目击，接敌和完整搜索采样分别检查整队 AI+区域 P99 <16毫秒、峰值<50毫秒。

纯值组合边界为 `squad_command_contract_test.gd`。旧协调器的候选注入、advisory/个人接管和旧任务表专项已移除，明确清单与承接关系见 [敌人测试](enemy-tests.md#当前回归)。仍适用的共享情报、友军枪线、个人执行及压制检查保留。旧报告中的套数不代表本次全量通过。

## 查询当前清单

2026-10-24 武器命中／压制精度、命中减速与三个受方倍率只做四个相关既有专项：准度43/43、命中减速57/57、配置清理／保存25/25、配置生命周期141/141。未运行完整玩家、敌人或地图回归。检查器18/18断言通过，进程退出的既有资源及Phantom Camera更新器错误另列，不视为无错误运行；细节见 [实施与清理记录](superpowers/specs/2026-10-24-weapon-impact-accuracy-cleanup-design.md#10-本次实施与验证记录)。

在仓库根目录运行：

```powershell
python movement_demo/tests/run_regressions.py --list
python movement_demo/tests/run_regressions.py --check
```

`--list` 直接读取敌人与玩家运行器的 `TESTS`，同时列出系统专项及需要其他运行环境的脚本；数量以此输出为准。`--check` 检查遗漏、重复与失效路径，不启动 Godot，也不表示游戏测试通过。新增或移除测试时同步维护清单与其调用关系。

## 运行游戏回归

波次出生搜索定向入口为敌人组 `enemy_wave_search_test`，复用原波次夹具，使用真实区域时钟、实体墙和实际 AI／身体更新验证三种配合等级、一次性取样、持续警戒、首波／重排保护及复位。原 `enemy_wave_test` 保留运行断言，并在独立副本的 `--headless --editor --script` 分支检查新参数、复制、排序及保存重开；详见[波次说明](gameplay/ENEMY_WAVES.md#后续波出生即搜索)。

玩家／相机分场景复用的定向入口为 `player_scene_reuse_test`，已登记在 combat。它保存重载一个另建关卡，使用改名、嵌套的玩家与先就绪的独立相机，通过真实武器槽输入验证武器视野与跟随绑定；原 `player_camera_test`、`camera_occlusion_test` 保留视野／遮挡及死亡重开断言，仅更新移入相机场景的两个子节点路径。验证记录见 [相机说明](gameplay/CAMERA.md#玩家与相机分场景复用2026-10-24)。

2026-10-24 装备统一入口：原 WeaponSlots 节点改名为 Equipment，医疗资源 `medkit` 与数量 `medkit_count` 直接在装备检查器导出。`player_scene_reuse_test` 同时覆盖检查器字段、医疗组件归属、关卡保存重载后数量／疗效／时间覆盖以及原预制默认值隔离；`player_medkit_test` 保留原动作、受击、消耗与暂停断言，并核对真实治疗消耗 Equipment 的库存。原测试只同步授权改名涉及的路径，不降低已有行为断言。

最终本地工程完整玩家战斗回归26/27套：医疗98/98、玩家复用及医疗配置保存重载21/21、双方受击准度30/30；唯一失败为医疗生命周期的真实 NPC B 对话关闭检查（19/20），修改前的本地隔离副本同项失败。主场景、当前 lvl1／lvl3 各启动25帧，无脚本或资源错误。额外敌人武器专项22/26，四项失败及 Debug 旧夹具缺少 `CoordinatorPaths/Overlay` 的报错均在修改前副本复现，未修改原断言、用户武器／训练／地图以取得通过，未运行完整敌人回归。记录保存在本地忽略目录 `logs/equipment_20261024/`。

地图维护命令 `tests/bake_levels.gd` 只重烘五张独立地图的导航，已列入维护脚本排除清单，不作为回归运行；用法与实体轮廓排除说明见 [关卡地图](gameplay/LEVEL_MAPS.md)。

翻越定向检查包括 `vault_navigation_world_test`（原生 Bake／静态图）、`enemy_vault_link_contract_test`（增量查询／多段执行／生命周期）和 `enemy_vault_link_runtime_test`（默认0级双近战实战）。运行后者时在 Godot `--script` 参数后追加 `-- --level=1` 或 `-- --level=2` 验证团队，追加 `--all-trained` 装配该兵种全部战术。旧 `enemy_vault_navigation_test` 保留旧单次路线兼容断言；两种表示分别验证，不用旧夹具的单次同步调用代替新分帧流程。

```powershell
python movement_demo/tests/run_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe
python movement_demo/tests/run_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe --suite systems
python movement_demo/tests/run_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe --suite combat --suite enemy
```

| 分组 | 内容与清单来源 |
| --- | --- |
| `systems` | 移动、奔跑、NPC 交互、听觉、声音模式、Debug、表现接口／复位、对话文件扫描，以及任务条件、任务状态、阶段接线、任务面板和唱片机支线；由统一入口登记。可选交互物原型测试仅在本地文件存在时加入 |
| `combat` | `tests/run_combat_regressions.py` 的原玩家战斗清单 |
| `enemy` | `tests/enemy/run_enemy_regressions.py` 的原敌人清单 |

默认按系统、玩家、敌人顺序串行运行。统一入口为每次运行创建独立的 `logs/regressions/<时间>/`，分组保留 `results.json`、完整进程输出和 Godot 日志，总报告为 `report.json`。`--output` 可指定一个尚不存在的目录，避免覆盖旧结果。普通脚本超时仍为75秒；新的保存地图小队连续实战专项为180秒，旧协调器专项已从清单退出。

原有单组／定向命令仍可使用：

```powershell
python movement_demo/tests/run_combat_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe dialogue_cache_test interaction_test
python movement_demo/tests/enemy/run_enemy_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe enemy_basic_capabilities_test enemy_scene_test
```

两个旧入口继续写各自固定日志目录；需要保留多轮结果时使用统一入口或另存日志。共用进程执行及判错逻辑位于 `tests/regression_runner.py`：非零退出、超时、启动失败、`SCRIPT ERROR:`、`FAIL `／`FAIL:` 和普通 `ERROR:` 均判失败；仅沿用此前针对 `root certificate store` 的例外。

游戏回归必须保留实际运行基线。用户场景、武器或训练的本地修改可能与某些旧夹具的固定预期不同；保留失败及必要的修改前对照，不通过覆盖用户资源、跳过失败或放宽断言取得全绿。当前敌人整体性能与旧行为未完成项见 [敌人测试](enemy-tests.md#当前回归)和 [待办](TODO.md)。测试登记、局部通过及完整通过是不同事实。

PR #2 的五套任务／阶段测试已登记到 `systems`。2026-10-19 在 PR 与 `main` 的独立合并工作树中，任务条件、任务状态、阶段接线、任务面板、唱片机支线、交互物、Debug、相机共8/8套通过；竞技场场景整合与敌人场景共2/2套通过，主场景180帧启动无脚本或引擎错误。清单检查与运行器自身8项检查通过。空缓存首次导入出现已有的字体导入前引用错误，第二次导入退出码0且无错误。该记录仅代表本次合并定向验证，不代表完整系统、战斗或敌人回归全绿。

## 需要其他环境的测试

| 类型 | 入口与运行方式 |
| --- | --- |
| 兼容子检查 | 瞄准模式、散布、移动精度、武器模式参数、第一碰撞物由 `combat_compatibility_test` 调用；`range_reset_test` 由 `presentation_range_reset_test` 调用，均不重复计数 |
| 编辑器独立脚本 | `presentation_editor_test`、`weapon_fire_mode_inspector_test`、`enemy/enemy_training_inspector_test` 使用 `--headless --editor --script`；编辑器退出时的资源提示与断言结果分别记录，见 [敌人测试](enemy-tests.md)及 [表现说明](gameplay/PRESENTATION.md) |
| 已打开编辑器的测试 | `test_cover_instance_save`、`test_weapon_mode_inspector`、`enemy/test_enemy_probability_inspector` 依赖 Godot AI 测试工具和相应打开场景；操作编辑器节点，不进入普通批处理 |
| 图形输入专项 | `player_health_ui_test` 在独立渲染的 Main 中调用 `await script.new().run(scene)`，依赖真实 GUI 输入，见 [生命与界面](gameplay/PLAYER_HEALTH.md) |
| 尚待迁移的旧夹具 | `combat_test`、`combat_refinement_test`、`range_door_test`、`target_health_test` 保留原脚本及有效断言。前两者含旧移动精度预期，后两者依赖固定出生位置／武器弹药；需逐项迁移后才能纳入批处理，不计为当前已自动覆盖 |
| 辅助脚本 | `presentation_fixture`、`enemy_fire_fixture`、`modular_probe_action` 由正式测试加载 |
| 维护工具 | `bake_arena.gd` 会写入导航资源，是显式烘焙命令，不属于回归测试 |

不要通过通配符直接执行整个 `tests/`；脚本继承、辅助资源、编辑器环境与导航写入工具的运行方式不同。

运行器自身检查不需要 Godot：

```powershell
python -B movement_demo/tests/regression_runner_test.py
```

## 旧竞技场测试的替代关系

2026-10-13 移除未被运行器调用的 `tests/arena_test.gd` 及其 UID。它仍访问身体上已迁走的感知、记忆和状态接口，并要求交战搜索最终停止。下表按原断言列出迁移或已有覆盖；这些映射不替代实际运行结果。

| 原断言 | 当前覆盖 |
| --- | --- |
| `arena_instanced_in_main`、`navigation_baked` | `enemy_basic_capabilities_test` 检查 Main 中的竞技场与真实已烘焙导航；`enemy_scene_test` 覆盖绑定、激活与资源生命周期 |
| `clear_view_detects_player`、`behind_enemy_not_detected` | `enemy_basic_capabilities_test` 使用 `AI/Perception` 检查真实正面视线及近身范围外的背面拒绝 |
| `visible_player_is_remembered`、`wall_blocks_vision`、`hidden_player_does_not_update_memory` | `search_persistence_test`、`search_reacquisition_test` 保留真实目击、遮挡失视及隐藏坐标不刷新记忆 |
| `enemy_visits_last_seen_position`、`navigation_detours_around_wall`、`navigation_reaches_far_side` | `search_evidence_test` 的真实到点推进，以及 `search_reacquisition_test`／`search_pursuit_test` 的实际绕墙、重新目击与攻击；故障恢复由 `search_navigation_recovery_test` 覆盖 |
| `search_eventually_stops` | 旧交战搜索终止预期已被持续警戒要求替代；`search_persistence_test` 检查跨时限、多轮实走、死亡／离场复位及纯声音调查仍可结束 |
| `dead_enemy_stops_and_unlocks` | `enemy_basic_capabilities_test` 验证死亡身体拒绝移动并退出 `combat_target`；`search_persistence_test` 检查死亡清理搜索 |

## 对话文件扫描与日志隔离

`logs/.gdignore` 同时作为 Godot 与 Dialogue Manager 文件扫描的目录边界。验证副本保存在该目录下；项目的 `internationalization/locale/translations_pot_files` 只登记实际对话源，不保存副本路径。插件本地兼容补丁及升级复核见 [LOCAL_CHANGES.md](../movement_demo/addons/dialogue_manager/LOCAL_CHANGES.md)。

## 2026-10-13 首批维护验证

- 运行器自身8/8项通过，覆盖脚本报错但退出0、两种失败前缀、非零退出、超时、启动失败、原证书例外及完整清单检查。原敌人／玩家 `TESTS` 内容和顺序逐项一致。
- 对话扫描相同夹具修改前4/6、修改后6/6；两份隔离工程都在日志目录放入对话副本，编辑器重扫后原版仍登记该文件，修复版不登记。本地项目清除了443条日志副本路径，保留3条实际对话源；已有提交配置本身没有这些日志条目，因此没有将本地配置的其他差异顺带提交。
- 本地工程的隔离副本定向系统／玩家检查4/5，NPC 交互的“离开后按 E 不触发”失败在修改前副本也复现。四套敌人专项均被本地 `Enemy2/3/4` 与旧固定 `Enemy` 路径不一致阻断；原基础执行和场景测试的限定帧数启动对照复现同样错误，这不是完整基线回归。原场景及资源保持本地状态。
- 仅含本轮维护补丁的独立提交副本：统一入口完整玩家战斗26/26；敌人基础执行29/29、场景28/28、持续搜索22/22、重新发现34/34，共4/4套、113项。扫描、弹药、医疗包、区域复位的定向检查通过；上述NPC交互失败仍存在。未运行系统组全套、完整敌人回归或重新宣称性能达标。
- 首次空缓存编辑器启动在修改前／修改后副本均出现字体导入前引用与 Dialogue Manager 初始主题设置错误；完成导入后的第二次启动均无这些错误。首次输出保留，未扩大运行器错误过滤。

本轮日志、首次失败、前后对照与汇总保存在本地 `movement_demo/logs/structure_maintenance_20261013/`，不提交 Git。后续 AI 内部拆分和角色场景复用尚未实施。
