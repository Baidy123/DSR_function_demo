class_name StageDefinition
extends Resource

## 一个任务阶段的定义：只描述阶段本身（第几个任务、对应哪个任务、目标场地），
## 不保存运行进度；进度由控制器实例持有。

## 阶段序号，从 1 开始；任务一完成、任务二配置好以后，推进条件会让它变成 2。
@export var index: int = 1
## 记录与界面显示的名字，例如“任务一”。
@export var display_name: String = ""
## 该阶段对应的任务 id，需与 QuestDefinition.id 一致；留空表示本阶段没有任务。
@export var quest_id: StringName = &""
## 该阶段任务场地的标识，例如 arena / site_2，供记录与后续场景切换使用。
@export var target_area: StringName = &""
## 给配置者看的备注，不参与运行。
@export_multiline var note: String = ""
