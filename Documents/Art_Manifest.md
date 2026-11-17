# 美术资产清单（Art_Manifest）

> 本文件跟踪实际生成的美术资产与审阅状态。
> 资产由 `Resources/ArtGen/ArtGen_Main.cpp` 生成，源文件输出到 `Resources/Art/`，运行时包为 `Resources/ArtPack.bin`。
> 修改生成器后必须重新生成，并更新本表与 `Agent_Mem.md`。

---

## 1. 生成信息

| 项目 | 值 |
| --- | --- |
| 生成器 | `Resources/ArtGen/ArtGen_Main.cpp` |
| 生成命令 | `Temp/ArtGen.exe Resources` |
| 输出目录 | `Resources/Art/` |
| 运行时包 | `Resources/ArtPack.bin`（FCPK v1） |
| 分辨率 | 1:1 像素，无缩放 |
| 随机种子 | 固定（保证可重复） |

---

## 2. 资产状态

> 状态：`已生成` / `已生成` / `已审阅` / `需修改`
> 审阅方式：查看 `Resources/Art/*.png` 或离屏截图。

### 2.1 瓷砖

| 资源名 | 尺寸 | 状态 | 备注 |
| --- | --- | --- | --- |
| `TILE_BAR_FLOOR_A/B/C` | 16×16 | 已生成 | 木地板 |
| `TILE_BAR_CARPET_A/B` | 16×16 | 已生成 | 暗红地毯 |
| `TILE_BAR_WALL_A/B` | 16×16 | 已生成 | 砖墙/护墙板 |
| `TILE_BAR_WALL_SHELF` | 16×16 | 已生成 | 酒架 |
| `TILE_BAR_WALL_WINDOW` | 16×16 | 已生成 | 暖光窗 |
| `TILE_STREET_FLOOR_A/B` | 16×16 | 已生成 | 湿沥青 |
| `TILE_STREET_WALL_A/B` | 16×16 | 已生成 | 外墙 |
| `TILE_STREET_CURB` | 16×16 | 已生成 | 路缘 |
| `TILE_HARBOR_FLOOR_A/B/C` | 16×16 | 已生成 | 水泥/油渍/警示线 |
| `TILE_HARBOR_WALL_A/B` | 16×16 | 已生成 | 钢板/锈墙 |
| `TILE_HARBOR_DOOR` | 16×16 | 已生成 | 卷帘门 |
| `TILE_VOID` | 16×16 | 已生成 | 纯黑 |

### 2.2 道具

| 资源名 | 尺寸 | 状态 | 备注 |
| --- | --- | --- | --- |
| `PROP_BAR_COUNTER` | 48×16 | 已生成 | 可拼接 |
| `PROP_BAR_SHELF` | 32×16 | 已生成 | 酒架 |
| `PROP_BOOTH` | 48×32 | 已生成 | 卡座 |
| `PROP_BOOTH_CURTAIN` | 16×32 | 已生成 | 门帘 |
| `PROP_TABLE_ROUND` | 16×16 | 已生成 | 圆桌 |
| `PROP_CHAIR` | 12×16 | 已生成 | 椅子 |
| `PROP_JUKEBOX` | 16×24 | 已生成 | 亮/暗 |
| `PROP_NEON_AFTERGLOW` | 80×16 | 已生成 | 招牌 |
| `PROP_DOOR` | 16×32 | 已生成 | 酒吧门 |
| `PROP_WINDOW_LIT` | 16×16 | 已生成 | 暖光窗 |
| `PROP_LAMP_PENDANT` | 16×16 | 已生成 | 吊灯 |
| `PROP_CRATE_S` | 16×16 | 已生成 | 小箱 |
| `PROP_CRATE_L` | 32×32 | 已生成 | 大箱 |
| `PROP_CARGO` | 32×24 | 已生成 | 任务货物 |
| `PROP_BARREL` | 16×20 | 已生成 | 油桶 |
| `PROP_CAR` | 48×24 | 已生成 | 车辆 |
| `PROP_CONTAINER` | 64×32 | 已生成 | 集装箱 |
| `PROP_FORKLIFT` | 24×20 | 已生成 | 叉车 |
| `PROP_ALARM_OFF/ON` | 16×16 | 已生成 | 警报灯两态 |
| `PROP_PART` | 12×12 | 已生成 | 零件 |
| `PROP_PUDDLE` | 32×8 | 已生成 | 水洼 |

