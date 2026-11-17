# 余烬自由城 / Ember of Free City

一个基于 `Documents/场景剧本.docx` 扩展的 **2D 俯视角像素风叙事动作 RPG Demo**。
玩家扮演没有思维接入装置的新居民“小明”，在自由城旧城区接下一份来自“大姐头”大美的委托，前往铁港仓库取货，并面对公司特工的伏击。

- 技术栈：C++17 + Win32 + Direct3D 11 + 自研 2D 渲染/文字/音频/资源管线
- 产物：单个静态链接的 `Build/Release/Target.exe`，资源已嵌入，无需安装环境
- 内部分辨率：480×270，整数最近邻放大
- 美术：程序化生成的像素资产（195 项），仓库内附 PNG 与运行时资产包
- 时长：约 20–30 分钟
- 文档：世界观、角色、美术、玩法、剧情、技术、规则与验收记录均在 `Documents/`

---

## 1. 构建

要求：

- Windows 10/11 x64
- MinGW-w64（已在 x86_64-win32-seh-rev0 / GCC 16.1.0 验证）
- GNU Make
- `d3dcompiler_47.dll`（Windows 系统组件，用于运行时编译内置 HLSL）

在项目根目录执行：

```powershell
# Release + Debug
make

# 只构建 Release
make release

# 只构建 Debug
make debug

# 清理
make clean
```

产物：

- `Build/Release/Target.exe`
- `Build/Debug/Target.exe`

> 最终 exe 通过 `windres` 嵌入 `Resources/ArtPack.bin`；运行时不需要外部资源文件。
> 根 `Makefile` 只构建游戏本体；测试工具使用 `Tools/Makefile`，见 `Tools/README.md`。

---

## 2. 运行

```powershell
.\Build\Release\Target.exe
```

- 双击也可直接运行。
- 首次进入为标题界面；`Enter` 开始。
- `Alt+Enter` 切换无边框全屏。
- `Esc` 在标题界面退出；游戏中打开暂停菜单。

### 操作

| 操作 | 键位 |
| --- | --- |
| 移动 | `W A S D` / 方向键 |
| 瞄准 | 鼠标 |
| 射击 | 鼠标左键 |
| 装填 | `R` |
| 交互 | `E` |
| 医疗包 | `F` |
| 任务日志 | `Tab` |
| 静音 | `M` |
| 暂停 / 返回 | `Esc` |
| 对话推进 | `Space` / `Enter` / 鼠标左键 |
| 对话选项 | `W/S` 选择，`E` 确认 |
| 商店 | `W/S` 选择，`E` 购买，`Esc` 离开 |

> 菜单使用键盘操作；系统鼠标指针在窗口客户区内隐藏，游戏内使用像素准星。

---

## 3. Demo 内容

- **三个可玩场景**：雨夜酒吧外、余烬酒吧内、铁港仓库。
- **四名原始角色**：小明、大美、东子、小帅，均有符合剧本的对白、头像与世界精灵。
- **一条主线**：进入酒吧 → 打听大姐头 → 接受委托 → 找东子领装备 → 前往铁港 → 取货 → 击退公司特工 → 返回交差 → 结局选择。
- **一条支线**：帮小帅找点唱机零件，修好点唱机。
- **系统**：对话打字机/分支、任务目标、商店、货币/弹药/医疗包、实时射击战斗、敌人 AI、掉落、检查点重试、日志、程序化音乐/环境音/音效。
- **结局**：接入或暂缓接入，两段不同的收束独白。

---

## 4. 美术与资源

- 生成器：`Resources/ArtGen/ArtGen_Main.cpp`（C++17，仅标准库）
- 可审阅 PNG：`Resources/Art/`
- 运行时包：`Resources/ArtPack.bin`（FCPK v1，BGRA8）
- 资源脚本：`Resources/Resources.rc`
- 预览图：`Resources/Art/_ContactSheet.png`、`_CharacterPreview.png`、`_PortraitPreview.png`、`_TitlePreview.png`

重新生成：

```powershell
g++ -std=c++17 -O2 Resources\ArtGen\ArtGen_Main.cpp -o Temp\ArtGen.exe
.\Temp\ArtGen.exe Resources
make release
```

详细说明见 `Resources/README.md` 与 `Documents/Design_Art.md`。

---

## 5. 测试工具

```powershell
make -C Tools

# 纯逻辑单元测试（无窗口）
.\Tools\UnitTests\Build\UnitTests.exe

# 隐藏窗口渲染截图（不抢焦点）
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar --ui dialogue --out Temp\Screenshots\dialogue.bmp

# 无头完整主线流程测试
.\Tools\OffscreenTest\Build\OffscreenTest.exe --flow
```

当前结果：

- `UnitTests`：68 / 68 通过
- `OffscreenTest --flow`：25 / 25 通过（完整主线）
- 离屏截图：标题、街道、酒吧、仓库、对话、商店、日志、结局、死亡、暂停均通过人工审阅

工具说明与约束见 `Tools/README.md`。默认只做针对性测试，不自动跑全量测试。

---

## 6. 目录

```text
Components/
├─ Main/        # 入口与主循环
├─ Shared/      # 类型、数学、字符串、随机、日志、COM 指针
├─ Platform/    # Win32 窗口、输入、计时、资源读取
├─ Render/      # D3D11 设备、图集、SpriteBatch、GDI 文字
├─ World/       # 地图、碰撞、场景蓝本
├─ Game/        # 玩法、战斗、对话、任务、商店、UI
└─ Audio/       # waveOut 程序化音乐/环境音/音效
Documents/      # 规则、记忆、世界观、角色、美术、玩法、剧情、技术、测试
Resources/      # 美术生成器、PNG、资产包、资源脚本
Tools/          # 编译型验证工具（独立 Makefile）
Temp/           # 临时文件（不入库）
Build/          # 构建产物（不入库）
```

---

## 7. 文档

| 文档 | 内容 |
| --- | --- |
| `Documents/Project_Rules.md` | 最高约束、目录/命名/注释/构建/测试/Git 规则 |
| `Documents/Agent_Mem.md` | 多 Agent 协作记忆、当前状态、接口契约、验证记录 |
| `Documents/Design_World.md` | 自由城、FS-Link、公司、旧城、铁港、经济与术语 |
| `Documents/Design_Characters.md` | 原始角色保护、视觉设定、像素规格、对白语气 |
| `Documents/Design_Art.md` | 色板、场景构图、资产清单、动画、UI、生成流程 |
| `Documents/Design_Gameplay.md` | 操作、战斗、交互、任务、商店、节奏与平衡 |
| `Documents/Design_Story.md` | Demo 剧情流程、对白节拍、分支、结局 |
| `Documents/Design_Technical.md` | 架构、渲染、资源包、输入、碰撞、构建、测试 |
| `Documents/Test_Plan.md` | 测试范围、用例、无头验证流程与结果 |
| `Documents/Art_Manifest.md` | 资产清单与审阅状态 |

---

## 8. 已知限制

- 无存档系统；Demo 使用场景检查点与重试。
- 音乐/音效为程序化合成，非成品配乐。
- 中文文字依赖系统字体（`Microsoft YaHei UI` → `SimSun`）。
- 菜单为键盘操作；无手柄支持。
- 仓库中的美术为程序化生成，若需更高完成度可在 `Resources/ArtGen` 基础上迭代。
- 运行时依赖系统组件 `d3dcompiler_47.dll`（Windows 10/11 默认存在）。
