#ifndef __GAME_TYPES_HPP__
#define __GAME_TYPES_HPP__

#include "Shared_Types.hpp"
#include "World_Types.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace fc {

/** @brief 玩家移动速度（像素/秒）。 */
constexpr float PLAYER_SPEED = 92.0f;

/** @brief 玩家碰撞半径（像素）。 */
constexpr float PLAYER_RADIUS = 5.0f;

/** @brief 玩家生命上限。 */
constexpr int PLAYER_MAX_HP = 100;

/** @brief 玩家子弹速度（像素/秒）。 */
constexpr float PLAYER_BULLET_SPEED = 520.0f;

/** @brief 玩家射击间隔（秒）。 */
constexpr float PLAYER_FIRE_INTERVAL = 0.18f;

/** @brief 玩家子弹伤害。 */
constexpr int PLAYER_BULLET_DAMAGE = 26;

/** @brief 装填耗时（秒）。 */
constexpr float RELOAD_TIME = 1.10f;

/** @brief 医疗包使用耗时（秒）。 */
constexpr float MEDKIT_TIME = 0.60f;

/** @brief 医疗包回复量。 */
constexpr int MEDKIT_HEAL = 40;

/** @brief 受伤后的无敌时间（秒）。 */
constexpr float PLAYER_INVULNERABLE_TIME = 0.35f;

/**
 * @brief 游戏模式。
 */
enum class GameMode : std::uint8_t {
    TITLE = 0,
    PLAYING,
    DIALOGUE,
    SHOP,
    JOURNAL,
    PAUSED,
    DEAD,
    EPILOGUE,
    TRANSITION
};

/**
 * @brief 当前对话的上下文，用于对话结束后的状态推进。
 */
enum class DialogueContext : std::uint8_t {
    NONE = 0,
    INTRO,
    BARTENDER_FIRST,
    BARTENDER_SIDE_OFFER,
    BARTENDER_SIDE_COMPLETE,
    BARTENDER_IDLE,
    BIGSISTER_FIRST,
    BIGSISTER_RETURN,
    BIGSISTER_IDLE,
    MERCHANT_FIRST,
    MERCHANT_SHOP,
    CAR_LOCKED,
    BAR_EXIT_LOCKED,
    JUKEBOX,
    BACKDOOR,
    STREET_SIGN
};

/**
 * @brief 结局选择。
 */
enum class EndingChoice : std::uint8_t {
    NONE = 0,
    ACCEPT,
    WAIT
};

/**
 * @brief 玩家战斗状态。
 */
struct Player {
    Vec2 position;
    Vec2 aim;
    float aimAngle = 0.0f;
    int facingDir = 0;  ///< 0=S，1=N，2=E，3=W。
    int hp = PLAYER_MAX_HP;
    float fireCooldown = 0.0f;
    float reloadTimer = 0.0f;
    float medkitTimer = 0.0f;
    float invulnerableTimer = 0.0f;
    float hitFlash = 0.0f;
    float animTime = 0.0f;
    float muzzleTimer = 0.0f;
    bool reloading = false;
    bool usingMedkit = false;
    bool moving = false;
};

/**
 * @brief 敌人战斗状态。
 */
struct Enemy {
    EnemyType type = EnemyType::SCAVENGER;
    Vec2 position;
    float hp = 45.0f;
    float maxHp = 45.0f;
    float speed = 52.0f;
    float radius = 6.0f;
    float shootTimer = 0.0f;
    float hitFlash = 0.0f;
    float animTime = 0.0f;
    float deathTimer = 0.0f;
    float muzzleTimer = 0.0f;
    float wanderTimer = 0.0f;
    Vec2 wanderDirection;
    int facingDir = 0;
    bool alerted = false;
    bool dead = false;
    bool moving = false;
};

/**
 * @brief 子弹。
 */
struct Bullet {
    Vec2 position;
    Vec2 velocity;
    float damage = 0.0f;
    float life = 0.0f;
    bool hostile = false;
    bool active = true;
};

/**
 * @brief 粒子。
 */
struct Particle {
    Vec2 position;
    Vec2 velocity;
    float life = 0.0f;
    float maxLife = 0.0f;
    float size = 1.0f;
    Color color;
    bool additive = false;
    bool smoke = false;
};

/**
 * @brief 掉落物类型。
 */
enum class PickupType : std::uint8_t {
    AMMO = 0,
    MEDKIT,
    MONEY,
    PART
};

/**
 * @brief 掉落物。
 */
struct Pickup {
    PickupType type = PickupType::AMMO;
    Vec2 position;
    int amount = 0;
    float bob = 0.0f;
    bool active = true;
};

/**
 * @brief 屏幕提示。
 */
struct Toast {
    std::string text;
    float remaining = 0.0f;
    Color color;
};

/**
 * @brief 雨滴（屏幕空间）。
 */
struct RainDrop {
    float x = 0.0f;
    float y = 0.0f;
    float speed = 0.0f;
    float length = 0.0f;
    float alpha = 0.0f;
};

/**
 * @brief 商店商品。
 */
enum class ShopItem : std::uint8_t {
    AMMO = 0,
    MEDKIT,
    ENERGY,
    JACK,
    COUNT
};

/**
 * @brief 商店界面状态。
 */
struct ShopState {
    int selected = 0;
    int purchaseCount = 0;
    bool browseOnly = false;
    std::string message;
    float messageTimer = 0.0f;
};

} // namespace fc

#endif // __GAME_TYPES_HPP__
