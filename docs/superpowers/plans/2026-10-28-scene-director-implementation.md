# 场景总调度实施计划

日期：2026-10-28。用户已授权按设计实施，并使用两个协作agent。
依据：../specs/2026-10-25-enemy-wave-event-triggers-design_todo.md。

## 范围

实现现有场景生命周期、可选引导、统一暂停、死亡/通关UI与加载请求、事件动作、独立事件波次、专用演出相机。用户后续明确要求入口改名SceneDirector、事件节点接线、镜头手动绑定目标和检查器教程；只改五关入口名称/必要引用，原层级、CombatZone、区域服务及其余路径/UID保持。连续玩家数据属于后续单独确认阶段，不改变装备与携带规则。

## 文件分工

- 主agent：enemy_wave_controller兼容入口、systems/scene_director核心/暂停/动作资源、Health/PlayGuide/LevelFlow适配、区域协调、集成测试/登记/文档。
- agent 1：presentation_camera组件/场景、必要的player_camera适配、相机专项。
- agent 2：enemy_wave_runtime、Wave定义、共享事件触发/过滤/订阅辅助、事件波次专项。
- 新增协作会话1：Health/PlayGuide/LevelFlow视图适配、原夹具接线更新、五关最小改名及GUI切关回归。
- 新增协作会话2：总调度与事件节点独立测试；定位并修正同owner多暂停令牌的释放问题。
- 协作者不提交不推送，主agent检查集成后的完整文件集合再提交；不修改用户保存地图、武器和训练。

## 实施与验收

1. 并行实现独立模块；核心先建立无Wave/无PlayGuide也可运行的生命周期和控制权。
2. 接管现有UI：Health仅结算死亡；可选引导和结果UI只报告意图；核心统一处理暂停、结果、重开、加载失败。
3. 集成波次与事件动作，保留模板/占位/出生搜索，区域复位取消旧动作，事件引发动作不递归执行。
4. 集成独立相机与生成屏障，验证真实画面、切入/返回/取消/死亡优先。
5. 运行scene director、event wave、camera新增专项；原enemy_wave_test、enemy_wave_search_test、level_flow_test、player_health/复用/相机相关专项，登记检查；针对保存五关验证加载和界面。
6. 同步README、project-layout、使用说明、设计状态与TODO，审查差异，仅提交本任务已验证文件并普通push origin main。

## 当前状态

- [x] 本地基线和分工已确定。
- [x] 代码实现与集成。
- [x] 必要验证与问题修复。
- [x] 中文检查器提示、使用教程及相关文档同步。
- 提交与推送结果由本轮最终回复记录；提交仅包含本任务，lvl1仅暂存必要改名，用户既有场景块留在工作区。

用户未提交的资源、场景、插件与其他文档修改保持原状；不pull或引入远端内容。测试失败须区分原配置/旧夹具前提与新增问题，不改用户数值凑通过。

## 实施结果与验证证据

当前接口和逐步配置见[SceneDirector教程](../../gameplay/SCENE_DIRECTOR.md)。核心是内部Always节点，入口和敌人不设Always；事件/相机各自保留单一推进时钟。Health不再控制死亡UI/暂停/重载，场景结果与加载重试由核心控制。旧Main通过区域为场景玩家绑定同一核心，不新增AutoLoad。

本地Godot 4.7.2检查进程退出及SCRIPT ERROR/ERROR/FAIL，不能只看断言。日志均在忽略的movement_demo/logs，不提交。

| 验证 | 结果／证据目录 |
| --- | --- |
| 场景核心 | scene_director_test 137/137；scene_director_collaboration_final_edges，scene_event_node_collaboration_verified |
| 事件节点 | scene_event_node_test至少91/91，后续追加配置校验专项沿同组日志；Timer、0～8参数、过滤、重绑/失源、循环保护、规则快捷入口 |
| 事件波次 | enemy_wave_events_test 118/118；原wave 80/80、search 79/79，enemy_regressions与wave生命周期日志 |
| 真实增援 | scene_reinforcement_test 111/111；原/新增敌人AI、玩家、协同、治疗/换弹、延迟冻结，真实提交屏障、手选目标、直接Wave入口、占位、死亡/离区取消 |
| 暂停鼠标/准星 | 渲染mouse-ownership-only验证真实右键捕获、暂停松开、镜头返回/死亡释放；暂停后再保存已释放临时捕获的鼠标基线，准星立即隐藏但表现计时保留；原combat_view_test通过 |
| 专用相机 | headless 49/49，真实渲染58/58，10张交接/返回截图；原player_camera 26/26，camera_occlusion 46/46 |
| 五关改名/真实UI | level_flow 45/45，headless及真实渲染均通过；scene_director_20261028/rename_combat、rename_rendered，含1152/640说明与最终通关截图 |
| 保存第五关 | enemy_wave_search_test --saved-lvl5通过；rename_saved_lvl5_fixed，检查真实出生搜索、离开出生点及团队控制权 |
| 玩家兼容 | player_health_test、combat_view_test通过；reload42/42、checkpoint38/38、medkit98/98；医疗生命周期20/20、玩家复用21/21 |
| 登记与差异 | run_regressions.py --check通过；git diff --check通过；不是全量项目/团队性能回归 |

首轮发现并修正的实现问题：同一拥有者多暂停令牌的退出释放、来源消失/离树后的过期信号、UI退树焦点清理、缺meta默认null的Godot诊断、无结果UI的原独立波次不应自动进入通关暂停、旧场景正常卸载不应报活成员丢失、异步完成先订阅、显式切关失败重试原目标、区域复位取消旧波次等待。收尾真实输入对照复现了暂停前保存鼠标模式会恢复过期捕获，已改为暂停通知释放后保存；旧顺序对照失败日志保留。

保留且修正夹具前提而不修改用户数据：旧复用测试引用已删除test_sidearm资源，改为深复制当前test_rifle再显式设置测试值；旧医疗测试假定NPC_B单句，明确建立已完成任务的单句分支；换弹夹具明确各弹种测试库存36，不覆盖实际场景；保存第五关分支等待调度初始化后再关闭临时说明。旧失败日志未删除，原行为断言保留。

范围限制：未运行全部AI性能与全量回归；未替用户配置五关镜头锚点或启用展示；未验证新美术/Shader/多DPI完整覆盖。PlayerSession、跨关血量/库存与持久存档仍未实施，须另行确认规则。
