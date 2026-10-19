class_name MedkitData
extends Resource

## 完整使用后恢复的生命值；只保存配置，不保存库存或使用进度。
@export_range(0.1, 10000.0, 0.1) var heal_amount: float = 50.0
## 一次完整医疗的秒数；开始时冻结本次参数，修改资源影响下次使用。
@export_range(0.05, 60.0, 0.05, "suffix:s") var use_seconds: float = 2.0
