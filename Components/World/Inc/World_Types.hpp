#ifndef __WORLD_TYPES_HPP__
#define __WORLD_TYPES_HPP__

#include "Shared_Types.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace fc {

/**
 * @brief 可玩场景 ID。
 */
enum class SceneId : std::uint8_t {
    BAR_EXTERIOR = 1,
    BAR_INTERIOR = 2,
    IRON_HARBOR = 3
};

/**
 * @brief 场景主题，决定瓷砖与光照风格。
 */
enum class SceneTheme : std::uint8_t {
    BAR = 0,
    STREET = 1,
    HARBOR = 2
};

/**
 * @brief 敌人类型。
 */
enum class EnemyType : std::uint8_t {
    SCAVENGER = 0,
    AGENT = 1
};

/**
 * @brief 静态道具定义（含 NPC 站/坐姿精灵）。
 */
struct PropDef {
    std::string sprite;  ///< 资产名。
    float x = 0.0f;      ///< 左上角 x（世界像素）。
    float y = 0.0f;      ///< 左上角 y。
    bool blocking = true;
};

/**
 * @brief 交互点定义。
 */
struct InteractDef {
    std::string id;       ///< 逻辑 ID，由 GameApp 分发。
    float x = 0.0f;       ///< 交互中心 x（世界像素）。
    float y = 0.0f;       ///< 交互中心 y。
    float radius = 28.0f; ///< 交互半径。
    std::string prompt;   ///< 提示文本（UTF-8）。
};

/**
 * @brief 敌人出生点。
 */
struct EnemySpawnDef {
    EnemyType type = EnemyType::SCAVENGER;
    float x = 0.0f;
    float y = 0.0f;
};

/**
 * @brief 场景蓝本：瓷砖、道具、交互点、出生点与氛围参数。
 */
struct SceneDefinition {
    SceneId id = SceneId::BAR_EXTERIOR;
    SceneTheme theme = SceneTheme::STREET;
    int widthTiles = 30;
    int heightTiles = 17;
    std::vector<std::string> tiles;     ///< 每行一个字符串。
    std::vector<PropDef> props;
    std::vector<InteractDef> interactions;
    std::vector<EnemySpawnDef> enemies;
    Vec2 playerSpawn;
    bool cameraFollow = false;
    bool raining = true;
    std::string displayName;

    /**
     * @brief 地图像素宽度。
     * @return 宽度。
     */
    int PixelWidth() const { return widthTiles * TILE_SIZE; }

    /**
     * @brief 地图像素高度。
     * @return 高度。
     */
    int PixelHeight() const { return heightTiles * TILE_SIZE; }
};

} // namespace fc

#endif // __WORLD_TYPES_HPP__
