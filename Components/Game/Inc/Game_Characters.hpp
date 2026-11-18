#ifndef __GAME_CHARACTERS_HPP__
#define __GAME_CHARACTERS_HPP__

#include "Render_Mesh.hpp"
#include "Shared_Types.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace fc {

class RenderDevice;

/**
 * @brief 可用的角色形象。
 */
enum class CharacterId : std::uint8_t {
    PLAYER = 0,
    BIGSISTER = 1,
    MERCHANT = 2,
    BARTENDER = 3,
    SCAVENGER = 4,
    AGENT = 5,
    THUG = 6
};

/** @brief 角色数量（含近战打手）。 */
constexpr int CHARACTER_COUNT = 7;

/**
 * @brief 角色持有的武器类型。
 */
enum class WeaponKind : std::uint8_t {
    NONE = 0,
    PISTOL,
    RIFLE,
    PIPE
};

/**
 * @brief 角色风格参数：配色、服装部件开关与体型。
 *
 * 所有角色共用同一套骨骼（见 `Game_Characters.cpp` 的骨骼表），
 * 通过这里的不同开关组合出可辨识的轮廓与服装层次。
 */
struct CharacterStyle {
    Color skin{0.79f, 0.56f, 0.42f, 1.0f};
    Color skinShade{0.62f, 0.42f, 0.32f, 1.0f};
    Color hair{0.10f, 0.10f, 0.12f, 1.0f};
    Color coat{0.18f, 0.23f, 0.18f, 1.0f};
    Color coatShade{0.12f, 0.15f, 0.13f, 1.0f};
    Color shirt{0.62f, 0.62f, 0.58f, 1.0f};
    Color pants{0.15f, 0.17f, 0.20f, 1.0f};
    Color boots{0.10f, 0.10f, 0.12f, 1.0f};
    Color belt{0.09f, 0.08f, 0.08f, 1.0f};
    Color accent{0.18f, 0.66f, 0.63f, 1.0f};
    Color accentHi{0.50f, 0.85f, 0.81f, 1.0f};
    Color metal{0.42f, 0.45f, 0.47f, 1.0f};

    float height = 1.0f;      ///< 整体身高倍率。
    float bulk = 1.0f;        ///< 躯干与四肢的宽度倍率。
    WeaponKind weapon = WeaponKind::NONE;

    bool longCoat = false;    ///< 及膝长风衣。
    bool apron = false;       ///< 吧台围裙。
    bool vest = false;        ///< 工作背心。
    bool hood = false;        ///< 兜帽。
    bool helmet = false;      ///< 全罩头盔。
    bool visor = false;       ///< 发光面甲。
    bool goggles = false;     ///< 护目镜（架在额头）。
    bool mask = false;        ///< 半脸面罩。
    bool scarf = false;       ///< 围巾。
    bool backpack = false;    ///< 背包。
    bool bandolier = false;   ///< 斜挎弹带。
    bool shoulderPads = false;///< 硬质护肩。
    bool hairLong = false;    ///< 长发。
    bool bun = false;         ///< 发髻。
    bool bald = false;        ///< 光头/剃短。
};

/**
 * @brief 角色动画输入。
 */
struct CharacterAnim {
    float walkPhase = 0.0f;   ///< 步行相位（弧度）。
    float walkAmp = 0.0f;     ///< 步行幅度（0 站立，1 全速）。
    float time = 0.0f;        ///< 累计时间（呼吸与微动作）。
    bool running = false;     ///< 是否奔跑（影响前倾与摆臂）。
    bool aiming = false;      ///< 是否举枪。
    float aimOffset = 0.0f;   ///< 上半身相对身体的偏航（弧度）。
    float aimPitch = 0.0f;    ///< 俯仰（-1 下，1 上）。
    float recoil = 0.0f;      ///< 后坐力（0–1）。
    float reloadProgress = -1.0f; ///< 换弹进度（0–1，负值表示未换弹）。
    float meleeProgress = -1.0f;  ///< 近战挥击进度（0–1，负值表示未攻击）。
    float hitFlash = 0.0f;    ///< 受击闪红（0–1）。
    float alpha = 1.0f;       ///< 透明度。
    float deathLean = 0.0f;   ///< 死亡倒地程度（0–1）。
    WeaponKind weapon = WeaponKind::NONE; ///< 手上的武器类型。
    bool showWeapon = true;   ///< 是否绘制手中武器（空手时隐藏）。
};

/**
 * @brief 角色网格库：所有角色都由程序化多面体组合，无模型文件。
 */
class CharacterLibrary {
public:
    /**
     * @brief 构建全部角色的网格。
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
     * @brief 绘制角色（含骨骼层级与动画）。
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
    CharacterStyle m_styles[CHARACTER_COUNT];
    const Mesh* m_meshes[CHARACTER_COUNT] = {};
};

/**
 * @brief 角色 ID 对应的名称（用于调试与日志）。
 * @param [IN] id 角色。
 * @return ASCII 名称。
 */
const char* CharacterName(CharacterId id);

} // namespace fc

#endif // __GAME_CHARACTERS_HPP__
