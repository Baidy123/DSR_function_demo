# 余烬自由城 / Ember of Free City（`fish-dev` 分支）

一个**纯手写 3D 小 Demo**：C++17 + Win32 + Direct3D 11，没有引擎、没有第三方运行时库、没有任何图片或音频文件。
画面是复古低清多面体（low-poly）+ 像素化 CG，视觉方向参考 *SIGNALIS*：冷调环境 + 暖调实用光源 + 480×270 的内部渲染分辨率。

> 本分支（`fish-dev`）把早先的 2D 像素 Demo 整体重写为三维版本：几何由代码生成，道具是文本网格资产，美术零二进制。
> 只做本地提交，不向远端推送。

---

## 1. 现在能玩到什么

- 三个可玩场景：**酒吧外（雨夜街道）**、**余烬酒吧**、**铁港仓库**。
- 一条完整主线：进酒吧 → 接委托 → 找大美 → 找东子领装备 → 去铁港取货 → 清理公司特工 → 回酒吧交差 → 两个结局。
- 一条支线：修好酒吧的点唱机，需要去铁港捡回旧零件。
- 系统：商店、任务日志、暂停、死亡重试、对话逐字显示与选项、3D 头像、程序化音乐与音效。
- 固定机位按区域切换、雨与积水、警报红闪、受击染色、扫描线/抖动/暗角后处理。

---

## 2. 目录结构

```text
.
├─ Components/
│  ├─ Main/       入口、窗口生命周期、内嵌网格库装载
│  ├─ Shared/     基础类型、Mat4/Vec3 数学、碰撞与射线、日志
│  ├─ Platform/   Win32 窗口、输入、计时、RCDATA 读取
│  ├─ Render/     D3D11 设备、3D 管线、文本网格解析、SpriteBatch、文字纹理、后处理
│  ├─ World/      场景体块/道具/灯光/机位/交互、碰撞世界
│  ├─ Game/       角色骨架、渲染编排、剧情、任务、背包、商店、UI
│  └─ Audio/      程序化音乐与音效（waveOut）
├─ Documents/     规则、记忆、设计与验收文档
├─ Resources/
│  ├─ Meshes/Props/*.fcm   文本网格资产（UTF-8 + LF，可直接 diff）
│  └─ Resources.rc         以 RCDATA 把 .fcm 打进 exe
├─ Tools/         UnitTests / OffscreenTest（独立 Makefile）
├─ Makefile       只构建最终游戏
└─ Temp/          截图与临时文件（不入库）
```

---

## 3. 构建

需要 **MinGW-w64**（`x86_64-win32-seh-rev0`，GCC 16.1.0）+ **GNU Make 4.4**，无需其它依赖。

```powershell
make release -j4        # 产出 Build/Release/Target.exe（静态链接，单文件）
make debug -j4          # 产出 Build/Debug/Target.exe
```

产物约 1.4 MB，双击即可运行；着色器在运行时由系统的 `d3dcompiler_47.dll` 编译。

---

## 4. 操作

| 输入 | 动作 |
| --- | --- |
| `W A S D` | 相对相机移动 |
| `Shift` | 疾跑 |
| 鼠标 | 瞄准 |
| 鼠标左键 | 射击 |
| `R` | 换弹 |
| `E` | 交互 / 推进对话 / 确认选项 |
| `W` / `S`（对话中） | 切换选项 |
| `F` | 医疗包 |
| `Tab` | 任务日志 |
| `Esc` | 暂停 |
| `M` | 静音 |

---

## 5. 验证（无头，不抢鼠标键盘）

```powershell
make -C Tools                                            # 构建两个工具
& .\Tools\UnitTests\Build\UnitTests.exe                  # 纯逻辑单元测试
& .\Tools\OffscreenTest\Build\OffscreenTest.exe --flow   # 完整主线流程断言
& .\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar --ui dialogue
```

- 截图落在 `Temp/Screenshots/`，只写 `Temp/`，不进仓库。
- 当前基线：`UnitTests` **93/93**，`OffscreenTest --flow` **25/25**。

---

## 6. 资产策略

1. **零二进制**：仓库里没有 `.png`/`.wav`/`.ttf`/`.bin`。截图只在 `Temp/`。
2. 静态道具用文本网格 `.fcm` 描述（`box`/`bevel`/`cyl`/`cone`/`sphere`/`quad`/`tri` + 材质与程序化图案）。
3. 房间、墙面、家具等大体块直接写在 `Components/World/World_Scenes`。
4. 角色由 `Components/Game/Game_Characters` 用骨架 + 色块程序化生成。
5. 材质细节（砖、木纹、金属筋、锈、布料、混凝土）由着色器按世界坐标生成，不采样贴图。
6. 音频全部由代码合成，无音频文件。

---

## 7. 分支说明

| 分支 | 内容 |
| --- | --- |
| `master` / 远端分支 | 只作为参考，`fish-dev` 不合并、不推送、不改写 |
| `fish-dev` | 当前工作分支：三维重写、文本资产、纯程序化美术、Docs 全面对齐 3D |

- 提交身份仅在本工作区生效：`DeepSeek-V4.1-Flash <>`。
- 提交信息用简洁中文说明“改了什么 + 为什么”。

---

## 8. 文档

从 `Documents/Project_Rules.md` 开始，然后读 `Documents/Agent_Mem.md`（当前状态 / 下一步 / 已知问题）。
设计细节见 `Design_World`、`Design_Characters`、`Design_Art`、`Design_Gameplay`、`Design_Story`、`Design_Technical`，验收见 `Test_Plan`。
