#include "World_Types.hpp"

#include "Shared_Math.hpp"

#include <string>

namespace fc {

namespace {

/** @brief 取表面材质编号，便于在体块参数里直接写材质。 */
int Mat(SurfaceMaterial material)
{
    return static_cast<int>(material);
}

/**
 * @brief 由程序化图案推导默认表面材质。
 *
 * 场景体块在大多数情况下只需要指定图案，材质跟随图案就能得到合理的
 * 反射表现；需要特例时再显式传入材质编号。
 * @param [IN] pattern 图案编号。
 * @return 材质编号。
 */
int DefaultMaterialForPattern(int pattern)
{
    using M = SurfaceMaterial;
    switch (pattern) {
    case 1:
    case 6:
        return Mat(M::PLASTER);
    case 2:
        return Mat(M::WOOD);
    case 3:
    case 4:
        return Mat(M::METAL_MATTE);
    case 5:
        return Mat(M::FABRIC);
    case 7:
    case 8:
        return Mat(M::CARDBOARD);
    case 9:
        return Mat(M::GLASS);
    case 10:
    case 11:
        return Mat(M::CERAMIC);
    case 12:
        return Mat(M::PLASTIC);
    case 13:
        return Mat(M::RUBBER);
    case 14:
        return Mat(M::EMISSIVE);
    default:
        return Mat(M::PLASTER);
    }
}

RoomBlock Block(const Vec3& center, const Vec3& half, unsigned int rgb,
                int pattern, bool solid = true, int material = -1)
{
    RoomBlock block;
    block.center = center;
    block.half = half;
    block.color = ColorFromHex(rgb);
    block.pattern = pattern;
    block.material =
        material >= 0 ? material : DefaultMaterialForPattern(pattern);
    block.solid = solid;
    return block;
}

PropDef Prop(const char* mesh, const Vec3& position, float yawDegrees,
             float scale = 1.0f, unsigned int tint = 0xFFFFFF, bool solid = true)
{
    PropDef prop;
    prop.mesh = mesh;
    prop.position = position;
    prop.yawDegrees = yawDegrees;
    prop.scale = scale;
    prop.tint = ColorFromHex(tint);
    prop.solid = solid;
    return prop;
}

LightDef Light(const Vec3& position, unsigned int rgb, float intensity,
               float range, float flicker = 0.0f)
{
    LightDef light;
    light.position = position;
    light.color = ColorFromHex(rgb);
    light.intensity = intensity;
    light.range = range;
    light.flicker = flicker;
    return light;
}

InteractDef Interact(const char* id, const Vec3& position, float radius,
                     const char* prompt)
{
    InteractDef interact;
    interact.id = id;
    interact.position = position;
    interact.radius = radius;
    interact.prompt = prompt;
    return interact;
}

EnemySpawnDef Spawn(EnemyType type, const Vec3& position, float yawDegrees)
{
    EnemySpawnDef spawn;
    spawn.type = type;
    spawn.position = position;
    spawn.yawDegrees = yawDegrees;
    return spawn;
}

CameraZoneDef CameraZone(const Vec3& min, const Vec3& max, const Vec3& eye,
                         const Vec3& target, float fov)
{
    CameraZoneDef zone;
    zone.bounds = AABB(min, max);
    zone.pose.eye = eye;
    zone.pose.target = target;
    zone.pose.fovDegrees = fov;
    return zone;
}

// ---------------------------------------------------------------------------
// 酒吧外：雨夜街道。一侧是酒吧砖墙与雨棚，两侧是老楼立面（窗、消防梯、
// 空调、管线），路面有积水、垃圾桶、售货机与杂物。
// ---------------------------------------------------------------------------
SceneDef BuildExterior()
{
    SceneDef scene;
    scene.id = SceneId::BAR_EXTERIOR;
    scene.displayName = "旧城区 · 余烬酒吧外";
    scene.fogColor = ColorFromHex(0x0A0E16);
    scene.fogNear = 5.0f;
    scene.fogFar = 28.0f;
    scene.fogDensity = 0.60f;
    scene.ambient = ColorFromHex(0x5A6478);
    scene.rain = true;
    scene.outdoor = true;
    scene.playerSpawn = Vec3(0.6f, 0.0f, 8.6f);
    scene.playerYawDegrees = 180.0f;

    // ---- 地面：沥青路面 + 人行道 + 路缘 ----
    scene.blocks.push_back(Block(Vec3(0.0f, -0.1f, 7.0f),
                                 Vec3(7.0f, 0.1f, 7.2f), 0x252B35, 6, false,
                                 Mat(SurfaceMaterial::RUBBER)));
    scene.blocks.push_back(Block(Vec3(0.0f, 0.02f, 0.9f),
                                 Vec3(7.0f, 0.03f, 1.05f), 0x3B4048, 10, false));
    scene.blocks.push_back(Block(Vec3(0.0f, 0.06f, 2.0f),
                                 Vec3(7.0f, 0.05f, 0.07f), 0x4C525A, 6, false));

    // ---- 酒吧外墙：砖墙 + 石质墙裙 + 门洞 ----
    scene.blocks.push_back(Block(Vec3(-3.95f, 2.6f, -0.2f),
                                 Vec3(3.05f, 2.6f, 0.25f), 0x2A2422, 1));
    scene.blocks.push_back(Block(Vec3(4.55f, 2.6f, -0.2f),
                                 Vec3(2.45f, 2.6f, 0.25f), 0x2A2422, 1));
    scene.blocks.push_back(Block(Vec3(0.6f, 3.4f, -0.2f),
                                 Vec3(1.5f, 0.8f, 0.25f), 0x241E1C, 1));
    scene.blocks.push_back(Block(Vec3(0.0f, 0.42f, -0.02f),
                                 Vec3(7.0f, 0.42f, 0.06f), 0x3A3A40, 6));
    // 门两侧壁柱
    scene.blocks.push_back(Block(Vec3(-0.95f, 2.1f, 0.02f),
                                 Vec3(0.16f, 2.1f, 0.14f), 0x35302E, 1));
    scene.blocks.push_back(Block(Vec3(2.15f, 2.1f, 0.02f),
                                 Vec3(0.16f, 2.1f, 0.14f), 0x35302E, 1));
    // 酒吧橱窗：玻璃 + 室内暖光
    scene.blocks.push_back(Block(Vec3(-4.9f, 1.9f, 0.0f),
                                 Vec3(1.35f, 0.85f, 0.05f), 0x2A3A42, 9));
    scene.blocks.push_back(Block(Vec3(5.4f, 1.9f, 0.0f),
                                 Vec3(1.1f, 0.85f, 0.05f), 0x2A3A42, 9));
    scene.blocks.push_back(Block(Vec3(-4.9f, 1.9f, 0.05f),
                                 Vec3(1.2f, 0.7f, 0.02f), 0xC98A4A, 14,
                                 false));
    scene.blocks.push_back(Block(Vec3(5.4f, 1.9f, 0.05f),
                                 Vec3(0.95f, 0.7f, 0.02f), 0xC98A4A, 14,
                                 false));

    // ---- 两侧老楼立面 ----
    scene.blocks.push_back(Block(Vec3(-7.2f, 3.2f, 7.0f),
                                 Vec3(0.25f, 3.2f, 7.2f), 0x1E2126, 1));
    scene.blocks.push_back(Block(Vec3(7.2f, 3.2f, 7.0f),
                                 Vec3(0.25f, 3.2f, 7.2f), 0x1E2126, 1));
    // 窗：西侧三扇、东侧两扇
    for (int i = 0; i < 3; ++i) {
        const float z = 2.6f + static_cast<float>(i) * 3.1f;
        scene.blocks.push_back(Block(Vec3(-6.93f, 2.5f, z),
                                     Vec3(0.04f, 0.55f, 0.75f), 0x1E3038, 9,
                                     false));
        scene.blocks.push_back(Block(Vec3(-6.92f, 2.5f, z),
                                     Vec3(0.03f, 0.42f, 0.6f), 0x4A6A72, 9,
                                     false, Mat(SurfaceMaterial::GLASS)));
    }
    for (int i = 0; i < 2; ++i) {
        const float z = 4.2f + static_cast<float>(i) * 4.0f;
        scene.blocks.push_back(Block(Vec3(6.93f, 2.7f, z),
                                     Vec3(0.04f, 0.55f, 0.75f), 0x1E3038, 9,
                                     false));
        scene.blocks.push_back(Block(Vec3(6.92f, 2.7f, z),
                                     Vec3(0.03f, 0.42f, 0.6f), 0x3A5A64, 9,
                                     false, Mat(SurfaceMaterial::GLASS)));
    }
    // 消防梯平台与栏杆
    for (int i = 0; i < 2; ++i) {
        const float y = 3.6f + static_cast<float>(i) * 1.5f;
        scene.blocks.push_back(Block(Vec3(-6.5f, y, 4.4f),
                                     Vec3(0.55f, 0.05f, 1.6f), 0x3A4046, 3));
        scene.blocks.push_back(Block(Vec3(-6.0f, y + 0.5f, 4.4f),
                                     Vec3(0.04f, 0.5f, 1.6f), 0x3A4046, 3,
                                     false));
    }
    // 东侧落水管与壁挂空调托架
    scene.blocks.push_back(Block(Vec3(6.9f, 2.2f, 8.6f),
                                 Vec3(0.07f, 2.2f, 0.07f), 0x3A3E44, 3,
                                 false));
    scene.blocks.push_back(Block(Vec3(6.78f, 3.0f, 6.4f),
                                 Vec3(0.24f, 0.06f, 0.7f), 0x3A3E44, 3));
    // 雨棚（布料）与支撑杆
    scene.blocks.push_back(Block(Vec3(0.6f, 2.85f, 1.35f),
                                 Vec3(1.9f, 0.06f, 1.25f), 0x5C2530, 5,
                                 true, Mat(SurfaceMaterial::FABRIC)));
    scene.blocks.push_back(Block(Vec3(-1.2f, 2.55f, 2.45f),
                                 Vec3(0.04f, 0.28f, 0.04f), 0x3A3030, 3));
    scene.blocks.push_back(Block(Vec3(2.4f, 2.55f, 2.45f),
                                 Vec3(0.04f, 0.28f, 0.04f), 0x3A3030, 3));

    // ---- 对面的背街建筑：厚重墙体 + 天际线剪影 ----
    scene.blocks.push_back(Block(Vec3(0.0f, 2.6f, 14.3f),
                                 Vec3(7.2f, 2.6f, 0.25f), 0x1B1E23, 1));
    scene.blocks.push_back(Block(Vec3(-4.2f, 6.4f, 15.2f),
                                 Vec3(2.6f, 3.0f, 1.2f), 0x14181F, 6,
                                 false));
    scene.blocks.push_back(Block(Vec3(2.6f, 5.4f, 15.0f),
                                 Vec3(3.2f, 2.0f, 1.0f), 0x171B22, 6,
                                 false));
    scene.blocks.push_back(Block(Vec3(6.2f, 7.2f, 15.6f),
                                 Vec3(1.3f, 3.8f, 1.0f), 0x121620, 6,
                                 false));
    // 对面楼的窗光
    for (int i = 0; i < 4; ++i) {
        const float x = -5.6f + static_cast<float>(i) * 3.4f;
        scene.blocks.push_back(Block(Vec3(x, 4.2f, 14.02f),
                                     Vec3(0.5f, 0.4f, 0.04f), 0x6E8296, 14,
                                     false));
    }
    // 电线（横跨街道）
    for (int i = 0; i < 2; ++i) {
        const float y = 5.2f + static_cast<float>(i) * 0.5f;
        scene.blocks.push_back(Block(Vec3(0.0f, y, 4.0f + i * 3.0f),
                                     Vec3(7.0f, 0.02f, 0.02f), 0x1A1A1E, 13,
                                     false));
    }

    // ---- 道具 ----
    scene.props.push_back(Prop("PROP_NEON_BAR", Vec3(0.6f, 2.55f, -0.35f), 0.0f));
    scene.props.push_back(Prop("PROP_DOOR_FRAME", Vec3(0.6f, 0.0f, -0.05f), 0.0f, 1.0f, 0xFFFFFF, false));
    // 车靠西侧停放，横停但不把整条街堵死。
    scene.props.push_back(Prop("PROP_CAR", Vec3(-5.3f, 0.0f, 9.4f), 96.0f));
    scene.props.push_back(Prop("PROP_BIN", Vec3(5.5f, 0.0f, 2.6f), 12.0f));
    scene.props.push_back(Prop("PROP_BIN", Vec3(6.1f, 0.0f, 3.3f), -20.0f));
    scene.props.push_back(Prop("PROP_LAMPPOST", Vec3(5.2f, 0.0f, 9.4f), 0.0f));
    scene.props.push_back(Prop("PROP_LAMPPOST", Vec3(-5.6f, 0.0f, 4.2f), 180.0f));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(-2.0f, 0.02f, 6.2f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(3.2f, 0.02f, 4.4f), 30.0f, 1.2f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(-5.4f, 0.02f, 11.4f), -14.0f, 0.9f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_VENDING", Vec3(6.35f, 0.0f, 5.6f), -90.0f));
    scene.props.push_back(Prop("PROP_DUMPSTER", Vec3(-6.0f, 0.0f, 12.0f), 8.0f));
    scene.props.push_back(Prop("PROP_CONE", Vec3(3.6f, 0.0f, 10.8f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_CONE", Vec3(-3.0f, 0.0f, 7.6f), 16.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_BOLLARD", Vec3(-6.4f, 0.0f, 2.35f), 0.0f));
    scene.props.push_back(Prop("PROP_BOLLARD", Vec3(3.9f, 0.0f, 2.35f), 0.0f));
    scene.props.push_back(Prop("PROP_CRATE_STACK", Vec3(-6.5f, 0.0f, 6.4f), -12.0f));
    scene.props.push_back(Prop("PROP_BOX", Vec3(6.5f, 0.0f, 7.8f), 24.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_BOX", Vec3(6.1f, 0.0f, 8.4f), -8.0f, 0.9f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_TARP", Vec3(-4.6f, 0.02f, 6.4f), 14.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_SHOP_SIGN", Vec3(3.4f, 0.0f, 0.9f), 24.0f));
    scene.props.push_back(Prop("PROP_AC", Vec3(6.45f, 3.06f, 6.4f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PLANT", Vec3(-2.7f, 0.0f, 0.95f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_FIRE_EXT", Vec3(1.95f, 1.02f, 0.06f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PIPE", Vec3(-6.85f, 0.0f, 12.6f), 0.0f, 1.0f, 0xFFFFFF, false));

    // ---- 灯光 ----
    scene.lights.push_back(Light(Vec3(0.6f, 2.45f, 1.35f), 0xFFC785, 2.6f, 7.5f));
    scene.lights.push_back(Light(Vec3(2.5f, 2.55f, 0.9f), 0xFF2F7A, 1.6f, 7.5f, 0.55f));
    scene.lights.push_back(Light(Vec3(5.2f, 3.7f, 10.15f), 0xFFD8A0, 1.5f, 9.5f));
    scene.lights.push_back(Light(Vec3(-5.6f, 3.7f, 4.95f), 0xFFD8A0, 1.2f, 8.0f));
    scene.lights.push_back(Light(Vec3(-4.3f, 0.8f, 8.6f), 0xFFC46B, 0.8f, 4.5f));
    scene.lights.push_back(Light(Vec3(6.1f, 1.4f, 5.4f), 0x6AC8E0, 1.1f, 5.0f));
    scene.lights.push_back(Light(Vec3(-4.9f, 1.9f, 0.6f), 0xFFB066, 0.9f, 4.0f));
    scene.lights.push_back(Light(Vec3(5.4f, 1.9f, 0.6f), 0xFFB066, 0.9f, 4.0f));

    scene.interactions.push_back(
        Interact("bar_entrance", Vec3(0.6f, 1.2f, 0.85f), 1.7f,
                 "[E] 进入余烬酒吧"));
    scene.interactions.push_back(
        Interact("car", Vec3(-4.15f, 1.1f, 9.4f), 2.2f, "[E] 上车前往铁港"));
    scene.interactions.push_back(
        Interact("street_sign", Vec3(2.2f, 1.3f, 0.9f), 1.9f, "[E] 看看招牌"));

    scene.cameras.push_back(CameraZone(
        Vec3(-7.0f, 0.0f, 0.0f), Vec3(7.0f, 4.0f, 14.0f),
        Vec3(4.2f, 3.35f, 12.1f), Vec3(0.3f, 1.25f, 4.4f), 58.0f));
    return scene;
}

// ---------------------------------------------------------------------------
// 余烬酒吧：吧台、后柜、卡座、圆桌、点唱机、账本终端、吊灯与壁灯。
// ---------------------------------------------------------------------------
SceneDef BuildInterior()
{
    SceneDef scene;
    scene.id = SceneId::BAR_INTERIOR;
    scene.displayName = "旧城区 · 余烬酒吧";
    scene.fogColor = ColorFromHex(0x0C0708);
    scene.fogNear = 5.0f;
    scene.fogFar = 28.0f;
    scene.fogDensity = 0.5f;
    scene.ambient = ColorFromHex(0x4A5468);
    scene.rain = false;
    scene.outdoor = false;
    scene.playerSpawn = Vec3(0.6f, 0.0f, 4.2f);
    scene.playerYawDegrees = 180.0f;

    // ---- 地板 / 天花板 ----
    scene.blocks.push_back(Block(Vec3(0.0f, -0.1f, 0.0f),
                                 Vec3(7.0f, 0.1f, 5.0f), 0x3A2A20, 2, false,
                                 Mat(SurfaceMaterial::WOOD)));
    // 吧台前的瓷砖带
    scene.blocks.push_back(Block(Vec3(-1.8f, 0.005f, -1.6f),
                                 Vec3(5.0f, 0.01f, 0.8f), 0x4A4038, 10,
                                 false));
    scene.blocks.push_back(Block(Vec3(0.0f, 3.5f, 0.0f),
                                 Vec3(7.0f, 0.12f, 5.0f), 0x1A1416, 6, false));

    // ---- 墙体 ----
    scene.blocks.push_back(Block(Vec3(0.0f, 1.7f, -5.2f),
                                 Vec3(7.2f, 1.8f, 0.25f), 0x2C2420, 1));
    scene.blocks.push_back(Block(Vec3(-7.2f, 1.7f, 0.0f),
                                 Vec3(0.25f, 1.8f, 5.2f), 0x2C2420, 1));
    scene.blocks.push_back(Block(Vec3(7.2f, 1.7f, 0.0f),
                                 Vec3(0.25f, 1.8f, 5.2f), 0x2C2420, 1));
    scene.blocks.push_back(Block(Vec3(-3.2f, 1.7f, 5.2f),
                                 Vec3(4.0f, 1.8f, 0.25f), 0x2C2420, 1));
    scene.blocks.push_back(Block(Vec3(4.6f, 1.7f, 5.2f),
                                 Vec3(2.6f, 1.8f, 0.25f), 0x2C2420, 1));
    scene.blocks.push_back(Block(Vec3(0.6f, 2.75f, 5.2f),
                                 Vec3(1.0f, 0.75f, 0.25f), 0x241D1B, 1));

    // ---- 天花板横梁与踢脚线 ----
    for (int i = -1; i <= 1; ++i) {
        scene.blocks.push_back(
            Block(Vec3(static_cast<float>(i) * 3.2f, 3.32f, 0.0f),
                  Vec3(0.16f, 0.18f, 5.0f), 0x241C18, 2, false,
                  Mat(SurfaceMaterial::WOOD)));
    }
    scene.blocks.push_back(Block(Vec3(0.0f, 0.12f, -5.0f),
                                 Vec3(7.0f, 0.12f, 0.1f), 0x1E1816, 2, false,
                                 Mat(SurfaceMaterial::WOOD)));
    scene.blocks.push_back(Block(Vec3(-7.0f, 0.12f, 0.0f),
                                 Vec3(0.1f, 0.12f, 5.0f), 0x1E1816, 2, false,
                                 Mat(SurfaceMaterial::WOOD)));
    scene.blocks.push_back(Block(Vec3(7.0f, 0.12f, 0.0f),
                                 Vec3(0.1f, 0.12f, 5.0f), 0x1E1816, 2, false,
                                 Mat(SurfaceMaterial::WOOD)));
    // 墙面护墙板
    scene.blocks.push_back(Block(Vec3(0.0f, 0.55f, -4.93f),
                                 Vec3(7.0f, 0.55f, 0.03f), 0x3A2A1E, 2,
                                 false, Mat(SurfaceMaterial::WOOD)));
    scene.blocks.push_back(Block(Vec3(-6.93f, 0.55f, 0.0f),
                                 Vec3(0.03f, 0.55f, 5.0f), 0x3A2A1E, 2,
                                 false, Mat(SurfaceMaterial::WOOD)));
    scene.blocks.push_back(Block(Vec3(6.93f, 0.55f, 0.0f),
                                 Vec3(0.03f, 0.55f, 5.0f), 0x3A2A1E, 2,
                                 false, Mat(SurfaceMaterial::WOOD)));

    // ---- 长吧台：台体 + 台面 + 黄铜压边 + 前立面木条 + 脚踏杆 ----
    scene.blocks.push_back(Block(Vec3(-1.8f, 0.55f, -2.35f),
                                 Vec3(3.3f, 0.55f, 0.3f), 0x4A3220, 2, true,
                                 Mat(SurfaceMaterial::WOOD)));
    scene.blocks.push_back(Block(Vec3(-1.8f, 1.12f, -2.35f),
                                 Vec3(3.45f, 0.06f, 0.42f), 0x8C6A2E, 0, true,
                                 Mat(SurfaceMaterial::METAL_POLISHED)));
    scene.blocks.push_back(Block(Vec3(-1.8f, 1.02f, -2.06f),
                                 Vec3(3.45f, 0.05f, 0.05f), 0xC79A4A, 0, true,
                                 Mat(SurfaceMaterial::METAL_POLISHED)));
    scene.blocks.push_back(Block(Vec3(-1.8f, 0.18f, -1.95f),
                                 Vec3(3.3f, 0.035f, 0.035f), 0x8C6A2E, 3,
                                 false, Mat(SurfaceMaterial::METAL_POLISHED)));
    // 台体竖向木条
    for (int i = 0; i < 11; ++i) {
        const float x = -4.95f + static_cast<float>(i) * 0.6f;
        scene.blocks.push_back(Block(Vec3(x, 0.55f, -2.03f),
                                     Vec3(0.04f, 0.55f, 0.03f), 0x3A2818, 2,
                                     false, Mat(SurfaceMaterial::WOOD)));
    }
    // 吧台后置物架背板
    scene.blocks.push_back(Block(Vec3(-1.8f, 1.75f, -4.72f),
                                 Vec3(3.4f, 1.1f, 0.08f), 0x3A2A1E, 2, true,
                                 Mat(SurfaceMaterial::WOOD)));
    // 卡座隔断墙
    scene.blocks.push_back(Block(Vec3(3.4f, 1.25f, -1.1f),
                                 Vec3(0.12f, 1.25f, 1.1f), 0x33262A, 5));
    scene.blocks.push_back(Block(Vec3(-6.4f, 1.25f, -2.4f),
                                 Vec3(0.12f, 1.25f, 1.4f), 0x33262A, 5));

    // ---- 道具：吧台区 ----
    scene.props.push_back(Prop("PROP_BAR_CABINET", Vec3(-4.6f, 0.0f, -4.6f), 0.0f));
    scene.props.push_back(Prop("PROP_BAR_CABINET", Vec3(1.2f, 0.0f, -4.6f), 0.0f));
    scene.props.push_back(Prop("PROP_BAR_SHELF", Vec3(-1.7f, 1.1f, -4.62f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_BOTTLE_RACK", Vec3(-4.4f, 0.0f, -4.85f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_BOTTLE_RACK", Vec3(3.9f, 0.0f, -4.85f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_FRIDGE", Vec3(2.9f, 0.0f, -4.55f), 0.0f));
    scene.props.push_back(Prop("PROP_SINK", Vec3(5.6f, 0.0f, -4.5f), 0.0f));
    scene.props.push_back(Prop("PROP_TAP", Vec3(-2.9f, 1.18f, -2.4f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_TAP", Vec3(-2.4f, 1.18f, -2.4f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_TAP", Vec3(-1.9f, 1.18f, -2.4f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_REGISTER", Vec3(0.55f, 1.18f, -2.55f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_GLASS", Vec3(-1.35f, 1.18f, -2.45f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_GLASS", Vec3(-1.15f, 1.18f, -2.5f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_GLASS", Vec3(0.9f, 1.18f, -2.42f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_ASHTRAY", Vec3(-0.25f, 1.18f, -2.4f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_KEG", Vec3(6.2f, 0.0f, -3.6f), 0.0f));
    scene.props.push_back(Prop("PROP_KEG", Vec3(6.2f, 0.0f, -2.9f), 0.0f));
    scene.props.push_back(Prop("PROP_BEER_CASE", Vec3(4.4f, 0.0f, -4.35f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_WINE_CRATE", Vec3(-6.1f, 0.0f, -4.3f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_WINE_CRATE", Vec3(-6.1f, 0.41f, -4.3f), 24.0f, 0.85f, 0xFFFFFF, false));

    // ---- 道具：座位区 ----
    scene.props.push_back(Prop("PROP_STOOL", Vec3(-3.2f, 0.0f, -1.5f), 0.0f));
    scene.props.push_back(Prop("PROP_STOOL", Vec3(-1.8f, 0.0f, -1.5f), 0.0f));
    scene.props.push_back(Prop("PROP_STOOL", Vec3(-0.4f, 0.0f, -1.5f), 0.0f));
    scene.props.push_back(Prop("PROP_BOOTH", Vec3(4.7f, 0.0f, -3.3f), 180.0f));
    scene.props.push_back(Prop("PROP_BOOTH", Vec3(-5.3f, 0.0f, 1.4f), 90.0f));
    scene.props.push_back(Prop("PROP_TABLE", Vec3(2.4f, 0.0f, 1.4f), 0.0f));
    scene.props.push_back(Prop("PROP_TABLE", Vec3(-3.6f, 0.0f, 2.0f), 20.0f));
    scene.props.push_back(Prop("PROP_TABLE", Vec3(0.4f, 0.0f, 2.9f), -8.0f));
    scene.props.push_back(Prop("PROP_CHAIR", Vec3(1.85f, 0.0f, 1.4f), -90.0f));
    scene.props.push_back(Prop("PROP_CHAIR", Vec3(2.95f, 0.0f, 1.4f), 90.0f));
    scene.props.push_back(Prop("PROP_CHAIR", Vec3(2.4f, 0.0f, 0.85f), 180.0f));
    scene.props.push_back(Prop("PROP_CHAIR", Vec3(-4.15f, 0.0f, 2.0f), 90.0f));
    scene.props.push_back(Prop("PROP_CHAIR", Vec3(-3.05f, 0.0f, 2.0f), -90.0f));
    scene.props.push_back(Prop("PROP_TABLE_LAMP", Vec3(2.4f, 0.78f, 1.4f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_TABLE_LAMP", Vec3(-3.6f, 0.78f, 2.0f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_RUG", Vec3(0.4f, 0.0f, 1.2f), 6.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_RUG", Vec3(4.2f, 0.0f, -2.6f), -4.0f, 0.72f, 0xFFFFFF, false));

    // ---- 道具：陈设与设备 ----
    scene.props.push_back(Prop("PROP_JUKEBOX", Vec3(6.1f, 0.0f, -0.4f), -90.0f));
    scene.props.push_back(Prop("PROP_TERMINAL", Vec3(4.9f, 0.0f, -4.4f), 0.0f));
    scene.props.push_back(Prop("PROP_SPEAKER", Vec3(-6.2f, 0.0f, -0.6f), 90.0f));
    scene.props.push_back(Prop("PROP_SPEAKER", Vec3(-6.2f, 0.0f, 2.6f), 90.0f));
    scene.props.push_back(Prop("PROP_POSTER", Vec3(-7.05f, 0.0f, -3.4f), 90.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_POSTER", Vec3(7.05f, 0.0f, 1.9f), -90.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_POSTER", Vec3(2.6f, 0.0f, -5.05f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_MENU_BOARD", Vec3(1.9f, 0.0f, 4.85f), 180.0f));
    scene.props.push_back(Prop("PROP_COAT_RACK", Vec3(-1.3f, 0.0f, 4.6f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PLANT", Vec3(-6.4f, 0.0f, 4.3f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PLANT", Vec3(6.5f, 0.0f, 3.9f), 0.0f, 0.9f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_FIRE_EXT", Vec3(6.85f, 0.0f, 2.3f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_CRATE_S", Vec3(6.3f, 0.0f, 1.0f), 18.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_BARREL", Vec3(-6.5f, 0.0f, 4.2f), 0.0f));
    scene.props.push_back(Prop("PROP_BARREL", Vec3(-6.0f, 0.0f, 4.5f), 22.0f));

    // ---- 灯饰 ----
    scene.props.push_back(Prop("PROP_PENDANT", Vec3(-3.4f, 3.3f, -2.35f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PENDANT", Vec3(-1.8f, 3.3f, -2.35f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PENDANT", Vec3(-0.2f, 3.3f, -2.35f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PENDANT", Vec3(3.4f, 3.3f, 0.2f), 0.0f, 0.9f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_WALL_LAMP", Vec3(-6.95f, 2.2f, 1.4f), 90.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_WALL_LAMP", Vec3(6.95f, 2.2f, -2.6f), -90.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_WALL_LAMP", Vec3(0.6f, 2.55f, 5.05f), 180.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_CEILING_FAN", Vec3(0.2f, 3.34f, 2.4f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_DOOR_FRAME", Vec3(0.6f, 0.0f, 5.05f), 180.0f, 1.0f, 0xFFFFFF, false));

    scene.lights.push_back(Light(Vec3(-1.8f, 2.55f, -2.35f), 0xFFA04C, 3.2f, 9.0f));
    scene.lights.push_back(Light(Vec3(-0.2f, 2.55f, -2.35f), 0xFFB262, 2.2f, 7.0f));
    scene.lights.push_back(Light(Vec3(-3.4f, 2.2f, -2.35f), 0xFFC785, 1.6f, 6.0f));
    scene.lights.push_back(Light(Vec3(0.6f, 2.6f, 4.4f), 0xFFC785, 1.9f, 7.5f));
    scene.lights.push_back(Light(Vec3(-6.0f, 2.2f, 1.0f), 0xCC301A, 1.7f, 6.0f));
    scene.lights.push_back(Light(Vec3(-5.3f, 1.7f, 1.4f), 0x66E0D0, 0.9f, 4.5f));
    scene.lights.push_back(Light(Vec3(6.1f, 1.4f, -0.4f), 0xFF3D8B, 1.0f, 4.5f));
    scene.lights.push_back(Light(Vec3(3.4f, 2.5f, 0.2f), 0xFFA860, 1.5f, 6.0f));

    scene.interactions.push_back(
        Interact("bartender", Vec3(-1.8f, 1.2f, -3.3f), 2.2f, "[E] 和酒保聊聊"));
    scene.interactions.push_back(
        Interact("bigsister", Vec3(4.7f, 1.2f, -2.2f), 2.0f, "[E] 掀开门帘"));
    scene.interactions.push_back(
        Interact("merchant", Vec3(-5.3f, 1.2f, 2.5f), 2.0f, "[E] 找东子"));
    scene.interactions.push_back(
        Interact("jukebox", Vec3(6.1f, 1.0f, -0.4f), 1.8f, "[E] 查看点唱机"));
    scene.interactions.push_back(
        Interact("terminal", Vec3(4.9f, 1.0f, -4.4f), 1.8f, "[E] 查看账本终端"));
    scene.interactions.push_back(
        Interact("bar_exit", Vec3(0.6f, 1.2f, 4.7f), 1.9f, "[E] 离开酒吧"));

    scene.cameras.push_back(CameraZone(
        Vec3(-7.0f, 0.0f, -5.0f), Vec3(7.0f, 3.4f, 5.0f),
        Vec3(4.55f, 2.72f, 4.15f), Vec3(-1.5f, 1.12f, -2.2f), 58.0f));
    return scene;
}

// ---------------------------------------------------------------------------
// 铁港仓库：集装箱、货架、油桶、叉车、吊灯与警戒设施。
// ---------------------------------------------------------------------------
SceneDef BuildHarbor()
{
    SceneDef scene;
    scene.id = SceneId::IRON_HARBOR;
    scene.displayName = "铁港 · 仓库区";
    scene.fogColor = ColorFromHex(0x0C1219);
    scene.fogNear = 7.0f;
    scene.fogFar = 34.0f;
    scene.fogDensity = 0.58f;
    scene.ambient = ColorFromHex(0x566073);
    scene.rain = false;
    scene.outdoor = false;
    scene.playerSpawn = Vec3(-11.0f, 0.0f, 7.0f);
    scene.playerYawDegrees = 90.0f;

    // ---- 地面与屋顶 ----
    scene.blocks.push_back(Block(Vec3(0.0f, -0.1f, 0.0f),
                                 Vec3(12.0f, 0.1f, 10.0f), 0x363C45, 6, false,
                                 Mat(SurfaceMaterial::PLASTER)));
    scene.blocks.push_back(Block(Vec3(0.0f, 6.0f, 0.0f),
                                 Vec3(12.0f, 0.1f, 10.0f), 0x23282E, 3, false,
                                 Mat(SurfaceMaterial::METAL_MATTE)));
    // 地面导向标线
    for (int i = -1; i <= 1; i += 2) {
        scene.blocks.push_back(Block(Vec3(static_cast<float>(i) * 2.6f, 0.02f, 0.0f),
                                     Vec3(0.08f, 0.01f, 8.6f), 0xB0902E, 0,
                                     false, Mat(SurfaceMaterial::PLASTIC)));
    }
    scene.blocks.push_back(Block(Vec3(0.0f, 0.02f, 6.4f),
                                 Vec3(9.0f, 0.01f, 0.06f), 0xB0902E, 0, false,
                                 Mat(SurfaceMaterial::PLASTIC)));

    // ---- 墙体 ----
    scene.blocks.push_back(Block(Vec3(0.0f, 3.5f, -10.2f),
                                 Vec3(12.2f, 3.6f, 0.25f), 0x2D353D, 1));
    scene.blocks.push_back(Block(Vec3(0.0f, 3.5f, 10.2f),
                                 Vec3(12.2f, 3.6f, 0.25f), 0x2D353D, 1));
    scene.blocks.push_back(Block(Vec3(12.2f, 3.5f, 0.0f),
                                 Vec3(0.25f, 3.6f, 10.2f), 0x2D353D, 1));
    scene.blocks.push_back(Block(Vec3(-12.2f, 3.5f, -1.8f),
                                 Vec3(0.25f, 3.6f, 8.2f), 0x2D353D, 1));
    scene.blocks.push_back(Block(Vec3(-12.2f, 3.5f, 8.9f),
                                 Vec3(0.25f, 3.6f, 1.3f), 0x2D353D, 1));
    scene.blocks.push_back(Block(Vec3(-12.2f, 2.9f, 7.0f),
                                 Vec3(0.25f, 0.7f, 0.9f), 0x2D353D, 1));
    // 墙上勒脚与加强柱
    for (int i = -3; i <= 3; ++i) {
        const float x = static_cast<float>(i) * 3.4f;
        scene.blocks.push_back(Block(Vec3(x, 2.4f, -9.9f),
                                     Vec3(0.12f, 2.4f, 0.12f), 0x3A4148, 3,
                                     false, Mat(SurfaceMaterial::METAL_MATTE)));
    }

    // ---- 屋顶桁架与吊灯轨道 ----
    for (int i = -2; i <= 2; ++i) {
        scene.blocks.push_back(Block(Vec3(static_cast<float>(i) * 5.0f, 5.6f, 0.0f),
                                     Vec3(0.12f, 0.12f, 9.6f), 0x3A4148, 3,
                                     false, Mat(SurfaceMaterial::METAL_MATTE)));
    }
    scene.blocks.push_back(Block(Vec3(0.0f, 5.7f, -3.0f),
                                 Vec3(11.6f, 0.1f, 0.16f), 0x3A4148, 3,
                                 false, Mat(SurfaceMaterial::METAL_MATTE)));

    // ---- 卷帘门（东侧）与出口（西侧）----
    scene.props.push_back(Prop("PROP_ROLLER_DOOR", Vec3(11.9f, 0.0f, 0.0f), -90.0f));
    scene.props.push_back(Prop("PROP_DOOR_FRAME", Vec3(-11.9f, 0.0f, 7.0f), 90.0f, 1.0f, 0xFFFFFF, false));

    // ---- 集装箱与货堆 ----
    scene.props.push_back(Prop("PROP_CONTAINER", Vec3(-6.5f, 0.0f, -6.4f), 0.0f));
    scene.props.push_back(Prop("PROP_CONTAINER", Vec3(5.4f, 0.0f, -6.6f), 8.0f));
    scene.props.push_back(Prop("PROP_CONTAINER", Vec3(8.4f, 0.0f, 4.6f), 90.0f));
    scene.props.push_back(Prop("PROP_CONTAINER", Vec3(-8.4f, 0.0f, -6.2f), 0.0f, 1.0f, 0x9AA3AD));
    scene.props.push_back(Prop("PROP_CRATE_L", Vec3(-4.2f, 0.0f, 3.4f), 16.0f));
    scene.props.push_back(Prop("PROP_CRATE_L", Vec3(-3.9f, 0.0f, 5.4f), -8.0f));
    scene.props.push_back(Prop("PROP_CRATE_S", Vec3(-2.4f, 0.0f, 4.4f), 22.0f));
    scene.props.push_back(Prop("PROP_CRATE_L", Vec3(5.0f, 0.0f, 3.0f), 4.0f));
    scene.props.push_back(Prop("PROP_CRATE_S", Vec3(6.4f, 0.0f, 4.2f), -18.0f));
    scene.props.push_back(Prop("PROP_CRATE_L", Vec3(2.6f, 0.0f, 6.6f), 12.0f));
    scene.props.push_back(Prop("PROP_BOX", Vec3(-1.0f, 0.0f, 5.6f), 8.0f));
    scene.props.push_back(Prop("PROP_CRATE_PLASTIC", Vec3(-1.4f, 0.0f, 4.6f), -12.0f));

    // ---- 货架、油桶、工作台等 ----
    scene.props.push_back(Prop("PROP_SHELF_RACK", Vec3(-2.6f, 0.0f, -8.6f), 0.0f));
    scene.props.push_back(Prop("PROP_SHELF_RACK", Vec3(2.6f, 0.0f, -8.6f), 0.0f));
    scene.props.push_back(Prop("PROP_DRUM", Vec3(-9.4f, 0.0f, -8.2f), 0.0f));
    scene.props.push_back(Prop("PROP_DRUM", Vec3(-8.6f, 0.0f, -8.5f), 22.0f));
    scene.props.push_back(Prop("PROP_DRUM", Vec3(-9.0f, 0.0f, -7.4f), -16.0f));
    scene.props.push_back(Prop("PROP_DRUM", Vec3(10.4f, 0.0f, -8.0f), 8.0f));
    scene.props.push_back(Prop("PROP_WORKBENCH", Vec3(-10.0f, 0.0f, 1.6f), 90.0f));
    scene.props.push_back(Prop("PROP_CABLE_SPOOL", Vec3(8.8f, 0.0f, -3.4f), 0.0f));
    scene.props.push_back(Prop("PROP_CARDBOARD_PILE", Vec3(6.8f, 0.0f, -8.6f), -6.0f));
    scene.props.push_back(Prop("PROP_BOX", Vec3(4.6f, 0.0f, -8.5f), 12.0f));
    scene.props.push_back(Prop("PROP_HAZARD_BARRIER", Vec3(3.2f, 0.0f, 4.0f), 90.0f));
    scene.props.push_back(Prop("PROP_HAZARD_BARRIER", Vec3(-3.4f, 0.0f, -3.4f), 18.0f));
    scene.props.push_back(Prop("PROP_TARP", Vec3(-7.8f, 0.02f, 6.4f), 24.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PIPE", Vec3(-11.6f, 0.0f, -8.0f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PIPE", Vec3(11.6f, 0.0f, 6.4f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_FIRE_EXT", Vec3(-11.7f, 0.0f, 5.2f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_FORKLIFT", Vec3(8.2f, 0.0f, 7.8f), -35.0f));
    scene.props.push_back(Prop("PROP_BARREL", Vec3(3.8f, 0.0f, 7.4f), 0.0f));
    scene.props.push_back(Prop("PROP_BARREL", Vec3(4.6f, 0.0f, 7.0f), 0.0f));
    scene.props.push_back(Prop("PROP_PALLET", Vec3(0.0f, 0.0f, 0.0f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_CARGO", Vec3(0.0f, 0.1f, 0.0f), 0.0f));
    scene.props.push_back(Prop("PROP_LAMP_HANG", Vec3(-6.0f, 5.4f, 0.0f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_LAMP_HANG", Vec3(0.0f, 5.4f, -2.0f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_LAMP_HANG", Vec3(6.0f, 5.4f, 1.5f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(-2.2f, 0.02f, 7.6f), 24.0f, 1.4f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(4.2f, 0.02f, -2.2f), -10.0f, 1.2f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(-7.4f, 0.02f, -2.6f), 8.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PART", Vec3(9.6f, 0.0f, 6.8f), 18.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_CONE", Vec3(1.8f, 0.0f, 8.2f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_CONE", Vec3(2.4f, 0.0f, 8.0f), 12.0f, 1.0f, 0xFFFFFF, false));

    scene.lights.push_back(Light(Vec3(-6.0f, 4.7f, 0.0f), 0xFFB266, 2.4f, 14.0f, 0.25f));
    scene.lights.push_back(Light(Vec3(0.0f, 4.7f, -2.0f), 0xFFC98C, 2.3f, 14.0f, 0.18f));
    scene.lights.push_back(Light(Vec3(6.0f, 4.7f, 1.5f), 0xFFB266, 2.3f, 14.0f, 0.22f));
    scene.lights.push_back(Light(Vec3(-11.0f, 3.0f, 6.5f), 0xE0B478, 1.3f, 10.0f));
    scene.lights.push_back(Light(Vec3(11.0f, 3.0f, 6.5f), 0xE0B478, 1.3f, 10.0f));
    scene.lights.push_back(Light(Vec3(11.0f, 2.8f, 0.0f), 0xFF2440, 0.0f, 9.0f, 0.0f));

    scene.interactions.push_back(
        Interact("cargo", Vec3(0.0f, 1.2f, 0.0f), 2.2f, "[E] 搬起货物"));
    scene.interactions.push_back(
        Interact("part", Vec3(9.6f, 1.0f, 6.8f), 1.5f, "[E] 拾取旧零件"));
    scene.interactions.push_back(
        Interact("warehouse_exit", Vec3(-11.2f, 1.2f, 7.0f), 1.9f, "[E] 返回旧城"));

    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, Vec3(-4.0f, 0.0f, -1.6f), 180.0f));
    scene.enemies.push_back(Spawn(EnemyType::THUG, Vec3(3.4f, 0.0f, -4.2f), 180.0f));
    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, Vec3(6.6f, 0.0f, 1.2f), 200.0f));
    scene.enemies.push_back(Spawn(EnemyType::THUG, Vec3(-1.6f, 0.0f, 5.4f), 140.0f));
    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, Vec3(-8.6f, 0.0f, 2.6f), 90.0f));

    scene.cameras.push_back(CameraZone(
        Vec3(-12.2f, 0.0f, -10.0f), Vec3(-3.2f, 8.0f, 10.0f),
        Vec3(-8.6f, 4.4f, 8.4f), Vec3(-1.6f, 1.1f, -1.2f), 56.0f));
    scene.cameras.push_back(CameraZone(
        Vec3(-3.2f, 0.0f, -10.0f), Vec3(3.2f, 8.0f, 10.0f),
        Vec3(0.0f, 4.8f, 8.2f), Vec3(0.0f, 1.0f, -1.6f), 56.0f));
    scene.cameras.push_back(CameraZone(
        Vec3(3.2f, 0.0f, -10.0f), Vec3(12.2f, 8.0f, 10.0f),
        Vec3(8.6f, 4.4f, 8.4f), Vec3(1.6f, 1.1f, -1.2f), 56.0f));
    return scene;
}

} // namespace

const char* SceneDisplayName(SceneId id)
{
    switch (id) {
    case SceneId::BAR_EXTERIOR:
        return "旧城区 · 余烬酒吧外";
    case SceneId::BAR_INTERIOR:
        return "旧城区 · 余烬酒吧";
    case SceneId::IRON_HARBOR:
        return "铁港 · 仓库区";
    default:
        return "";
    }
}

SceneDef BuildScene(SceneId id)
{
    switch (id) {
    case SceneId::BAR_INTERIOR:
        return BuildInterior();
    case SceneId::IRON_HARBOR:
        return BuildHarbor();
    case SceneId::BAR_EXTERIOR:
    default:
        return BuildExterior();
    }
}

} // namespace fc
