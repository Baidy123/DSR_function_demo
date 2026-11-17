#ifndef __GAME_TYPES_HPP__
#define __GAME_TYPES_HPP__

#include "Game_Characters.hpp"
#include "Shared_Types.hpp"
#include "World_Types.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace fc {

/** @brief 玩家移动速度（米/秒）。 */
constexpr float PLAYER_SPEED = 3.0f;

/** @brief 玩家奔跑速度（米/秒）。 */
constexpr float PLAYER_RUN_SPEED = 4.4f;

/** @brief 玩家碰撞半径（米）。 */
constexpr float PLAYER_RADIUS = 0.28f;

/** @brief 玩家生命上限。 */
constexpr int PLAYER_MAX_HP = 100;

/** @brief 玩家子弹速度（米/秒）。 */
constexpr float PLAYER_BULLET_SPEED = 42.0f;

/** @brief 玩家射击间隔（秒）。 */
constexpr float PLAYER_FIRE_INTERVAL = 0.20f;

/** @brief 玩家子弹伤害。 */
constexpr int PLAYER_BULLET_DAMAGE = 28;

/** @brief 装填耗时（秒）。 */
constexpr float RELOAD_TIME = 1.05f;

/** @brief 医疗包使用耗时（秒）。 */
constexpr float MEDKIT_TIME = 0.75f;

/** @brief 医疗包回复量。 */
constexpr int MEDKIT_HEAL = 40;

/** @brief 受伤无敌时间（秒）。 */
constexpr float PLAYER_INVULNERABLE_TIME = 0.45f;

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
 * @brief 当前对话上下文。
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
    TERMINAL,
    STREET_SIGN,
    AMBUSH_WARNING
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
 * @brief 玩家状态。
 */
struct Player {
    Vec3 position;
    float yaw = 0.0f;
    float aimYaw = 0.0f;
    float aimPitch = 0.0f;
    int hp = PLAYER_MAX_HP;
    float fireCooldown = 0.0f;
    float reloadTimer = 0.0f;
    float medkitTimer = 0.0f;
    float invulnerableTimer = 0.0f;
    float hitFlash = 0.0f;
    float walkPhase = 0.0f;
    float time = 0.0f;
    float recoil = 0.0f;
    bool reloading = false;
    bool usingMedkit = false;
    bool moving = false;
    bool running = false;
    bool aiming = true;
};

/**
 * @brief 敌人状态。
 */
struct Enemy {
    EnemyType type = EnemyType::SCAVENGER;
    CharacterId character = CharacterId::SCAVENGER;
    Vec3 position;
    float yaw = 0.0f;
    float hp = 45.0f;
    float maxHp = 45.0f;
    float speed = 2.1f;
    float radius = 0.3f;
    float shootTimer = 0.0f;
    float hitFlash = 0.0f;
    float walkPhase = 0.0f;
    float time = 0.0f;
    float deathTimer = 0.0f;
    float muzzleTimer = 0.0f;
    float aimPitch = 0.0f;
    bool alerted = false;
    bool dead = false;
    bool moving = false;
    bool aiming = false;
};

/**
 * @brief 子弹。
 */
struct Bullet {
    Vec3 position;
    Vec3 direction{0.0f, 0.0f, 1.0f};
    float speed = PLAYER_BULLET_SPEED;
    float damage = 0.0f;
    float life = 0.0f;
    bool hostile = false;
    bool active = true;
};

/**
 * @brief 粒子。
 */
struct Particle {
    Vec3 position;
    Vec3 velocity;
    float life = 0.0f;
    float maxLife = 0.0f;
    float size = 0.05f;
    Color color;
    bool additive = false;
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
    Vec3 position;
    int amount = 0;
    float bob = 0.0f;
    bool active = true;
};

/**
 * @brief 界面提示。
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
 * @brief 商店商品索引。
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

/**
 * @brief 摄像机运行时状态（支持区域平滑切换）。
 */
struct CameraRuntime {
    CameraPose current;
    CameraPose target;
    float blend = 1.0f;
    int zoneIndex = -1;
    float shakeTime = 0.0f;
    float shakeDuration = 0.0f;
    float shakeIntensity = 0.0f;
    Vec3 shakeOffset;
    Mat4 view;
    Mat4 projection;
    Mat4 viewProjection;
};

} // namespace fc

#endif // __GAME_TYPES_HPP__
