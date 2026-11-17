#ifndef __GAME_CHARACTERS_HPP__
#define __GAME_CHARACTERS_HPP__

#include "Render_Device.hpp"
#include "Render_Mesh.hpp"
#include "Shared_Types.hpp"

#include <cstdint>
#include <string>

namespace fc {

/**
 * @brief 角色类型。
 */
enum class CharacterId : std::uint8_t {
    PLAYER = 0,
    BIGSISTER,
    MERCHANT,
    BARTENDER,
    SCAVENGER,
    AGENT
};

/**
 * @brief 角色风格参数（低多面体配色与轮廓特征）。
 */
struct CharacterStyle {
    Color skin{0.79f, 0.56f, 0.42f, 1.0f};
    Color skinShade{0.62f, 0.42f, 0.32f, 1.0f};
    Color hair{0.10f, 0.10f, 0.12f, 1.0f};
    Color coat{0.18f, 0.23f, 0.18f, 1.0f};
    Color coatShade{0.12f, 0.15f, 0.13f, 1.0f};
    Color pants{0.15f, 0.17f, 0.20f, 1.0f};
    Color boots{0.10f, 0.10f, 0.12f, 1.0f};
    Color accent{0.18f, 0.66f, 0.63f, 1.0f};
    Color accentHi{0.50f, 0.85f, 0.81f, 1.0f};
    Color metal{0.42f, 0.45f, 0.47f, 1.0f};
    bool longCoat = false;
    bool apron = false;
    bool vest = false;
    bool hood = false;
    bool visor = false;
    bool goggles = false;
    bool bulky = false;
    bool bun = false;
    bool scarf = false;
    bool armed = false;
    bool hairLong = false;
};

/**
 * @brief 角色动画输入。
 */
struct CharacterAnim {
    float walkPhase = 0.0f;
    float time = 0.0f;
    bool walking = false;
    bool aiming = false;
    float aimPitch = 0.0f;
    float recoil = 0.0f;
    float hitFlash = 0.0f;
    float alpha = 1.0f;
};

/**
 * @brief 角色网格库：所有角色都由程序化多面体组合，无模型文件。
 */
class CharacterLibrary {
public:
    /**
     * @brief 构建六名角色的网格。
     * @param [IN/OUT] meshes 网格库。
     */
    void Build(MeshLibrary& meshes);

    /**
     * @brief 获取角色网格。
     * @param [IN] id 角色。
     * @return 网格指针；未构建返回 nullptr。
     */
    const Mesh* Get(CharacterId id) const;

    /**
     * @brief 绘制角色。
     * @param [IN/OUT] device 渲染设备。
     * @param [IN] mesh 网格。
     * @param [IN] base 角色世界矩阵（含朝向）。
     * @param [IN] anim 动画状态。
     * @param [IN] tint 颜色乘数。
     */
    void Draw(RenderDevice& device, const Mesh& mesh, const Mat4& base,
              const CharacterAnim& anim, const Color& tint) const;

    /**
     * @brief 获取角色风格。
     * @param [IN] id 角色。
     * @return 风格引用。
     */
    const CharacterStyle& Style(CharacterId id) const;

private:
    CharacterStyle m_styles[6];
    const Mesh* m_meshes[6] = {nullptr, nullptr, nullptr, nullptr, nullptr,
                               nullptr};
};

/**
 * @brief 角色 ID 对应的名称（用于调试与日志）。
 * @param [IN] id 角色。
 * @return ASCII 名称。
 */
const char* CharacterName(CharacterId id);

} // namespace fc

#endif // __GAME_CHARACTERS_HPP__
