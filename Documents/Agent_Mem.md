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
| 当前阶段 | 阶段 2：构建系统与渲染平台层（美术资产已完成） |
| 最近更新 | 2026-11-17 |
| 更新者 | DeepSeek-V4.1-Flash |
| 构建状态 | 尚未开始（Makefile 待填充；ArtGen 已可独立编译） |
| 可玩状态 | 不可运行 |
| Git 基线 | `1f4395a` 初始提交；`c9fa7bb` 文档体系；美术资产随本阶段提交 |
| 下一步负责人 | 任意接手 Agent（见第 2 节） |

### 1.1 本阶段完成内容

- 建立本地 Git 仓库，提交身份仅在本工作区生效（`DeepSeek-V4.1-Flash` / `<>`）。
- 完善 `.gitignore`：忽略 Office 锁文件、构建产物、临时目录、ArtGen 本地构建。
- 完善 `.gitattributes`：源码/文档/Makefile/资源脚本统一 UTF-8 + LF，`.bat` 使用 CRLF，二进制资产标记 binary。
- 完成需求提取：从 `Documents/场景剧本.docx` 提取全文，确认角色与剧情基线。
- 产出一套设计文档与项目规则（见第 5 节文档索引）。
- 完成 C++ 像素美术生成器：195 项资产、19 类角色帧、4 张头像、标题图与资产包。
- 生成 `Resources/ArtPack.bin`（约 1.97 MB）与审阅预览图，并完成首轮视觉审阅。
- 本工作区设置 `core.autocrlf=false`、`core.eol=lf`，确保检出为 LF。

---

## 2. 下一步（按优先级）

1. **阶段 1：美术生成器与资产**
   - 编写 `Resources/ArtGen`（C++，纯自研绘图 + PNG 写出 + 二进制资产包）。
   - 生成瓷砖、角色、道具、头像、UI 图标、特效、标题图。
   - 用 `view_image` 审阅关键 PNG；不适配则迭代。
2. **阶段 2：构建与渲染平台层**
   - 填充根 `Makefile` 的源文件/头文件索引；加入 `Resources/Resources.rc`。
   - 实现 `Platform`（窗口、输入、计时、RCDATA 读取）与 `Render`（D3D11、SpriteBatch、文字纹理）。
   - 实现离屏截图钩子，供 `Tools/OffscreenTest` 使用。
3. **阶段 3：玩法与内容**
   - 场景：酒吧外、酒吧内、铁港仓库。
   - 系统：移动碰撞、交互、对话、任务、商店、战斗、HUD、日志、结局。
4. **阶段 4：音频与打磨**
   - 程序化环境音/音乐/SFX；雨、霓虹闪烁、屏幕震动、后处理。
5. **阶段 5：测试与发布**
   - `Tools/UnitTests` 覆盖任务/背包/伤害逻辑。
   - `Tools/OffscreenTest` 输出三场景截图。
   - Release 构建、启动验证、提交。

---

## 3. 已知问题 / 风险

| 编号 | 类型 | 描述 | 处理建议 |
| --- | --- | --- | --- |
| R-01 | 环境 | 系统未安装 Python，无法用 PIL 生成美术 | **已解决**：使用 C++ 编写 `ArtGen`，随 MinGW 工具链编译 |
| R-02 | 兼容 | 全局 `core.autocrlf=true`，Git 对 LF 文件仍可能提示警告 | 以 `.gitattributes` 为准，提交后用 `git ls-files --eol` 校验 |
| R-03 | 原始资料 | `场景剧本.docx` 存在 `~$` 锁文件，说明可能被 Word 占用 | 已忽略锁文件；读取时用共享模式复制，不修改原文件 |
| R-04 | 范围 | 剧本中第二个主线委托内容为空白（“此处接……”） | Demo 使用“铁港仓库取货 + 公司特工伏击”补全，并在设计文档说明 |
| R-05 | 技术 | 中文字体依赖系统字体 | 文字渲染使用 GDI，优先 `Microsoft YaHei UI`，回退 `SimSun`；不做字体嵌入 |
| R-06 | 技术 | 运行时着色器编译依赖 `d3dcompiler_47.dll` | 属 Windows 10/11 系统组件；若缺失则降级为纯色矩形并记录日志 |
| R-07 | 验证 | 无头截图需要隐藏窗口 + D3D11 | 在 `OffscreenTest` 中创建 `SW_HIDE` 窗口；若 swapchain 受限则改用离屏 RTV 读回 |

