# 剧情演出相机通用控制器设计

日期：2026-11-23

状态：设计已与用户确认，待实现。

## 1. 目标

建立场景级、单次播放的剧情演出相机控制器，统一承接剧情节点、SceneDirector、Wave 和调试面板的镜头请求，并在镜头结束后可靠恢复玩家相机。

本方案解决以下问题：

- 当前 Wave 出场镜头直接挂在 SceneDirector 的 presentation 流程中，缺少可独立复用的剧情镜头入口。
- 现有 `presentation_camera.gd` 只支持“复制玩家俯视视角后平移目标”，不能自由手摆机位、缩放和抖动。
- 剧情节点、调试工具和战斗增援需要共用同一套相机切换、暂停、取消和恢复规则。

## 2. 用户确认的边界

- 只管剧情演出相机。
- 玩家相机内部的 Phantom Camera 跟随、武器视野、切枪过渡和遮挡透明继续由现有玩家相机负责，不并入本控制器。
- 一次只播放一个 Shot，不做队列、连续分镜或自动接力。
- 忙时拒绝新请求，不打断当前 Shot。
- 每个 Shot 可配置是否暂停世界。
- 对话进行中可以播放镜头；镜头不关闭、不推进对话。
- 调试面板纳入本期方案。
- 单镜头必须支持机位、朝向、放大和抖动，不只支持平移。

## 3. 非目标

- 不重写 Phantom Camera 或修改插件源码。
- 不改变武器 Aim Range、玩家相机 Size/FOV 或遮挡透明参数。
- 不支持多镜头排队、时间线编辑、过场动画资源的连续切镜。
- 不支持多人分屏或同时使用多个活动相机。
- 不把镜头画面变化作为敌人视觉感知、命中或任务完成证据。

## 4. 当前基线

- 玩家相机 `Camera3D` 由 `player_camera.gd` 管理武器视野、过渡和遮挡适配，位置由 Phantom Camera 跟随。
- `presentation_camera.gd` 是非当前状态的第二台相机，由 SceneDirector 显式执行 `start_presentation()` 与 `advance_presentation()`，支持复制玩家视图、平移、停留和返回。
- SceneDirector 已是每场唯一的场景生命周期与暂停权威，管理死亡、加载、区域复位、前台请求和取消。
- Wave 只有在真实部署完成后发出 `wave_committed`，现有出场镜头在该边界之后启动。

## 5. 场景层级

```text
LevelRoot
├── Player
├── Camera3D                         # 玩家相机
├── SceneDirector
│   ├── CinematicCameraController    # 单 Shot 入口和状态机
│   │   └── PresentationCamera       # 运行时演出相机
│   ├── CinematicShots
│   │   ├── BossEntranceShot         # CinematicShot3D
│   │   └── WaveReinforcementShot
│   ├── Wave1
│   └── Wave2
└── ...
```

约束：

- 控制器必须是场景中可见的 SceneDirector 普通子节点，不能作为 SceneDirector 内部运行时核心节点的隐藏子节点。
- 控制器随 SceneDirector 和场景一起创建、释放。
- 不把控制器挂在 Wave、CombatZone 或玩家相机下。
- `PresentationCamera` 是控制器的子节点，但仍在同一 Viewport 内切换为当前相机。
- 不把 SceneDirector 外层节点设为 Always；镜头时钟由取得暂停令牌后的 SceneDirector 核心显式推进。

## 6. 组件职责

### 6.1 CinematicShot3D

新增 `class_name CinematicShot3D extends Camera3D`，编辑器可实例化。节点自身的 Transform 表示演出机位和朝向。

要求：

- `current = false`，不加入自动处理循环，不作为普通活动相机。
- 使用自身 Camera3D 属性描述目标构图和镜头参数。
- 加入 `cinematic_shot` 组，供控制器和调试面板枚举。
- 提供配置校验，不自动改变玩家的 Phantom 或武器相机参数。

建议导出字段：

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `enter_seconds` | 0.6 | 玩家画面过渡到 Shot 的时间 |
| `hold_seconds` | 1.2 | Shot 停留时间 |
| `return_seconds` | 0.6 | 返回玩家最新画面的时间 |
| `pause_world` | true | 是否取得独立暂停令牌 |
| `transition_easing` | Smooth | 进入和返回的缓动；首版提供 Linear、Smooth、Ease In、Ease Out、Ease In Out |
| `shake_enabled` | false | 是否叠加抖动 |
| `shake_position_amplitude` | Vector3(0.1, 0.05, 0.1) | 机位局部空间抖动幅度，单位米 |
| `shake_rotation_degrees` | Vector3(1.0, 1.0, 1.0) | 机位局部空间旋转抖动幅度 |
| `shake_frequency` | 12.0 | 基础噪声频率 |
| `shake_fade_in_seconds` | 0.15 | 抖动渐入时间 |
| `shake_fade_out_seconds` | 0.25 | 抖动渐出时间 |
| `shake_seed` | 0 | 可复现噪声种子 |

