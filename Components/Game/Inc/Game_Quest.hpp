#ifndef __GAME_QUEST_HPP__
#define __GAME_QUEST_HPP__

#include <cstdint>
#include <string>

namespace fc {

/**
 * @brief 主线阶段。
 */
enum class MainStage : std::uint8_t {
    ENTER_BAR = 0,
    TALK_BARTENDER = 1,
    TALK_BIGSISTER = 2,
    GET_GEAR = 3,
    GO_WAREHOUSE = 4,
    FIND_CARGO = 5,
    DEFEAT_AGENTS = 6,
    RETURN_BAR = 7,
    COMPLETE = 8
};

/**
 * @brief 点唱机支线阶段。
 */
enum class SideStage : std::uint8_t {
    NOT_STARTED = 0,
    ACCEPTED = 1,
    HAVE_PART = 2,
    COMPLETED = 3,
    DECLINED = 4
};

/**
 * @brief 任务状态与一次性事件标记。
 */
struct QuestState {
    MainStage main = MainStage::ENTER_BAR;
    SideStage side = SideStage::NOT_STARTED;
    bool cargoTaken = false;
    bool ambushTriggered = false;
    bool agentsCleared = false;
    bool jukeboxRepaired = false;
    bool starterKitGiven = false;
};

/**
 * @brief 主线目标文本。
 * @param [IN] quest 任务状态。
 * @return UTF-8 目标文本。
 */
std::string MainObjective(const QuestState& quest);

/**
 * @brief 支线目标文本。
 * @param [IN] quest 任务状态。
 * @return UTF-8 目标文本；不显示支线时返回空串。
 */
std::string SideObjective(const QuestState& quest);

/**
 * @brief 支线是否应显示在日志中。
 * @param [IN] quest 任务状态。
 * @return 显示返回 true。
 */
bool IsSideQuestVisible(const QuestState& quest);

/**
 * @brief 主线是否已完成。
 * @param [IN] quest 任务状态。
 * @return 完成返回 true。
 */
bool IsMainQuestComplete(const QuestState& quest);

} // namespace fc

#endif // __GAME_QUEST_HPP__
