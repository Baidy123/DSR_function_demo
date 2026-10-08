# 模型动画与命中特效接入

更新：2026-10-09。

接口已经接入玩家、敌人、NPC 和掩体。**角色模型、动画和特效默认留空，直接运行仍使用原胶囊、方块和敌人倒地效果；装备武器且未配置武器模型时，自动显示方块武器。** 不需要添加素材才能继续试玩。现有移动、弹道、弹药、AI、对话与碰撞仍由原组件负责。

## 先看示例

打开 `res://scenes/presentation/presentation_preview.tscn`，按 F6。蓝色简单模型每两秒切换动作，右侧墙面显示命中粒子。当前演示23种状态，包含蹲起、蹲姿战斗、翻越、下落和落地，手中使用方块武器；站高1.75米、蹲高1米。这是接口演示，不是正式角色美术；不影响 F5 启动的主场景。

可复用的示例文件：

| 文件 | 用途 |
| --- | --- |
| `scenes/presentation/example_model.tscn` | 带 AnimationPlayer、WeaponSocket 和23段示意动画的简单模型 |
| `resources/animations/example_actor.tres` | 示例动作对应表，包含蹲姿与翻越各阶段 |
| `scenes/presentation/weapon_placeholder.tscn` | 没有武器素材时使用的无碰撞方块 |
| `resources/effects/metal_example.tres` | 火花配置 |
| `scenes/effects/impact_sparks.tscn` | 粒子场景 |

## 给对象指定模型

| 对象 | 在场景树中选择 |
| --- | --- |
| 玩家 | Main → Player → Visual → Presentation |
| 敌人 | enemy.tscn → Presentation，或竞技场实例的对应节点 |
| NPC | Main → NPC → Presentation，NPCB 同理 |
| 掩体 | cover.tscn / low_cover.tscn → Presentation，或地图中该实例的对应节点 |

在检查器的 **Model Scene** 指定自己的模型场景，或先拖入上面的 example_model.tscn。模型应以 Node3D 为根，只包含外观；不要带新的物理身体、碰撞体或导航节点。脚底对齐原点、朝向 -Z、Y 朝上最方便；需要补偿时调整 Presentation 自身的 Position、Rotation、Scale。掩体根在墙体中心附近，模型偏移按实际碰撞盒对齐。

只调整一个敌人或掩体时，在地图实例上启用可编辑子节点并保存实例覆盖。修改独立源场景会影响使用它的其他实例。动画或表面资源也是共享配置：只想修改一处时先复制资源或设为唯一。

运行时只有模型加载成功才隐藏旧占位外观。清空 Model Scene 会恢复旧外观。编辑器显示模型预览，但保留原占位 Mesh 的可见属性，避免把“预览时隐藏”误存为场景初态；因此编辑器里可能看到模型与占位外观重叠，运行时只保留模型。内部预览实例不写入场景。

## 给武器指定模型

打开实际装备使用的 **WeaponData** 资源，例如 `resources/weapons/test_pistol.tres`，在 **武器外观** 分组设置：

| 配置栏 | 用途 |
| --- | --- |
| Visual Model | 可选的纯外观 Node3D 场景；留空显示方块 |
| Visual Position | 相对挂点的模型位置补偿 |
| Visual Rotation Degrees | 模型角度补偿，单位为度 |
| Visual Scale | 模型缩放补偿 |

武器场景不应带碰撞或导航节点；不合规场景会警告并回退方块。武器自己的自动动画播放器会停用，当前接口只负责模型挂载。上述补偿叠加在场景原根变换之前，不修改资源或真实武器参数。每个装备实例独立挂载，切换主副槽、更换敌人装备、卸装和复位都会更新外观；未装备时不显示方块。

角色的 **Presentation → Weapon Socket Path** 默认是相对于外部模型根的 `WeaponSocket`。正式角色可在手部骨骼下配置 `BoneAttachment3D`，将其路径填在这里；武器会跟随挂点的位置、方向和缩放。示例模型已经有该挂点。挂点不存在，或缺少蹲姿动画而回退胶囊时，使用原实际枪口高度加 **Weapon Mount Offset** 的默认持枪位置，跟随真实蹲起高度。角色模型已经自带武器时，关闭 **Show Weapon** 避免重复显示。没有手部挂点的占位角色死亡后隐藏武器，复位后恢复。

武器外观在运行时挂载，可用 F6 示例检查。**这些模型和挂点不决定射击起点、准度、近战碰撞、换弹时间或 AI 决策**；正式骨骼枪口与当前逻辑枪口的精确对齐属于后续美术接入工作。

## 给模型指定动作

模型本身需要有动画，或者已在包装场景中接入骨骼匹配的动画素材。接口负责播放，不能自动制作动作或转换不同骨骼。

1. **Animation Player Path** 填相对于模型根的播放器路径，默认 `AnimationPlayer`。静态模型可以留空。
2. **Animation Profile** 新建 `PresentationAnimationProfile`，或使用示例配置。
3. 在对应栏填写素材里的动画名称；有动画库前缀时填写完整名称，例如 `movement/Run`。

