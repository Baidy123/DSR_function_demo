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
 * @brief 敌人类型。
 *
 * `SCAVENGER` 远程拾荒者、`THUG` 近战打手、`AGENT` 公司特工。
 * 三者的移动、攻击节奏与威胁方式均不同。
 */
enum class EnemyType : std::uint8_t {
    SCAVENGER = 0,
    AGENT = 1,
    THUG = 2
};

/**
 * @brief 场景中的静态房间块（墙、地板、天花板、管道等）。
 */
struct RoomBlock {
    Vec3 center;
    Vec3 half;
    Color color{0.5f, 0.5f, 0.5f, 1.0f};
    int pattern = 0;      ///< 程序化图案（见 `SurfacePattern`）。
    int material = 0;     ///< 表面材质（见 `SurfaceMaterial`）。
    bool solid = true;
};

/**
 * @brief 场景道具（使用文本网格资产）。
 */
struct PropDef {
    std::string mesh;
    Vec3 position;
    float yawDegrees = 0.0f;
    float scale = 1.0f;
    Color tint{1.0f, 1.0f, 1.0f, 1.0f};
    bool solid = true;
    Vec3 colliderHalf;   ///< 为零时按网格包围盒推导。
    Vec3 colliderOffset; ///< 相对于道具位置的碰撞盒中心偏移。
    bool transparent = false; ///< 玻璃等需要透明排序的道具。
};

/**
 * @brief 点光源定义。
 */
struct LightDef {
    Vec3 position;
    Color color{1.0f, 0.8f, 0.5f, 1.0f};
    float intensity = 1.0f;
    float range = 6.0f;
    float flicker = 0.0f;  ///< 0 稳定，>0 为闪烁强度。
};

/**
 * @brief 交互点定义。
 */
struct InteractDef {
    std::string id;
    Vec3 position;
    float radius = 1.4f;
    std::string prompt;
};

/**
 * @brief 敌人出生点。
 */
struct EnemySpawnDef {
    EnemyType type = EnemyType::SCAVENGER;
    Vec3 position;
    float yawDegrees = 0.0f;
};

/**
 * @brief 固定摄像机区域；玩家进入区域时平滑切换到对应机位。
 */
struct CameraZoneDef {
    AABB bounds;
    CameraPose pose;
};

/**
 * @brief 场景定义。
 */
struct SceneDef {
    SceneId id = SceneId::BAR_EXTERIOR;
    std::string displayName;
    Color fogColor{0.02f, 0.03f, 0.05f, 1.0f};
    float fogNear = 5.0f;
    float fogFar = 30.0f;
    float fogDensity = 0.8f;
    Color ambient{0.10f, 0.11f, 0.14f, 1.0f};
    std::vector<RoomBlock> blocks;
    std::vector<PropDef> props;
    std::vector<LightDef> lights;
    std::vector<InteractDef> interactions;
    std::vector<EnemySpawnDef> enemies;
    std::vector<CameraZoneDef> cameras;
    Vec3 playerSpawn;
    float playerYawDegrees = 180.0f;
    bool rain = false;
    bool outdoor = false;
};

/**
 * @brief 构建场景定义。
 * @param [IN] id 场景 ID。
 * @return 场景定义。
 */
SceneDef BuildScene(SceneId id);

/**
 * @brief 场景显示名。
 * @param [IN] id 场景 ID。
 * @return UTF-8 名称。
 */
const char* SceneDisplayName(SceneId id);

} // namespace fc

#endif // __WORLD_TYPES_HPP__
