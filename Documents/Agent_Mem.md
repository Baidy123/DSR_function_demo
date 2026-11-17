# Agent 记忆（Agent_Mem）

> **所有 Agent 接手工作前必读。**
> 阅读顺序：`Project_Rules.md` → 本文件“当前状态 / 下一步 / 已知问题 / 接口契约” → `git log --oneline -5`。
> 完成阶段性任务后，必须按本文件模板追加记录，保持结构清晰、可检索。

---

## 0. 快速索引

| 章节 | 用途 |
| --- | --- |
| 1. 当前状态 | 一眼确认项目进行到哪一步 |
| 2. 下一步 | 下一位 Agent 直接可执行的任务 |
| 3. 已知问题 | 阻塞项、风险、待确认事项 |
| 4. 接口契约 | 跨组件函数、场景 ID、资源名约定 |
| 5. 架构速查 | 组件职责与关键文件 |
| 6. 阶段日志 | 按阶段追加的工作记录 |
| 7. 验证记录 | 已执行的命令与结果 |
| 8. 决策记录 | 重要设计/技术选择及理由 |
| 9. 续作指南 | 中断后如何恢复上下文 |

---

## 1. 当前状态

| 项目 | 值 |
| --- | --- |
| 当前阶段 | 阶段 5：核心 Demo 已完成，进入打磨与验收 |
| 最近更新 | 2026-11-17 |
| 更新者 | DeepSeek-V4.1-Flash |
| 构建状态 | `make` Release + Debug 通过；Release exe 3,309,056 B，Debug 12,597,980 B |
| 可玩状态 | 可玩；主线可完整通关（流程测试 25/25） |
| Git 基线 | `1f4395a` 初始；`c9fa7bb` 文档；`7291f33` 美术；`5fe5fa1` 核心实现与工具；`13d5879` 换行规范；`e9a077c` 文档/音频微调 |
| 下一步负责人 | 任意接手 Agent（见第 2 节） |

### 1.1 已完成内容

- 建立本地 Git 仓库，提交身份仅在本工作区生效（`DeepSeek-V4.1-Flash` / `<>`）。
- 完善 `.gitignore` / `.gitattributes`；本工作区设置 `core.autocrlf=false`、`core.eol=lf`。
- 从 `Documents/场景剧本.docx` 提取全文，完成世界观、角色、美术、玩法、剧情、技术、规则与测试文档。
- C++ 像素美术生成器：195 项资产、六类角色帧、四张头像、UI/特效/标题图，以及 1.97 MB 资产包。
- 完整平台/渲染层：Win32 窗口、输入、计时、RCDATA、D3D11、图集、SpriteBatch、GDI 中文文字、后处理、离屏截图。
- 完整玩法：三场景、碰撞、交互、打字机对话/分支、任务、商店、实时射击、敌人 AI、掉落、检查点重试、日志、结局。
- 程序化音频：waveOut 音乐/环境音/音效，支持静音与场景/战斗切换。
- 工具：`UnitTests`（68/68）与 `OffscreenTest`（截图 + `--flow` 25/25）。
- 最终视觉复核：标题、街道、酒吧、仓库、对话（含选项）、商店、日志、结局、死亡、暂停。

---

## 2. 下一步（按优先级）

1. **最终验收与提交**
   - 运行 `make`、`UnitTests`、`OffscreenTest --flow`、三场景截图。
   - 校验 `git status`、LF/UTF-8、无绝对路径、无临时文件。
2. **美术与场景密度（可选）**
   - 街道与仓库仍偏空旷；可增加路灯、广告牌、积水反光、货架与管线。
   - 可为角色增加更多待机/受击帧，为酒吧增加环境 NPC。
3. **系统完善（续作方向）**
   - 存档/读档、检查点 UI、手柄支持、鼠标菜单点击。
   - 难度选项、更多敌人类型、掩体与投掷物。
