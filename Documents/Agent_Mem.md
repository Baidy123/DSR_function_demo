# Agent 记忆（Agent_Mem）

> 接手工作先读本文件的“当前状态 / 下一步 / 已知问题 / 接口契约”，再读 `Project_Rules.md`。
> 本章节只记录对后续工作有价值的事实与决策。

---

## 1. 当前状态（截至本轮）

| 项 | 状态 |
| --- | --- |
| 分支 | `fish-dev`（本地提交，**禁止推送**） |
| 远端 | `github` = `git@github.com:Baidy123/DSR_function_demo.git`（只读参考，不推送、不重建分支） |
| 构建 | `make release -j4` 通过；产物 `Build/Release/Target.exe`（约 1.4 MB） |
| 渲染 | 纯 D3D11 三维管线；内部 480×270，整数倍放大 + 后处理（抖动/扫描线/暗角/噪点/故障） |
| 场景 | 酒吧外（雨夜街道）、酒吧内、铁港仓库；固定机位 + 区域混合 |
| 角色 | 6 套程序化骨架：`PLAYER / BIGSISTER / MERCHANT / BARTENDER / SCAVENGER / AGENT` |
| 剧情 | 主线闭环 + 点唱机支线 + 商店 + 日志 + 双结局 |
| 资产 | 文本网格 `Resources/Meshes/Props/*.fcm`；无二进制素材入库 |
| 工具 | `UnitTests` 93/93 通过；`OffscreenTest --flow` 25/25 通过；离屏截图正常 |

---

## 2. 本轮完成的工作

1. **定位并修复 UI 文字残缺**：`SpriteBatch::Flush` 未绑定深度模板状态，精灵沿用了 3D 场景的深度状态，UI 与文字被场景深度部分裁剪。新增 `RenderDevice::m_depthDisabled` 并在每次 flush 时绑定。
2. **修复三维头像空白**：`RenderDevice::BeginScene3D` 固定绑定 `m_internal`，导致 `BeginRenderTarget(m_portraits[i])` 之后的绘制全被写回主目标。改为记录 `m_currentTarget` 并按当前目标的尺寸设置视口。
3. **修复剧情事件丢失**：`HandleDialogueFinished` 未派发挂起的 `DialogueEvent`，导致“接受支线”“结局选择”在调试与快速推进路径下丢失。收尾前统一 drain 事件；`BIGSISTER_RETURN` 不再无条件覆盖结局选择。
4. **相机与光照**：酒吧相机移入房间（`eye ≈ (5.6, 2.95, 4.35)`），铁港屋顶抬高到 y≈5.9、三台相机进入室内；环境光整体提亮；边缘光系数由 `2.2` 降到 `0.45`（原先细长圆柱体全轮廓过曝成白条）。
5. **工具适配 3D**：`UnitTests` 数学用例改写为 Vec3/Mat4/AABB/碰撞；`OffscreenTest` 改为直接读取 `Resources/Meshes/Props/*.fcm` 文本拼接成网格库（不再依赖已删除的 `ArtPack.bin`）。
6. **文本换行统一**：把工作区文本文件重写为 UTF-8 无 BOM + LF。

---

## 3. 下一步（建议顺序）

1. 视觉打磨：检查 `DrawLightGlows` 的辉光尺寸与 `uEmission` 全局自发光项是否过强；核对酒吧内白色圆环（疑似拾取物/标记）的绘制条件。
2. 场景补全：铁港的集装箱与吊灯在当前机位下几乎不可见，考虑调整道具位置或增加一台反向机位。
3. 战斗手感：命中反馈、受击闪白、弹道拖尾的时长与强度需要按最终帧率再调。
4. 音频：确认 `Audio_System` 在场景切换时不会叠加过多音源；紧急警报的循环需要显式停止。
5. 若继续扩展内容，优先补“东子”与“小帅”的支线对白，保持与剧本语气一致。

---

## 4. 已知问题