---

## 4. 接口契约

> 变更以下名称/签名时必须在此登记，并同步修改调用方。

### 4.1 场景 ID

| 枚举 | 值 | 说明 |
| --- | --- | --- |
| `SCENE_ID_TITLE` | 0 | 标题界面 |
| `SCENE_ID_BAR_EXTERIOR` | 1 | 酒吧外，夜，雨 |
| `SCENE_ID_BAR_INTERIOR` | 2 | 酒吧大厅与卡座 |
| `SCENE_ID_IRON_HARBOR` | 3 | 铁港仓库 |
| `SCENE_ID_EPILOGUE` | 4 | 结局界面 |

### 4.2 资源命名

- 瓷砖：`TILE_<区域>_<类型>_<变体>`，例如 `TILE_BAR_FLOOR_A`。
- 角色：`CHAR_<角色>_<动作>_<方向>`，例如 `CHAR_PLAYER_WALK_S`。
- 头像：`PORTRAIT_<角色>`。
- 图标：`UI_ICON_<名称>`。
- 特效：`FX_<名称>`。
- 标题：`UI_TITLE_LOGO`。
- 资产包内名称均为 ASCII 大写；运行时通过名称查找。

### 4.3 关键接口

| 接口 | 约定 |
| --- | --- |
| `ArtPack::Get(name)` | 返回只读纹理数据视图；找不到返回空视图并记录日志 |
| `GameApp::Initialize(HWND)` | 初始化游戏与渲染；失败返回 false |
| `GameApp::Update(float dt)` | 推进一帧逻辑；不含渲染 |
| `GameApp::Render()` | 渲染一帧到离屏目标 |
| `GameApp::Present()` | 缩放呈现到窗口 |
| `GameApp::DebugLoadScene(SceneId)` | 仅供离屏测试加载指定场景 |
| `TextRenderer::Draw(...)` | 仅在渲染层使用；玩法层只传 UTF-8 文本与样式 |

---

## 5. 架构速查

| 组件 | 职责 | 关键文件（计划） |
| --- | --- | --- |
| Main | 入口、主循环、窗口消息 | `Main_Entry.cpp` |
| Shared | 数学、类型、字符串、随机、日志 | `Shared_Math.*`、`Shared_String.*`、`Shared_Log.*` |
| Platform | Win32 窗口/输入/计时/资源读取 | `Platform_Window.*`、`Platform_Input.*`、`Platform_Resource.*` |
| Render | D3D11 设备、纹理、精灵批处理、文字、后处理 | `Render_Device.*`、`Render_SpriteBatch.*`、`Render_Text.*` |
| World | 地图、碰撞、场景蓝本、深度排序 | `World_Map.*`、`World_Scene.*`、`World_Collision.*` |
| Game | 玩法编排、实体、战斗、对话、任务、商店、UI | `Game_App.*`、`Game_Story.*`、`Game_Combat.*`、`Game_UI.*` |
| Audio | 程序化音乐与音效 | `Audio_System.*` |
| Tools/UnitTests | 纯逻辑测试 | `UnitTests_Main.cpp` |
| Tools/OffscreenTest | 隐藏窗口渲染截图 | `OffscreenTest_Main.cpp` |

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
| 1 | 2026-11-17 | DeepSeek-V4.1-Flash | C++ 美术生成器、195 项资产、资产包、预览图 | 生成器编译通过；PNG/包已生成；接触表/角色/头像/标题预览已审阅 | 本阶段提交 |
| 2 | - | - | 待执行 | - | - |
| 3 | - | - | 待执行 | - | - |
| 4 | - | - | 待执行 | - | - |
| 5 | - | - | 待执行 | - | - |

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
| 2026-11-17 | 视觉审阅 `_ContactSheet.png` / `_CharacterPreview.png` / `_PortraitPreview.png` / `_TitlePreview.png` | 通过 | 角色辨识度可用，后续在场景截图中复核 |

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