4. **剧情扩展**
   - 原剧本第二个主线委托为空白；可补全“第二天下午”的新委托。
   - 扩展灰烬阵线、前雇主下落、未登记神经桥的来源。
5. **性能与兼容（可选）**
   - 在无独显/远程桌面环境验证 WARP 回退。
   - 测试不同 DPI/分辨率/全屏切换。

---

## 3. 已知问题 / 风险

| 编号 | 类型 | 描述 | 处理建议 |
| --- | --- | --- | --- |
| R-01 | 环境 | 系统未安装 Python，无法用 PIL 生成美术 | **已解决**：使用 C++ 编写 `ArtGen`，随 MinGW 工具链编译 |
| R-02 | 兼容 | 全局 `core.autocrlf=true`，Git 对 LF 文件仍可能提示警告 | 本工作区已设 `core.autocrlf=false` / `core.eol=lf`；提交后用 `git ls-files --eol` 校验 |
| R-03 | 原始资料 | `场景剧本.docx` 存在 `~$` 锁文件，说明可能被 Word 占用 | 已忽略锁文件；读取时用共享模式复制，不修改原文件 |
| R-04 | 范围 | 剧本中第二个主线委托内容为空白（“此处接……”） | Demo 使用“铁港仓库取货 + 公司特工伏击”补全，并在设计文档说明 |
| R-05 | 技术 | 中文字体依赖系统字体 | 文字渲染使用 GDI，优先 `Microsoft YaHei UI`，回退 `SimSun`；不做字体嵌入 |
| R-06 | 技术 | 运行时着色器编译依赖 `d3dcompiler_47.dll` | 属 Windows 10/11 系统组件；缺失时记录错误并无法初始化渲染 |
| R-07 | 验证 | 无头截图需要隐藏窗口 + D3D11 | **已解决**：`OffscreenTest` 使用 `SW_HIDE` 窗口 + 离屏纹理读回 BMP |
| R-08 | 功能 | 无存档/读档 | Demo 使用场景检查点；续作可加存档 |
| R-09 | 音频 | 音乐/音效为程序化合成 | 可接受；后续可替换为成品配乐/音效 |
| R-10 | UX | 菜单为键盘操作，客户区系统光标隐藏 | 提示已写明按键；后续可加鼠标点击与光标切换 |
| R-11 | 美术 | 街道/仓库偏空旷、偏暗 | 可增加路灯、广告牌、货架、积水与更多光池 |
| R-12 | 剧情 | 第二个主线委托未实现 | 原稿为空，Demo 以铁港委托收束；续作可补全 |
| R-13 | 兼容 | 远程桌面/无独显环境可能无法创建 D3D11 硬件设备 | **已缓解**：硬件失败时自动尝试 `D3D_DRIVER_TYPE_WARP`；仍失败则记录错误 |

---

## 4. 接口契约

> 变更以下名称/签名时必须在此登记，并同步修改调用方。

### 4.1 场景 ID（`enum class SceneId`）

| 枚举 | 值 | 说明 |
| --- | --- | --- |
| `SceneId::BAR_EXTERIOR` | 1 | 酒吧外，夜，雨 |
| `SceneId::BAR_INTERIOR` | 2 | 酒吧大厅与卡座 |
| `SceneId::IRON_HARBOR` | 3 | 铁港仓库 |

标题/结局为 `GameMode::TITLE` / `GameMode::EPILOGUE`，不占用 SceneId。

### 4.2 资源命名

- 瓷砖：`TILE_<区域>_<类型>_<变体>`，例如 `TILE_BAR_FLOOR_A`。
- 角色：`CHAR_<角色>_<方向>_<帧>` 或 `CHAR_<角色>_<方向>_IDLE`，例如 `CHAR_PLAYER_S_0`。
- 头像：`PORTRAIT_<角色>`。
- 图标：`UI_ICON_<名称>`。
- 特效：`FX_<名称>`。
- 标题：`UI_TITLE_LOGO`、`UI_TITLE_BG`、`UI_ENDING_BG`。
- 资产包内名称均为 ASCII 大写；运行时通过名称查找；缺失时返回洋红占位。
- FCPK v1：头 8 字节，条目 44 字节，名称 32 字节，BGRA8 数据。

