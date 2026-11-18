#include "Game_Characters.hpp"

#include "Shared_Math.hpp"

#include <string>
#include <unordered_map>
#include <vector>

namespace fc {

namespace {

const Color WHITE = Color(1.0f, 1.0f, 1.0f, 1.0f);

// ---- 骨架比例（米，身高 1.70 m）----
constexpr float HIP_Y = 0.90f;        ///< 髋关节高度。
constexpr float HIP_X = 0.10f;        ///< 髋关节左右偏移。
constexpr float SHOULDER_X = 0.205f;  ///< 肩关节左右偏移。
constexpr float SHOULDER_Y = 0.41f;   ///< 肩关节相对腰关节的高度。
constexpr float ELBOW_Y = -0.25f;     ///< 肘相对肩的偏移。
constexpr float WRIST_Y = -0.225f;    ///< 腕相对肘的偏移。
constexpr float KNEE_Y = -0.44f;      ///< 膝相对髋的偏移。
constexpr float ANKLE_Y = -0.37f;     ///< 踝相对膝的偏移。
constexpr float NECK_Y = 0.48f;       ///< 颈相对腰的偏移。

/**
 * @brief 骨骼链：名称与父骨骼。
 *
 * 数组顺序必须是父在子之前，`Draw` 依赖该顺序做一次自顶向下遍历。
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
    {"thighL", "hips"},
    {"shinL", "thighL"},
    {"footL", "shinL"},
    {"thighR", "hips"},
    {"shinR", "thighR"},
    {"footR", "shinR"}
};

void SetMat(MeshBuilder& builder, const Color& color, int pattern)
{
    builder.SetColor(color);
    builder.SetPattern(pattern);
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

void BuildHips(MeshBuilder& builder, const CharacterStyle& style)
{
    const float w = 0.155f * style.bulk;
    const float d = 0.105f * style.bulk;

    SetMat(builder, style.pants, 5);
    builder.AddBeveledBox(Vec3(0.0f, -0.04f, 0.0f),
                          Vec3(w, 0.10f, d), 0.22f);
    // 大腿根部，填住髋与腿之间的缝。
    builder.AddBox(Vec3(-HIP_X, -0.07f, 0.0f), Vec3(0.082f, 0.075f, d * 0.92f));
    builder.AddBox(Vec3(HIP_X, -0.07f, 0.0f), Vec3(0.082f, 0.075f, d * 0.92f));

    SetMat(builder, style.belt, 0);
    builder.AddBox(Vec3(0.0f, 0.048f, 0.0f), Vec3(w + 0.008f, 0.028f, d + 0.008f));
    SetMat(builder, style.accent, 3);
    builder.AddBox(Vec3(0.0f, 0.048f, d + 0.006f), Vec3(0.034f, 0.022f, 0.012f));

    // 腰带上的小挂件，让腰线不再是一条直边。
    SetMat(builder, style.belt, 0);
    builder.AddBox(Vec3(w * 0.7f, 0.02f, d * 0.55f), Vec3(0.03f, 0.05f, 0.02f));
}

void BuildTorso(MeshBuilder& builder, const CharacterStyle& style)
{
    const float w = 0.185f * style.bulk;
    const float d = 0.105f * style.bulk;

    // 腹部
    SetMat(builder, style.coatShade, 2);
    builder.AddBeveledBox(Vec3(0.0f, 0.115f, 0.0f),
                          Vec3(w * 0.86f, 0.105f, d * 0.94f), 0.2f);
    // 胸腔
    SetMat(builder, style.coat, style.longCoat ? 5 : 2);
    builder.AddBeveledBox(Vec3(0.0f, 0.30f, 0.0f), Vec3(w, 0.135f, d), 0.16f);
    // 肩线
    builder.AddBox(Vec3(0.0f, 0.412f, 0.0f),
                   Vec3(w + 0.028f, 0.042f, d + 0.004f));

    // 内衬（背心/围裙角色露出衬衫）
    if (style.vest || style.apron) {
        SetMat(builder, style.shirt, 5);
        builder.AddBox(Vec3(0.0f, 0.33f, d * 0.72f),
                       Vec3(w * 0.40f, 0.13f, 0.016f));
        SetMat(builder, style.shirt, 5);
        builder.AddBox(Vec3(0.0f, 0.44f, 0.0f), Vec3(0.075f, 0.028f, d * 0.86f));
    }

    // 中缝
    SetMat(builder, style.coatShade, 0);
    builder.AddBox(Vec3(0.0f, 0.30f, d + 0.003f), Vec3(0.006f, 0.13f, 0.004f));

    // 口袋
    SetMat(builder, style.coatShade, 5);
    builder.AddBox(Vec3(w * 0.56f, 0.16f, d * 0.62f),
                   Vec3(0.048f, 0.042f, 0.014f));
    builder.AddBox(Vec3(-w * 0.56f, 0.16f, d * 0.62f),
                   Vec3(0.048f, 0.042f, 0.014f));

    if (style.vest) {
        SetMat(builder, Color(0.15f, 0.18f, 0.19f, 1.0f), 5);
        builder.AddBox(Vec3(0.0f, 0.27f, d * 0.92f),
                       Vec3(w * 0.78f, 0.13f, 0.012f));
        builder.AddBox(Vec3(-w * 0.86f, 0.29f, 0.0f),
                       Vec3(0.026f, 0.15f, d * 0.92f));
        builder.AddBox(Vec3(w * 0.86f, 0.29f, 0.0f),
                       Vec3(0.026f, 0.15f, d * 0.92f));
        SetMat(builder, style.accent, 0);
        builder.AddBox(Vec3(-w * 0.42f, 0.13f, d * 0.98f),
                       Vec3(0.042f, 0.038f, 0.014f));
        builder.AddBox(Vec3(-w * 0.42f, 0.21f, d * 0.96f),
                       Vec3(0.014f, 0.036f, 0.010f));
    }

    if (style.apron) {
        SetMat(builder, Color(0.26f, 0.22f, 0.18f, 1.0f), 5);
        builder.AddBox(Vec3(0.0f, 0.20f, d * 0.84f),
                       Vec3(w * 0.60f, 0.21f, 0.012f));
        builder.AddBox(Vec3(0.0f, 0.41f, d * 0.86f),
                       Vec3(w * 0.46f, 0.012f, 0.010f));
        SetMat(builder, Color(0.18f, 0.15f, 0.12f, 1.0f), 0);
        builder.AddBox(Vec3(0.0f, 0.20f, d * 0.86f),
                       Vec3(w * 0.52f, 0.006f, 0.006f));
    }

    if (style.longCoat) {
        SetMat(builder, style.coat, 5);
        builder.AddBeveledBox(Vec3(0.0f, -0.11f, 0.0f),
                              Vec3(w * 1.02f, 0.16f, d * 1.03f), 0.08f);
        SetMat(builder, style.coatShade, 5);
        builder.AddBox(Vec3(0.0f, -0.235f, 0.0f),
                       Vec3(w * 1.06f, 0.032f, d * 1.06f));
        SetMat(builder, Color(0.05f, 0.05f, 0.06f, 1.0f), 0);
        builder.AddBox(Vec3(0.0f, -0.10f, d * 1.02f),
                       Vec3(0.010f, 0.15f, 0.008f));
    }

    if (style.scarf) {
        SetMat(builder, style.accent, 5);
        builder.AddBeveledBox(Vec3(0.0f, 0.435f, 0.0f),
                              Vec3(w * 0.90f, 0.042f, d * 1.02f), 0.3f);
        SetMat(builder, style.accentHi, 5);
        builder.AddBox(Vec3(0.0f, 0.435f, d * 0.62f),
                       Vec3(w * 0.52f, 0.014f, 0.012f));
        SetMat(builder, style.accent, 5);
        builder.AddBox(Vec3(w * 0.62f, 0.29f, -d * 0.72f),
                       Vec3(0.042f, 0.14f, 0.018f));
    }

    if (style.backpack) {
        SetMat(builder, Color(0.20f, 0.19f, 0.16f, 1.0f), 5);
        builder.AddBeveledBox(Vec3(0.0f, 0.24f, -d - 0.065f),
                              Vec3(w * 0.58f, 0.14f, 0.07f), 0.22f);
        SetMat(builder, style.accent, 0);
        builder.AddBox(Vec3(0.0f, 0.30f, -d - 0.132f),
                       Vec3(0.028f, 0.018f, 0.006f));
        SetMat(builder, Color(0.13f, 0.13f, 0.12f, 1.0f), 5);
        builder.AddBox(Vec3(-w * 0.5f, 0.30f, -d * 0.5f),
                       Vec3(0.026f, 0.14f, 0.018f));
        builder.AddBox(Vec3(w * 0.5f, 0.30f, -d * 0.5f),
                       Vec3(0.026f, 0.14f, 0.018f));
    }

    if (style.bandolier) {
        SetMat(builder, Color(0.26f, 0.21f, 0.14f, 1.0f), 5);
        builder.AddBox(Vec3(-w * 0.34f, 0.40f, d * 0.90f), Vec3(0.036f, 0.03f, 0.012f));
        builder.AddBox(Vec3(-w * 0.10f, 0.34f, d * 0.92f), Vec3(0.036f, 0.03f, 0.012f));
        builder.AddBox(Vec3(w * 0.16f, 0.28f, d * 0.92f), Vec3(0.036f, 0.03f, 0.012f));
        builder.AddBox(Vec3(w * 0.42f, 0.22f, d * 0.90f), Vec3(0.036f, 0.03f, 0.012f));
    }

    if (style.shoulderPads) {
        SetMat(builder, style.metal, 3);
        builder.AddBeveledBox(Vec3(-w - 0.012f, 0.408f, 0.0f),
                              Vec3(0.066f, 0.045f, d * 1.02f), 0.34f);
        builder.AddBeveledBox(Vec3(w + 0.012f, 0.408f, 0.0f),
                              Vec3(0.066f, 0.045f, d * 1.02f), 0.34f);
    }
}

void BuildHead(MeshBuilder& builder, const CharacterStyle& style)
{
    // 颈
    SetMat(builder, style.skinShade, 0);
    builder.AddCylinder(Vec3(0.0f, -0.02f, 0.0f), 0.052f, 0.048f, 0.075f, 8);

    if (style.helmet) {
        // 全罩头盔：没有面部，只有一个发光面甲。
        SetMat(builder, style.coat, 3);
        builder.AddBeveledBox(Vec3(0.0f, 0.135f, 0.0f),
                              Vec3(0.108f, 0.125f, 0.112f), 0.32f);
        SetMat(builder, style.metal, 3);
        builder.AddBox(Vec3(0.0f, 0.045f, 0.045f), Vec3(0.09f, 0.05f, 0.058f));
        builder.AddBox(Vec3(0.0f, 0.20f, -0.02f), Vec3(0.05f, 0.035f, 0.09f));
        SetMat(builder, style.accentHi, 8);
        builder.AddBox(Vec3(0.0f, 0.158f, 0.108f), Vec3(0.074f, 0.020f, 0.008f));
        SetMat(builder, style.metal, 3);
        builder.AddBox(Vec3(0.086f, 0.14f, 0.03f), Vec3(0.018f, 0.05f, 0.05f));
        builder.AddBox(Vec3(-0.086f, 0.14f, 0.03f), Vec3(0.018f, 0.05f, 0.05f));
        return;
    }

    // 头骨
    SetMat(builder, style.skin, 0);
    builder.AddBeveledBox(Vec3(0.0f, 0.135f, 0.0f),
                          Vec3(0.098f, 0.112f, 0.10f), 0.28f);
    // 下颌
    builder.AddBox(Vec3(0.0f, 0.052f, 0.012f), Vec3(0.072f, 0.036f, 0.082f));
    // 耳朵
    SetMat(builder, style.skinShade, 0);
    builder.AddBox(Vec3(-0.098f, 0.128f, 0.004f), Vec3(0.012f, 0.026f, 0.018f));
    builder.AddBox(Vec3(0.098f, 0.128f, 0.004f), Vec3(0.012f, 0.026f, 0.018f));
    // 鼻
    builder.AddBox(Vec3(0.0f, 0.122f, 0.102f), Vec3(0.014f, 0.022f, 0.014f));
    // 眉骨
    builder.AddBox(Vec3(0.0f, 0.184f, 0.092f), Vec3(0.082f, 0.012f, 0.012f));

    // 眼
    SetMat(builder, Color(0.05f, 0.045f, 0.05f, 1.0f), 0);
    builder.AddBox(Vec3(-0.041f, 0.162f, 0.097f), Vec3(0.025f, 0.017f, 0.006f));
    builder.AddBox(Vec3(0.041f, 0.162f, 0.097f), Vec3(0.025f, 0.017f, 0.006f));
    SetMat(builder, Color(0.86f, 0.84f, 0.80f, 1.0f), 0);
    builder.AddBox(Vec3(-0.041f, 0.162f, 0.103f), Vec3(0.016f, 0.011f, 0.003f));
    builder.AddBox(Vec3(0.041f, 0.162f, 0.103f), Vec3(0.016f, 0.011f, 0.003f));
    SetMat(builder, Color(0.09f, 0.08f, 0.09f, 1.0f), 0);
    builder.AddBox(Vec3(-0.045f, 0.161f, 0.106f), Vec3(0.007f, 0.008f, 0.002f));
    builder.AddBox(Vec3(0.045f, 0.161f, 0.106f), Vec3(0.007f, 0.008f, 0.002f));

    // 嘴
    SetMat(builder, style.skinShade, 0);
    builder.AddBox(Vec3(0.0f, 0.076f, 0.098f), Vec3(0.026f, 0.007f, 0.004f));

    // 头发
    if (!style.bald && !style.hood) {
        SetMat(builder, style.hair, 0);
        builder.AddBeveledBox(Vec3(0.0f, 0.223f, -0.006f),
                              Vec3(0.104f, 0.045f, 0.106f), 0.32f);
        builder.AddBox(Vec3(0.0f, 0.155f, -0.093f), Vec3(0.098f, 0.082f, 0.022f));
        builder.AddBox(Vec3(-0.092f, 0.178f, 0.018f), Vec3(0.016f, 0.048f, 0.068f));
        builder.AddBox(Vec3(0.092f, 0.178f, 0.018f), Vec3(0.016f, 0.048f, 0.068f));
        if (style.hairLong) {
            builder.AddBox(Vec3(0.0f, 0.06f, -0.10f), Vec3(0.092f, 0.13f, 0.028f));
            builder.AddBox(Vec3(-0.086f, 0.09f, -0.02f), Vec3(0.018f, 0.11f, 0.055f));
            builder.AddBox(Vec3(0.086f, 0.09f, -0.02f), Vec3(0.018f, 0.11f, 0.055f));
        }
        if (style.bun) {
            builder.AddSphere(Vec3(0.0f, 0.232f, -0.116f), 0.050f, 8, 6);
        }
    }

    if (style.hood) {
        SetMat(builder, style.coat, 5);
        builder.AddBeveledBox(Vec3(0.0f, 0.185f, -0.012f),
                              Vec3(0.128f, 0.152f, 0.13f), 0.3f);
        builder.AddBox(Vec3(0.0f, 0.09f, -0.098f), Vec3(0.118f, 0.10f, 0.05f));
        builder.AddBox(Vec3(-0.112f, 0.12f, 0.03f), Vec3(0.018f, 0.09f, 0.08f));
        builder.AddBox(Vec3(0.112f, 0.12f, 0.03f), Vec3(0.018f, 0.09f, 0.08f));
        // 兜帽内的阴影
        SetMat(builder, Color(0.05f, 0.045f, 0.05f, 1.0f), 0);
        builder.AddBox(Vec3(0.0f, 0.14f, 0.086f), Vec3(0.088f, 0.078f, 0.03f));
        SetMat(builder, style.skin, 0);
        builder.AddBox(Vec3(0.0f, 0.13f, 0.104f), Vec3(0.072f, 0.062f, 0.014f));
        SetMat(builder, Color(0.05f, 0.045f, 0.05f, 1.0f), 0);
        builder.AddBox(Vec3(-0.032f, 0.152f, 0.114f), Vec3(0.020f, 0.012f, 0.004f));
        builder.AddBox(Vec3(0.032f, 0.152f, 0.114f), Vec3(0.020f, 0.012f, 0.004f));
    }

    if (style.goggles) {
        SetMat(builder, style.metal, 3);
        builder.AddBox(Vec3(0.0f, 0.242f, 0.052f), Vec3(0.10f, 0.022f, 0.03f));
        SetMat(builder, style.accent, 8);
        builder.AddBox(Vec3(-0.048f, 0.242f, 0.082f), Vec3(0.032f, 0.017f, 0.006f));
        builder.AddBox(Vec3(0.048f, 0.242f, 0.082f), Vec3(0.032f, 0.017f, 0.006f));
    }

    if (style.mask) {
        SetMat(builder, Color(0.10f, 0.10f, 0.11f, 1.0f), 5);
        builder.AddBox(Vec3(0.0f, 0.048f, 0.086f), Vec3(0.076f, 0.048f, 0.016f));
        SetMat(builder, style.accent, 3);
        builder.AddBox(Vec3(0.0f, 0.052f, 0.10f), Vec3(0.038f, 0.007f, 0.004f));
    }

    if (style.visor) {
        SetMat(builder, style.accentHi, 8);
        builder.AddBox(Vec3(0.0f, 0.164f, 0.10f), Vec3(0.080f, 0.020f, 0.008f));
    }
}

void BuildUpperArm(MeshBuilder& builder, const CharacterStyle& style)
{
    const float r = style.bulk;
    SetMat(builder, style.coat, style.longCoat ? 5 : 2);
    builder.AddBeveledBox(Vec3(0.0f, -0.115f, 0.0f),
                          Vec3(0.058f * r, 0.122f, 0.062f * r), 0.18f);
    // 肩头
    builder.AddSphere(Vec3(0.0f, -0.012f, 0.0f), 0.062f * r, 8, 6);
    // 卷袖
    SetMat(builder, style.coatShade, 5);
    builder.AddBox(Vec3(0.0f, -0.223f, 0.0f),
                   Vec3(0.054f * r, 0.022f, 0.059f * r));
}

void BuildForeArm(MeshBuilder& builder, const CharacterStyle& style)
{
    SetMat(builder, style.coatShade, style.longCoat ? 5 : 2);
    builder.AddBeveledBox(Vec3(0.0f, -0.105f, 0.0f),
                          Vec3(0.042f, 0.108f, 0.047f), 0.16f);
    // 护腕
    SetMat(builder, style.belt, 5);
    builder.AddBox(Vec3(0.0f, -0.198f, 0.0f), Vec3(0.045f, 0.020f, 0.050f));
    SetMat(builder, style.metal, 3);
    builder.AddBox(Vec3(0.0f, -0.183f, 0.046f), Vec3(0.020f, 0.010f, 0.006f));
}

void BuildHand(MeshBuilder& builder, const CharacterStyle& style, bool right)
{
    SetMat(builder, style.skin, 0);
    builder.AddBeveledBox(Vec3(0.0f, -0.044f, 0.004f),
                          Vec3(0.037f, 0.042f, 0.032f), 0.3f);
    // 拇指
    builder.AddBox(Vec3(right ? -0.031f : 0.031f, -0.038f, 0.020f),
                   Vec3(0.013f, 0.021f, 0.013f));
    // 指节
    SetMat(builder, style.skinShade, 0);
    builder.AddBox(Vec3(0.0f, -0.078f, 0.006f), Vec3(0.033f, 0.011f, 0.029f));

    if (!right) {
        return;
    }
    switch (style.weapon) {
    case WeaponKind::PISTOL: {
        SetMat(builder, Color(0.09f, 0.09f, 0.10f, 1.0f), 3);
        builder.AddBox(Vec3(0.0f, -0.055f, 0.062f), Vec3(0.017f, 0.026f, 0.062f));
        builder.AddBox(Vec3(0.0f, -0.092f, 0.020f), Vec3(0.016f, 0.024f, 0.024f));
        SetMat(builder, Color(0.20f, 0.19f, 0.18f, 1.0f), 2);
        builder.AddBox(Vec3(0.0f, -0.090f, 0.020f), Vec3(0.017f, 0.022f, 0.020f));
        SetMat(builder, style.accent, 8);
        builder.AddBox(Vec3(0.0f, -0.038f, 0.126f), Vec3(0.005f, 0.005f, 0.004f));
        break;
    }
    case WeaponKind::RIFLE: {
        SetMat(builder, Color(0.10f, 0.10f, 0.11f, 1.0f), 3);
        builder.AddBox(Vec3(0.0f, -0.055f, 0.10f), Vec3(0.016f, 0.024f, 0.14f));
        builder.AddBox(Vec3(0.0f, -0.075f, 0.16f), Vec3(0.008f, 0.008f, 0.08f));
        builder.AddBox(Vec3(0.0f, -0.095f, 0.010f), Vec3(0.014f, 0.022f, 0.05f));
        SetMat(builder, Color(0.22f, 0.20f, 0.17f, 1.0f), 2);
        builder.AddBox(Vec3(0.0f, -0.055f, -0.03f), Vec3(0.016f, 0.028f, 0.05f));
        SetMat(builder, style.accent, 8);
        builder.AddBox(Vec3(0.0f, -0.033f, 0.115f), Vec3(0.004f, 0.004f, 0.006f));
        break;
    }
    case WeaponKind::PIPE: {
        SetMat(builder, style.metal, 4);
        builder.AddCylinder(Vec3(0.0f, -0.05f, 0.02f), 0.016f, 0.014f, 0.42f, 6);
        break;
    }
    default:
        break;
    }
}

void BuildThigh(MeshBuilder& builder, const CharacterStyle& style)
{
    SetMat(builder, style.pants, 5);
    builder.AddBeveledBox(Vec3(0.0f, -0.215f, 0.0f),
                          Vec3(0.072f * style.bulk, 0.215f, 0.082f * style.bulk),
                          0.12f);
    // 侧袋
    SetMat(builder, ColorScale(style.pants, 0.82f), 5);
    builder.AddBox(Vec3(0.056f * style.bulk, -0.20f, 0.052f),
                   Vec3(0.026f, 0.048f, 0.018f));
    // 膝部补丁
    SetMat(builder, ColorScale(style.pants, 0.7f), 5);
    builder.AddBox(Vec3(0.0f, -0.38f, 0.062f), Vec3(0.058f, 0.042f, 0.018f));
}

void BuildShin(MeshBuilder& builder, const CharacterStyle& style)
{
    SetMat(builder, style.pants, 5);
    builder.AddBeveledBox(Vec3(0.0f, -0.165f, 0.0f),
                          Vec3(0.058f, 0.165f, 0.064f), 0.1f);
    // 靴筒
    SetMat(builder, style.boots, 2);
    builder.AddBeveledBox(Vec3(0.0f, -0.295f, 0.006f),
                          Vec3(0.064f, 0.088f, 0.074f), 0.16f);
    SetMat(builder, style.belt, 0);
    builder.AddBox(Vec3(0.0f, -0.272f, 0.006f), Vec3(0.067f, 0.008f, 0.077f));
    // 靴口翻边
    SetMat(builder, ColorScale(style.boots, 1.35f), 2);
    builder.AddBox(Vec3(0.0f, -0.226f, 0.006f), Vec3(0.062f, 0.014f, 0.072f));
}

void BuildFoot(MeshBuilder& builder, const CharacterStyle& style)
{
    SetMat(builder, style.boots, 2);
    builder.AddBeveledBox(Vec3(0.0f, -0.045f, 0.028f),
                          Vec3(0.066f, 0.042f, 0.096f), 0.2f);
    // 鞋头
    builder.AddBox(Vec3(0.0f, -0.058f, 0.112f), Vec3(0.054f, 0.028f, 0.034f));
    // 鞋底
    SetMat(builder, Color(0.055f, 0.055f, 0.065f, 1.0f), 0);
    builder.AddBox(Vec3(0.0f, -0.083f, 0.034f), Vec3(0.068f, 0.011f, 0.102f));
    // 鞋带
    SetMat(builder, style.metal, 3);
    builder.AddBox(Vec3(0.0f, -0.030f, 0.062f), Vec3(0.030f, 0.008f, 0.006f));
    builder.AddBox(Vec3(0.0f, -0.040f, 0.048f), Vec3(0.030f, 0.008f, 0.006f));
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

/**
 * @brief 单帧姿态：各关节的局部欧拉角与偏移。
 */
struct Pose {
    float hipOffsetY = 0.0f;
    float hipRoll = 0.0f;
    float torsoPitch = 0.0f;
    float torsoYaw = 0.0f;
    float torsoRoll = 0.0f;
    float headPitch = 0.0f;
    float headYaw = 0.0f;
    float armOutL = -0.12f;
    float armOutR = 0.12f;
    float armL = 0.0f;
    float foreL = 0.0f;
    float armR = 0.0f;
    float foreR = 0.0f;
    float handR = 0.0f;
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
        return Mat4::RotationZ(pose.hipRoll);
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
    if (name == "upperArmR") {
        return Mat4::RotationZ(pose.armOutR) * Mat4::RotationX(pose.armR);
    }
    if (name == "foreArmR") {
        return Mat4::RotationX(pose.foreR);
    }
    if (name == "handR") {
        return Mat4::RotationX(pose.handR);
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

Pose MakePose(const CharacterAnim& anim)
{
    Pose pose;
    const float amp = Clamp(anim.walkAmp, 0.0f, 1.0f);
    const float phase = anim.walkPhase;
    const float sw = std::sin(phase);
    const float sw2 = std::sin(phase + PI);
    const float idle = 1.0f - amp;
    const float breath = std::sin(anim.time * 1.55f);

    // 步行：大腿前后摆，膝盖在后摆阶段弯曲，脚踝保持接近水平。
    pose.thighL = -sw * 0.66f * amp;
    pose.thighR = -sw2 * 0.66f * amp;
    const float kneeL = 0.16f + 0.62f * std::max(0.0f, std::sin(phase + 1.35f));
    const float kneeR = 0.16f + 0.62f * std::max(0.0f, std::sin(phase + PI + 1.35f));
    pose.shinL = kneeL * amp;
    pose.shinR = kneeR * amp;
    pose.footL = -(pose.thighL + pose.shinL) * 0.55f;
    pose.footR = -(pose.thighR + pose.shinR) * 0.55f;

    // 重心上下：每两步一个周期。
    pose.hipOffsetY = -0.024f * amp * (0.5f + 0.5f * std::cos(phase * 2.0f));
    pose.hipOffsetY += breath * 0.004f * idle;
    // 髋部左右轻摆，走路时更明显。
    pose.hipRoll = sw * 0.045f * amp;
    pose.torsoRoll = -sw * 0.03f * amp;

    // 摆臂：与同侧腿反相。
    pose.armL = sw * 0.52f * amp + breath * 0.02f * idle;
    pose.armR = sw2 * 0.52f * amp + breath * 0.02f * idle;
    pose.foreL = -0.22f - 0.16f * std::fabs(sw) * amp;
    pose.foreR = -0.22f - 0.16f * std::fabs(sw2) * amp;

    // 躯干前倾与左右扭动。
    pose.torsoPitch = 0.055f * amp + breath * 0.010f * idle;
    pose.torsoYaw = -sw * 0.055f * amp;
    pose.headPitch = -0.02f * amp + breath * 0.008f * idle;
    pose.headYaw = sw * 0.03f * amp + std::sin(anim.time * 0.63f) * 0.05f * idle;

    if (anim.aiming) {
        // 举枪：右臂前伸，左臂托握，上身与头转向瞄准方向。
        pose.armR = -1.30f + anim.aimPitch * 0.26f - anim.recoil * 0.30f;
        pose.foreR = -0.26f + anim.recoil * 0.18f;
        pose.armL = -1.02f + anim.aimPitch * 0.16f;
        pose.foreL = -1.02f;
        pose.armOutL = -0.28f;
        pose.armOutR = 0.10f;
        pose.handR = -0.12f;
        pose.torsoPitch = 0.02f - anim.recoil * 0.10f;
        pose.torsoYaw = anim.aimOffset * 0.55f;
        pose.headYaw = anim.aimOffset * 0.45f;
        pose.headPitch = -anim.aimPitch * 0.18f;
        pose.hipRoll *= 0.4f;
        pose.torsoRoll *= 0.4f;
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
    agent.coat = Color(0.10f, 0.11f, 0.13f, 1.0f);
    agent.coatShade = Color(0.06f, 0.07f, 0.08f, 1.0f);
    agent.shirt = Color(0.22f, 0.24f, 0.27f, 1.0f);
    agent.pants = Color(0.08f, 0.09f, 0.11f, 1.0f);
    agent.boots = Color(0.05f, 0.05f, 0.06f, 1.0f);
    agent.belt = Color(0.12f, 0.13f, 0.15f, 1.0f);
    agent.accent = Color(0.22f, 0.88f, 0.82f, 1.0f);
    agent.accentHi = Color(0.62f, 1.0f, 0.96f, 1.0f);
    agent.metal = Color(0.18f, 0.20f, 0.23f, 1.0f);
    agent.height = 1.02f;
    agent.bulk = 1.06f;
    agent.helmet = true;
    agent.visor = true;
    agent.shoulderPads = true;
    agent.weapon = WeaponKind::RIFLE;
    m_styles[5] = agent;

    // 统一提亮：保证角色在暗场景里依然有可读的剪影。
    for (int i = 0; i < 6; ++i) {
        BrightenStyle(m_styles[i], 1.30f);
    }

    m_meshes[0] = meshes.AddMesh(
        BuildCharacterMesh("CHAR_PLAYER", m_styles[0]), "CHAR_PLAYER");
    m_meshes[1] = meshes.AddMesh(
        BuildCharacterMesh("CHAR_BIGSISTER", m_styles[1]), "CHAR_BIGSISTER");
    m_meshes[2] = meshes.AddMesh(
        BuildCharacterMesh("CHAR_MERCHANT", m_styles[2]), "CHAR_MERCHANT");
    m_meshes[3] = meshes.AddMesh(
        BuildCharacterMesh("CHAR_BARTENDER", m_styles[3]), "CHAR_BARTENDER");
    m_meshes[4] = meshes.AddMesh(
        BuildCharacterMesh("CHAR_SCAVENGER", m_styles[4]), "CHAR_SCAVENGER");
    m_meshes[5] = meshes.AddMesh(
        BuildCharacterMesh("CHAR_AGENT", m_styles[5]), "CHAR_AGENT");
}

const Mesh* CharacterLibrary::Get(CharacterId id) const
{
    const int index = static_cast<int>(id);
    if (index < 0 || index >= 6) {
        return nullptr;
    }
    return m_meshes[index];
}

const CharacterStyle& CharacterLibrary::Style(CharacterId id) const
{
    const int index = ClampInt(static_cast<int>(id), 0, 5);
    return m_styles[index];
}

void CharacterLibrary::Draw(RenderDevice& device, const Mesh& mesh,
                            const Mat4& base, const CharacterAnim& anim,
                            const Color& tint) const
{
    const Pose pose = MakePose(anim);

    // 预先按名字索引部件，避免每帧字符串比较。
    const MeshPart* parts[15] = {};
    for (const MeshPart& part : mesh.parts) {
        for (int i = 0; i < 15; ++i) {
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

    Mat4 world[15];
    for (int i = 0; i < 15; ++i) {
        world[i] = Mat4::Identity();
    }

    for (int i = 0; i < 15; ++i) {
        const MeshPart* part = parts[i];
        if (part == nullptr) {
            continue;
        }
        Mat4 parentWorld = Mat4::Identity();
        if (kSkeleton[i].parent != nullptr) {
            for (int p = 0; p < 15; ++p) {
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

    for (int i = 0; i < 15; ++i) {
        const MeshPart* part = parts[i];
        if (part == nullptr || part->indexCount == 0) {
            continue;
        }
        device.DrawMeshPart(*part, world[i] * base, partTint);
    }
}

} // namespace fc
