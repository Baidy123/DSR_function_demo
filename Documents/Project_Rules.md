# 项目规则（Project Rules）

> 本文件是本仓库的最高约束。修改代码、资源、文档前，先读本文件与 `Documents/Agent_Mem.md`。
> 规则与实际需求冲突时，先在 `Agent_Mem.md` 记录冲突，再按“最小改动 + 可回滚”执行。

---

## 1. 项目定位

| 项目 | 内容 |
| --- | --- |
| 作品名 | 《余烬自由城》 / **Ember of Free City** |
| 类型 | 复古低清多面体（low-poly）第三人称叙事动作 Demo |
| 主题 | 接入、归属、灰色生存；自由城的霓虹与制度性排斥 |
| 输入 | `Documents/场景剧本.docx`（唯一原始设定，角色设定必须保护）+ 远端 Godot 仓库的既有世界观 |
| 产出 | 单个 `Build/Release/Target.exe`，双击即玩，不依赖外部资产或运行时 DLL |
| 时长 | 15–25 分钟（探索、对话、商店、一场遭遇战、结局） |
| 技术栈 | C++17 + Win32 + Direct3D 11 + 自研 3D/UI/音频管线（无第三方引擎、无第三方运行时库） |
| 构建 | MinGW-w64（`x86_64-win32-seh-rev0` 16.1.0）+ GNU Make |

### 1.1 完成标准（Definition of Done）

1. 标题界面进入游戏，可完成“进酒吧 → 接委托 → 铁港仓库取货 → 遭遇公司特工 → 返回酒吧交差 → 结局”的闭环。
2. 四名原始角色（小明、大美、东子、小帅）形象可辨认、对白符合原剧本性格。
3. 商店、支线（点唱机零件）、战斗、任务日志、暂停、死亡、结局界面全部可用。
4. Release 产物为单文件静态 exe；资源以文本资产 + 程序化生成的方式内嵌。
5. `Tools` 下至少有 `UnitTests`（纯逻辑）与 `OffscreenTest`（离屏截图 + 主线流程）两个编译型工具。
6. 所有源码、资源、文档符合本文件的命名、注释、编码与换行规范。

### 1.2 非目标

- 不做联网、云存档、多语言、手柄、开放世界。
- 不引入图片/音频/字体等二进制素材；美术一律来自程序化几何与着色器。
- 不引入第三方引擎、第三方运行时库、需要安装的依赖。

---

## 2. 创作边界（最高优先级）

1. **原始角色不可改写**：姓名、身份、背景、性格、动机、人物关系必须与 `场景剧本.docx` 一致。
2. 允许扩展：世界观细节、城市地理、组织与科技名词、敌人类型、支线事件、视觉设计。
3. 扩展与原文冲突时以原文为准，并在 `Agent_Mem.md` 登记冲突点。
4. 基调保持“克制的赛博黑色”：不煽情、不说教，用环境、交易和短对白表达制度性困境。
5. 不添加与原文气质不符的要素（魔法、无厘头搞笑、过度血腥）。

---

## 3. 目录结构

```text
./
├─ Components/                 # 最终产物的功能组件块
│  ├─ Main/                    # 入口、窗口生命周期、内嵌资源装载
│  ├─ Shared/                  # 基础类型、数学、字符串、随机数、日志
│  ├─ Platform/                # Win32 窗口、输入、计时、内嵌资源读取
│  ├─ Render/                  # D3D11 设备、3D 场景管线、文本网格、SpriteBatch、文字纹理、后处理
│  ├─ World/                   # 场景定义、碰撞世界
│  ├─ Game/                    # 角色、渲染编排、剧情、任务、背包、商店、UI
│  └─ Audio/                   # 程序化音乐与音效（waveOut）
│     └─ Inc/ + Src/           # 每个组件必须有 Inc 与 Src
├─ Documents/                  # 规则、记忆、设计与验收文档
├─ Resources/
│  ├─ Meshes/Props/*.fcm       # 文本网格资产（UTF-8、LF）
│  └─ Resources.rc             # 把 .fcm 以 RCDATA 打进 exe
├─ Tools/                      # 验证工具（独立 Makefile，编译型）
│  ├─ UnitTests/  ├─ OffscreenTest/  ├─ Makefile  └─ README.md
├─ Temp/                       # 临时文件、截图（不入库）
├─ Build/                      # 构建产物（不入库）
├─ Makefile
├─ .gitattributes
└─ .gitignore
```

### 3.1 目录硬性规则

