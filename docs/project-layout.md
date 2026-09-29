# 项目目录结构

游戏工程在 `movement_demo/`，说明文档集中在仓库的 `docs/`；仓库根目录仅保留 README 作为入口。脚本、场景与资源已按用途分类，移动时保留脚本 `.gd.uid` 和场景资源内的 UID。

```text
movement_demo/
├── project.godot          Godot 工程入口
├── scenes/
│   ├── main.tscn          主场景，F5 默认入口
│   ├── arena.tscn         战斗区域与敌人实例
│   ├── enemy/             可直接拖入竞技场的 enemy.tscn
│   ├── player/            玩家战斗、生命与武器槽场景
│   ├── world/             掩体、训练区域和墙体场景
│   └── ui/                对话界面场景
├── scripts/
│   ├── enemy/             身体、AI 协调、装配与评分入口
│   │   ├── actions/       默认行为、战术动作和共用动作执行组件
│   │   ├── config/        兵种、训练、动作定义及参数资源脚本
│   │   └── services/      感知、记忆、上下文、射击、搜索提示/覆盖和空间查询
│   ├── player/            玩家移动、战斗、生命和武器槽
│   ├── weapons/           武器数据与弹药执行
│   ├── world/             掩体、训练靶、区域、门和 NPC
│   ├── ui/                对话界面与锁定准星
│   ├── debug/             调试开关、声音和攻击点预览
│   └── systems/           公共游戏状态与声音数据
├── resources/
│   ├── enemy/
│   │   ├── actions/       可配置动作 .tres
│   │   ├── units/         兵种模板 .tres
│   │   └── training/      训练配置 .tres
│   ├── weapons/           玩家与敌人的武器 .tres
│   ├── noise/             移动声、枪声配置
│   ├── navigation/        烘焙导航资源
│   └── dialogue/          NPC 对话、导入元数据与原有剧情源文件
├── tests/
│   ├── enemy/             敌人测试、公共辅助和回归运行器
│   └── 其他系统测试与测试资源
├── addons/                编辑器插件及第三方依赖
└── logs/                  运行日志与验证输出，Git 忽略
```

新增运行脚本按职责放入对应目录；新增敌人动作实现放 `scripts/enemy/actions/`，其定义资源放 `resources/enemy/actions/`。测试或临时诊断不要放回工程根目录，也不要混入运行脚本目录。

`docs/enemy-ai.md` 是敌人结构、维护和使用部署说明；`docs/gameplay/` 保留移动、武器、掩体等专项说明，`docs/TODO.md` 记录后续方向，`docs/superpowers/` 保存仍有价值的设计与验收记录。第三方插件自带文档留在插件目录，以保留其使用说明和许可。

敌人配置与扩展见 [敌人 AI](enemy-ai.md)，验证入口见 [敌人测试](enemy-tests.md)，未完成方向见 [待办](TODO.md)。

整理目录只改文件位置和引用，不重设场景布局、武器数值或训练参数。`player_combat_v3.gd` 是当前玩家战斗实现，保留原文件名；已无引用的更早版本已删除。
