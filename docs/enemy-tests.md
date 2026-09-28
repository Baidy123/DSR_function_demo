# 敌人测试与诊断

此目录集中保存敌人验证脚本、测试辅助和运行器；游戏主场景不加载这里的测试。运行代码说明见 [敌人模块化 AI](enemy-ai.md)。

## 当前回归

在仓库根目录运行：

```powershell
python movement_demo/tests/enemy/run_enemy_regressions.py --godot E:/Godot/Godot_v4.7.2-stable_win64_console.exe
```

运行器 `TESTS` 列出当前 16 套正式回归。末尾可指定测试名（不含 `.gd`）。日志固定写入 `movement_demo/logs/enemy_regressions/`，同名结果覆盖。

`enemy_fire_fixture.gd` 是公共辅助，`modular_probe_action.gd` 验证动态扩展；二者不单独运行。检查器使用编辑器模式：

```powershell
& E:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --editor --path E:/Godot/movement_demo --script res://tests/enemy/enemy_training_inspector_test.gd
```

## 其他专项脚本

其他文件保留武器执行、地图几何、历史行为检查或复现场景。部分仍使用旧接口，未全部迁移或复测，不属于上述 16 套通过结果。使用前核对入口，不应将扫描整个目录当作当前统一测试集。

已被替代的旧结构迁移、固定优先级、旧权限测试和性能探针已删除，见 [实施记录](superpowers/plans/2026-09-29-enemy-modular-ai.md)。