### 4.3 关键接口

| 接口 | 约定 |
| --- | --- |
| `RenderDevice::LoadArtPack(const std::vector<uint8_t>&)` | 解析 FCPK、建立 2048×2048 图集与精灵索引 |
| `RenderDevice::FindSprite(const char*)` | 按名称返回 `Sprite*`；缺失返回洋红占位 |
| `GameApp::Initialize(HWND, int, int, pack, muted)` | 初始化游戏、渲染、文字、音频；失败返回 false |
| `GameApp::Update(float dt)` | 推进一帧逻辑；不含渲染 |
| `GameApp::Render()` | 渲染一帧到离屏目标 |
| `GameApp::Present(bool vsync)` | 缩放呈现到窗口 |
| `GameApp::Capture(path)` | 保存离屏 BMP（无头验证） |
| `GameApp::DebugLoadScene(SceneId)` | 加载场景并进入 PLAYING，仅测试使用 |
| `GameApp::DebugShowDialogue/Shop/Journal/Ending` | 测试界面状态 |
| `GameApp::DebugInteract(id)` | 直接触发交互，仅流程测试使用 |
| `GameApp::DebugAdvanceDialogue/FinishDialogue/ChooseDialogue` | 无输入推进对话 |
| `GameApp::DebugCloseShop/KillEnemies` | 流程测试专用 |
| `TextRenderer::Get/Draw` | 仅在渲染/UI 层使用；玩法层只传 UTF-8 文本 |
| `AudioSystem::PlaySfx/SetScene/SetCombat/SetMuted` | 程序化音频事件入口 |

---

## 5. 架构速查

| 组件 | 职责 | 关键文件 |
| --- | --- | --- |
| Main | 入口、主循环、窗口消息 | `Main_Entry.cpp` |
| Shared | 数学、类型、字符串、随机、日志 | `Shared_Math.*`、`Shared_String.*`、`Shared_Log.*` |
| Platform | Win32 窗口/输入/计时/资源读取 | `Platform_Window.*`、`Platform_Input.*`、`Platform_Resource.*` |
| Render | D3D11 设备、纹理、精灵批处理、文字、后处理 | `Render_Device.*`、`Render_SpriteBatch.*`、`Render_Text.*` |
| World | 地图、碰撞、场景蓝本 | `World_Map.*`、`World_SceneData.*`、`World_Types.hpp` |
| Game | 玩法编排、实体、战斗、对话、任务、商店、UI | `Game_App.*`、`Game_Story.*`、`Game_Renderer.*`、`Game_UI.*`、`Game_Dialogue.*` |
| Audio | 程序化音乐与音效 | `Audio_System.*` |
| Tools/UnitTests | 纯逻辑测试（68 项） | `Tools/UnitTests/Src/UnitTests_Main.cpp` |
| Tools/OffscreenTest | 隐藏窗口截图 + 主线流程测试（25 项） | `Tools/OffscreenTest/Src/OffscreenTest_Main.cpp` |

### 5.1 文档索引

- `Project_Rules.md`：最高约束与验收标准。
- `Design_World.md`：世界观与地理扩展。
- `Design_Characters.md`：原始角色保护与视觉设定。
- `Design_Art.md`：美术方向、色板、资产清单。
- `Design_Gameplay.md`：玩法、系统、操作、关卡节奏。
- `Design_Story.md`：Demo 剧情流程与对白节拍。
- `Design_Technical.md`：架构、渲染、资源、构建、测试方案。
- `Agent_Mem.md`：本文件。

---

