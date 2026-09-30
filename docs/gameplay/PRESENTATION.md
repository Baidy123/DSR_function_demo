# 模型动画与命中特效接入

更新：2026-09-30。

接口已经接入玩家、敌人、NPC 和掩体。**所有模型、动画和特效默认留空，直接运行仍使用原胶囊、方块和敌人倒地效果。** 不需要添加素材才能继续试玩。现有移动、弹道、弹药、AI、对话与碰撞仍由原组件负责。

## 先看示例

打开 `res://scenes/presentation/presentation_preview.tscn`，按 F6。蓝色简单模型每两秒切换动作，右侧墙面显示命中粒子。这是接口演示，不是正式角色美术；不影响 F5 启动的主场景。

可复用的示例文件：

| 文件 | 用途 |
| --- | --- |
| `scenes/presentation/example_model.tscn` | 带 AnimationPlayer 的简单模型 |
| `resources/animations/example_actor.tres` | 示例动作对应表，包含冲刺 |
| `resources/effects/metal_example.tres` | 火花配置 |
| `scenes/effects/impact_sparks.tscn` | 粒子场景 |

## 给对象指定模型

| 对象 | 在场景树中选择 |
| --- | --- |
| 玩家 | Main → Player → Visual → Presentation |
| 敌人 | enemy.tscn → Presentation，或竞技场实例的对应节点 |
| NPC | Main → NPC → Presentation，NPCB 同理 |
| 掩体 | cover.tscn → Presentation，或地图中该实例的对应节点 |

在检查器的 **Model Scene** 指定自己的模型场景，或先拖入上面的 example_model.tscn。模型应以 Node3D 为根，只包含外观；不要带新的物理身体、碰撞体或导航节点。脚底对齐原点、朝向 -Z、Y 朝上最方便；需要补偿时调整 Presentation 自身的 Position、Rotation、Scale。掩体根在墙体中心附近，模型偏移按实际碰撞盒对齐。

只调整一个敌人或掩体时，在地图实例上启用可编辑子节点并保存实例覆盖。修改独立源场景会影响使用它的其他实例。动画或表面资源也是共享配置：只想修改一处时先复制资源或设为唯一。

运行时只有模型加载成功才隐藏旧占位外观。清空 Model Scene 会恢复旧外观。编辑器显示模型预览，但保留原占位 Mesh 的可见属性，避免把“预览时隐藏”误存为场景初态；因此编辑器里可能看到模型与占位外观重叠，运行时只保留模型。内部预览实例不写入场景。

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
| Hit | 有效受伤；换弹中不抢占换弹表现 | Hit |
| Dead | 死亡 | Death |
| Dialogue | 发起该次对话的 NPC、处于对话中的玩家 | Talk |
| Impact | 配置了命中表现路径的掩体被击中 | Impact |

敌人不新增冲刺战术，而是根据现有身体实际速度切换 Sprint；换弹限速、顶墙或停止后退出冲刺。移动倍率只调整动画播放，不改变身体速度。

没有冲刺片段时回退 Move；Move、Aim、Dialogue 缺失时回退 Idle。Fire、Hit、Impact 缺失时跳过。Reload 缺失时使用基础姿态，实际换弹照常。没有死亡片段的已配置模型采用挂点倒地；没有模型的敌人保留旧 Body 倒地。死亡后复位会恢复姿态和占位可见性。

换弹仍由 Ammo 计时和补弹。动画跟随快慢模式、50%阶段暂停及切枪续换，不通过动画结束信号补弹。第一版使用原地动作和单一播放器，不提供上下半身同时混合；AnimationTree、IK 和根运动可后续沿相同状态接口扩展。

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

新增公开通知：Enemy 的 shot_fired、died；Player Health 的 damage_applied、died；DialogueUI 的 dialogue_started、dialogue_ended（携带发起 NPC）；区域控制脚本的 presentation_reset。原有信号签名和 open_dialogue 三参数调用保持兼容。

VisualPresentation 的 `apply_state`、`play_event`、`reset_presentation` 是表现入口。动画实例及被动画修改的嵌套资源独立，轨道不能调用方法或指向模型之外的节点。动画不应直接改变武器、生命或碰撞。配置资源只保存静态设置，不保存播放进度。

DialogueUI 用会话标识拒绝旧异步结果，并在关闭、来源移除和卸载时清理。当前 Dialogue Manager 会在源台词字典注入资源自身；UI 在取得独立 DialogueLine 后移除该临时回链，避免结束对话后的资源循环，不改第三方插件源码。

运行表现回归：

```powershell
python movement_demo/tests/run_combat_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe presentation_interfaces_test presentation_movement_compatibility_test presentation_range_reset_test
```

编辑器预览与保存验证使用 `--headless --editor --path movement_demo --script res://tests/presentation_editor_test.gd`。其检查结果与编辑器自定义 SceneTree 退出时已有的 RID 提示分开记录。已有敌人和战斗回归见 [敌人测试](../enemy-tests.md)，完整结果见 [本次实施记录](../superpowers/plans/2026-09-30-presentation-interfaces.md)。