Shot 的投影、Keep Aspect、Size/FOV、裁剪、偏移、环境、Attributes 和 Compositor 从 Shot 节点复制为本次镜头目标值。无效时间和非有限数在开始前拒绝。

### 6.2 CinematicCameraController

新增场景级 Node：

- 公开 `play_shot()`、`cancel_shot()` 和只读状态查询。
- 维护单 Shot 状态机，业务上只有 IDLE 和一个 active Shot。
- 负责请求校验、busy 拒绝、与 SceneDirector 协作、状态信号和错误码。
- 缓存当前 Shot 的静态参数快照；播放中删除 Shot 节点时取消，而不是继续读取失效节点。
- 不直接写敌人、任务、对话、玩家生命或武器状态。

建议状态：

```text
IDLE -> ENTER -> HOLD -> RETURN -> IDLE
```

公开快照至少包含：

```gdscript
{
    "phase": &"idle" | &"enter" | &"hold" | &"return",
    "shot": Node or null,
    "request_id": int,
    "elapsed": float,
    "remaining": float,
    "pause_world": bool,
    "last_error": StringName,
}
```

建议信号：

```gdscript
signal shot_started(request_id: int, shot: CinematicShot3D)
signal shot_phase_changed(request_id: int, phase: StringName)
signal shot_finished(request_id: int, result: StringName)
```

公开调用接口：

```gdscript
func play_shot(shot: CinematicShot3D) -> Dictionary
func cancel_shot(reason: StringName = &"manual") -> bool
func get_snapshot() -> Dictionary
```

`play_shot()` 的返回结构：

```gdscript
{
    "accepted": bool,
    "request_id": int,          # 接受时大于0
    "result": StringName,       # started、busy、invalid_shot、no_source_camera
    "reason": StringName,
}
```

单 Shot 场景可等待 `shot_finished(request_id, result)`，无需轮询。拒绝请求不创建活动相机、不取得暂停，也不产生完成信号。

### 6.3 Cinematic Camera 执行器

保留 `scripts/systems/presentation_camera.gd` 和
`scenes/player/presentation_camera.tscn` 的路径、脚本 UID 和公开兼容接口，将其扩展为通用镜头执行器。

职责：

- 复制玩家相机当前可见 Transform、投影、环境、裁剪和镜头参数。
- 在 ENTER 阶段从玩家当前画面插值到 Shot 机位与镜头参数。
- 在 HOLD 阶段保持 Shot 构图并叠加抖动。
- 在 RETURN 阶段重新读取玩家最新画面，插值返回并恢复玩家相机。
- 维护唯一的遮挡材质写入所有权。
- 不自行开始 `_process`；只接受 SceneDirector/控制器显式推进。

旧接口 `start_presentation(source, focus, options, request_id)` 保留，以满足现有 Wave 配置和测试；内部转换为“平移兼容 Shot”。新的剧情流程使用 `CinematicShot3D`。

### 6.4 SceneDirector

SceneDirector 继续拥有场景控制权：

- 新增 `cinematic_shot` 请求类型，并把请求交给控制器执行。
- 根据 Shot 的 `pause_world` 取得或跳过暂停令牌。
- 死亡、加载、区域复位和卸载时先取消镜头，再处理其他终态。
- 镜头只允许与正在进行的对话并存；商店、普通交互、引导或其他前台请求存在时返回 `busy`，但镜头只释放自己的令牌。
- 镜头播放时不能打开普通暂停菜单。
- 保持镜头时钟在对话暂停期间可推进；死亡、加载失败和控制器离场时停止。

## 7. 数据流

### 7.1 剧情节点直接请求

```text
剧情节点
→ CinematicCameraController.play_shot(shot)
→ 校验 Shot 与当前玩家相机
→ 通过 SceneDirector 建立 cinematic_shot 请求
→ 可选取得暂停令牌
→ PresentationCamera 切入、进入、停留、返回
→ 恢复玩家相机并释放自己的令牌
```

剧情节点不直接调用 `PresentationCamera`，也不保存活动相机引用。

### 7.2 战斗波次触发

Wave 新增可选 `cinematic_shot_path`。执行顺序：

```text
敌人真实部署成功
→ 计算提交结果
→ 发出 wave_committed
→ Controller/CinematicCamera 建立镜头屏障
→ 公开 spawned 通知
```

出生失败、波次取消或 Shot 无效时不播放镜头，不回滚已经成功提交的敌人。

同一物理步多个 Wave 都请求镜头时，第一个取得单 Shot 所有权，其余因 `busy` 跳过镜头，不回滚敌人部署。

