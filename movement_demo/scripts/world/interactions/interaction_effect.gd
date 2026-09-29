extends Resource
class_name InteractionEffect

## 场景交互效果的抽象基类：每个子类只负责一件事，由 Interactable 按数组顺序调用。
## 效果只依赖 InteractionContext 注入的引用，不直接查找全局节点或具体系统。


func apply(_context: InteractionContext) -> void:
	push_warning("InteractionEffect 缺少 apply 实现：%s" % get_script().resource_path)