## 6. 阶段日志（追加式，不要删改历史）

| 阶段 | 日期 | 执行者 | 内容 | 验证 | 提交 |
| --- | --- | --- | --- | --- | --- |
| 0 | 2026-11-17 | DeepSeek-V4.1-Flash | 仓库初始化、规则与设计文档、需求提取 | `git log`、文档人工校对 | `1f4395a` / `c9fa7bb` |
| 1 | 2026-11-17 | DeepSeek-V4.1-Flash | C++ 美术生成器、195 项资产、资产包、预览图 | 生成器编译通过；PNG/包已生成；接触表/角色/头像/标题预览已审阅 | `7291f33` |
| 2 | 2026-11-17 | DeepSeek-V4.1-Flash | 平台/渲染：Win32、D3D11、图集、SpriteBatch、GDI 中文、离屏截图 | Release 构建通过；隐藏窗口截图通过 | `5fe5fa1` |
| 3 | 2026-11-17 | DeepSeek-V4.1-Flash | 世界/玩法：三场景、碰撞、交互、对话、任务、商店、战斗、UI、结局 | 流程测试 25/25；三场景截图审阅 | `5fe5fa1` |
| 4 | 2026-11-17 | DeepSeek-V4.1-Flash | 程序化音频、雨/霓虹/震动、HUD/菜单打磨 | 隐藏启动正常退出；静音测试通过 | `5fe5fa1` |
| 5 | 2026-11-17 | DeepSeek-V4.1-Flash | Tools：UnitTests 68 项、OffscreenTest 截图 + flow 25 项 | 全部通过；文档与记忆更新 | `5fe5fa1` |
| 6 | 2026-11-17 | DeepSeek-V4.1-Flash | 修正 .gitattributes 大小写；同步文档；音频缓冲降至 512 帧 | Release/Debug + UnitTests 68/68 + flow 25/25 + 隐藏截图 | `13d5879` / `e9a077c` |

---

## 7. 验证记录

| 日期 | 命令 | 结果 | 备注 |
| --- | --- | --- | --- |
| 2026-11-17 | `git init` + `git config --local` | 通过 | 身份仅本工作区 |
| 2026-11-17 | `git ls-files --eol .gitattributes .gitignore` | `i/lf w/lf` | 换行符合规范 |
| 2026-11-17 | `g++ --version` / `make --version` / `windres --version` | 通过 | MinGW 16.1.0 / Make 4.4.1 / Binutils 2.46 |
| 2026-11-17 | `python --version` | 不存在 | 改用 C++ ArtGen |
| 2026-11-17 | `g++ -std=c++17 -O2 Resources\ArtGen\ArtGen_Main.cpp -o Temp\ArtGen.exe` | 通过 | 无错误 |
| 2026-11-17 | `.\Temp\ArtGen.exe Resources` | 通过 | 195 PNG；ArtPack.bin = 1,972,556 B |
| 2026-11-17 | 视觉审阅 `_ContactSheet.png` / `_CharacterPreview.png` / `_PortraitPreview.png` / `_TitlePreview.png` | 通过 | 角色辨识度可用 |
| 2026-11-17 | `make release` / `make debug` | 通过 | 单文件 exe；资源嵌入；静态链接 |
| 2026-11-17 | `.\Build\Release\Target.exe --shot Temp\shot_*.bmp`（隐藏窗口） | 通过 | 标题/街道/酒吧/仓库/对话/商店/日志/结局/死亡/暂停截图 |
| 2026-11-17 | `.\Tools\UnitTests\Build\UnitTests.exe` | 通过 | 68 / 68 |
| 2026-11-17 | `.\Tools\OffscreenTest\Build\OffscreenTest.exe --flow` | 通过 | 25 / 25（完整主线 + 支线 + 结局） |
| 2026-11-17 | `make -C Tools` | 通过 | UnitTests + OffscreenTest |
| 2026-11-17 | 最终视觉复核 | 通过 | 修复多行文字重叠、HUD 遮挡、商店上下文、结局布局 |
| 2026-11-17 | `git commit` | 通过 | `5fe5fa1 核心：完成可玩 Demo、程序化音频与无头验证` |
| 2026-11-17 | `objdump -p Build\Release\Target.exe` | 通过 | 仅依赖系统 DLL（d3d11/d3dcompiler/gdi32/user32/winmm/ucrt） |
| 2026-11-17 | 隐藏窗口运行嵌入资源 exe | 通过 | 195 项资产从 RCDATA 加载，截图正常，进程正常退出 |
| 2026-11-17 | 新克隆换行验证（全局 autocrlf=true） | 通过 | `.gitattributes` 使用小写 `eol=lf` 后，Makefile/源码/文档/RC 均为 LF |
| 2026-11-17 | 音频缓冲 512 帧后的 `make release` / `make debug` / `make -C Tools` | 通过 | 68/68 单元测试、25/25 流程测试、隐藏截图正常退出 |