| 配置栏 | 何时自动播放 | 名称示例 |
| --- | --- | --- |
| Idle | 站立待机 | Idle |
| Move | 实际普通移动 | Walk |
| Sprint | 玩家冲刺、敌人实际快速移动 | Run |
| Aim | 原地瞄准 | Aim |
| Fire | 实际发射成功 | Shoot |
| Reload | 真实换弹，并跟随进度定位 | Reload |
| Melee | 玩家／敌人近战，跟随各自执行逻辑的前摇和收招进度 | Melee |
| Crouch / Crouch Move | 实际蹲姿／蹲行，缺片段时显示胶囊占位 | Crouch / CrouchWalk |
| Crouch Enter / Crouch Exit | 实际蹲下／起身过渡，跟随身体高度进度 | CrouchEnter / CrouchExit |
| Crouch Aim | 原地蹲姿瞄准 | CrouchAim |
| Crouch Fire | 蹲姿实际发射成功 | CrouchShoot |
| Crouch Reload | 蹲姿真实换弹，跟随 Ammo 进度 | CrouchReload |
| Crouch Hit | 蹲姿有效受伤，仍遵守动作占用规则 | CrouchHit |
| Vault | 翻越，时间位置跟随身体实际进度 | Vault |
| Vault Fall | 翻越受阻／受击后或末段实际下落，不沿用冻结的翻越进度 | VaultFall |
| Land / Crouch Land | 翻越实际落地时，按当时真实站姿／蹲姿选择 | Land / CrouchLand |
| Hit | 有效受伤；换弹中不抢占换弹表现 | Hit |
| Dead | 死亡 | Death |
| Dialogue | 发起该次对话的 NPC、处于对话中的玩家 | Talk |
| Impact | 配置了命中表现路径的掩体被击中 | Impact |

敌人不新增冲刺战术，而是根据现有身体实际速度切换 Sprint；换弹限速、顶墙或停止后退出冲刺。移动倍率只调整动画播放，不改变身体速度。

没有冲刺片段时回退 Move；Move、Aim、Dialogue 缺失时回退 Idle。Fire、Hit、Impact 缺失时跳过。Reload 缺失时使用基础姿态，实际换弹照常。没有死亡片段的已配置模型采用挂点倒地；没有模型的敌人保留旧 Body 倒地。死亡后复位会恢复姿态和占位可见性。

蹲姿与翻越快照使用 `crouch_amount`、`posture_transition`、`vaulting`、`vault_progress` 和 `vault_falling`。蹲下动画按实际蹲姿比例定位，起身按其反向进度定位；头顶受阻时停在真实高度，不让动画自行穿过天花板。实际蹲起优先于单播放器的开火、受击和落地片段，过渡中跳过这些一次性表现，真实伤害和发射仍照常。蹲姿瞄准、移动、换弹及过渡缺少专用片段时回退 Crouch，仍没有安全蹲姿片段则显示实际胶囊；蹲姿开火、受击和落地片段缺失时直接跳过，不播放对应站姿片段。`Crouch Move Reference Speed` 独立控制蹲行播放倍率。

Vault 跟随真实翻越进度，Vault Fall 在身体下落期间独立循环；缺少片段时显示胶囊，不冻结旧翻越帧。Land / Crouch Land 是可选通知，不负责解除攻击占用，也不会因没播完而推迟攻击。翻越优先于换弹和近战表现，死亡与对话仍优先。可复用的蹲姿模板为 `resources/models/crouch_capsule.tres`，各身体复制后驱动自己的实际高度，不能修改共享网格。

换弹仍由 Ammo 计时和补弹。动画跟随快慢模式、50%阶段暂停及切枪续换，不通过动画结束信号补弹。第一版使用原地动作和单一播放器，不提供上下半身同时混合；AnimationTree、IK 和根运动可后续沿相同状态接口扩展。

`Blend Seconds` 控制按时间播放的片段切换。蹲起、换弹、近战与正常翻越直接按真实进度定位，切入这些片段时不叠加时间混合，避免其计时冻结后停留在旧姿态；无需将整个配置的混合时间改成0。片段自身承担动作过程中的姿态变化，下落、移动和一次性事件仍按正常播放时间推进。

近战期间由 Melee 状态占用播放器；缺少片段时回退 Idle，游戏命中不受影响。出手位置在动画归一化时间的 `前摇 / (前摇 + 收招)`，默认约32.4%。`melee_active`、`melee_phase` 和 `melee_progress` 分别由玩家 Combat、敌人近战控制器提供；敌人适配器通过 `presentation_state()` 读取独立快照，不直接读取阶段字段或修改执行进度。死亡与对话优先于近战。无模型也会显示独立剑光，玩家在 Combat、敌人在 EnemyPresentation 上替换或关闭特效场景。见 [近战说明](MELEE.md)。

## 给掩体设置命中特效

选择掩体的 **ImpactReceiver**，在 **Profile** 中指定 `metal_example.tres`，即可在玩家或敌人的真实子弹撞到掩体时播放示例火花。

