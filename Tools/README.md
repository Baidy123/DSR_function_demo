# Tools 目录说明

> 本目录只放**验证工具**。每个工具都有自己的 `Inc/`、`Src/`，并通过 `Tools/Makefile` 编译。
> 工具**不参与**最终游戏产物的构建；根 `Makefile` 永远只构建游戏本体。
> **默认只做针对性测试**，只有用户明确要求“跑一遍所有测试”时才全量执行。

---

## 1. 目录结构

```text
Tools/
├─ Makefile                      # 工具统一构建入口
├─ README.md                     # 本文件
├─ UnitTests/
│  ├─ Inc/UnitTests_Config.hpp
│  └─ Src/UnitTests_Main.cpp
└─ OffscreenTest/
   ├─ Inc/OffscreenTest_Config.hpp
   └─ Src/OffscreenTest_Main.cpp
```

构建产物输出到 `Tools/<工具>/Build/`（已被 `.gitignore` 忽略）。
截图与临时文件统一写 `Temp/`，禁止写入 `Tools/` 或仓库根目录。

---

## 2. 工具清单

| 工具 | 用途 | 依赖 D3D | 产物 |
| --- | --- | --- | --- |
| `UnitTests` | 纯逻辑测试：数学、碰撞、背包、任务、对话、剧情数据完整性 | 否 | `Tools/UnitTests/Build/UnitTests.exe` |
| `OffscreenTest` | 隐藏窗口渲染真实场景/界面并截图；`--flow` 跑完整主线 | 是 | `Tools/OffscreenTest/Build/OffscreenTest.exe` + `Temp/Screenshots/*.bmp` |

当前基线：`UnitTests` **93/93**，`OffscreenTest --flow` **25/25**。

---

## 3. 构建

在项目根目录执行：

```powershell
# 构建全部工具
make -C Tools

# 只构建单元测试
make -C Tools unit

# 只构建离屏测试
make -C Tools offscreen

# 清理产物
make -C Tools clean
```

---

## 4. 运行

### 4.1 UnitTests

```powershell
& .\Tools\UnitTests\Build\UnitTests.exe
```

- 输出 `[PASS]/[FAIL]` 列表与汇总；有失败时退出码非 0。
- 不创建窗口、不初始化 D3D、不读资源文件。

### 4.2 OffscreenTest

```powershell
# 默认：标题界面
& .\Tools\OffscreenTest\Build\OffscreenTest.exe

# 指定场景与界面
& .\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar --ui dialogue --out Temp/Screenshots/bar_dialogue.bmp
```

| 参数 | 取值 | 说明 |
| --- | --- | --- |
| `--scene` | `title` / `street` / `bar` / `harbor` | 载入指定场景 |
| `--ui` | `none` / `dialogue` / `shop` / `journal` / `ending` / `death` / `pause` | 切换到指定界面 |
| `--choice` | `accept` / `wait` | 结局分支（配合 `--ui ending`） |
| `--pose` | `none` / `aim` / `melee` / `walk` | 角色姿态：举枪、近战出拳或原地行走 |
| `--frames` | 正整数 | 推进帧数，默认 150 |
| `--out` | 路径 | 截图输出，默认 `Temp/Screenshots/<scene>_<ui>.bmp` |
| `--meshes` | 目录 | 文本网格目录，默认 `Resources/Meshes/Props` |
| `--flow` | 无 | 跑完整主线流程并断言，不截图 |

`OffscreenTest` 直接读取 `Resources/Meshes/Props/*.fcm` 并拼接成网格库，所以改完 `.fcm` 重新运行即可看到效果，不需要重新编译 exe。

---

## 5. 注意事项

1. 两个工具都必须**无头**运行：不创建可见窗口、不抢焦点、不抓屏、不移动鼠标。
2. 截图一律写 `Temp/`，不允许写进 `Tools/` 或仓库根目录。
3. 新增工具时：建 `Inc/` + `Src/`，在 `Tools/Makefile` 里加目标，并同步更新本文件与 `Documents/Test_Plan.md`。
4. 工具里可以用 `GameApp` 的 `Debug*` 钩子，但正式玩法路径不得依赖这些钩子。
5. 修改渲染相关代码后，至少跑一次 `--scene bar --ui dialogue`、`--scene street --pose aim`
   与 `--flow`，确认 UI、角色姿态与流程不回归。
