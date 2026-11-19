# 余烬自由城 / Ember of Free City（`fish-dev` 分支）

一个**纯手写 3D 小 Demo**：C++17 + Win32 + Direct3D 11，没有引擎、没有第三方运行时库、没有任何图片或音频文件。
画面是复古低清多面体（low-poly）+ 像素化 CG，视觉方向参考 *SIGNALIS*：冷调环境 + 暖调实用光源。
场景在 720×405 的低分辨率目标上渲染，界面（文字与图标）则按窗口像素密度高清绘制。

> 三维版本：几何由代码生成，道具是文本网格资产，材质由着色器程序化生成，美术零二进制文件。

---

## 1. 现在能玩到什么

- 三个可玩场景：**酒吧外（雨夜街道）**、**余烬酒吧**、**铁港仓库**，每个场景都有家具、货架、招牌、灯具等成组道具。
- 一条完整主线：进酒吧 → 接委托 → 找大美 → 找东子领装备 → 去铁港取货 → 清理公司特工 → 回酒吧交差 → 两个结局。
- 一条支线：修好酒吧的点唱机，需要去铁港捡回旧零件。
- 系统：商店、任务日志、暂停、死亡重试、对话逐字显示与选项（按住 Ctrl 快进）、3D 头像、程序化音乐与音效。
- 战斗：手枪远程与徒手近战两套武器槽（滚轮切换），三类敌人（远程拾荒者、近战打手、公司特工）行为不同。
- 材质：木材、玻璃、哑光/抛光金属、塑料、纸箱、布料、陶瓷、皮革、积水等，靠反射模型与程序化图案区分。
- 区域机位切换 + 相机跟随、雨与积水、警报红闪、受击染色、扫描线/抖动/暗角后处理。

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

# 需要保留正在运行/正在测试的产物时，可以改输出文件名：
make release -j4 TARGET_FILE_NAME=TargetDev   # 产出 Build/Release/TargetDev.exe
```

产物约 1.4 MB，双击即可运行；着色器在运行时由系统的 `d3dcompiler_47.dll` 编译。

---

## 4. 操作

| 输入 | 动作 |
| --- | --- |
| `W A S D` | 相对相机移动 |
| `Shift` | 疾跑 |
| 鼠标 | 瞄准 |
| 鼠标左键 | 射击（空手时为近战出拳） |
| 鼠标滚轮 | 切换武器槽：手枪 / 空手 |
| `R` | 换弹 |
| `E` | 交互 / 推进对话 / 确认选项 |
| `W` / `S`（对话中） | 切换选项 |
| 按住 `Ctrl` 0.4 秒 | 快进对话（松开立即取消） |
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
& .\Tools\OffscreenTest\Build\OffscreenTest.exe --scene street --pose aim   # 检查举枪姿态
```

- 截图落在 `Temp/Screenshots/`，只写 `Temp/`，不进仓库。
- 当前基线：`UnitTests` **93/93**，`OffscreenTest --flow` **25/25**。

---

## 6. 资产策略

1. **零二进制**：仓库里没有 `.png`/`.wav`/`.ttf`/`.bin`。截图只在 `Temp/`。
2. 静态道具用文本网格 `.fcm` 描述（`box`/`bevel`/`cyl`/`cone`/`sphere`/`quad`/`tri` + `pattern` 图案 + `surface` 材质）。
3. 房间、墙面、家具等大体块直接写在 `Components/World/World_Scenes`，同样带图案与材质。
4. 角色由 `Components/Game/Game_Characters` 用分段骨骼 + 色块 + 材质程序化生成。
5. 材质区分靠反射模型而非贴图：`SurfaceMaterial` 决定高光宽度、金属感与环境反射，
   `SurfacePattern` 生成砖缝、木纹、纸箱褶皱、玻璃条纹等细节。
6. 音频全部由代码合成，无音频文件。

---

## 7. 分支说明

| 分支 | 内容 |
| --- | --- |
| `fish-dev` | 当前开发分支：三维重写、文本资产、程序化材质与美术 |
| 其它分支 | 历史版本，仅作参考 |

- 提交身份仅在本工作区生效：`DeepSeek-V4.1-Flash <>`。
- 提交信息用简洁中文说明“改了什么 + 为什么”。

---

## 8. 文档

从 `Documents/Project_Rules.md` 开始，然后读 `Documents/Agent_Mem.md`（当前状态 / 下一步 / 已知问题）。
设计细节见 `Design_World`、`Design_Characters`、`Design_Art`、`Design_Gameplay`、`Design_Story`、`Design_Technical`，验收见 `Test_Plan`。
