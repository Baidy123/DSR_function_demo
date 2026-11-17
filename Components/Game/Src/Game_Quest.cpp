#include "Game_Quest.hpp"

namespace fc {

std::string MainObjective(const QuestState& quest)
{
    switch (quest.main) {
    case MainStage::ENTER_BAR:
        return "进入余烬酒吧";
    case MainStage::TALK_BARTENDER:
        return "向酒保打听大姐头";
    case MainStage::TALK_BIGSISTER:
        return "去最里侧的卡座找大美";
    case MainStage::GET_GEAR:
        return "找东子领取装备并购买补给";
    case MainStage::GO_WAREHOUSE:
        return "前往铁港仓库取回货物";
    case MainStage::FIND_CARGO:
        return "在仓库里找到大姐头的货物";
    case MainStage::DEFEAT_AGENTS:
        return "击退公司特工";
    case MainStage::RETURN_BAR:
        return "带着货物返回余烬酒吧";
    case MainStage::COMPLETE:
        return "委托完成";
    default:
        return "委托完成";
    }
}

std::string SideObjective(const QuestState& quest)
{
    switch (quest.side) {
    case SideStage::NOT_STARTED:
        return "";
    case SideStage::ACCEPTED:
        return "在铁港仓库找到点唱机零件";
    case SideStage::HAVE_PART:
        return "把旧零件交给小帅";
    case SideStage::COMPLETED:
        return "点唱机已经修好";
    case SideStage::DECLINED:
        return "小帅自己去了仓库";
    default:
        return "";
    }
}

bool IsSideQuestVisible(const QuestState& quest)
{
    return quest.side != SideStage::NOT_STARTED;
}

bool IsMainQuestComplete(const QuestState& quest)
{
    return quest.main == MainStage::COMPLETE;
}

} // namespace fc