- `Components/<组件>/Inc` 放头文件，`Components/<组件>/Src` 放源文件。
- `Tools/` 下每个工具同样有 `Inc/` 与 `Src/`，产物写入各自的 `Build/`。
- `Tools/Makefile` 独立于根 `Makefile`；根 `Makefile` 只构建最终游戏。
- `Tools/` 只接受“源码 + 自有 Makefile”的编译型工具，禁止脚本型测试。
- 临时输出、截图、诊断导出一律写 `Temp/`，禁止写入 `Tools/` 或仓库根目录。

---

## 4. 文件与命名规范

1. 文件名只用 ASCII 字母、数字、下划线，禁止空格。
2. 文件名以组件名作前缀：`Render_SpriteBatch.cpp`、`Game_Quest.hpp`。
3. 缩写保持大写：`UI`、`HUD`、`D3D11`、`FS`、`NPC`、`SFX`、`AABB`、`RT`、`ID`。
4. C++ 头文件 `.hpp`、源文件 `.cpp`；本仓库不写 C 代码。
5. 头文件保护宏固定为“文件名全大写 + 双下划线”：

```cpp
#ifndef __GAME_QUEST_HPP__
#define __GAME_QUEST_HPP__
// ...
#endif // __GAME_QUEST_HPP__
```

6. 宏与枚举常量全大写加下划线（`MAX_ENEMY_COUNT`）；类名大驼峰（`SpriteBatch`）；函数与变量小驼峰（`DrawScene`、`currentHealth`）；成员变量 `m_` 前缀。
7. 常量用 `constexpr` 集中定义，禁止魔法数字散落。
8. 中文只出现在数据、文档与注释中；标识符、文件名、资源名一律 ASCII。

---

## 5. 代码规范

1. C++17；单文件不依赖第三方库；不用异常做流程控制。
2. 所有权优先 RAII；D3D 对象用 `ComPtr`，禁止裸 `new/delete` 管理长期资源。
3. 分层：渲染层不含玩法逻辑；玩法层不直接调用 D3D API；平台层只暴露窗口/输入/资源接口。
4. 头文件最小化；禁止在头文件定义全局对象。
5. 每个公开函数、结构体、类都要有 IntelliSense 可识别的注释：

```cpp
/**
 * @brief 把世界坐标投影到内部渲染分辨率。
 * @param [IN] camera 相机运行时数据。
 * @param [IN] world 世界坐标（米）。
 * @param [OUT] screen 内部像素坐标。
 * @return 位于相机前方返回 true。
 */
bool WorldToScreen(const CameraRuntime& camera, const Vec3& world, Vec2& screen) const;
```

6. 输出参数标 `@param [OUT]`，会被修改的标 `@param [IN/OUT]`。
7. 枚举用 `enum class` 并明确底层类型；`switch` 必须有 `default`。
8. 资源加载失败必须写日志并降级，不允许静默崩溃。
9. Release 不保留调试输出；调试信息统一走 `Shared_Log`，需要时再按需临时加入并删除。

---

## 6. 构建规范

1. 根 `Makefile` 是最终产物的唯一入口，默认构建 Release 与 Debug 两个目标。
2. 新目录必须显式加入 `CXX_INCLUDES_PATHS` 与 `CXX_SOURCES_PATHS`。
3. 最终产物静态链接（`-static`），不得依赖 MinGW 运行时 DLL。
4. 图形接口固定 D3D11；着色器运行时由 `d3dcompiler_47.dll` 编译（Windows 系统组件）。
5. 资源通过 `windres` 以 RCDATA 内嵌；exe 不得依赖外部资产路径。
6. 保持 `-Wall`，不得用关闭告警的方式掩盖问题。

---

## 7. 资源与编码规范

1. 所有文本文件 UTF-8（无 BOM）+ LF；例外：仅 Windows 专用 `.bat` 用 CRLF。
2. 新增文本扩展名必须同步登记到 `.gitattributes`。
3. **禁止入库二进制素材**：`.png`、`.bmp`、`.jpg`、`.wav`、`.ttf`、`.bin` 等一律不入库；截图与导出只写 `Temp/`。
4. 三维美术来自三处，均可用文本审阅与 diff：
   - 代码内几何：`Components/World`（房间、墙、台面等体块）、`Components/Game/Game_Characters`（角色骨架）；
   - 文本网格 `.fcm`：`Resources/Meshes/Props/*.fcm`；
   - 着色器程序化图案：`Render_Device` 中的 `ApplyPattern`。
5. 资产命名 ASCII 大写下划线：`PROP_LAMPPOST`、`PROP_CARGO`、`PORTRAIT_PLAYER`。
6. 禁止把机器绝对路径、用户名、密钥写入任何入库文件；文档路径以 `./` 或相对路径表示。
7. 外部素材只能先放 `Temp/`，确认授权与必要性后再决定是否以文本形式转写进仓库。

