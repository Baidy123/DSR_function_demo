# Resources 目录说明

> 本目录存放美术资产生成器、可审阅的 PNG 资产、运行时二进制包与资源脚本。
> 最终 exe 通过 `windres` 把 `ArtPack.bin` 以 RCDATA 嵌入，不依赖任何外部文件。

---

## 1. 目录结构

```text
Resources/
├─ ArtGen/
│  └─ ArtGen_Main.cpp     # 像素美术生成器（C++17，仅标准库）
├─ Art/
│  ├─ *.png               # 1:1 像素资产，供人工审阅
│  ├─ _ContactSheet.png   # 全资产接触表（自动生成）
│  ├─ _CharacterPreview.png
│  ├─ _PortraitPreview.png
│  └─ _TitlePreview.png
├─ ArtPack.bin            # FCPK v1 运行时资产包（BGRA8）
├─ Resources.rc           # windres 资源脚本
└─ README.md              # 本文件
```

---

## 2. 生成流程

本机可能没有 Python/PIL，因此生成器使用 C++ 编写，只依赖标准库。

```powershell
# 1. 编译生成器（不进入根 Makefile）
g++ -std=c++17 -O2 Resources\ArtGen\ArtGen_Main.cpp -o Temp\ArtGen.exe

# 2. 生成资产（从项目根目录运行）
.\Temp\ArtGen.exe Resources
```

产物：

- `Resources/Art/*.png`：RGBA8，PNG（无压缩 Deflate，体积较大但无依赖）。
- `Resources/ArtPack.bin`：运行时包，格式见下。
- 预览图：`Resources/Art/_*.png`，不进入运行时包。

> 生成器使用固定随机种子，重复运行结果一致。
> 修改生成器后必须重新生成，并更新 `Documents/Art_Manifest.md` 与 `Documents/Agent_Mem.md`。

---

## 3. FCPK v1 资产包格式

```text
Header (8 bytes):
  char[4] magic = "FCPK"
  uint16  version = 1
  uint16  count
Entry (44 bytes each):
  char[32] name        // ASCII 大写，0 填充
  uint16   width
  uint16   height
  uint32   dataOffset  // 从文件起始
  uint32   dataSize    // width * height * 4
Data:
  BGRA8，straight alpha，行优先
```

- 小端序。
- 名称以 `_` 开头的资产只写出 PNG，不进入包（预览图）。
- 运行时缺失资产时使用 1×1 洋红占位并写日志。

---

## 4. 资产命名

| 前缀 | 含义 | 示例 |
| --- | --- | --- |
| `TILE_` | 16×16 瓷砖 | `TILE_BAR_FLOOR_A` |
| `PROP_` | 场景道具 | `PROP_BOOTH`、`PROP_CARGO` |
| `CHAR_` | 角色精灵 | `CHAR_PLAYER_S_0` |
| `PORTRAIT_` | 48×48 头像 | `PORTRAIT_BIGSISTER` |
| `UI_` | 界面资源/图标 | `UI_ICON_AMMO`、`UI_TITLE_LOGO` |
| `FX_` | 特效 | `FX_MUZZLE_0`、`FX_GLOW` |

角色帧命名：`CHAR_<角色>_<方向>_<帧>`；方向为 `S/N/E/W`；帧为 `0..3`，`IDLE` 为待机帧。

---

## 5. 审阅与替换

1. 打开 `Resources/Art/_ContactSheet.png` 总览全部资产。
2. 角色与头像查看 `_CharacterPreview.png`、`_PortraitPreview.png`。
3. 标题画面查看 `_TitlePreview.png`。
4. 场景整体效果通过 `Tools/OffscreenTest` 的隐藏窗口截图验证。
5. 若只想替换单张 PNG，而不改生成器：替换后需要重新生成 `ArtPack.bin` 才能进入游戏；
   建议始终以生成器为唯一事实来源。

---

## 6. 约束

- 禁止在 RC、生成器、资产名中出现真机绝对路径或用户名。
- 资产名一律 ASCII 大写 + 下划线。
- PNG 与 `ArtPack.bin` 必须同时更新；两者不一致会导致游戏画面与审阅图不符。
- 不把 `Temp/ArtGen.exe` 或临时截图提交到仓库。