其他对象也可以使用同样的节点。对于墙壁或地面，在射线实际碰撞到的 StaticBody3D 下添加名为 `ImpactReceiver` 的 Node，挂载 `scripts/systems/effects/impact_receiver.gd`，再选择配置。

- Profile 留空：使用当前场景 ImpactEffects 的 Default Profile；主场景默认也为空，因此不播放。
- Enabled 关闭：这个对象不播放默认或专用的命中表现，伤害与碰撞照常。
- 不同表面：分别复制并配置不同的 ImpactProfile，例如金属、木头和石头。
- Presentation Path：相对于 Receiver 的可选路径。掩体已填 `../Presentation`；人物留空，避免与 Hit 动画重复。

主场景已放置一个 **ImpactEffects** 节点。单独运行新场景时可拖入 `scenes/effects/impact_effects.tscn`，保持节点名 ImpactEffects。射击代码向上查找最近祖先下的服务；不必给每个敌人加一个管理器。没有服务时只忽略特效。

管理器只接收实际射击的第一次碰撞结果，瞄准、AI 视线检查和近弹通知不会生成粒子。火花使用世界命中点和表面法线，不会跟着目标倒地。伤害与特效分别执行，未设置血量的墙也可有特效。

## 制作自己的特效场景

复制 impact_sparks.tscn 或新建 Node3D 场景，根节点挂 `scripts/systems/effects/impact_effect.gd`，再添加粒子。根节点局部 +Y 是从命中表面向外的方向。

新建 ImpactProfile，把特效场景填入 Effect Scene，Surface Offset 控制离表面的少量偏移，Max Lifetime 是超时回收上限。示例根脚本的 Duration 应覆盖所有粒子的可见寿命。自定义根脚本需提供 `start(event)` 和 `finished` 信号。

粒子在管理器下独立播放，完成或超时自动释放；默认最多64个活动实例，超过后回收最早实例。暂停时寿命与粒子一起暂停，离场复位只清理所属区域，重开随场景清理。音效、附着弹孔和掩体破坏不在本轮实现范围。

## 维护与验证

通用挂载、动画后端及状态类型放在 `scripts/systems/presentation/`；命中快照、表面配置与特效管理在 `scripts/systems/effects/`。玩家、敌人和 NPC 各自的 Presentation 适配器读取已有状态。敌人 AI 和战术模块不引用模型、素材名称或粒子。

`weapon_presentation.gd` 只负责装备外观的实例生命周期、挂点跟随及方块回退；配置保留在既有 `WeaponData`，由 `visual_presentation.gd` 消费状态中的 `weapon` 和相对本节点的 `weapon_mount_position`。它不读取 Ammo 或修改装备、身体、战术，原场景节点路径不变。

玩家与敌人身体公开 `get_posture_presentation_state()`，返回独立字典，包含 `amount`、`transition`、`vaulting`、`vault_progress`、`vault_falling`。敌人委托原 BodyMotion 服务生成；表现适配器不直接读取私有阶段字段。双方 `vault_landed` 无参信号仅在活体实际完成翻越落地时触发一次；开始、空中、死亡取消或复位不伪造落地通知。适配器先同步真实状态再提交 `play_event(&"land")`，由后端选择蹲姿／站姿片段。信号不控制物理和攻击许可。

新增公开通知：Enemy 的 shot_fired、died；Player Health 的 damage_applied、died；DialogueUI 的 dialogue_started、dialogue_ended（携带发起 NPC）；区域控制脚本的 presentation_reset。原有信号签名和 open_dialogue 三参数调用保持兼容。

VisualPresentation 的 `apply_state`、`play_event`、`reset_presentation` 是表现入口。动画实例及被动画修改的嵌套资源独立，轨道不能调用方法或指向模型之外的节点。动画不应直接改变武器、生命或碰撞。配置资源只保存静态设置，不保存播放进度。

压制仍复用真实 `shot_fired` 通知，不把 Utility 战术名称写进动画层。当前接口还未实现 AnimationTree 混合、IK、根运动或骨骼重定向。`NoiseData.audio_stream` 已留资源字段，但当前声音感知不播放该音频；不能将其视为已接入的脚步音效播放器。

DialogueUI 用会话标识拒绝旧异步结果，并在关闭、来源移除和卸载时清理。当前 Dialogue Manager 会在源台词字典注入资源自身；UI 在取得独立 DialogueLine 后移除该临时回链，避免结束对话后的资源循环，不改第三方插件源码。

运行表现回归：

```powershell
python movement_demo/tests/run_combat_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe presentation_interfaces_test presentation_movement_compatibility_test presentation_range_reset_test posture_animation_profile_test posture_animation_adapter_test weapon_presentation_test
```

编辑器预览与保存验证使用 `--headless --editor --path movement_demo --script res://tests/presentation_editor_test.gd`。其检查结果与编辑器自定义 SceneTree 退出时已有的 RID 提示分开记录。已有敌人和战斗回归见 [敌人测试](../enemy-tests.md)，完整结果见 [本次实施记录](../superpowers/plans/2026-09-30-presentation-interfaces.md)。
