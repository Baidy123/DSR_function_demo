class_name StagePhase
extends RefCounted

## 阶段环节：同一个任务内固定按这五步循环，供阶段控制器、配置表和记录共用。
## 环节只描述“循环走到哪一步”，第几个任务由 StageController 的阶段序号表示。

enum Id {
	TAVERN_IDLE, ## 酒馆待命：还没有接取本阶段任务
	QUEST_TAKEN, ## 已接任务：任务进行中，玩家尚未离开酒馆
	TRAVELING, ## 前往场地：已经离开酒馆，还没有到达任务场地
	IN_SITE, ## 场地战斗：玩家位于任务场地内
	RETURNED, ## 返回结算：已经离开场地，等待结算或进入下一阶段
}

const NAMES: Dictionary = {
	Id.TAVERN_IDLE: "酒馆待命",
	Id.QUEST_TAKEN: "已接任务",
	Id.TRAVELING: "前往场地",
	Id.IN_SITE: "场地战斗",
	Id.RETURNED: "返回结算",
}


## 记录与界面使用的环节名；未知值回退为占位文本。
static func name_of(id: int) -> String:
	return NAMES.get(id, "未知环节")
