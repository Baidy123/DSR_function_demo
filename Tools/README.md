# Tools 目录说明

> 本目录只用于放置**验证工具**。每个工具都有自己的 `Inc/`、`Src/`，并通过 `Tools/Makefile` 编译。
> 工具**不参与**最终游戏产物的构建；根 `Makefile` 永远只构建游戏本体。
>
> **默认只做针对性测试，不要每次运行全部工具。**
> 只有用户明确要求“跑一遍所有测试”时，才执行全量验证。

---

## 1. 目录结构

```text
Tools/
├─ Makefile                          # 工具统一构建入口
├─ README.md                         # 本文件
├─ UnitTests/
│  ├─ Inc/UnitTests_Config.hpp
│  └─ Src/UnitTests_Main.cpp
└─ OffscreenTest/
   ├─ Inc/OffscreenTest_Config.hpp
   └─ Src/OffscreenTest_Main.cpp
```

构建产物输出到 `Tools/<工具>/Build/`，已被 `.gitignore` 忽略。
临时截图与报告统一写到 `Temp/`，禁止写入 `Tools/`。

---

## 2. 工具清单

| 工具 | 用途 | 依赖 D3D | 产物 | 状态 |
| --- | --- | --- | --- | --- |
| `UnitTests` | 纯逻辑测试：数学、背包、任务、对话、剧情数据完整性 | 否 | `Tools/UnitTests/Build/UnitTests.exe` | 已实现，68/68 通过 |
| `OffscreenTest` | 隐藏窗口渲染真实场景/界面并截图；`--flow` 跑完整主线 | 是 | `Tools/OffscreenTest/Build/OffscreenTest.exe` + `Temp/Screenshots/*.bmp` | 已实现，截图与 25/25 流程通过 |

---

## 3. 构建

在项目根目录执行：

```powershell
# 构建全部工具
make -C Tools

# 只构建单元测试
make -C Tools unit

# 只构建离屏截图/流程测试
make -C Tools offscreen
```

---

## 4. UnitTests

```powershell
.\Tools\UnitTests\Build\UnitTests.exe
```

覆盖范围：

- `Shared_Math`：向量长度、零向量归一化、clamp、lerp、圆-矩形相交、方向角。
- `Game_Inventory`：购买成功/失败、余额不足、弹药上限、医疗包上限、使用医疗包、装填、初始装备。
- `Game_Quest`：主线目标文本、完成状态、支线可见性与文本。
- `Game_Dialogue`：线性推进、打字机完成、选项光标与跳转、节点事件。
- `Game_Story`：全部对话节点/选项索引合法性、头像名合法性、结局分支事件完整性。

输出格式：逐项 `[PASS]/[FAIL]`，最后打印汇总；失败返回非 0。

当前结果：

```text
PASSED: 68  FAILED: 0
```

### 线上测试流程

1. 修改纯逻辑代码后构建 `UnitTests`。
2. 运行并确认退出码为 0。
3. 失败时阅读 `[FAIL]` 行，修复逻辑或测试。
4. 将结果记录到 `Documents/Agent_Mem.md` 的“验证记录”。

---

## 5. OffscreenTest

### 5.1 截图

```powershell
# 标题
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene title --out Temp\Screenshots\title.bmp --frames 60

# 酒吧外
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene street --out Temp\Screenshots\street.bmp --frames 100

# 酒吧内
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar --out Temp\Screenshots\bar.bmp --frames 100

# 铁港仓库
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene harbor --out Temp\Screenshots\harbor.bmp --frames 100

# 对话（含选项）
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar --ui dialogue --out Temp\Screenshots\dialogue.bmp --frames 220

# 商店 / 日志 / 结局 / 死亡 / 暂停
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar --ui shop --out Temp\Screenshots\shop.bmp
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar --ui journal --out Temp\Screenshots\journal.bmp
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene title --ui ending --out Temp\Screenshots\ending.bmp
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene harbor --ui death --out Temp\Screenshots\death.bmp
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar --ui pause --out Temp\Screenshots\pause.bmp
```

参数：

| 参数 | 说明 |
| --- | --- |
| `--scene title/street/bar/harbor` | 场景；`title` 不加载世界 |
| `--ui none/dialogue/shop/journal/ending/death/pause` | 界面状态 |
| `--out <path>` | 输出 BMP；默认 `Temp/Screenshots/<scene>_<ui>.bmp` |
| `--frames <N>` | 推进帧数，默认 150 |
| `--assets <path>` | 资产包路径，默认 `Resources/ArtPack.bin` |
| `--choice wait` | 结局选择“再等等”（默认“我接”） |
| `--flow` | 运行完整主线流程测试，不截图 |

### 5.2 完整主线流程测试

```powershell
.\Tools\OffscreenTest\Build\OffscreenTest.exe --flow
```

验证项（25 项）：

- 开场独白、进入酒吧、酒保/大美/东子的对话推进。
- 支线接受、商店打开、初始装备发放。
- 离开酒吧、上车、抵达铁港、拾取点唱机零件。
- 搬起货物、触发伏击、击退特工、返回酒吧。
- 支线完成、主线交差、结局选择“我接”、奖励发放。

当前结果：

```text
Flow summary: PASSED=25 FAILED=0
```

### 5.3 约束

- 窗口以 `SW_HIDE` 创建，不显示、不抢焦点。
- 不调用 `SetForegroundWindow`、`SetCursorPos`、`SendInput`。
- 工具启动时音频静音，避免测试发声。
- 临时文件只写 `Temp/`。
- BMP 可直接用图片查看器打开；如需 PNG，可用任意转换工具。

---

## 6. 新增工具登记模板

```markdown
| 工具名 | 一句话用途 | 是否依赖 D3D | 产物路径 | 运行命令 |
| --- | --- | --- | --- | --- |

### 工具名

- **用途**：
- **输入**：
- **输出**：
- **构建**：`make -C Tools <target>`
- **运行**：`.\Tools\<工具>\Build\<工具>.exe ...`
- **注意事项**：
```

---

## 7. 常见问题

| 问题 | 处理 |
| --- | --- |
| `make -C Tools` 找不到 g++ | 确认 MinGW `bin` 在 PATH 中 |
| 截图全黑 | 确认从项目根目录运行，`Resources/ArtPack.bin` 存在；检查 D3D 设备初始化日志 |
| 中文显示为方块 | 检查系统字体与 UTF-8 解码 |
| 测试工具抢占焦点 | 立即停止；检查是否误用了 `ShowWindow`/`SetForegroundWindow` |
| `--flow` 失败 | 先看首个 `[FAIL]` 行；通常是对话事件/商店上下文/场景切换状态 |
