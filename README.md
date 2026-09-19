# DSR_function_demo

使用 Godot 和 GDScript 制作的 3D 俯视角功能性 demo。

当前工程包含玩家移动与耐力、对话、枪械锁定与 3D 散射、训练靶、竞技场及敌人巡逻、感知、搜索和掩体走位。竞技场 AI 在玩家进入区域后运行，离场后刷新并等待再次进入。

## 打开工程

1. 使用本工程已验证的 Godot 4.7.2 标准版。
2. 在 Godot 项目管理器中导入 `movement_demo/project.godot`。
3. 等待资源和插件首次导入完成，按 F6 运行 Main，或按 F5 运行主场景。

所需的 Dialogue Manager、Phantom Camera 和 Godot AI 插件源码及各自许可证随工程保存。Godot 可执行程序、导入缓存和临时文件不纳入仓库。

## 项目说明

- [后续总待办](movement_demo/TODO.md)
- [操作与移动说明](movement_demo/README.md)
- [战斗说明](movement_demo/COMBAT.md)
- [竞技场说明](movement_demo/ARENA.md)
- [协作规则与进度](AGENTS.md)

部分带版本号的脚本保留为迭代记录；当前场景所用入口见总待办中的“当前代码入口”。