---

## 8. 决策记录（ADR 摘要）

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D-01 | 采用 2D 俯视角像素风，而非 3D | 美术可控、单文件体积小、符合参考作品气质、便于无头验证 |
| D-02 | 内部分辨率 480×270，整数最近邻放大 | 像素边缘干净，性能稳定，中文 UI 仍可读 |
| D-03 | D3D11 + 运行时编译 HLSL | 工具链已有 `-ld3d11 -ld3dcompiler`，系统普遍具备 |
| D-04 | 美术由 C++ 生成器产出 PNG + 二进制包 | 无 Python 环境；资产可重现、可审阅、可嵌入 |
| D-05 | 中文文本用 GDI 渲染成纹理 | 避免自带 CJK 字库，保证任意 Windows 可读 |
| D-06 | 对话/任务用代码内数据结构而非外部脚本 | 避免运行时解析器复杂度，便于类型检查与测试 |
| D-07 | 音频使用 waveOut + 程序化合成 | 无外部素材、无额外依赖，能提供氛围与反馈 |
| D-08 | Demo 以“仓库货物是未登记神经桥”收束 | 把主线动机与取货目标绑定，形成完整叙事弧 |
| D-09 | 美术生成器使用 C++ 自实现 PNG 写出（无压缩 Deflate） | 本机无 Python/zlib；PNG 体积换实现简单可靠 |
| D-10 | 仓库级 `core.autocrlf=false` + `core.eol=lf` | 全局 `autocrlf=true` 会使检出变为 CRLF，违背 .gitattributes |
| D-11 | 音频使用 waveOut + 程序化合成器 | 无外部素材、无第三方依赖；场景氛围与战斗反馈完整 |
| D-12 | 增加 `OffscreenTest --flow` 脚本化主线测试 | 无输入环境下验证完整主线，避免只测单点逻辑 |
| D-13 | 菜单保持键盘操作，客户区隐藏系统光标 | 像素风统一；键位在标题/商店/日志/暂停中明确标注 |
| D-14 | 调试入口全部以 `Debug` 前缀公开 | 供 Tools 使用，不影响正常游戏流程 |

---

## 9. 续作指南

1. 新 Agent 先执行：
   ```powershell
   git status
   git log --oneline -5
   ```
2. 读取本文件第 1、2、3、4 节；确认当前阶段与下一步。
3. 若需要修改接口，先更新第 4 节，再改代码。
4. 若需要新增源文件，确保：
   - 放入正确的 `Components/<组件>/Src`；
   - 同步根 `Makefile` 的目录索引（目录级索引即可，新增文件自动被 wildcard 收录）；
   - 头文件保护宏与注释标签齐全。
5. 完成阶段后：
   - 运行针对性验证（不是全量）；
   - 更新第 1、2、3、6、7 节；
   - 提交并记录提交哈希。
