# 项目内的兼容补丁

当前随工程保存的 Dialogue Manager 版本为 `plugin.cfg` 标记的 4.1.0。上游许可证保持在原 `LICENSE`。

2026-10-13：`utilities/dialogue_cache.gd` 的 `_get_dialogue_files_in_filesystem()` 在递归进入目录前检查 `.gdignore`。原扫描只跳过 `.godot` 和 `.tmp`，会把 `logs/` 下的验证副本加入对话缓存，再由 `plugin.gd` 自动写入项目翻译源列表。补丁保留普通子目录、原扩展名规则和原有排除项。

升级插件时核对上游是否已尊重 `.gdignore`，然后运行 `res://tests/dialogue_cache_test.gd`。专项检查正常文件、忽略目录及嵌套内容、直接扫描忽略目录、移除标记后的重新发现和不存在目录。另用带 `logs/.gdignore` 的验证副本启动编辑器，确认翻译源列表不会重新登记日志内对话。