### 2.3 角色

| 资源名 | 尺寸 | 状态 | 备注 |
| --- | --- | --- | --- |
| `CHAR_PLAYER_*` | 16×24 | 已生成 | 4 方向 × 4 帧 + 待机 |
| `CHAR_BIGSISTER_*` | 16×24 / 24×24 | 已生成 | 站姿/坐姿 |
| `CHAR_MERCHANT_*` | 16×24 / 24×24 | 已生成 | 站姿/坐姿 |
| `CHAR_BARTENDER_*` | 16×24 | 已生成 | 站姿 |
| `CHAR_SCAVENGER_*` | 16×24 | 已生成 | 敌人 |
| `CHAR_AGENT_*` | 16×24 | 已生成 | 敌人 |

### 2.4 头像与 UI

| 资源名 | 尺寸 | 状态 | 备注 |
| --- | --- | --- | --- |
| `PORTRAIT_PLAYER` | 48×48 | 已生成 | 小明 |
| `PORTRAIT_BIGSISTER` | 48×48 | 已生成 | 大美 |
| `PORTRAIT_MERCHANT` | 48×48 | 已生成 | 东子 |
| `PORTRAIT_BARTENDER` | 48×48 | 已生成 | 小帅 |
| `UI_TITLE_LOGO` | 240×64 | 已生成 | 标题 |
| `UI_TITLE_BG` | 480×270 | 已生成 | 标题背景 |
| `UI_ENDING_BG` | 480×270 | 已生成 | 结局背景 |
| `UI_ICON_*` | 12×12 | 已生成 | 图标组 |
| `UI_VIGNETTE` | 480×270 | 已生成 | 暗角 |
| `UI_SCANLINE` | 4×4 | 已生成 | 扫描线 |
| `UI_NOISE` | 64×64 | 已生成 | 噪点 |

### 2.5 特效

| 资源名 | 尺寸 | 状态 | 备注 |
| --- | --- | --- | --- |
| `FX_GLOW` | 64×64 | 已生成 | 加色光晕 |
| `FX_MUZZLE_0/1` | 16×16 | 已生成 | 枪口焰 |
| `FX_BULLET` | 6×2 | 已生成 | 子弹 |
| `FX_SPARK` | 4×4 | 已生成 | 火花 |
| `FX_BLOOD` | 4×4 | 已生成 | 血点 |
| `FX_SHELL` | 2×2 | 已生成 | 弹壳 |
| `FX_RAIN` | 2×8 | 已生成 | 雨丝 |
| `FX_SMOKE` | 8×8 | 已生成 | 烟雾 |
| `FX_ALARM` | 32×32 | 已生成 | 警报光 |
| `FX_PICKUP` | 16×16 | 已生成 | 拾取光圈 |

---

## 3. 审阅记录

| 日期 | 审阅者 | 范围 | 结论 | 修改项 |
| --- | --- | --- | --- | --- |
| 2026-11-17 | DeepSeek-V4.1-Flash | 接触表、角色预览、头像预览、标题预览 | 可用：角色轮廓/主色可区分，头像辨识度达标，标题氛围符合预期 | 修正角色预览布局；为拾荒者加护目镜；为大美加长发 |
| 2026-11-17 | DeepSeek-V4.1-Flash | 实机离屏截图：标题、街道、酒吧、仓库、对话、商店、日志、结局、死亡、暂停 | 通过：中文可读、图集无缺失、HUD/对话框布局可用 | 修复多行文字重叠；调整 HUD 透明度与场景出生点；移动卡座/招牌/车门；减少仓库警示区面积 |

### 3.1 最终资产统计

| 项目 | 数量/大小 |
| --- | --- |
| 运行时资产 | 195 项 |
| 角色帧 | 6 类 × 4 方向 ×（4 行走 + 1 待机），含大美/东子坐姿 |
| 头像 | 4 张（48×48） |
| 资产包 | `Resources/ArtPack.bin` ≈ 1.97 MB |
| 可审阅 PNG | `Resources/Art/*.png` |
| 总资源体积 | 约 12.8 MB（PNG + 包） |

---

## 4. 缺失与占位

- 若运行时找不到资源，渲染层使用 1×1 洋红占位纹理并写日志。
- 阶段性生成器可先输出占位图，但提交前必须替换为正式资产。
