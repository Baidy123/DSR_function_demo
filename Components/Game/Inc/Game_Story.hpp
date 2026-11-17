#ifndef __GAME_STORY_HPP__
#define __GAME_STORY_HPP__

#include "Game_Dialogue.hpp"
#include "Game_Quest.hpp"

namespace fc {

/**
 * @brief 剧情对白构建器：根据任务状态生成不同分支的对话。
 */
class Story {
public:
    /** @brief 开场车内独白（旁白 + 小明）。 */
    Dialogue BuildIntro() const;

    /** @brief 第一次与酒保小帅对话。 */
    Dialogue BuildBartenderFirst() const;

    /** @brief 小帅的点唱机支线委托。 */
    Dialogue BuildBartenderSideOffer() const;

    /** @brief 交付点唱机零件。 */
    Dialogue BuildBartenderSideComplete() const;

    /** @brief 小帅的日常闲聊。 */
    Dialogue BuildBartenderIdle(const QuestState& quest) const;

    /** @brief 第一次与大美对话（主线委托）。 */
    Dialogue BuildBigSisterFirst() const;

    /** @brief 返回酒吧交差并进入结局选择。 */
    Dialogue BuildBigSisterReturn() const;

    /** @brief 大美的日常闲聊。 */
    Dialogue BuildBigSisterIdle(const QuestState& quest) const;

    /** @brief 第一次与东子对话（打开商店）。 */
    Dialogue BuildMerchantFirst() const;

    /** @brief 东子的日常对话（打开商店）。 */
    Dialogue BuildMerchantShop(int purchaseCount) const;

    /** @brief 前往铁港前的提示。 */
    Dialogue BuildCarLocked() const;

    /** @brief 酒吧出口未解锁时的提示。 */
    Dialogue BuildBarExitLocked() const;

    /** @brief 点唱机环境描述。 */
    Dialogue BuildJukebox(bool repaired) const;

    /** @brief 后门环境描述。 */
    Dialogue BuildBackdoor() const;

    /** @brief 街边招牌环境描述。 */
    Dialogue BuildStreetSign() const;
};

} // namespace fc

#endif // __GAME_STORY_HPP__
