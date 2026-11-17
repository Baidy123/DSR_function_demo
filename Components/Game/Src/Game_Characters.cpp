#include "Game_Characters.hpp"

#include "Shared_Math.hpp"

#include <unordered_map>

namespace fc {

namespace {

const Color WHITE = Color(1.0f, 1.0f, 1.0f, 1.0f);

void BuildHead(MeshBuilder& builder, const CharacterStyle& style, float top,
               float hip)
{
    (void)hip;
    // 头部
    builder.SetColor(style.skin);
    builder.SetPattern(0);
    builder.AddBeveledBox(Vec3(0.0f, top + 0.14f, 0.0f),
                          Vec3(0.11f, 0.15f, 0.11f), 0.25f);
    // 下颌阴影
    builder.SetColor(style.skinShade);
    builder.AddBox(Vec3(0.0f, top + 0.06f, 0.0f), Vec3(0.09f, 0.02f, 0.09f));

    // 头发
    builder.SetColor(style.hair);
    builder.SetPattern(0);
    if (style.hood) {
        builder.AddBeveledBox(Vec3(0.0f, top + 0.2f, -0.01f),
                              Vec3(0.15f, 0.16f, 0.15f), 0.3f);
        builder.AddBox(Vec3(0.0f, top + 0.12f, -0.09f),
                       Vec3(0.13f, 0.1f, 0.05f));
        builder.SetColor(style.skinShade);
        builder.AddBox(Vec3(0.0f, top + 0.13f, 0.09f),
                       Vec3(0.085f, 0.08f, 0.03f));
    } else {
        builder.AddBox(Vec3(0.0f, top + 0.26f, -0.01f),
                       Vec3(0.115f, 0.05f, 0.115f));
        builder.AddBox(Vec3(0.0f, top + 0.2f, -0.09f),
                       Vec3(0.11f, 0.09f, 0.03f));
        if (style.hairLong || style.bun) {
            builder.AddBox(Vec3(0.0f, top + 0.1f, -0.1f),
                           Vec3(0.1f, 0.13f, 0.03f));
        }
        if (style.bun) {
            builder.SetColor(style.hair);
            builder.AddBox(Vec3(0.0f, top + 0.22f, -0.15f),
                           Vec3(0.06f, 0.06f, 0.06f));
        }
    }

    // 面部：眼睛与嘴
    builder.SetColor(Color(0.06f, 0.05f, 0.06f, 1.0f));
    builder.SetPattern(0);
    builder.AddBox(Vec3(-0.045f, top + 0.16f, 0.108f),
                   Vec3(0.02f, 0.012f, 0.005f));
    builder.AddBox(Vec3(0.045f, top + 0.16f, 0.108f),
                   Vec3(0.02f, 0.012f, 0.005f));
    builder.SetColor(style.skinShade);
    builder.AddBox(Vec3(0.0f, top + 0.09f, 0.108f),
                   Vec3(0.03f, 0.008f, 0.004f));
    builder.SetColor(style.skinShade);
    builder.AddBox(Vec3(0.0f, top + 0.15f, 0.112f),
                   Vec3(0.012f, 0.025f, 0.006f));

    if (style.visor) {
        builder.SetColor(style.accentHi);
        builder.SetPattern(8);
        builder.AddBox(Vec3(0.0f, top + 0.16f, 0.112f),
                       Vec3(0.095f, 0.022f, 0.008f));
        builder.SetColor(Color(0.05f, 0.06f, 0.08f, 1.0f));
        builder.SetPattern(0);
        builder.AddBox(Vec3(0.0f, top + 0.2f, 0.05f),
                       Vec3(0.12f, 0.13f, 0.06f));
    }
    if (style.goggles) {
        builder.SetColor(style.metal);
        builder.SetPattern(3);
        builder.AddBox(Vec3(0.0f, top + 0.26f, 0.1f),
                       Vec3(0.1f, 0.03f, 0.02f));
        builder.SetColor(style.accent);
        builder.SetPattern(8);
        builder.AddBox(Vec3(-0.055f, top + 0.26f, 0.115f),
                       Vec3(0.03f, 0.018f, 0.008f));
        builder.AddBox(Vec3(0.055f, top + 0.26f, 0.115f),
                       Vec3(0.03f, 0.018f, 0.008f));
    }
}

void BuildTorso(MeshBuilder& builder, const CharacterStyle& style,
                const Vec3& hip, const Vec3& shoulder)
{
    const float width = style.bulky ? 0.25f : 0.22f;
    const float depth = style.bulky ? 0.15f : 0.13f;
    const Vec3 center(0.0f, (hip.y + shoulder.y) * 0.5f, 0.0f);
    const Vec3 half(width, (shoulder.y - hip.y) * 0.5f, depth);

    builder.SetColor(style.coat);
    builder.SetPattern(style.longCoat ? 5 : 2);
    builder.AddBeveledBox(center, half, 0.1f);

    // 肩部
    builder.SetColor(style.coat);
    builder.AddBox(Vec3(0.0f, shoulder.y - 0.02f, 0.0f),
                   Vec3(width + 0.03f, 0.05f, depth + 0.01f));

    if (style.vest) {
        builder.SetColor(Color(0.13f, 0.18f, 0.20f, 1.0f));
        builder.SetPattern(5);
        builder.AddBox(Vec3(0.0f, center.y + 0.02f, depth * 0.72f),
                       Vec3(width * 0.72f, half.y * 0.8f, 0.02f));
        builder.SetColor(Color(0.72f, 0.62f, 0.34f, 1.0f));
        builder.AddBox(Vec3(0.0f, center.y, depth * 0.78f),
                       Vec3(0.012f, half.y * 0.7f, 0.008f));
    }
    if (style.apron) {
        builder.SetColor(Color(0.29f, 0.23f, 0.18f, 1.0f));
        builder.SetPattern(5);
        builder.AddBox(Vec3(0.0f, center.y - 0.05f, depth * 0.75f),
                       Vec3(width * 0.55f, half.y * 0.85f, 0.015f));
    }
    if (style.longCoat) {
        builder.SetColor(style.coat);
        builder.SetPattern(5);
        builder.AddBox(Vec3(0.0f, hip.y - 0.12f, 0.0f),
                       Vec3(width * 0.95f, 0.2f, depth * 0.95f));
        builder.SetColor(style.coatShade);
        builder.AddBox(Vec3(0.0f, hip.y - 0.24f, 0.0f),
                       Vec3(width, 0.04f, depth));
    }
    if (style.scarf) {
        builder.SetColor(style.accent);
        builder.SetPattern(5);
        builder.AddBox(Vec3(0.0f, shoulder.y - 0.04f, 0.0f),
                       Vec3(width * 0.9f, 0.035f, depth * 1.02f));
        builder.SetColor(style.accentHi);
        builder.AddBox(Vec3(0.0f, shoulder.y - 0.04f, depth * 0.55f),
                       Vec3(width * 0.6f, 0.02f, 0.02f));
        builder.SetColor(style.accent);
        builder.AddBox(Vec3(width * 0.75f, shoulder.y - 0.2f, -depth * 0.3f),
                       Vec3(0.035f, 0.16f, 0.02f));
    }
}

void BuildArms(MeshBuilder& builder, const CharacterStyle& style,
               float shoulderY, bool right)
{
    const float side = right ? 1.0f : -1.0f;
    const float x = side * (style.bulky ? 0.3f : 0.27f);

    builder.SetColor(style.coat);
    builder.SetPattern(2);
    builder.AddBox(Vec3(x, shoulderY - 0.2f, 0.0f),
                   Vec3(0.065f, 0.2f, 0.075f));
    builder.SetColor(style.coatShade);
    builder.AddBox(Vec3(x, shoulderY - 0.4f, 0.0f),
                   Vec3(0.055f, 0.16f, 0.065f));
    builder.SetColor(style.skin);
    builder.SetPattern(0);
    builder.AddBox(Vec3(x, shoulderY - 0.55f, 0.0f),
                   Vec3(0.055f, 0.06f, 0.06f));

    if (style.armed && right) {
        builder.SetColor(Color(0.10f, 0.10f, 0.11f, 1.0f));
        builder.SetPattern(3);
        builder.AddBox(Vec3(x, shoulderY - 0.64f, 0.02f),
                       Vec3(0.035f, 0.09f, 0.04f));
        builder.SetColor(Color(0.16f, 0.17f, 0.18f, 1.0f));
        builder.AddBox(Vec3(x, shoulderY - 0.74f, 0.02f),
                       Vec3(0.025f, 0.06f, 0.028f));
        builder.SetColor(style.accent);
        builder.SetPattern(8);
        builder.AddBox(Vec3(x, shoulderY - 0.66f, 0.062f),
                       Vec3(0.012f, 0.01f, 0.004f));
    }
}

void BuildLegs(MeshBuilder& builder, const CharacterStyle& style, float hipY,
               bool right)
{
    const float side = right ? 1.0f : -1.0f;
    const float x = side * 0.11f;
    builder.SetColor(style.pants);
    builder.SetPattern(5);
    builder.AddBox(Vec3(x, hipY * 0.5f, 0.0f),
                   Vec3(0.085f, hipY * 0.5f, 0.1f));
    builder.SetColor(style.boots);
    builder.SetPattern(0);
    builder.AddBox(Vec3(x, 0.06f, 0.02f), Vec3(0.09f, 0.06f, 0.13f));
    builder.SetColor(style.boots);
    builder.AddBox(Vec3(x, 0.13f, 0.0f), Vec3(0.088f, 0.03f, 0.1f));
}

MeshData BuildCharacterMesh(MeshLibrary& meshes, const std::string& name,
                            const CharacterStyle& style)
{
    (void)meshes;
    MeshBuilder builder;

    const float hipY = 0.9f;
    const float shoulderY = 1.45f;
    const float headBase = shoulderY;

    builder.BeginPart("legL", Vec3(-0.11f, hipY, 0.0f));
    BuildLegs(builder, style, hipY, false);
    builder.BeginPart("legR", Vec3(0.11f, hipY, 0.0f));
    BuildLegs(builder, style, hipY, true);

    builder.BeginPart("torso", Vec3(0.0f, hipY, 0.0f));
    BuildTorso(builder, style, Vec3(0.0f, hipY, 0.0f),
               Vec3(0.0f, shoulderY, 0.0f));

    builder.BeginPart("head", Vec3(0.0f, headBase, 0.0f));
    BuildHead(builder, style, headBase, hipY);

    builder.BeginPart("armL", Vec3(-0.27f, shoulderY, 0.0f));
    BuildArms(builder, style, shoulderY, false);

    builder.BeginPart("armR", Vec3(0.27f, shoulderY, 0.0f));
    BuildArms(builder, style, shoulderY, true);

    return builder.Finish(name);
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
    player.skin = Color(0.79f, 0.56f, 0.42f, 1.0f);
    player.skinShade = Color(0.62f, 0.42f, 0.32f, 1.0f);
    player.hair = Color(0.10f, 0.10f, 0.12f, 1.0f);
    player.coat = Color(0.18f, 0.23f, 0.18f, 1.0f);
    player.coatShade = Color(0.12f, 0.15f, 0.13f, 1.0f);
    player.pants = Color(0.15f, 0.17f, 0.20f, 1.0f);
    player.accent = Color(0.18f, 0.66f, 0.63f, 1.0f);
    player.accentHi = Color(0.50f, 0.85f, 0.81f, 1.0f);
    player.scarf = true;
    player.armed = true;
    m_styles[0] = player;

    CharacterStyle sister;
    sister.skin = Color(0.80f, 0.58f, 0.45f, 1.0f);
    sister.skinShade = Color(0.62f, 0.42f, 0.33f, 1.0f);
    sister.hair = Color(0.23f, 0.16f, 0.15f, 1.0f);
    sister.coat = Color(0.55f, 0.18f, 0.25f, 1.0f);
    sister.coatShade = Color(0.36f, 0.12f, 0.16f, 1.0f);
    sister.pants = Color(0.09f, 0.09f, 0.11f, 1.0f);
    sister.accent = Color(1.0f, 0.70f, 0.28f, 1.0f);
    sister.accentHi = Color(1.0f, 0.86f, 0.59f, 1.0f);
    sister.longCoat = true;
    sister.bun = true;
    sister.hairLong = true;
    m_styles[1] = sister;

    CharacterStyle merchant;
    merchant.skin = Color(0.77f, 0.55f, 0.42f, 1.0f);
    merchant.skinShade = Color(0.60f, 0.41f, 0.31f, 1.0f);
    merchant.hair = Color(0.18f, 0.14f, 0.12f, 1.0f);
    merchant.coat = Color(0.35f, 0.29f, 0.20f, 1.0f);
    merchant.coatShade = Color(0.24f, 0.20f, 0.14f, 1.0f);
    merchant.pants = Color(0.18f, 0.17f, 0.15f, 1.0f);
    merchant.accent = Color(0.79f, 0.64f, 0.15f, 1.0f);
    merchant.accentHi = Color(1.0f, 0.86f, 0.47f, 1.0f);
    merchant.bulky = true;
    merchant.goggles = true;
    m_styles[2] = merchant;

    CharacterStyle bartender;
    bartender.skin = Color(0.79f, 0.56f, 0.42f, 1.0f);
    bartender.skinShade = Color(0.62f, 0.42f, 0.32f, 1.0f);
    bartender.hair = Color(0.30f, 0.20f, 0.14f, 1.0f);
    bartender.coat = Color(0.80f, 0.78f, 0.72f, 1.0f);
    bartender.coatShade = Color(0.60f, 0.58f, 0.54f, 1.0f);
    bartender.pants = Color(0.16f, 0.19f, 0.21f, 1.0f);
    bartender.accent = Color(0.29f, 0.23f, 0.18f, 1.0f);
    bartender.accentHi = Color(0.58f, 0.47f, 0.31f, 1.0f);
    bartender.vest = true;
    bartender.apron = true;
    m_styles[3] = bartender;

    CharacterStyle scavenger;
    scavenger.skin = Color(0.55f, 0.45f, 0.36f, 1.0f);
    scavenger.skinShade = Color(0.42f, 0.34f, 0.27f, 1.0f);
    scavenger.hair = Color(0.16f, 0.15f, 0.13f, 1.0f);
    scavenger.coat = Color(0.28f, 0.27f, 0.22f, 1.0f);
    scavenger.coatShade = Color(0.19f, 0.18f, 0.15f, 1.0f);
    scavenger.pants = Color(0.20f, 0.19f, 0.17f, 1.0f);
    scavenger.accent = Color(1.0f, 0.54f, 0.24f, 1.0f);
    scavenger.accentHi = Color(1.0f, 0.75f, 0.47f, 1.0f);
    scavenger.hood = true;
    scavenger.goggles = true;
    scavenger.bulky = true;
    scavenger.armed = true;
    m_styles[4] = scavenger;

    CharacterStyle agent;
    agent.skin = Color(0.24f, 0.26f, 0.29f, 1.0f);
    agent.skinShade = Color(0.14f, 0.16f, 0.18f, 1.0f);
    agent.hair = Color(0.07f, 0.08f, 0.10f, 1.0f);
    agent.coat = Color(0.08f, 0.09f, 0.11f, 1.0f);
    agent.coatShade = Color(0.05f, 0.06f, 0.07f, 1.0f);
    agent.pants = Color(0.07f, 0.08f, 0.10f, 1.0f);
    agent.boots = Color(0.05f, 0.05f, 0.06f, 1.0f);
    agent.accent = Color(0.22f, 0.88f, 0.82f, 1.0f);
    agent.accentHi = Color(0.59f, 1.0f, 0.96f, 1.0f);
    agent.metal = Color(0.16f, 0.18f, 0.21f, 1.0f);
    agent.visor = true;
    agent.bulky = true;
    agent.armed = true;
    m_styles[5] = agent;

    m_meshes[0] = meshes.AddMesh(
        BuildCharacterMesh(meshes, "CHAR_PLAYER", m_styles[0]), "CHAR_PLAYER");
    m_meshes[1] = meshes.AddMesh(
        BuildCharacterMesh(meshes, "CHAR_BIGSISTER", m_styles[1]),
        "CHAR_BIGSISTER");
    m_meshes[2] = meshes.AddMesh(
        BuildCharacterMesh(meshes, "CHAR_MERCHANT", m_styles[2]),
        "CHAR_MERCHANT");
    m_meshes[3] = meshes.AddMesh(
        BuildCharacterMesh(meshes, "CHAR_BARTENDER", m_styles[3]),
        "CHAR_BARTENDER");
    m_meshes[4] = meshes.AddMesh(
        BuildCharacterMesh(meshes, "CHAR_SCAVENGER", m_styles[4]),
        "CHAR_SCAVENGER");
    m_meshes[5] = meshes.AddMesh(
        BuildCharacterMesh(meshes, "CHAR_AGENT", m_styles[5]), "CHAR_AGENT");
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
    float bob = 0.0f;
    float legSwing = 0.0f;
    float armSwing = 0.0f;
    if (anim.walking) {
        bob = std::sin(anim.walkPhase * 2.0f) * 0.022f;
        legSwing = std::sin(anim.walkPhase) * 0.52f;
        armSwing = -std::sin(anim.walkPhase) * 0.42f;
    } else {
        bob = std::sin(anim.time * 1.4f) * 0.006f;
    }

    float armRaise = 0.0f;
    float armRaiseLeft = 0.0f;
    if (anim.aiming) {
        armRaise = 1.42f + anim.aimPitch * 0.35f - anim.recoil * 0.25f;
        armRaiseLeft = 1.18f;
    }
    const float recoilBack = anim.recoil * 0.12f;

    Color partTint = tint;
    if (anim.hitFlash > 0.0f) {
        partTint = Color(1.0f, 0.45f, 0.45f, tint.a);
    }
    partTint.a *= anim.alpha;

    for (const MeshPart& part : mesh.parts) {
        Mat4 local = Mat4::Identity();
        const float px = part.pivot.x;
        const float py = part.pivot.y;
        const float pz = part.pivot.z;

        float rotationX = 0.0f;
        float rotationY = 0.0f;
        float extraY = 0.0f;

        if (part.name == "legL") {
            rotationX = legSwing * 0.9f;
        } else if (part.name == "legR") {
            rotationX = -legSwing * 0.9f;
        } else if (part.name == "armL") {
            rotationX = anim.aiming ? armRaiseLeft : -armSwing * 0.8f;
        } else if (part.name == "armR") {
            rotationX = anim.aiming ? armRaise : armSwing * 0.8f;
            extraY = -recoilBack;
        } else if (part.name == "torso") {
            rotationX = anim.walking ? 0.05f : 0.0f;
        } else if (part.name == "head") {
            rotationX = anim.aimPitch * 0.18f;
            rotationY = anim.aiming ? -0.05f : 0.0f;
        }

        Mat4 partWorld = local;
        if (rotationX != 0.0f || rotationY != 0.0f || extraY != 0.0f) {
            Mat4 rotation = Mat4::RotationX(rotationX) *
                             Mat4::RotationY(rotationY);
            partWorld = Mat4::Translation(Vec3(px, py, pz)) * rotation *
                        Mat4::Translation(Vec3(-px, -py, -pz));
        }
        // 躯干整体上下浮动。
        const Mat4 bobMatrix = Mat4::Translation(Vec3(0.0f, bob, 0.0f));
        const Mat4 finalWorld = partWorld * bobMatrix * base;
        device.DrawMeshPart(part, finalWorld, partTint);
    }
}

} // namespace fc
