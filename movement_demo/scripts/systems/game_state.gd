extends Node

# 本次运行共享的对话状态；重新运行游戏会重置。
var talked_to_a: bool = false
# 空字符串：尚未选择；accepted：答应；refused：拒绝。
var help_choice: String = ""