### 7.3 SceneFlowAction

增加 `PLAY_CINEMATIC_SHOT` 动作：

- Target Path 选择 `CinematicShot3D`。
- 等待 Shot 完成、取消或失败后继续后续 Action。
- 不自动生成敌人。
- busy 时该 Action 失败并报告原因，不把错误伪装为完成。

## 8. 镜头阶段与插值

### 8.1 ENTER

- 快照玩家相机当前 Transform 和可见镜头属性。
- 目标值为 Shot 节点的 Transform、投影、Size/FOV、裁剪与可见属性。
- Transform 使用配置缓动插值；正交 Size 或透视 FOV 同步插值，形成放大/缩小。
- 当 `enter_seconds = 0` 时立即到达 Shot。
- 抖动按渐入包络叠加，不修改基础目标 Transform。

### 8.2 HOLD

- 基础 Transform 和镜头参数固定在 Shot 值。
- 抖动按完整包络持续。
- 不自动旋转、不自动绕目标运动；需要动态构图时通过更换 Shot 节点实现，不加入首版自动路径。

### 8.3 RETURN

- 返回前刷新玩家相机最新跟随位置和武器视野，不能回到镜头开始前的旧画面。
- 从当前镜头画面插值到玩家最新 Transform 和镜头参数。
- 抖动按渐出包络关闭。
- 返回完成后才切回玩家相机并通知完成。
- `return_seconds = 0` 时立即恢复。

## 9. 抖动模型

- 使用连续、确定性的低频噪声，不使用每帧随机跳值。
- 位置与旋转都在镜头局部空间叠加，避免世界轴抖动构图不一致。
- 使用 `shake_seed` 生成可复现结果，便于截图和自动测试。
- 包络只控制幅度，不改变 Shot 的基础机位。
- 抖动不得写入 Shot、玩家相机或共享资源。
- 当源相机、Shot 或控制器失效时立即停止，不继续采样噪声。

## 10. 暂停与并发

- 控制器存在一个活动 Shot 时，新请求返回 `busy`。
- 不排队、不替换当前 Shot、不自动切换到下一条。
- `pause_world = true` 时取得 SceneDirector 的 `cinematic_shot` 暂停令牌。
- 对话已经暂停世界时，镜头仍可取得自己的令牌；两者独立释放。
- 商店、普通交互、引导或其他前台请求占用场景时，新镜头返回 `busy`。
- 镜头先结束不会解除对话暂停；对话先结束也不会解除镜头暂停。
- `pause_world = false` 时不取得暂停令牌，世界正常运行。
- 镜头播放时普通暂停菜单不可叠加。
- 显式 `cancel_shot()`、死亡、切场、区域复位、控制器卸载和调试取消走同一取消实现。

## 11. 结果与错误

外部可见结果：

| 结果 | 含义 |
| --- | --- |
| `completed` | ENTER、HOLD、RETURN 正常完成 |
| `cancelled` | 死亡、加载、区域复位、显式取消或卸载 |
| `busy` | 已有 Shot 播放，本次拒绝 |
| `invalid_shot` | Shot 类型、参数或时间无效 |
| `no_source_camera` | 没有可用的当前玩家相机 |
| `camera_lost` | 播放期间活动相机被外部系统切换 |
| `source_lost` | 玩家相机离树、删除或跨 Viewport |
| `failed` | 相机切入、显式推进或其他运行时错误 |

错误发生前不得半途进入暂停：

1. 先校验 Shot 和源相机。
2. 建立受管理请求。
3. 取得暂停令牌。
4. 切入运行相机。
5. 若切入失败，立即恢复并释放令牌。

## 12. 调试面板

在现有 DebugSettings 总开关下增加 `CinematicCameraDebug`：

- 自动枚举当前场景 `cinematic_shot` 组。
- 显示 Shot 名称、路径、pause_world、当前阶段和最近结果。
- 提供“播放”“取消”按钮。
- 忙时显示 busy，不自动覆盖已有镜头。
- Debug 关闭时不显示，不创建活动相机或暂停令牌。
- 面板只调用控制器公开接口，不直接改 PresentationCamera。

## 13. 文件与职责

```text
movement_demo/scripts/systems/cinematic/cinematic_shot_3d.gd
movement_demo/scenes/cinematic/cinematic_shot_3d.tscn
movement_demo/scripts/systems/cinematic/cinematic_camera_controller.gd
movement_demo/scenes/cinematic/cinematic_camera_controller.tscn
movement_demo/scripts/debug/cinematic_camera_debug.gd
movement_demo/scenes/debug/cinematic_camera_debug.tscn
movement_demo/scripts/systems/presentation_camera.gd
movement_demo/scenes/player/presentation_camera.tscn
```

