# 角色移动练习

这是第一步：用 3D 占位角色验证“先原地转好，再移动”。

## 打开与运行

1. 打开 Godot，在项目管理器中点击“导入”，选择本目录的 `project.godot`。
2. 进入编辑器后，打开 `main.tscn`，按 F6 运行当前场景，或按 F5 运行项目。
3. 点击游戏画面后，用 WASD 移动；W+D 等双键走斜线。
4. 黄色短条代表角色正面。换方向时观察它先转动，角色再行走。
5. 按 F8 停止运行。重新运行会回到场地中央。

本地使用 Godot 4.7.2，GDScript，Compatibility 渲染器。

## 先看这两个文件

- `main.tscn`：可在编辑器中直接查看的场景，包含平地、边界、角色、灯光和摄像机。
- `player.gd`：挂在 Player 节点上的移动脚本，共三段逻辑：读方向 → 原地转向 → 对齐后移动。

主要节点：

```text
Main
├── Floor                 地面与碰撞
├── Borders               场地边界，防止走出镜头
├── Player                CharacterBody3D，负责移动与碰撞
│   ├── CollisionShape3D  角色的碰撞形状
│   └── Visual            外观分组，当前随 Player 一起旋转
│       ├── Body          蓝色占位角色
│       └── FrontMarker   黄色正面标记
└── Camera3D              固定倾斜俯视，不跟随角色旋转
```

`project.godot` 保存工程设置和 WASD 输入映射。`tests/` 是自动检查，可以暂时不读。若看到 `addons/godot_ai`，它是本机环境加入的工具插件，移动脚本不调用它。

## 怎样理解移动脚本

每个物理帧先清空水平速度，所以角色不会带着上一个方向的速度继续滑行。

按键产生一个目标方向。脚本比较“当前面朝角度”和“目标角度”：还没对齐时，旋转 visual 引用的节点（当前为 Player 自身）；已经对齐时，才设置水平速度。最后由 `move_and_slide()` 执行移动和碰撞处理。

`Input.get_vector()` 将斜向输入长度限制到 1，因此斜走不会比直走更快。这里的 WASD 按画面方向移动，不是左右键控制转向的坦克式操作。

## 调整手感

停止运行，在场景树中选中 Player，右侧检查器会显示：

| 参数 | 临时测试值 | 作用 |
| --- | --- | --- |
| Move Speed | 3.0 | 行走速度，单位为场景单位/秒 |
| Turn Speed Degrees | 720.0 | 转向速度，单位为度/秒；转 90 度约需 0.125 秒 |

这些数值和固定倾斜俯视镜头是测试设置，尚未经过用户手感确认。建议一次只改一个参数，再运行比较效果。

目前的输入边界处理：松键立即停止移动与转身；反向键同时按下互相抵消；转身期间更换按键时改朝最新方向转。这些是本版简单处理，可根据试玩反馈修改。

## 验证与当前进度

已通过编辑器导入和 14 项自动检查，覆盖平滑转向、转向时停止位移、对齐后移动、换方向停步、松键、斜向等速、反向键抵消、边界碰撞和落地。已运行图形窗口并检查初始画面。

尚未由用户试玩确认转向速度、移动速度和镜头手感。

自动检查命令（在本目录的 PowerShell 执行）：

```powershell
& '..\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/movement_test.gd
```

本步完成后先试玩、理解和调整移动，不自动继续制作对话或战斗。

参考：[Godot CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html)、[角度旋转函数](https://docs.godotengine.org/en/stable/classes/class_@globalscope.html#class-globalscope-method-rotate-toward)。


## 奔跑与耐力（2026-09-14）

已按讨论加入：按住 Shift 奔跑，速度为走路的 2 倍；满耐力可连续跑 5 秒，从空回满需 3 秒。参数为已同意用于试玩的初值，后续可调整。

- 奔跑消耗耐力；行走、站立、原地转向都会立即恢复耐力。
- 未耗尽时可以随时再次奔跑。
- 耗尽后仍可行走，但必须回满才能再次奔跑；一直按着 Shift 会在回满后的下一物理帧自动续跑。
- 仍然先转好再移动，转身速度沿用现有的 720 度/秒。
- 当前按奔跑输入状态计费：对准方向、按住方向键和 Shift 时，即使顶住墙也会消耗耐力。
- 本步没有新增耐力条；先通过速度变化验证规则。

实现位于 player.gd：stamina 保存 0～100 的耐力，stamina_exhausted 保存耗尽后的锁定状态，is_sprinting 表示当前是否进入奔跑移动分支。_update_stamina(delta) 根据经过的时间消耗或恢复耐力。project.godot 新增 sprint 输入，绑定 Shift。

在 Godot 中按 F6 运行，按住 W+Shift 观察加速；持续按住，约 5 秒后降回走路速度，再过约 3 秒恢复奔跑。碰到边界会被挡住，可以换方向继续观察，或重新运行测试；注意转身期间也会恢复耐力。

停止运行后选中 Player，可在检查器调整：
- Sprint Speed Multiplier：2.0，奔跑速度倍率。
- Sprint Duration：5.0，满耐力持续奔跑秒数。
- Stamina Recovery Duration：3.0，空耐力恢复到满的秒数。

本次实现顺序：先新增奔跑测试并观察缺失功能导致的 8 项失败，再实现 Shift 输入及耐力逻辑，最后回归检查原有移动。已通过 18 项奔跑检查和 14 项移动检查；本次未进行图形界面试玩，手感待用户确认。

新增自动检查命令：

```powershell
& '..\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/sprint_test.gd
```
## NPC 交互第一步（2026-09-15）

- 在 Godot 中打开 main.tscn，按 F6 运行当前场景。
- 橙色胶囊是占位 NPC，位于玩家初始位置右侧。按 D 靠近，松开方向键后按 E；编辑器底部“输出”面板应出现“开始对话”。远离后按 E 不触发。
- 当前没有对话框，也没有接入 Ink。每次按下 E 输出一次，长按不重复触发。
- main.tscn 中 NPC/Body 是外观，NPC/CollisionShape3D 是阻挡玩家的实体碰撞，NPC/InteractionArea 是检测玩家的范围。
- npc.gd 的 _unhandled_input 先判断 interact 按键，再检查范围内是否有属于 player 分组的物体，找到玩家后打印文字。
- project.godot 的 interact 输入绑定物理 E 键；Player 节点加入 player 分组，用于区分玩家和地板等物体。
- 临时交互球半径为 1.8，可选中 NPC/InteractionArea/CollisionShape3D，在检查器展开 Shape 调整 Radius。检测依据碰撞形状重叠，不是两个节点中心的精确距离。
- 已通过 7 项无窗口交互检查（tests/interaction_test.gd）；实际画面与距离手感尚待试玩。


## 对话 UI 与移动锁定（2026-09-15）

- F5 运行：靠近 NPC 按 E，立即停止移动，先原地转向 NPC，转好后才显示 test text；再按 E 关闭并恢复移动。
- dialogue_ui.gd 管理面板显隐和关闭按键；npc.gd 等待玩家转身完成；player.gd 的 is_in_dialogue 锁住移动但允许 NPC 转身。
- 转身等待期间重复 E 无效，长按不关闭，关闭事件不会再次开启对话。重力与原有耐力恢复保留。
- 已通过脚本检查、工程启动、11 项运行时交互检查，并检查实际叠加画面。尚未接入 Ink 或分支。
- 场景保留用户的 360 度/秒转速和 Phantom Camera 跟随；移动采用之前确认的加减速与沿朝向弧线转弯。
