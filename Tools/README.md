# Tools 目录说明

> 本目录只用于放置**验证工具**。每个工具必须有自己的 `Inc/`、`Src/`，并通过 `Tools/Makefile` 编译。
> 工具**不参与**最终游戏产物的构建；根 `Makefile` 永远只构建游戏本体。
>
> **默认只做针对性测试，不要每次运行全部工具。**
> 只有用户明确要求“跑一遍所有测试”时，才执行全量验证。

---

## 目录结构

```text
Tools/
├─ Makefile                 # 工具统一构建入口
├─ README.md                # 本文件（新增/修改工具后必须更新）
├─ UnitTests/
│  ├─ Inc/
│  └─ Src/UnitTests_Main.cpp
└─ OffscreenTest/
   ├─ Inc/
   └─ Src/OffscreenTest_Main.cpp
```

每个工具的构建产物输出到 `Tools/<工具>/Build/`（已在 `.gitignore` 中忽略）。

---

## 工具清单

| 工具 | 用途 | 是否依赖 D3D | 产物 | 状态 |
| --- | --- | --- | --- | --- |
| `UnitTests` | 纯逻辑单元测试：数学、背包、任务、对话数据 | 否 | `Tools/UnitTests/Build/UnitTests.exe` | 规划中 |
| `OffscreenTest` | 隐藏窗口渲染真实场景并截图，用于无头视觉验收 | 是 | `Tools/OffscreenTest/Build/OffscreenTest.exe` + `Temp/Screenshots/*.bmp` | 规划中 |

> 新增工具时必须在此表登记：用途、依赖、产物路径、运行方式、注意事项。

---

## 构建与运行

```powershell
# 构建全部工具（仅在需要时）
make -C Tools

# 只构建某个工具
make -C Tools unit
make -C Tools offscreen

# 运行单元测试（无窗口、无输入占用）
.\Tools\UnitTests\Build\UnitTests.exe

# 生成指定场景截图（隐藏窗口，不抢焦点）
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene bar   --frames 120
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene street --frames 120
.\Tools\OffscreenTest\Build\OffscreenTest.exe --scene harbor --frames 120
```

截图输出目录：`Temp/Screenshots/`（不入库）。

---

## 单元测试流程

1. 修改纯逻辑代码后，先构建 `UnitTests`。
2. 运行 `UnitTests.exe`，确认输出 `[PASS]` 且退出码为 0。
3. 若失败：
   - 阅读失败用例的输入/期望/实际；
   - 修复逻辑或测试；
   - 重新运行，直到全部通过。
4. 将结果记录到 `Documents/Agent_Mem.md` 的“验证记录”。

### 测试覆盖范围

- `Shared_Math`：向量、clamp/lerp、AABB、距离。
- `Game_Inventory`：购买、余额不足、上限、消耗。
- `Game_Quest`：主线/支线阶段推进、任务文本。
- 对话数据：节点跳转索引有效、事件覆盖、说话人存在。

### 不在单元测试范围

- D3D11 渲染、窗口消息、音频输出、字体渲染。
- 这些通过 `OffscreenTest` 或手动实机验证。

---

## 离屏截图流程

1. 确保游戏资源已生成：`Resources/ArtPack.bin` 存在。
2. 构建 `OffscreenTest`。
3. 运行指定场景：
   - 工具创建 `SW_HIDE` 窗口，初始化真实渲染管线；
   - 以固定步长推进逻辑，渲染 N 帧；
   - 将最终帧读回为 BMP，写入 `Temp/Screenshots/`。
4. 使用图片查看器或视觉工具审阅截图。
5. 若画面异常，优先检查：
   - 资产包是否最新；
   - 场景 ID 与相机是否匹配；
   - 文字纹理是否创建失败；
   - 采样器是否为 Point。

### 约束

- 不得调用 `SetForegroundWindow`、`SetCursorPos`、`SendInput`。
- 不得弹出控制台窗口（GUI 子系统）。
- 不得将临时文件写入 `Tools/` 或仓库根目录，统一写 `Temp/`。
- 若隐藏窗口的 swapchain 读回失败，改用离屏 RTV 模式（工具内备选）。

---

## 新增工具登记模板

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

## 常见问题

| 问题 | 处理 |
| --- | --- |
| `make -C Tools` 找不到 g++ | 确认 MinGW `bin` 在 PATH 中 |
| 截图全黑 | 检查是否在 Present 后读回；检查资源包是否加载 |
| 中文显示为方块 | 检查字体回退与 UTF-8 解码 |
| 测试工具抢占焦点 | 立即停止，检查是否误用了 `ShowWindow`/`SetForegroundWindow` |