| 现象 | 影响 | 备注 |
| --- | --- | --- |
| 酒吧场景底部中央出现白色圆环 | 轻微 | 疑似拾取物/目标标记在相机后方的投影，尚未定位 |
| 铁港部分道具（集装箱、吊灯）在当前机位下不可见 | 轻微 | 机位或道具位置需要再平衡 |
| 角色行走动画在低帧率下略有跳变 | 轻微 | 动画相位用累计时间驱动，可加插值 |
| 文本纹理按字符串缓存 | 中 | 每帧变化的数值文本（血量、弹药）会创建新纹理；若出现卡顿需改为字形图集 |

---

## 5. 接口契约

### 5.1 文本网格 `.fcm`

```text
mesh <名称>
part <部件名> pivot <x> <y> <z>
mat 0xRRGGBB          # 颜色
pattern <0..9>        # 0 素色 1 砖 2 木 3 金属筋 4 锈 5 布料 6 混凝土 8+ 自发光
box   <cx> <cy> <cz> <hx> <hy> <hz> [yaw]
bevel <cx> <cy> <cz> <hx> <hy> <hz> <bevel> [yaw]
cyl   <bx> <by> <bz> <rBottom> <rTop> <height> <segments>
cone  <bx> <by> <bz> <radius> <height> <segments>
sphere <cx> <cy> <cz> <radius> <segments> <rings>
plane <cx> <cy> <cz> <halfX> <halfZ>
quad   <x0> <y0> <z0> <x1> <y1> <z1> <x2> <y2> <z2> <x3> <y3> <z3>
tri    <x0> <y0> <z0> <x1> <y1> <z1> <x2> <y2> <z2>
endpart
endmesh
```

### 5.2 场景数据（`Components/World/Inc/World_Types.hpp`）

- `Block(center, half, color, pattern, solid)`：房间体块，`solid=false` 不参与碰撞。
- `Prop(meshName, position, yaw, scale, tint, hidden)`：静态道具，`hidden=true` 时初始隐藏。
- `Light(position, color, intensity, range, flicker)`：点光源，最多 8 盏生效。
- `CameraZone(boundsMin, boundsMax, eye, target, fov)`：按玩家 XZ 区域切换机位。
- `Interact(id, position, radius, prompt)`：交互点，`id` 与 `GameApp::HandleInteraction` 对应。

### 5.3 游戏接口（`Components/Game/Inc/Game_App.hpp`）

- `Initialize(hwnd, width, height, const std::string& meshLibraryText, bool muted)`
- `Update(dt)` / `Render()` / `Present(vsync)` / `Capture(path)`
- 调试钩子：`DebugStartNewGame / DebugLoadScene / DebugInteract / DebugAdvanceDialogue / DebugChooseDialogue / DebugFinishDialogue / DebugCloseShop / DebugKillEnemies / DebugSetMode / DebugMainStage / DebugSideStage / DebugScene / DebugMode / DebugMoney / DebugHasGear / DebugEndingChoice / DebugAliveEnemies`
- 调试钩子仅供 `Tools/OffscreenTest` 使用，不参与正式玩法路径。

---

## 6. 阶段日志

| 阶段 | 内容 | 验证 |
| --- | --- | --- |
| 1 | 2D 像素 Demo（已归档） | 曾经 68/68 + 25/25 |
| 2 | 清理二进制美术，改为纯程序化资产策略 | `git log` 归档提交 `9e2d90e` |
| 3 | 数学/网格/3D 渲染/后处理/场景/角色/剧情/UI 全量重写 | `make release` 通过 |
| 4 | 修复 UI 深度裁剪、头像空白、剧情事件丢失；相机与光照重调 | 93/93 + 25/25，截图复核 |
| 5 | 文档按 3D 现状重写 | 本文件与 `README.md` |

---

## 7. 常用命令

```powershell
make release -j4                       # 构建最终产物
make -C Tools                          # 构建全部工具
make -C Tools unit                     # 仅构建单元测试
& .\Tools\UnitTests\Build\UnitTests.exe
& .\Tools\OffscreenTest\Build\OffscreenTest.exe --flow
& .\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar --ui dialogue --out Temp/Screenshots/bar_dialogue.bmp
```

> 截图与临时文件只写 `Temp/`；`Build/`、`Temp/` 均被 `.gitignore` 忽略。
