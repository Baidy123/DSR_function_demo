#ifndef __GAME_RENDERER_HPP__
#define __GAME_RENDERER_HPP__

#include "Game_Characters.hpp"
#include "Game_Types.hpp"
#include "Render_Device.hpp"
#include "Render_Mesh.hpp"
#include "World_Types.hpp"

#include <string>
#include <vector>

namespace fc {

/**
 * @brief 场景中的静态道具实例。
 */
struct PropInstance {
    const Mesh* mesh = nullptr;
    Vec3 position;
    float yaw = 0.0f;
    float scale = 1.0f;
    Color tint{1.0f, 1.0f, 1.0f, 1.0f};
    AABB bounds;
    bool solid = false;
    bool hidden = false;
};

/**
 * @brief 场景中的 NPC 实例。
 */
struct NpcInstance {
    CharacterId id = CharacterId::BARTENDER;
    Vec3 position;
    float yaw = 0.0f;
    bool visible = true;
    bool armed = false;
};

/**
 * @brief 3D 场景渲染器：房间、道具、角色、子弹与掉落物。
 */
class GameRenderer {
public:
    GameRenderer() = default;

    /**
     * @brief 初始化。
     * @param [IN] device 渲染设备。
     * @param [IN] meshes 网格库。
     * @param [IN] characters 角色库。
     * @return 成功返回 true。
     */
    bool Initialize(RenderDevice* device, MeshLibrary* meshes,
                    CharacterLibrary* characters);

    /**
     * @brief 加载场景静态几何与道具。
     * @param [IN] scene 场景定义。
     * @param [IN/OUT] collision 碰撞世界（追加盒）。
     * @return 成功返回 true。
     */
    bool LoadScene(const SceneDef& scene, class CollisionWorld& collision);

    /**
     * @brief 绘制场景。
     * @param [IN] scene 场景定义。
     * @param [IN] player 玩家。
     * @param [IN] npcs NPC 列表。
     * @param [IN] enemies 敌人列表。
     * @param [IN] bullets 子弹列表。
     * @param [IN] particles 粒子列表。
     * @param [IN] pickups 掉落物列表。
     * @param [IN] camera 摄像机（含视图/投影矩阵）。
     * @param [IN] lights 光源列表（可被玩法层修改）。
     * @param [IN] time 累计时间。
     */
    void DrawScene(const SceneDef& scene, const Player& player,
                   const std::vector<NpcInstance>& npcs,
                   const std::vector<Enemy>& enemies,
                   const std::vector<Bullet>& bullets,
                   const std::vector<Particle>& particles,
                   const std::vector<Pickup>& pickups,
                   const CameraRuntime& camera,
                   const std::vector<LightDef>& lights, float time);

    /**
     * @brief 绘制世界空间辉光（在 2D 覆盖层之前调用）。
     * @param [IN] camera 摄像机。
     * @param [IN] lights 光源列表。
     * @param [IN] time 时间。
     * @param [IN] player 玩家（枪口辉光）。
     * @param [IN] alarm 是否警报（红色脉冲）。
     */
    void DrawLightGlows(const CameraRuntime& camera,
                        const std::vector<LightDef>& lights, float time,
                        const Player& player, bool alarm);

    /**
     * @brief 初始化角色头像（3D 胸像渲染到 64×64 纹理）。
     * @return 成功返回 true。
     */
    bool BuildPortraits();

    /**
     * @brief 获取角色头像纹理。
     * @param [IN] id 角色。
     * @return 纹理指针；未生成返回 nullptr。
     */
    const Texture* Portrait(CharacterId id) const;

    /**
     * @brief 世界坐标转内部像素坐标。
     * @param [IN] camera 摄像机。
     * @param [IN] world 世界坐标。
     * @param [OUT] screen 内部坐标。
     * @return 在摄像机前方返回 true。
     */
    bool WorldToScreen(const CameraRuntime& camera, const Vec3& world,
                       Vec2& screen) const;

    /**
     * @brief 获取道具实例。
     * @return 列表。
     */
    const std::vector<PropInstance>& Props() const { return m_props; }

    /**
     * @brief 按网格名隐藏道具（取走货物/零件后使用）。
     * @param [IN] meshName 网格名。
     */
    void HidePropsByMesh(const std::string& meshName);

private:
    void DrawShadow(const Vec3& position, float radius, float alpha);
    void DrawBullet(const Bullet& bullet) const;
    void DrawPickup(const Pickup& pickup) const;
    void DrawParticle(const Particle& particle) const;
    Vec3 MuzzlePosition(const Player& player) const;

    RenderDevice* m_device = nullptr;
    MeshLibrary* m_meshes = nullptr;
    CharacterLibrary* m_characters = nullptr;

    const Mesh* m_roomMesh = nullptr;
    const Mesh* m_cube = nullptr;
    const Mesh* m_shadowMesh = nullptr;
    const Mesh* m_sphere = nullptr;

    std::vector<PropInstance> m_props;
    RenderTarget m_portraits[6];
    bool m_portraitsReady = false;
};

/**
 * @brief 由摄像机姿态与宽高比构造视图/投影矩阵。
 * @param [IN/OUT] camera 摄像机运行时。
 * @param [IN] aspect 宽高比。
 */
void UpdateCameraMatrices(CameraRuntime& camera, float aspect);

} // namespace fc

#endif // __GAME_RENDERER_HPP__
