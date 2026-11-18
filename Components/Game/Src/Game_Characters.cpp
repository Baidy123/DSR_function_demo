#include "Game_Characters.hpp"

#include "Render_Device.hpp"
#include "Shared_Math.hpp"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace fc {

namespace {

const Color WHITE = Color(1.0f, 1.0f, 1.0f, 1.0f);

// ---- 骨架比例（米，基准身高约 1.74 m）----
constexpr float HIP_Y = 0.90f;        ///< 髋关节高度。
constexpr float HIP_X = 0.095f;       ///< 髋关节左右偏移。
constexpr float SHOULDER_X = 0.20f;   ///< 肩关节左右偏移。
constexpr float SHOULDER_Y = 0.41f;   ///< 肩关节相对腰关节的高度。
constexpr float ELBOW_Y = -0.25f;     ///< 肘相对肩的偏移。
constexpr float WRIST_Y = -0.225f;    ///< 腕相对肘的偏移。
constexpr float KNEE_Y = -0.44f;      ///< 膝相对髋的偏移。
constexpr float ANKLE_Y = -0.37f;     ///< 踝相对膝的偏移。
constexpr float NECK_Y = 0.47f;       ///< 颈相对腰的偏移。

/**
 * @brief 骨骼链：名称与父骨骼。
 *
 * 数组顺序必须是父在子之前，`Draw` 依赖该顺序做一次自顶向下遍历。
 * `weaponR` 挂在右手上，隐藏该部件即可表现空手状态。
 */
struct BoneLink {
    const char* name;
    const char* parent;
};

const BoneLink kSkeleton[] = {
    {"hips", nullptr},
    {"torso", "hips"},
    {"head", "torso"},
    {"upperArmL", "torso"},
    {"foreArmL", "upperArmL"},
    {"handL", "foreArmL"},
    {"upperArmR", "torso"},
    {"foreArmR", "upperArmR"},
    {"handR", "foreArmR"},
    {"weaponR", "handR"},
    {"thighL", "hips"},
    {"shinL", "thighL"},
    {"footL", "shinL"},
    {"thighR", "hips"},
    {"shinR", "thighR"},
    {"footR", "shinR"}
};

constexpr int BONE_COUNT = static_cast<int>(sizeof(kSkeleton) / sizeof(kSkeleton[0]));

/**
 * @brief 设置后续几何的颜色、图案与反射材质。
 * @param [IN/OUT] builder 网格构建器。
 * @param [IN] color 颜色。
 * @param [IN] pattern 程序化图案。
 * @param [IN] material 表面材质。
 */
void SetSurf(MeshBuilder& builder, const Color& color, SurfacePattern pattern,
             SurfaceMaterial material)
{
    builder.SetColor(color);
    builder.SetPattern(static_cast<int>(pattern));
    builder.SetMaterial(static_cast<int>(material));
}

/**
 * @brief 统一提亮角色色板。
 *
 * 角色处于暗场景时会与背景融成一片；轻微提亮能保证剪影始终可读，
 * 同时不至于让亮部过曝。
 * @param [IN/OUT] style 风格。
 * @param [IN] k 提亮系数。
 */
void BrightenStyle(CharacterStyle& style, float k)
{
    auto scale = [k](const Color& c) {
        return Color(std::min(1.0f, c.r * k), std::min(1.0f, c.g * k),
                     std::min(1.0f, c.b * k), c.a);
    };
    style.skin = scale(style.skin);
    style.skinShade = scale(style.skinShade);
    style.hair = scale(style.hair);
    style.coat = scale(style.coat);
    style.coatShade = scale(style.coatShade);
    style.shirt = scale(style.shirt);
    style.pants = scale(style.pants);
    style.boots = scale(style.boots);
    style.belt = scale(style.belt);
    style.metal = scale(style.metal);
}

// ---------------------------------------------------------------------------
// 骨骼部件
// ---------------------------------------------------------------------------

void BuildHips(MeshBuilder& builder, const CharacterStyle& style)
{
    const float w = 0.155f * style.bulk;
    const float d = 0.105f * style.bulk;

    SetSurf(builder, style.pants, SurfacePattern::CLOTH,
            SurfaceMaterial::FABRIC);
    builder.AddBeveledBox(Vec3(0.0f, -0.04f, 0.0f), Vec3(w, 0.10f, d), 0.22f);
    // 大腿根部，填住髋与腿之间的缝。
    builder.AddBox(Vec3(-HIP_X, -0.07f, 0.0f), Vec3(0.078f, 0.075f, d * 0.92f));
    builder.AddBox(Vec3(HIP_X, -0.07f, 0.0f), Vec3(0.078f, 0.075f, d * 0.92f));

    // 腰带与皮带扣
    SetSurf(builder, style.belt, SurfacePattern::LEATHER,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(0.0f, 0.048f, 0.0f),
                   Vec3(w + 0.008f, 0.028f, d + 0.008f));
    SetSurf(builder, style.accent, SurfacePattern::PLAIN,
            SurfaceMaterial::METAL_POLISHED);
    builder.AddBox(Vec3(0.0f, 0.048f, d + 0.006f), Vec3(0.034f, 0.022f, 0.012f));

    // 腰包与枪套，让腰线不再是一条直边。
    SetSurf(builder, style.belt, SurfacePattern::LEATHER,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(-w * 0.72f, 0.0f, d * 0.52f),
                   Vec3(0.042f, 0.055f, 0.026f));
    SetSurf(builder, style.coatShade, SurfacePattern::LEATHER,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(w * 0.78f, -0.02f, d * 0.4f),
                   Vec3(0.034f, 0.072f, 0.03f));
    // 后腰工具袋
    builder.AddBox(Vec3(0.0f, 0.0f, -d - 0.012f), Vec3(0.06f, 0.045f, 0.018f));
}

void BuildTorso(MeshBuilder& builder, const CharacterStyle& style)
{
    const float w = 0.185f * style.bulk;
    const float d = 0.105f * style.bulk;
    const SurfaceMaterial cloth = style.longCoat ? SurfaceMaterial::PLASTIC
                                                 : SurfaceMaterial::FABRIC;

    // 腹部
    SetSurf(builder, style.coatShade, SurfacePattern::CLOTH, cloth);
    builder.AddBeveledBox(Vec3(0.0f, 0.115f, 0.0f),
                          Vec3(w * 0.86f, 0.105f, d * 0.94f), 0.2f);
    // 胸腔
    SetSurf(builder, style.coat, SurfacePattern::CLOTH, cloth);
    builder.AddBeveledBox(Vec3(0.0f, 0.30f, 0.0f), Vec3(w, 0.135f, d), 0.16f);

    // 内衬衬衫：胸口的开襟
    SetSurf(builder, style.shirt, SurfacePattern::CLOTH,
            SurfaceMaterial::FABRIC);
    builder.AddBox(Vec3(0.0f, 0.33f, d - 0.004f), Vec3(0.052f, 0.115f, 0.012f));
    // 翻领
    SetSurf(builder, style.coatShade, SurfacePattern::CLOTH, cloth);
    builder.AddBox(Vec3(-0.062f, 0.40f, d + 0.004f), Vec3(0.05f, 0.06f, 0.014f));
    builder.AddBox(Vec3(0.062f, 0.40f, d + 0.004f), Vec3(0.05f, 0.06f, 0.014f));

    // 肩线与肩垫
    SetSurf(builder, style.coat, SurfacePattern::CLOTH, cloth);
    builder.AddBox(Vec3(-w * 0.86f, 0.395f, 0.0f), Vec3(0.07f, 0.045f, d * 0.9f));
    builder.AddBox(Vec3(w * 0.86f, 0.395f, 0.0f), Vec3(0.07f, 0.045f, d * 0.9f));

    if (style.shoulderPads) {
        SetSurf(builder, style.metal, SurfacePattern::METAL_RIBS,
                SurfaceMaterial::METAL_MATTE);
        builder.AddBeveledBox(Vec3(-w - 0.02f, 0.375f, 0.0f),
                              Vec3(0.075f, 0.055f, d * 0.92f), 0.3f);
        builder.AddBeveledBox(Vec3(w + 0.02f, 0.375f, 0.0f),
                              Vec3(0.075f, 0.055f, d * 0.92f), 0.3f);
    }

    if (style.vest) {
        SetSurf(builder, style.coatShade, SurfacePattern::CLOTH,
                SurfaceMaterial::PLASTIC);
        builder.AddBox(Vec3(0.0f, 0.30f, d + 0.006f),
                       Vec3(w * 0.66f, 0.10f, 0.012f));
        SetSurf(builder, style.accent, SurfacePattern::PLAIN,
                SurfaceMaterial::FABRIC);
        builder.AddBox(Vec3(-0.06f, 0.30f, d + 0.014f),
                       Vec3(0.012f, 0.095f, 0.004f));
        builder.AddBox(Vec3(0.06f, 0.30f, d + 0.014f),
                       Vec3(0.012f, 0.095f, 0.004f));
    }

    if (style.apron) {
        SetSurf(builder, style.accent, SurfacePattern::CLOTH,
                SurfaceMaterial::FABRIC);
        builder.AddBox(Vec3(0.0f, 0.10f, d + 0.012f), Vec3(0.13f, 0.13f, 0.008f));
        builder.AddBox(Vec3(0.0f, 0.36f, d + 0.008f), Vec3(0.055f, 0.09f, 0.006f));
        SetSurf(builder, style.accentHi, SurfacePattern::PLAIN,
                SurfaceMaterial::FABRIC);
        builder.AddBox(Vec3(0.0f, 0.22f, d + 0.016f), Vec3(0.05f, 0.02f, 0.004f));
    }

    if (style.scarf) {
        SetSurf(builder, style.accent, SurfacePattern::CLOTH,
                SurfaceMaterial::FABRIC);
        builder.AddBeveledBox(Vec3(0.0f, 0.435f, 0.0f),
                              Vec3(w * 0.72f, 0.036f, d * 1.02f), 0.3f);
        builder.AddBox(Vec3(0.055f, 0.33f, d + 0.012f),
                       Vec3(0.035f, 0.10f, 0.016f));
        SetSurf(builder, style.accentHi, SurfacePattern::CLOTH,
                SurfaceMaterial::FABRIC);
        builder.AddBox(Vec3(0.055f, 0.24f, d + 0.012f),
                       Vec3(0.032f, 0.03f, 0.014f));
    }

    if (style.bandolier) {
        SetSurf(builder, style.belt, SurfacePattern::LEATHER,
                SurfaceMaterial::PLASTIC);
        builder.AddBox(Vec3(0.0f, 0.30f, d + 0.012f),
                       Vec3(w * 1.02f, 0.028f, 0.012f), 0.0f);
        // 弹带上的小弹匣
        SetSurf(builder, style.metal, SurfacePattern::METAL_RIBS,
                SurfaceMaterial::METAL_POLISHED);
        for (int i = -2; i <= 2; ++i) {
            builder.AddBox(Vec3(static_cast<float>(i) * 0.045f, 0.30f,
                                d + 0.022f),
                           Vec3(0.016f, 0.038f, 0.012f));
        }
    }

    if (style.backpack) {
        SetSurf(builder, style.coatShade, SurfacePattern::CLOTH,
                SurfaceMaterial::PLASTIC);
        builder.AddBeveledBox(Vec3(0.0f, 0.29f, -d - 0.075f),
                              Vec3(0.115f, 0.135f, 0.075f), 0.2f);
        SetSurf(builder, style.belt, SurfacePattern::LEATHER,
                SurfaceMaterial::PLASTIC);
        builder.AddBox(Vec3(0.0f, 0.29f, -d - 0.152f),
                       Vec3(0.09f, 0.10f, 0.012f));
        SetSurf(builder, style.metal, SurfacePattern::METAL_RIBS,
                SurfaceMaterial::METAL_MATTE);
        builder.AddBox(Vec3(0.0f, 0.42f, -d - 0.10f),
                       Vec3(0.06f, 0.016f, 0.04f));
    }
}

void BuildHead(MeshBuilder& builder, const CharacterStyle& style)
{
    // 头颅
    SetSurf(builder, style.skin, SurfacePattern::PLAIN,
            SurfaceMaterial::PLASTIC);
    builder.AddBeveledBox(Vec3(0.0f, 0.145f, 0.0f), Vec3(0.086f, 0.10f, 0.088f),
                          0.28f);
    // 下颚
    SetSurf(builder, style.skinShade, SurfacePattern::PLAIN,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(0.0f, 0.075f, 0.028f), Vec3(0.062f, 0.036f, 0.05f));
    // 鼻梁
    SetSurf(builder, style.skin, SurfacePattern::PLAIN,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(0.0f, 0.135f, 0.086f), Vec3(0.016f, 0.026f, 0.016f));
    // 耳朵
    builder.AddBox(Vec3(-0.086f, 0.145f, 0.0f), Vec3(0.012f, 0.026f, 0.02f));
    builder.AddBox(Vec3(0.086f, 0.145f, 0.0f), Vec3(0.012f, 0.026f, 0.02f));

    // 头发
    if (!style.bald) {
        SetSurf(builder, style.hair, SurfacePattern::CLOTH,
                SurfaceMaterial::FABRIC);
        builder.AddBeveledBox(Vec3(0.0f, 0.205f, -0.008f),
                              Vec3(0.09f, 0.052f, 0.092f), 0.3f);
        if (style.hairLong) {
            builder.AddBox(Vec3(0.0f, 0.10f, -0.088f),
                           Vec3(0.085f, 0.12f, 0.022f));
            builder.AddBox(Vec3(-0.082f, 0.13f, -0.02f),
                           Vec3(0.016f, 0.10f, 0.06f));
            builder.AddBox(Vec3(0.082f, 0.13f, -0.02f),
                           Vec3(0.016f, 0.10f, 0.06f));
        }
        if (style.bun) {
            builder.AddSphere(Vec3(0.0f, 0.20f, -0.10f), 0.045f, 8, 6);
        }
    }

    // 护目镜（架在额头上）
    if (style.goggles) {
        SetSurf(builder, style.belt, SurfacePattern::LEATHER,
                SurfaceMaterial::PLASTIC);
        builder.AddBox(Vec3(0.0f, 0.205f, 0.06f), Vec3(0.088f, 0.018f, 0.028f));
        SetSurf(builder, style.accentHi, SurfacePattern::GLASS,
                SurfaceMaterial::GLASS);
        builder.AddBox(Vec3(-0.042f, 0.203f, 0.084f),
                       Vec3(0.026f, 0.020f, 0.008f));
        builder.AddBox(Vec3(0.042f, 0.203f, 0.084f),
                       Vec3(0.026f, 0.020f, 0.008f));
    }

    // 半脸面罩
    if (style.mask) {
        SetSurf(builder, style.coatShade, SurfacePattern::CLOTH,
                SurfaceMaterial::PLASTIC);
        builder.AddBeveledBox(Vec3(0.0f, 0.10f, 0.055f),
                              Vec3(0.072f, 0.052f, 0.042f), 0.25f);
        SetSurf(builder, style.metal, SurfacePattern::METAL_RIBS,
                SurfaceMaterial::METAL_MATTE);
        builder.AddBox(Vec3(0.0f, 0.11f, 0.10f), Vec3(0.04f, 0.02f, 0.012f));
    }

    // 兜帽
    if (style.hood) {
        SetSurf(builder, style.coat, SurfacePattern::CLOTH,
                SurfaceMaterial::FABRIC);
        builder.AddBeveledBox(Vec3(0.0f, 0.19f, -0.02f),
                              Vec3(0.108f, 0.10f, 0.11f), 0.35f);
        builder.AddBox(Vec3(0.0f, 0.10f, -0.10f), Vec3(0.10f, 0.09f, 0.02f));
        builder.AddBox(Vec3(-0.10f, 0.12f, -0.02f), Vec3(0.018f, 0.08f, 0.07f));
        builder.AddBox(Vec3(0.10f, 0.12f, -0.02f), Vec3(0.018f, 0.08f, 0.07f));
    }

    // 全罩头盔与面甲
    if (style.helmet) {
        SetSurf(builder, style.metal, SurfacePattern::METAL_RIBS,
                SurfaceMaterial::METAL_MATTE);
        builder.AddBeveledBox(Vec3(0.0f, 0.165f, 0.0f),
                              Vec3(0.095f, 0.108f, 0.098f), 0.3f);
        builder.AddBox(Vec3(0.0f, 0.10f, 0.05f), Vec3(0.08f, 0.045f, 0.05f));
        if (style.visor) {
            SetSurf(builder, style.accent, SurfacePattern::EMISSIVE,
                    SurfaceMaterial::EMISSIVE);
            builder.AddBox(Vec3(0.0f, 0.145f, 0.096f),
                           Vec3(0.062f, 0.03f, 0.01f));
        }
    }
}

void BuildUpperArm(MeshBuilder& builder, const CharacterStyle& style)
{
    const float r = style.bulk;
    const SurfaceMaterial cloth = style.longCoat ? SurfaceMaterial::PLASTIC
                                                 : SurfaceMaterial::FABRIC;
    SetSurf(builder, style.coat, SurfacePattern::CLOTH, cloth);
    builder.AddBeveledBox(Vec3(0.0f, -0.115f, 0.0f),
                          Vec3(0.058f * r, 0.118f, 0.062f * r), 0.18f);
    // 肩头
    builder.AddSphere(Vec3(0.0f, -0.012f, 0.0f), 0.062f * r, 8, 6);
    // 袖口翻边
    SetSurf(builder, style.coatShade, SurfacePattern::CLOTH, cloth);
    builder.AddBox(Vec3(0.0f, -0.222f, 0.0f),
                   Vec3(0.056f * r, 0.022f, 0.061f * r));
    // 臂章
    SetSurf(builder, style.accent, SurfacePattern::PLAIN,
            SurfaceMaterial::FABRIC);
    builder.AddBox(Vec3(-0.052f * r, -0.12f, 0.014f),
                   Vec3(0.008f, 0.026f, 0.026f));
}

void BuildForeArm(MeshBuilder& builder, const CharacterStyle& style)
{
    const SurfaceMaterial cloth = style.longCoat ? SurfaceMaterial::PLASTIC
                                                 : SurfaceMaterial::FABRIC;
    SetSurf(builder, style.coatShade, SurfacePattern::CLOTH, cloth);
    builder.AddBeveledBox(Vec3(0.0f, -0.105f, 0.0f),
                          Vec3(0.042f, 0.105f, 0.047f), 0.16f);
    // 护腕
    SetSurf(builder, style.belt, SurfacePattern::LEATHER,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(0.0f, -0.196f, 0.0f), Vec3(0.045f, 0.022f, 0.050f));
    SetSurf(builder, style.metal, SurfacePattern::METAL_RIBS,
            SurfaceMaterial::METAL_MATTE);
    builder.AddBox(Vec3(0.0f, -0.183f, 0.046f), Vec3(0.020f, 0.010f, 0.006f));
    // 袖口纽扣
    SetSurf(builder, style.metal, SurfacePattern::PLAIN,
            SurfaceMaterial::METAL_POLISHED);
    builder.AddBox(Vec3(0.0f, -0.20f, 0.05f), Vec3(0.006f, 0.006f, 0.004f));
}

/**
 * @brief 手掌与手指。
 * @param [IN/OUT] builder 网格构建器。
 * @param [IN] style 风格。
 * @param [IN] right 是否右手（左手镜像）。
 */
void BuildHand(MeshBuilder& builder, const CharacterStyle& style, bool right)
{
    const float side = right ? 1.0f : -1.0f;
    SetSurf(builder, style.skin, SurfacePattern::PLAIN,
            SurfaceMaterial::PLASTIC);
    builder.AddBeveledBox(Vec3(0.0f, -0.044f, 0.004f),
                          Vec3(0.035f, 0.040f, 0.031f), 0.3f);
    // 拇指
    builder.AddBox(Vec3(-0.030f * side, -0.038f, 0.020f),
                   Vec3(0.012f, 0.021f, 0.013f));
    // 四指：分成两节，让手不再是一块方砖
    SetSurf(builder, style.skinShade, SurfacePattern::PLAIN,
            SurfaceMaterial::PLASTIC);
    for (int i = 0; i < 4; ++i) {
        const float x = (-0.021f + static_cast<float>(i) * 0.014f) * side;
        builder.AddBox(Vec3(x, -0.072f, 0.008f), Vec3(0.006f, 0.014f, 0.026f));
        builder.AddBox(Vec3(x, -0.086f, 0.016f), Vec3(0.005f, 0.008f, 0.018f));
    }
    // 指节
    SetSurf(builder, style.skin, SurfacePattern::PLAIN,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(0.0f, -0.058f, 0.006f), Vec3(0.032f, 0.010f, 0.027f));
}

/**
 * @brief 手中的武器；作为独立部件挂在右手骨骼下。
 * @param [IN/OUT] builder 网格构建器。
 * @param [IN] style 风格（用于取点缀色）。
 * @param [IN] kind 武器类型。
 */
void BuildWeapon(MeshBuilder& builder, const CharacterStyle& style,
                 WeaponKind kind)
{
    const Color gunmetal(0.10f, 0.10f, 0.11f, 1.0f);
    const Color wood(0.24f, 0.17f, 0.11f, 1.0f);
    switch (kind) {
    case WeaponKind::PISTOL:
        SetSurf(builder, gunmetal, SurfacePattern::METAL_RIBS,
                SurfaceMaterial::METAL_MATTE);
        builder.AddBeveledBox(Vec3(0.0f, -0.050f, 0.072f),
                              Vec3(0.016f, 0.024f, 0.070f), 0.15f);
        builder.AddBox(Vec3(0.0f, -0.052f, 0.148f),
                       Vec3(0.009f, 0.009f, 0.020f));
        // 握把
        SetSurf(builder, Color(0.16f, 0.15f, 0.14f, 1.0f),
                SurfacePattern::LEATHER, SurfaceMaterial::PLASTIC);
        builder.AddBeveledBox(Vec3(0.0f, -0.092f, 0.020f),
                              Vec3(0.016f, 0.038f, 0.024f), 0.2f);
        // 扳机护圈
        SetSurf(builder, gunmetal, SurfacePattern::PLAIN,
                SurfaceMaterial::METAL_MATTE);
        builder.AddBox(Vec3(0.0f, -0.075f, 0.044f), Vec3(0.012f, 0.008f, 0.022f));
        builder.AddBox(Vec3(0.0f, -0.085f, 0.062f), Vec3(0.012f, 0.018f, 0.006f));
        // 准星与指示灯
        SetSurf(builder, style.accent, SurfacePattern::EMISSIVE,
                SurfaceMaterial::EMISSIVE);
        builder.AddBox(Vec3(0.0f, -0.032f, 0.132f), Vec3(0.004f, 0.004f, 0.004f));
        SetSurf(builder, style.accentHi, SurfacePattern::PLAIN,
                SurfaceMaterial::METAL_POLISHED);
        builder.AddBox(Vec3(0.0f, -0.030f, 0.024f), Vec3(0.010f, 0.006f, 0.006f));
        break;
    case WeaponKind::RIFLE:
        SetSurf(builder, gunmetal, SurfacePattern::METAL_RIBS,
                SurfaceMaterial::METAL_MATTE);
        builder.AddBeveledBox(Vec3(0.0f, -0.048f, 0.055f),
                              Vec3(0.018f, 0.026f, 0.115f), 0.12f);
        builder.AddBox(Vec3(0.0f, -0.048f, 0.205f),
                       Vec3(0.009f, 0.009f, 0.09f));
        builder.AddBox(Vec3(0.0f, -0.048f, 0.30f),
                       Vec3(0.014f, 0.014f, 0.014f));
        // 枪托
        SetSurf(builder, wood, SurfacePattern::WOOD, SurfaceMaterial::WOOD);
        builder.AddBeveledBox(Vec3(0.0f, -0.062f, -0.085f),
                              Vec3(0.016f, 0.030f, 0.065f), 0.2f);
        // 握把与弹匣
        SetSurf(builder, Color(0.16f, 0.15f, 0.14f, 1.0f),
                SurfacePattern::LEATHER, SurfaceMaterial::PLASTIC);
        builder.AddBeveledBox(Vec3(0.0f, -0.086f, 0.005f),
                              Vec3(0.014f, 0.032f, 0.024f), 0.2f);
        builder.AddBox(Vec3(0.0f, -0.096f, 0.062f), Vec3(0.012f, 0.036f, 0.020f));
        // 导轨与瞄具
        SetSurf(builder, style.metal, SurfacePattern::METAL_RIBS,
                SurfaceMaterial::METAL_MATTE);
        builder.AddBox(Vec3(0.0f, -0.020f, 0.065f), Vec3(0.012f, 0.008f, 0.09f));
        SetSurf(builder, style.accent, SurfacePattern::EMISSIVE,
                SurfaceMaterial::EMISSIVE);
        builder.AddBox(Vec3(0.0f, -0.012f, 0.10f), Vec3(0.004f, 0.004f, 0.012f));
        break;
    case WeaponKind::PIPE:
        SetSurf(builder, style.metal, SurfacePattern::RUST,
                SurfaceMaterial::METAL_MATTE);
        builder.AddBox(Vec3(0.0f, -0.058f, 0.16f), Vec3(0.019f, 0.019f, 0.30f));
        builder.AddBox(Vec3(0.0f, -0.058f, 0.45f), Vec3(0.022f, 0.022f, 0.03f));
        SetSurf(builder, Color(0.14f, 0.13f, 0.12f, 1.0f),
                SurfacePattern::LEATHER, SurfaceMaterial::PLASTIC);
        builder.AddBox(Vec3(0.0f, -0.058f, -0.02f), Vec3(0.024f, 0.024f, 0.05f));
        break;
    default:
        break;
    }
}

void BuildThigh(MeshBuilder& builder, const CharacterStyle& style)
{
    SetSurf(builder, style.pants, SurfacePattern::CLOTH,
            SurfaceMaterial::FABRIC);
    builder.AddBeveledBox(Vec3(0.0f, -0.215f, 0.0f),
                          Vec3(0.070f * style.bulk, 0.215f,
                               0.080f * style.bulk),
                          0.12f);
    // 侧袋
    SetSurf(builder, ColorScale(style.pants, 0.82f), SurfacePattern::CLOTH,
            SurfaceMaterial::FABRIC);
    builder.AddBox(Vec3(0.052f * style.bulk, -0.20f, 0.050f),
                   Vec3(0.026f, 0.048f, 0.020f));
    // 膝部补丁
    SetSurf(builder, ColorScale(style.pants, 0.7f), SurfacePattern::LEATHER,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(0.0f, -0.375f, 0.060f), Vec3(0.056f, 0.040f, 0.018f));
}

void BuildShin(MeshBuilder& builder, const CharacterStyle& style)
{
    SetSurf(builder, style.pants, SurfacePattern::CLOTH,
            SurfaceMaterial::FABRIC);
    builder.AddBeveledBox(Vec3(0.0f, -0.165f, 0.0f),
                          Vec3(0.056f, 0.165f, 0.062f), 0.1f);
    // 靴筒
    SetSurf(builder, style.boots, SurfacePattern::LEATHER,
            SurfaceMaterial::PLASTIC);
    builder.AddBeveledBox(Vec3(0.0f, -0.295f, 0.006f),
                          Vec3(0.062f, 0.086f, 0.072f), 0.16f);
    SetSurf(builder, style.belt, SurfacePattern::LEATHER,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(0.0f, -0.272f, 0.006f), Vec3(0.065f, 0.008f, 0.075f));
    // 靴口翻边
    SetSurf(builder, ColorScale(style.boots, 1.35f), SurfacePattern::LEATHER,
            SurfaceMaterial::PLASTIC);
    builder.AddBox(Vec3(0.0f, -0.226f, 0.006f), Vec3(0.060f, 0.014f, 0.070f));
    // 鞋带
    SetSurf(builder, style.metal, SurfacePattern::PLAIN,
            SurfaceMaterial::METAL_MATTE);
    builder.AddBox(Vec3(0.0f, -0.30f, 0.072f), Vec3(0.026f, 0.006f, 0.005f));
    builder.AddBox(Vec3(0.0f, -0.32f, 0.070f), Vec3(0.026f, 0.006f, 0.005f));
}

void BuildFoot(MeshBuilder& builder, const CharacterStyle& style)
{
    SetSurf(builder, style.boots, SurfacePattern::LEATHER,
            SurfaceMaterial::PLASTIC);
    builder.AddBeveledBox(Vec3(0.0f, -0.045f, 0.028f),
                          Vec3(0.064f, 0.042f, 0.094f), 0.2f);
    // 鞋头
    builder.AddBox(Vec3(0.0f, -0.058f, 0.110f), Vec3(0.052f, 0.028f, 0.032f));
    // 鞋底与后跟
    SetSurf(builder, Color(0.055f, 0.055f, 0.065f, 1.0f), SurfacePattern::RUBBER,
            SurfaceMaterial::RUBBER);
    builder.AddBox(Vec3(0.0f, -0.083f, 0.034f), Vec3(0.066f, 0.011f, 0.100f));
    builder.AddBox(Vec3(0.0f, -0.070f, -0.045f), Vec3(0.058f, 0.018f, 0.026f));
}

MeshData BuildCharacterMesh(const std::string& name, const CharacterStyle& style)
{
    MeshBuilder builder;

    builder.BeginPart("hips", Vec3(0.0f, HIP_Y, 0.0f));
    BuildHips(builder, style);

    builder.BeginPart("torso", Vec3(0.0f, 0.0f, 0.0f));
    BuildTorso(builder, style);

    builder.BeginPart("head", Vec3(0.0f, NECK_Y, 0.0f));
    BuildHead(builder, style);

    builder.BeginPart("upperArmL", Vec3(-SHOULDER_X, SHOULDER_Y, 0.0f));
    BuildUpperArm(builder, style);
    builder.BeginPart("foreArmL", Vec3(0.0f, ELBOW_Y, 0.0f));
    BuildForeArm(builder, style);
    builder.BeginPart("handL", Vec3(0.0f, WRIST_Y, 0.0f));
    BuildHand(builder, style, false);

    builder.BeginPart("upperArmR", Vec3(SHOULDER_X, SHOULDER_Y, 0.0f));
    BuildUpperArm(builder, style);
    builder.BeginPart("foreArmR", Vec3(0.0f, ELBOW_Y, 0.0f));
    BuildForeArm(builder, style);
    builder.BeginPart("handR", Vec3(0.0f, WRIST_Y, 0.0f));
    BuildHand(builder, style, true);
    builder.BeginPart("weaponR", Vec3(0.0f, 0.0f, 0.0f));
    BuildWeapon(builder, style, style.weapon);

    builder.BeginPart("thighL", Vec3(-HIP_X, 0.0f, 0.0f));
    BuildThigh(builder, style);
    builder.BeginPart("shinL", Vec3(0.0f, KNEE_Y, 0.0f));
    BuildShin(builder, style);
    builder.BeginPart("footL", Vec3(0.0f, ANKLE_Y, 0.0f));
    BuildFoot(builder, style);

    builder.BeginPart("thighR", Vec3(HIP_X, 0.0f, 0.0f));
    BuildThigh(builder, style);
    builder.BeginPart("shinR", Vec3(0.0f, KNEE_Y, 0.0f));
    BuildShin(builder, style);
    builder.BeginPart("footR", Vec3(0.0f, ANKLE_Y, 0.0f));
    BuildFoot(builder, style);

    return builder.Finish(name);
}

// ---------------------------------------------------------------------------
// 姿态
// ---------------------------------------------------------------------------

/**
 * @brief 单帧姿态：各关节的局部欧拉角与偏移。
 */
struct Pose {
    float hipOffsetY = 0.0f;
    float hipRoll = 0.0f;
    float hipYaw = 0.0f;
    float torsoPitch = 0.0f;
    float torsoYaw = 0.0f;
    float torsoRoll = 0.0f;
    float headPitch = 0.0f;
    float headYaw = 0.0f;
    float armOutL = -0.12f;
    float armOutR = 0.12f;
    float armL = 0.0f;
    float foreL = 0.0f;
    float handL = 0.0f;
    float armR = 0.0f;
    float foreR = 0.0f;
    float handR = 0.0f;
    float handRRoll = 0.0f;
    float thighL = 0.0f;
    float shinL = 0.0f;
    float footL = 0.0f;
    float thighR = 0.0f;
    float shinR = 0.0f;
    float footR = 0.0f;
};

Mat4 BoneRotation(const std::string& name, const Pose& pose)
{
    if (name == "hips") {
        return Mat4::RotationY(pose.hipYaw) * Mat4::RotationZ(pose.hipRoll);
    }
    if (name == "torso") {
        return Mat4::RotationX(pose.torsoPitch) *
               Mat4::RotationY(pose.torsoYaw) *
               Mat4::RotationZ(pose.torsoRoll);
    }
    if (name == "head") {
        return Mat4::RotationX(pose.headPitch) * Mat4::RotationY(pose.headYaw);
    }
    if (name == "upperArmL") {
        return Mat4::RotationZ(pose.armOutL) * Mat4::RotationX(pose.armL);
    }
    if (name == "foreArmL") {
        return Mat4::RotationX(pose.foreL);
    }
    if (name == "handL") {
        return Mat4::RotationX(pose.handL);
    }
    if (name == "upperArmR") {
        return Mat4::RotationZ(pose.armOutR) * Mat4::RotationX(pose.armR);
    }
    if (name == "foreArmR") {
        return Mat4::RotationX(pose.foreR);
    }
    if (name == "handR") {
        return Mat4::RotationZ(pose.handRRoll) *
               Mat4::RotationX(pose.handR);
    }
    if (name == "thighL") {
        return Mat4::RotationX(pose.thighL);
    }
    if (name == "shinL") {
        return Mat4::RotationX(pose.shinL);
    }
    if (name == "footL") {
        return Mat4::RotationX(pose.footL);
    }
    if (name == "thighR") {
        return Mat4::RotationX(pose.thighR);
    }
    if (name == "shinR") {
        return Mat4::RotationX(pose.shinR);
    }
    if (name == "footR") {
        return Mat4::RotationX(pose.footR);
    }
    return Mat4::Identity();
}

/** @brief 平滑阶跃：把 0–1 的线性进度变成缓入缓出。 */
float Smooth01(float t)
{
    t = Clamp(t, 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

/** @brief 分段插值：在 [a,b] 段内把 v 从 0 映射到 1。 */
float Segment(float v, float a, float b)
{
    if (b - a < 0.0001f) {
        return v >= b ? 1.0f : 0.0f;
    }
    return Clamp((v - a) / (b - a), 0.0f, 1.0f);
}

Pose MakePose(const CharacterAnim& anim)
{
    Pose pose;
    const float amp = Clamp(anim.walkAmp, 0.0f, 1.0f);
    const float phase = anim.walkPhase;
    const float sw = std::sin(phase);
    const float sw2 = std::sin(phase + PI);
    const float idle = 1.0f - amp;
    const float breath = std::sin(anim.time * 1.55f);
    const bool run = anim.running && amp > 0.15f;

    // ---- 步行 / 奔跑 ----
    const float stride = run ? 0.95f : 0.62f;
    pose.thighL = -sw * stride * amp;
    pose.thighR = -sw2 * stride * amp;
    const float kneeBase = run ? 0.28f : 0.14f;
    const float kneeAmp = run ? 1.05f : 0.62f;
    const float kneeL = kneeBase + kneeAmp * std::max(0.0f, std::sin(phase + 1.25f));
    const float kneeR =
        kneeBase + kneeAmp * std::max(0.0f, std::sin(phase + PI + 1.25f));
    pose.shinL = kneeL * amp;
    pose.shinR = kneeR * amp;
    pose.footL = -(pose.thighL + pose.shinL) * 0.45f;
    pose.footR = -(pose.thighR + pose.shinR) * 0.45f;

    // 重心上下与左右摆动
    const float bob = run ? 0.048f : 0.024f;
    pose.hipOffsetY = -bob * amp * (0.5f + 0.5f * std::cos(phase * 2.0f));
    pose.hipOffsetY += breath * 0.005f * idle;
    pose.hipRoll = sw * (run ? 0.06f : 0.045f) * amp;
    pose.torsoRoll = -sw * (run ? 0.05f : 0.03f) * amp;
    pose.hipYaw = sw * 0.05f * amp;
    pose.torsoYaw = -sw * (run ? 0.10f : 0.055f) * amp;

    // 摆臂：与同侧腿反相；奔跑时手臂弯得更多
    const float armSwing = run ? 0.85f : 0.52f;
    pose.armL = sw * armSwing * amp + breath * 0.02f * idle;
    pose.armR = sw2 * armSwing * amp + breath * 0.02f * idle;
    const float elbow = run ? 1.05f : 0.22f;
    pose.foreL = -(elbow + 0.16f * std::fabs(sw) * amp);
    pose.foreR = -(elbow + 0.16f * std::fabs(sw2) * amp);

    // 躯干前倾：奔跑明显
    pose.torsoPitch = (run ? 0.22f : 0.055f) * amp + breath * 0.010f * idle;
    pose.headPitch = -pose.torsoPitch * 0.55f + breath * 0.008f * idle;
    pose.headYaw = sw * 0.03f * amp + std::sin(anim.time * 0.63f) * 0.05f * idle;

    // ---- 站立：呼吸、重心左右倒、头部微动 ----
    const float shift = std::sin(anim.time * 0.9f);
    pose.hipRoll += shift * 0.022f * idle;
    pose.torsoRoll -= shift * 0.016f * idle;
    pose.hipOffsetY += breath * 0.004f * idle;
    pose.armOutL = -0.12f - 0.02f * idle;
    pose.armOutR = 0.12f + 0.02f * idle;
    pose.foreL += -0.10f * idle;
    pose.foreR += -0.10f * idle;

    // ---- 举枪 / 近战姿态 ----
    const bool melee = anim.meleeProgress >= 0.0f;
    if (melee) {
        // 徒手格斗式：双拳护在胸前，出拳时前手直击。
        const float p = Clamp(anim.meleeProgress, 0.0f, 1.0f);
        const float wind = Segment(p, 0.0f, 0.22f);
        const float punch = Segment(p, 0.22f, 0.45f) - Segment(p, 0.55f, 1.0f);
        const float back = 1.0f - wind * 0.5f;
        pose.armOutL = 0.30f;
        pose.armOutR = -0.26f;
        pose.armR = -0.62f * back - 1.25f * punch;
        pose.foreR = -1.85f * back + 1.55f * punch;
        pose.handR = 0.10f;
        pose.armL = -0.50f - 0.25f * punch;
        pose.foreL = -1.75f;
        pose.handL = -0.05f;
        pose.torsoYaw = anim.aimOffset * 0.5f - 0.32f * wind + 0.55f * punch;
        pose.headYaw = anim.aimOffset * 0.4f;
        pose.torsoPitch = 0.08f + 0.10f * punch;
        pose.handRRoll = 0.0f;
        return pose;
    }

    if (anim.aiming && anim.weapon != WeaponKind::NONE) {
        const bool rifle = anim.weapon == WeaponKind::RIFLE;
        // 右手主握，左手托握：左臂横过胸前靠近右手。
        pose.armR = -1.30f + anim.aimPitch * 0.24f - anim.recoil * 0.26f;
        pose.foreR = (rifle ? -0.45f : -0.30f) + anim.recoil * 0.14f;
        pose.armOutR = 0.14f;
        pose.handR = -0.12f;
        pose.armL = -1.14f + anim.aimPitch * 0.16f;
        pose.foreL = rifle ? -1.20f : -1.34f;
        pose.armOutL = rifle ? 0.86f : 0.68f;
        pose.handL = -0.06f;
        pose.torsoPitch = 0.03f - anim.recoil * 0.09f;
        pose.torsoYaw = anim.aimOffset * 0.55f;
        pose.headYaw = anim.aimOffset * 0.45f;
        pose.headPitch = -anim.aimPitch * 0.16f;
        pose.hipRoll *= 0.4f;
        pose.torsoRoll *= 0.4f;

        if (anim.reloadProgress >= 0.0f) {
            // 换弹：右手压枪下移，左手到腰间取弹匣再送回。
            const float p = Clamp(anim.reloadProgress, 0.0f, 1.0f);
            const float dip = std::sin(p * PI);
            const float reach = Smooth01(Segment(p, 0.05f, 0.42f)) *
                                (1.0f - Smooth01(Segment(p, 0.62f, 0.95f)));
            pose.armR = -1.30f + dip * 0.42f;
            pose.foreR = -0.30f - dip * 0.30f;
            pose.handRRoll = dip * 0.55f;
            pose.armL = -1.14f + reach * 0.55f + dip * 0.25f;
            pose.foreL = -1.34f + reach * 0.10f;
            pose.armOutL = 0.68f - reach * 0.42f;
            pose.torsoPitch = 0.03f + dip * 0.12f;
            pose.headPitch = 0.12f + dip * 0.22f;
            pose.hipRoll *= 0.7f;
        }
        return pose;
    }

    if (anim.weapon != WeaponKind::NONE && !anim.aiming && amp < 0.2f) {
        // 待机持枪：枪口朝下，手臂自然垂落，不再平举。
        pose.armR = -0.22f;
        pose.foreR = -0.55f;
        pose.armOutR = 0.16f;
        pose.handR = 0.18f;
        pose.handRRoll = 0.25f;
        pose.armL = -0.10f;
        pose.foreL = -0.30f;
    }

    if (anim.deathLean > 0.0f) {
        pose.torsoPitch += anim.deathLean * 1.25f;
        pose.torsoRoll += anim.deathLean * 0.35f;
        pose.headPitch += anim.deathLean * 0.4f;
        pose.armL -= anim.deathLean * 0.5f;
        pose.armR -= anim.deathLean * 0.5f;
        pose.thighL -= anim.deathLean * 0.4f;
        pose.shinL += anim.deathLean * 0.8f;
    }
    return pose;
}

} // namespace

const char* CharacterName(CharacterId id)
{
    switch (id) {
    case CharacterId::PLAYER: return "PLAYER";
    case CharacterId::BIGSISTER: return "BIGSISTER";
    case CharacterId::MERCHANT: return "MERCHANT";
    case CharacterId::BARTENDER: return "BARTENDER";
    case CharacterId::SCAVENGER: return "SCAVENGER";
    case CharacterId::AGENT: return "AGENT";
    case CharacterId::THUG: return "THUG";
    default: return "UNKNOWN";
    }
}

void CharacterLibrary::Build(MeshLibrary& meshes)
{
    CharacterStyle player;
    player.skin = Color(0.80f, 0.58f, 0.44f, 1.0f);
    player.skinShade = Color(0.63f, 0.43f, 0.33f, 1.0f);
    player.hair = Color(0.09f, 0.08f, 0.09f, 1.0f);
    player.coat = Color(0.19f, 0.24f, 0.20f, 1.0f);
    player.coatShade = Color(0.13f, 0.16f, 0.14f, 1.0f);
    player.shirt = Color(0.34f, 0.36f, 0.34f, 1.0f);
    player.pants = Color(0.16f, 0.18f, 0.21f, 1.0f);
    player.boots = Color(0.10f, 0.10f, 0.12f, 1.0f);
    player.belt = Color(0.10f, 0.09f, 0.08f, 1.0f);
    player.accent = Color(0.18f, 0.66f, 0.63f, 1.0f);
    player.accentHi = Color(0.52f, 0.86f, 0.82f, 1.0f);
    player.metal = Color(0.40f, 0.43f, 0.45f, 1.0f);
    player.weapon = WeaponKind::PISTOL;
    player.scarf = true;
    player.bandolier = true;
    m_styles[0] = player;

    CharacterStyle sister;
    sister.skin = Color(0.82f, 0.60f, 0.47f, 1.0f);
    sister.skinShade = Color(0.64f, 0.44f, 0.34f, 1.0f);
    sister.hair = Color(0.22f, 0.15f, 0.14f, 1.0f);
    sister.coat = Color(0.52f, 0.16f, 0.23f, 1.0f);
    sister.coatShade = Color(0.34f, 0.10f, 0.15f, 1.0f);
    sister.shirt = Color(0.16f, 0.14f, 0.16f, 1.0f);
    sister.pants = Color(0.09f, 0.09f, 0.11f, 1.0f);
    sister.boots = Color(0.08f, 0.07f, 0.08f, 1.0f);
    sister.belt = Color(0.14f, 0.10f, 0.10f, 1.0f);
    sister.accent = Color(1.0f, 0.70f, 0.28f, 1.0f);
    sister.accentHi = Color(1.0f, 0.87f, 0.60f, 1.0f);
    sister.metal = Color(0.46f, 0.44f, 0.40f, 1.0f);
    sister.height = 1.04f;
    sister.longCoat = true;
    sister.bun = true;
    sister.hairLong = true;
    sister.weapon = WeaponKind::NONE;
    m_styles[1] = sister;

    CharacterStyle merchant;
    merchant.skin = Color(0.76f, 0.55f, 0.42f, 1.0f);
    merchant.skinShade = Color(0.60f, 0.41f, 0.31f, 1.0f);
    merchant.hair = Color(0.17f, 0.13f, 0.11f, 1.0f);
    merchant.coat = Color(0.34f, 0.28f, 0.19f, 1.0f);
    merchant.coatShade = Color(0.23f, 0.19f, 0.13f, 1.0f);
    merchant.shirt = Color(0.44f, 0.36f, 0.24f, 1.0f);
    merchant.pants = Color(0.18f, 0.17f, 0.15f, 1.0f);
    merchant.boots = Color(0.12f, 0.11f, 0.10f, 1.0f);
    merchant.belt = Color(0.16f, 0.13f, 0.10f, 1.0f);
    merchant.accent = Color(0.80f, 0.64f, 0.16f, 1.0f);
    merchant.accentHi = Color(1.0f, 0.86f, 0.48f, 1.0f);
    merchant.metal = Color(0.40f, 0.40f, 0.38f, 1.0f);
    merchant.height = 0.96f;
    merchant.bulk = 1.14f;
    merchant.vest = true;
    merchant.goggles = true;
    merchant.backpack = true;
    merchant.bald = true;
    merchant.weapon = WeaponKind::NONE;
    m_styles[2] = merchant;

    CharacterStyle bartender;
    bartender.skin = Color(0.80f, 0.58f, 0.44f, 1.0f);
    bartender.skinShade = Color(0.63f, 0.43f, 0.33f, 1.0f);
    bartender.hair = Color(0.30f, 0.20f, 0.14f, 1.0f);
    bartender.coat = Color(0.74f, 0.72f, 0.66f, 1.0f);
    bartender.coatShade = Color(0.56f, 0.54f, 0.50f, 1.0f);
    bartender.shirt = Color(0.86f, 0.84f, 0.78f, 1.0f);
    bartender.pants = Color(0.15f, 0.17f, 0.19f, 1.0f);
    bartender.boots = Color(0.11f, 0.10f, 0.10f, 1.0f);
    bartender.belt = Color(0.28f, 0.20f, 0.14f, 1.0f);
    bartender.accent = Color(0.42f, 0.26f, 0.16f, 1.0f);
    bartender.accentHi = Color(0.72f, 0.52f, 0.30f, 1.0f);
    bartender.metal = Color(0.50f, 0.48f, 0.44f, 1.0f);
    bartender.height = 0.99f;
    bartender.bulk = 1.08f;
    bartender.apron = true;
    bartender.vest = true;
    bartender.weapon = WeaponKind::NONE;
    m_styles[3] = bartender;

    CharacterStyle scavenger;
    scavenger.skin = Color(0.58f, 0.47f, 0.37f, 1.0f);
    scavenger.skinShade = Color(0.44f, 0.35f, 0.28f, 1.0f);
    scavenger.hair = Color(0.14f, 0.13f, 0.12f, 1.0f);
    scavenger.coat = Color(0.27f, 0.26f, 0.21f, 1.0f);
    scavenger.coatShade = Color(0.18f, 0.17f, 0.14f, 1.0f);
    scavenger.shirt = Color(0.30f, 0.28f, 0.22f, 1.0f);
    scavenger.pants = Color(0.20f, 0.19f, 0.16f, 1.0f);
    scavenger.boots = Color(0.12f, 0.11f, 0.09f, 1.0f);
    scavenger.belt = Color(0.24f, 0.19f, 0.13f, 1.0f);
    scavenger.accent = Color(1.0f, 0.54f, 0.24f, 1.0f);
    scavenger.accentHi = Color(1.0f, 0.76f, 0.48f, 1.0f);
    scavenger.metal = Color(0.36f, 0.35f, 0.32f, 1.0f);
    scavenger.height = 0.97f;
    scavenger.bulk = 1.10f;
    scavenger.hood = true;
    scavenger.mask = true;
    scavenger.goggles = true;
    scavenger.backpack = true;
    scavenger.weapon = WeaponKind::RIFLE;
    m_styles[4] = scavenger;

    CharacterStyle agent;
    agent.skin = Color(0.26f, 0.28f, 0.31f, 1.0f);
    agent.skinShade = Color(0.15f, 0.17f, 0.19f, 1.0f);
    agent.hair = Color(0.07f, 0.08f, 0.10f, 1.0f);
    agent.coat = Color(0.12f, 0.14f, 0.18f, 1.0f);
    agent.coatShade = Color(0.07f, 0.08f, 0.11f, 1.0f);
    agent.shirt = Color(0.20f, 0.22f, 0.26f, 1.0f);
    agent.pants = Color(0.09f, 0.10f, 0.12f, 1.0f);
    agent.boots = Color(0.06f, 0.06f, 0.08f, 1.0f);
    agent.belt = Color(0.10f, 0.10f, 0.12f, 1.0f);
    agent.accent = Color(0.55f, 0.86f, 0.95f, 1.0f);
    agent.accentHi = Color(0.86f, 0.95f, 1.0f, 1.0f);
    agent.metal = Color(0.55f, 0.58f, 0.62f, 1.0f);
    agent.height = 1.02f;
    agent.bulk = 1.02f;
    agent.helmet = true;
    agent.visor = true;
    agent.shoulderPads = true;
    agent.weapon = WeaponKind::RIFLE;
    m_styles[5] = agent;

    CharacterStyle thug;
    thug.skin = Color(0.66f, 0.50f, 0.38f, 1.0f);
    thug.skinShade = Color(0.50f, 0.37f, 0.28f, 1.0f);
    thug.hair = Color(0.10f, 0.09f, 0.09f, 1.0f);
    thug.coat = Color(0.36f, 0.22f, 0.20f, 1.0f);
    thug.coatShade = Color(0.24f, 0.14f, 0.13f, 1.0f);
    thug.shirt = Color(0.28f, 0.24f, 0.20f, 1.0f);
    thug.pants = Color(0.22f, 0.20f, 0.17f, 1.0f);
    thug.boots = Color(0.14f, 0.12f, 0.10f, 1.0f);
    thug.belt = Color(0.28f, 0.16f, 0.14f, 1.0f);
    thug.accent = Color(0xE0, 0x4A, 0x3A, 1.0f);
    thug.accentHi = Color(1.0f, 0.66f, 0.50f, 1.0f);
    thug.metal = Color(0.45f, 0.43f, 0.40f, 1.0f);
    thug.height = 1.08f;
    thug.bulk = 1.22f;
    thug.hood = true;
    thug.mask = true;
    thug.shoulderPads = true;
    thug.bandolier = true;
    thug.weapon = WeaponKind::PIPE;
    m_styles[6] = thug;

    // 统一提亮：保证角色在暗场景里依然有可读的剪影。
    for (int i = 0; i < CHARACTER_COUNT; ++i) {
        BrightenStyle(m_styles[i], 1.28f);
    }

    static const char* kMeshNames[CHARACTER_COUNT] = {
        "CHAR_PLAYER", "CHAR_BIGSISTER", "CHAR_MERCHANT", "CHAR_BARTENDER",
        "CHAR_SCAVENGER", "CHAR_AGENT", "CHAR_THUG"};
    for (int i = 0; i < CHARACTER_COUNT; ++i) {
        m_meshes[i] = meshes.AddMesh(
            BuildCharacterMesh(kMeshNames[i], m_styles[i]), kMeshNames[i]);
    }
}

const Mesh* CharacterLibrary::Get(CharacterId id) const
{
    const int index = static_cast<int>(id);
    if (index < 0 || index >= CHARACTER_COUNT) {
        return nullptr;
    }
    return m_meshes[index];
}

const CharacterStyle& CharacterLibrary::Style(CharacterId id) const
{
    const int index = ClampInt(static_cast<int>(id), 0, CHARACTER_COUNT - 1);
    return m_styles[index];
}

void CharacterLibrary::Draw(RenderDevice& device, const Mesh& mesh,
                            const Mat4& base, const CharacterAnim& anim,
                            const Color& tint) const
{
    const Pose pose = MakePose(anim);

    // 预先按名字索引部件，避免每帧字符串比较。
    const MeshPart* parts[BONE_COUNT] = {};
    for (const MeshPart& part : mesh.parts) {
        for (int i = 0; i < BONE_COUNT; ++i) {
            if (part.name == kSkeleton[i].name) {
                parts[i] = &part;
                break;
            }
        }
    }

    Color partTint = tint;
    if (anim.hitFlash > 0.0f) {
        partTint = Color(1.0f, 0.42f, 0.42f, tint.a);
    }
    partTint.a *= anim.alpha;

    Mat4 world[BONE_COUNT];
    for (int i = 0; i < BONE_COUNT; ++i) {
        world[i] = Mat4::Identity();
    }

    for (int i = 0; i < BONE_COUNT; ++i) {
        const MeshPart* part = parts[i];
        if (part == nullptr) {
            continue;
        }
        Mat4 parentWorld = Mat4::Identity();
        if (kSkeleton[i].parent != nullptr) {
            for (int p = 0; p < BONE_COUNT; ++p) {
                if (kSkeleton[p].name == kSkeleton[i].parent) {
                    parentWorld = world[p];
                    break;
                }
            }
        }
        Vec3 offset = part->pivot;
        if (kSkeleton[i].parent == nullptr) {
            offset.y += pose.hipOffsetY;
        }
        Mat4 rotation = BoneRotation(part->name, pose);
        world[i] = rotation * Mat4::Translation(offset) * parentWorld;
    }

    for (int i = 0; i < BONE_COUNT; ++i) {
        const MeshPart* part = parts[i];
        if (part == nullptr || part->indexCount == 0) {
            continue;
        }
        // 空手或与武器类型不符时隐藏武器部件。
        const bool isWeapon = std::strcmp(kSkeleton[i].name, "weaponR") == 0;
        if (isWeapon && (!anim.showWeapon || anim.weapon == WeaponKind::NONE)) {
            continue;
        }
        device.DrawMeshPart(*part, world[i] * base, partTint);
    }
}

} // namespace fc
