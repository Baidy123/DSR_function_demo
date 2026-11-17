#include "Game_Inventory.hpp"

#include <algorithm>

namespace fc {

bool Inventory::CanAfford(int price) const
{
    return price >= 0 && money >= price;
}

void Inventory::AddMoney(int amount)
{
    if (amount <= 0) {
        return;
    }
    money += amount;
    if (money > 999999) {
        money = 999999;
    }
}

int Inventory::AddAmmo(int amount)
{
    if (amount <= 0) {
        return 0;
    }
    const int room = WEAPON_RESERVE_MAX - ammoReserve;
    const int added = std::min(room, amount);
    ammoReserve += added;
    return added;
}

int Inventory::AddMedkit(int amount)
{
    if (amount <= 0) {
        return 0;
    }
    const int room = MEDKIT_MAX - medkits;
    const int added = std::min(room, amount);
    medkits += added;
    return added;
}

bool Inventory::BuyAmmo(int price, int amount)
{
    if (amount <= 0 || ammoReserve >= WEAPON_RESERVE_MAX) {
        return false;
    }
    if (!CanAfford(price)) {
        return false;
    }
    money -= price;
    AddAmmo(amount);
    return true;
}

bool Inventory::BuyMedkit(int price)
{
    if (medkits >= MEDKIT_MAX || !CanAfford(price)) {
        return false;
    }
    money -= price;
    ++medkits;
    return true;
}

bool Inventory::UseMedkit(int& currentHp, int maxHp, int heal)
{
    if (medkits <= 0 || currentHp <= 0 || currentHp >= maxHp) {
        return false;
    }
    --medkits;
    currentHp = std::min(maxHp, currentHp + heal);
    return true;
}

bool Inventory::ConsumeRound()
{
    if (ammoMag <= 0) {
        return false;
    }
    --ammoMag;
    return true;
}

bool Inventory::Reload()
{
    if (ammoMag >= WEAPON_MAGAZINE_SIZE || ammoReserve <= 0) {
        return false;
    }
    const int needed = WEAPON_MAGAZINE_SIZE - ammoMag;
    const int taken = std::min(needed, ammoReserve);
    ammoMag += taken;
    ammoReserve -= taken;
    return true;
}

void Inventory::GiveStarterKit()
{
    hasGear = true;
    ammoMag = WEAPON_MAGAZINE_SIZE;
    AddAmmo(24);
    AddMedkit(1);
}

bool Inventory::HasAnyAmmo() const
{
    return ammoMag > 0 || ammoReserve > 0;
}

} // namespace fc
