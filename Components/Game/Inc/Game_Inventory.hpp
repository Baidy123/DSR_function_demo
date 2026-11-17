#ifndef __GAME_INVENTORY_HPP__
#define __GAME_INVENTORY_HPP__

#include <cstdint>

namespace fc {

/** @brief 弹匣容量。 */
constexpr int WEAPON_MAGAZINE_SIZE = 12;

/** @brief 备弹上限。 */
constexpr int WEAPON_RESERVE_MAX = 99;

/** @brief 医疗包上限。 */
constexpr int MEDKIT_MAX = 3;

/**
 * @brief 玩家物品与货币状态。
 */
struct Inventory {
    int money = 40;
    int ammoMag = 0;
    int ammoReserve = 0;
    int medkits = 0;
    bool hasGear = false;
    bool hasCargo = false;
    bool hasPart = false;

    /**
     * @brief 是否支付得起。
     * @param [IN] price 价格。
     * @return 足够返回 true。
     */
    bool CanAfford(int price) const;

    /**
     * @brief 增加信用点。
     * @param [IN] amount 数量。
     */
    void AddMoney(int amount);

    /**
     * @brief 增加备弹，自动截断到上限。
     * @param [IN] amount 数量。
     * @return 实际增加量。
     */
    int AddAmmo(int amount);

    /**
     * @brief 增加医疗包，自动截断到上限。
     * @param [IN] amount 数量。
     * @return 实际增加量。
     */
    int AddMedkit(int amount);

    /**
     * @brief 购买弹药。
     * @param [IN] price 价格。
     * @param [IN] amount 数量。
     * @return 成功返回 true；余额不足或已满返回 false。
     */
    bool BuyAmmo(int price, int amount);

    /**
     * @brief 购买医疗包。
     * @param [IN] price 价格。
     * @return 成功返回 true。
     */
    bool BuyMedkit(int price);

    /**
     * @brief 使用医疗包。
     * @param [IN/OUT] currentHp 当前生命，会被修改。
     * @param [IN] maxHp 生命上限。
     * @param [IN] heal 回复量。
     * @return 使用成功返回 true。
     */
    bool UseMedkit(int& currentHp, int maxHp, int heal);

    /**
     * @brief 消耗一发子弹。
     * @return 有子弹并消耗返回 true。
     */
    bool ConsumeRound();

    /**
     * @brief 装填弹匣。
     * @return 发生装填返回 true。
     */
    bool Reload();

    /**
     * @brief 发放大姐头的初始装备。
     */
    void GiveStarterKit();

    /**
     * @brief 是否满足射击条件。
     * @return 弹匣或备弹大于 0 返回 true。
     */
    bool HasAnyAmmo() const;
};

} // namespace fc

#endif // __GAME_INVENTORY_HPP__
