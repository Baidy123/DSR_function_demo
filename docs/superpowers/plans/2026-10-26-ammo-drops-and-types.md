# 弹药资源与实时掉落实施记录

依据：[已确认设计](../specs/2026-10-26-ammo-drops-and-types-design.md)。用户于2026-10-26要求按该文档实施；保留其对模块化及资源配置的补充。

1. 接入 `AmmoDefinition`、`AmmoSupply`、四种兼容资源与盒子模型；Equipment 统一使用稳定类型键，提供只读库存和补给入口。保留旧武器枚举与场景初值，验证存档、显式0、第五类弹药、切枪和换弹。
2. 区域订阅真实死亡，按实时总量选一种弹药；通用掉落场景负责模型和附近自动拾取。验证地面位置、墙和楼层、暂停／对话、重复事件、波次清理与区域复位。
3. 补齐操作入口、结构及验证记录；审查本任务差异后提交并普通推送，不带入现有调参和插件改动。

实施默认数量先采用步枪15～30、手枪6～12、冲锋枪15～30、霰弹3～6；这是可调初值，不是用户指定的平衡数值。新类型默认不启用掉落。

已完成以上三步。四类旧武器不必重写资源，`WeaponData.ammo_definition` 留空时解析原枚举；显式资源优先。库存键只保留一套 `StringName`，Equipment 初始列表展示稳定的条目对象并兼容旧字段，当前槽与收起槽冻结已解析类型。新增的有限落点检查独立为 `world/ammo_drop_position.gd`，不增加区域或AI循环。

验证：

- 新 `ammo_drop_test` **72/72**：四类兼容及第五类保存、初值显式0、继承加载前后顺序、检查器字段、条目撤销重做、共享池／独立弹匣／懒初始化、半匣与奇偶容量、掉落开关及范围、资源热改冻结、普通／爆头死亡、真实玩家霰弹同枪三人、重复事件、模型颜色／缩放／空值及无效根回退、物理拾取／墙／层／对话／暂停、区域复位／离场与两波清尸。
- 定向玩家回归 **10/10套**：`ammo_drop_test`、`weapon_ammo_test`、`weapon_slots_test`、`player_reload_test`、`player_reload_checkpoint_test`、`shotgun_reload_test`、`headshot_test`、`aim_convergence_test`、`aim_disruption_test`、`player_scene_reuse_test`。旧测试仅迁移库存键，原行为断言保留。
- 原 `enemy_wave_test` **80/80**。`run_regressions.py --check` 清单检查通过；当前主场景 headless 启动45帧，无脚本或资源错误。
- 旧 `shotgun_test` **40/43**，两个已保存图样及霰弹切回余量预期失败；修改前隔离副本同三项失败。`enemy_reload_test` **31/34** 的三个声音失败在隔离副本均复现（对照另两项实射失败，为29/34）；`enemy_melee_weapon_test` **24/26** 两项失败同样复现。保留本地武器、图样、训练及关卡调参，不放宽旧断言。
- 编辑器分支的资源与继承检查 **7/7断言通过**。直接 `--editor --script` 退出仍报告编辑器控件／资源泄漏；修改前隔离工程仅等待启动再退出的探针也报告相同747个对象／62个资源未释放。恢复用户窗口时还出现 Phantom Camera 退出找不到管理器的错误，不能算无错误的编辑器运行。普通运行的72项及上述10套无此退出错误；未宣称完成手动试玩或完整全仓库回归。

主要命令（仓库根目录）：

```powershell
python movement_demo/tests/run_combat_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe ammo_drop_test weapon_ammo_test weapon_slots_test player_reload_test player_reload_checkpoint_test shotgun_reload_test headshot_test aim_convergence_test aim_disruption_test player_scene_reuse_test
python movement_demo/tests/enemy/run_enemy_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe enemy_wave_test enemy_reload_test enemy_melee_weapon_test
python movement_demo/tests/run_regressions.py --check
```

日志与隔离副本位于忽略目录 `movement_demo/logs/ammo_implementation_20261026/`，正式回归日志沿用原 `combat_regressions/`、`enemy_regressions/`。未改原敌人身体、AI或协调策略，不引入剧情库存或全局弹药单例。

## 2026-10-27 用户追加：显示置顶与两包上限

用户明确“最上层”是渲染层级，避免尸体挡住弹药。原拾取脚本复制每个模型表面的材质，启用前景绘制；盒子优先级126，名称／数量Label3D为127，地面位置与拾取检测保持。标准／ORM保留原颜色和贴图；没有材质或自定义Shader时使用标准材质保证模型可见，不改共享模型资源。采用透明队列与关闭深度测试的组合，依据[Godot标准材质说明](https://docs.godotengine.org/en/latest/tutorials/3d/standard_material_3d.html)。

未拾取上限按每区合计2包实施，所有弹种共用；原区域服务在死亡时预留待生成名额，同帧多死者不会超额。拾取即释放，生成失败返还，重置清空；旧代际回调不影响新名额。满额时跳过该次死亡掉落，拾取后仅后续新死亡重新检查。此要求取代设计中原先没有地面包上限的规则。

验证：原运行专项扩为 **84/84**，包括真实霰弹三人死亡只生成两包、满额阻止、实际靠近拾取后恢复、旧死亡不补发、失败落点及新旧代际名额、材质副本／颜色保持和标签层级。原波次 **80/80**、测试清单检查通过。实际OpenGL兼容渲染器另 **4/4**：普通盒子被同一不透明遮挡物盖住，掉落盒子和数量标签仍显示；截图 `occluded_control.png`／`foreground_pickup.png` 保存在 `logs/ammo_visibility_limit_20261027/`，无脚本或资源错误。

运行命令仍为战斗组 `ammo_drop_test`；图形验证可用 `Godot_v4.7.2-stable_win64_console.exe --path movement_demo --rendering-method gl_compatibility --script res://tests/ammo_drop_test.gd -- --render-proof`。本次未重新运行上文的整套玩家／敌人历史回归。