---

## 8. 美术与交互基调

1. 内部渲染分辨率 `480×270`，整数倍最近邻放大 + 黑边，保持像素边缘干净。
2. 世界单位：1 米 ≈ 40 单位，角色约 1.75 米；相机光轴固定，按玩家所在区域切换机位并平滑过渡。
3. 参考方向：复古低清多面体 + 像素化 CG，参考 *SIGNALIS* 的构图与光色（冷调环境 + 暖调实用光源），不复制其素材。
4. 主色板：雨夜蓝黑、冷灰环境光、青绿 UI、洋红警示、琥珀暖光、骨白文字。
5. 场景氛围：酒吧内部“暖、拥挤、有人味”；酒吧外“湿冷、霓虹、孤独”；铁港仓库“工业、空旷、危险”。
6. UI 风格：终端化细线框、扫描线、抖动、轻微噪点；中文正文用系统字体渲染成纹理，保证可读。
7. 交互必须“提示 + 反馈”成对出现：靠近显示 `[E]` 提示，执行后有音效/动画/文本反馈。
8. 状态不得只靠颜色区分，文本与图形同时表达。

---

## 9. 测试与验证规范

1. 默认只做针对性测试，不自动跑全量；用户明确要求“跑一遍所有测试”时才全量执行。
2. 所有自动化测试必须无头运行，不抢占鼠标、键盘、屏幕焦点，不做屏幕抓取。
3. `Tools/UnitTests`：纯逻辑单元测试（数学、背包、任务、对话、剧情数据），不依赖 D3D 与窗口。
4. `Tools/OffscreenTest`：创建隐藏窗口跑真实渲染管线，输出 BMP 到 `Temp/Screenshots/`，`--flow` 跑完整主线。
5. 新增或修改工具后，必须更新 `Tools/README.md` 的用途、命令、产物路径与注意事项。
6. 每阶段结束在 `Agent_Mem.md` 记录：命令、结果、已知问题、下一步。
7. 视觉验收以离屏截图为准；禁止占用用户屏幕。

---

## 10. Git 规范

1. 仓库使用本地 Git，提交身份仅在本工作区生效：

```text
user.name  = DeepSeek-V4.1-Flash
user.email = <>
```

2. 禁止修改全局 Git 配置；本工作区额外设置（仅本地）：`core.autocrlf = false`、`core.eol = lf`。
3. **只做本地提交，禁止推送**；不修改、不重建任何远端分支。
4. 阶段性成果才提交；一次提交对应一个可说明的阶段，不提交半成品或临时文件。
5. 提交信息用简洁中文，说明“改了什么 + 为什么”；多行信息写入 `Temp/` 的 UTF-8 文件，用 `git commit -F` 提交。
6. 提交前检查 `git status`：`Build/`、`Temp/`、`*.o`、`*.exe` 不得入库。
7. 发现提交含敏感信息或隐私路径，立即在下一提交中移除并登记。

---

## 11. 多 Agent 协作规范

1. 接手工作第一步固定为：读 `Project_Rules.md` → 读 `Agent_Mem.md` 的“当前状态 / 下一步 / 已知问题” → 看 `git log --oneline -5` 与 `git status`。
2. 完成后必须更新 `Agent_Mem.md`：任务、改动文件、验证命令、结果、遗留问题、下一步建议。
3. `Agent_Mem.md` 保持可检索：固定章节、表格化阶段日志、明确文件索引。
4. 记忆只写对后续工作有价值的事实与决策，不写流水账。
5. 接口变更（函数签名、资源名、场景 ID、资产格式）必须写入“接口契约”章节。
6. 未经用户明确要求不删除他人阶段成果；必须替换时先记录原因。

---

## 12. 验收清单

- [ ] `make` 能产出 `Build/Release/Target.exe` 与 `Build/Debug/Target.exe`。
- [ ] Release 版在普通 Windows 上可启动并完成主线。
- [ ] 四名角色形象、对白、性格与剧本一致。
- [ ] 商店可购买、支线可完成、战斗可失败并重试、结局两个分支都可到达。
- [ ] 头文件保护宏、注释、命名规范检查通过。
- [ ] `Tools` 两个工具可编译；`UnitTests` 全通过；`OffscreenTest --flow` 全通过。
- [ ] 文档索引完整，`Agent_Mem.md` 为最新。
- [ ] `git status` 干净，无临时文件、无二进制素材、无隐私路径。