`presentation_camera.gd/.tscn` 保留现有路径和 UID，扩展为通用执行器；其余文件新增。

SceneDirector、Wave 定义、SceneFlowAction 和测试清单按本设计增加接口，不迁移既有 Wave/Squad 或关卡节点路径。

## 14. 兼容与迁移

- 现有 Wave 的 `show_spawn_presentation`、`presentation_target_path`、移动/停留/返回时间和 Size 继续可用。
- 旧配置由当前 presentation 兼容路径执行，行为不回退。
- 新场景优先新增 `cinematic_shot_path`，由通用控制器执行。
- 两种配置同时存在时，`cinematic_shot_path` 优先；旧字段不重复播放。
- 已有 `presentation_camera.gd` 的公开接口和 UID 保留。
- 不迁移玩家相机场景、Phantom 节点路径和武器视野资源。

## 15. 验证

### 15.1 Shot 与控制器

- 所有阶段的时间边界、零时长和瞬时切镜。
- 正交 Size 与透视 FOV 插值。
- 抖动 seed 可复现、包络正确、取消后不再变化。
- busy 拒绝、不排队。
- 无效 Shot、没有源相机和切入失败不泄漏暂停。
- Shot 删除中取消，不访问失效引用。

### 15.2 相机接入

- 从玩家当前画面进入 Shot，不从错误旧画面跳变。
- Shot 镜头属性复制但不修改源相机和 Shot 资源。
- RETURN 对齐玩家最新画面和最新武器视野。
- 玩家相机仍是 Phantom 跟随，武器视野和遮挡逻辑不变。
- 真实渲染检查自由机位、放大和抖动构图。

### 15.3 特殊打断矩阵

每项同时检查镜头状态、当前相机、暂停令牌、鼠标状态和场景业务状态：

| 场景 | 预期 |
| --- | --- |
| 玩家在 ENTER／HOLD／RETURN 中死亡 | 取消镜头，恢复玩家相机，保留死亡暂停 |
| 切场景或加载开始 | 取消镜头，停止镜头时钟，不抢新场景相机 |
| 离开战斗区或区域复位 | 取消区域镜头，释放区域与镜头暂停令牌 |
| SceneDirector 或控制器卸载 | 取消、清理相机、订阅和暂停令牌 |
| 玩家相机离树、删除或不再是当前相机 | 结束镜头，不抢回相机所有权 |
| Shot 节点播放中被删除 | 取消当前镜头，不出现半初始化状态 |
| 播放中再次请求 Shot | 返回 busy，当前 Shot 保持，不排队 |
| 调试面板取消 | 与正式取消走同一路径 |
| 对话期间播放镜头 | 两者并存，镜头结束只释放自己的暂停 |
| 对话先结束、镜头仍播放 | `pause_world` 开启时世界继续由镜头暂停 |
| 镜头先结束、对话仍进行 | 世界继续由对话暂停，不提前恢复 |
| `pause_world=false` 时死亡或切场 | 仍取消镜头，不遗留相机偏移或抖动 |
| 出生失败或 Wave 取消 | 不创建空镜头，不取得暂停 |
| 同帧多个 Wave 请求镜头 | 第一个执行，其余 busy 跳过，敌人部署不回滚 |
| 开始前没有玩家相机 | 返回 no_source_camera，不取得暂停 |
| 外部系统抢先切换相机 | 镜头结束并放弃所有权，不覆盖外部相机 |
| 镜头期间请求暂停菜单 | 不叠开菜单 |
| RETURN 中玩家相机失效 | 安全取消，不访问失效相机 |

### 15.4 Wave 与场景编排

- Wave 只在真实生成成功后播放，公开 spawned 前建立镜头屏障。
- 出生点被占、部署失败和区域复位不创建空镜头。
- `PLAY_CINEMATIC_SHOT` 等镜头结束后才继续后续 Action。
- 镜头见到的敌人不产生 AI 感知证据。

### 15.5 调试面板

- Debug 开启后枚举当前场景 Shot。
- 播放、取消、busy、状态和错误显示正确。
- Debug 关闭、场景卸载和控制器取消后无残留面板、相机或暂停令牌。

## 16. 验收标准

- 剧情节点可以用一次公开调用播放任意手摆单镜头。
- Wave 可以在真实生成后播放同一类 Shot。
- 每个 Shot 可组合机位、朝向、Size/FOV 缩放、缓动和抖动。
- 单 Shot 忙时拒绝，不排队。
- 对话和镜头可并存，暂停令牌独立释放。
- 全部特殊打断矩阵通过，取消后没有相机或暂停所有权残留。
- 玩家 Phantom 跟随、武器视野和遮挡逻辑保持原行为。
- 旧 Wave 出场镜头配置继续可用，新 Shot 路径优先且不重复播放。
