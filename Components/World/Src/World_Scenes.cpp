#include "World_Types.hpp"

#include "Shared_Math.hpp"

#include <string>

namespace fc {

namespace {

RoomBlock Block(const Vec3& center, const Vec3& half, unsigned int rgb,
                int pattern, bool solid = true)
{
    RoomBlock block;
    block.center = center;
    block.half = half;
    block.color = ColorFromHex(rgb);
    block.pattern = pattern;
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

SceneDef BuildExterior()
{
    SceneDef scene;
    scene.id = SceneId::BAR_EXTERIOR;
    scene.displayName = "旧城区 · 余烬酒吧外";
    scene.fogColor = ColorFromHex(0x05070D);
    scene.fogNear = 4.0f;
    scene.fogFar = 26.0f;
    scene.fogDensity = 0.82f;
    scene.ambient = ColorFromHex(0x333E54);
    scene.rain = true;
    scene.outdoor = true;
    scene.playerSpawn = Vec3(0.6f, 0.0f, 11.5f);
    scene.playerYawDegrees = 180.0f;

    // 地面与街道
    scene.blocks.push_back(Block(Vec3(0.0f, -0.1f, 7.0f),
                                 Vec3(7.2f, 0.1f, 7.2f), 0x1A1F27, 6, false));
    scene.blocks.push_back(Block(Vec3(0.0f, 0.03f, 1.1f),
                                 Vec3(7.0f, 0.04f, 1.3f), 0x2B2E33, 6, false));

    // 酒吧外墙与门洞
    scene.blocks.push_back(Block(Vec3(-3.95f, 2.6f, -0.2f),
                                 Vec3(3.05f, 2.6f, 0.25f), 0x2A2422, 1));
    scene.blocks.push_back(Block(Vec3(4.55f, 2.6f, -0.2f),
                                 Vec3(2.45f, 2.6f, 0.25f), 0x2A2422, 1));
    scene.blocks.push_back(Block(Vec3(0.6f, 3.4f, -0.2f),
                                 Vec3(1.5f, 0.8f, 0.25f), 0x241E1C, 1));

    // 街道两侧与后墙
    scene.blocks.push_back(Block(Vec3(-7.2f, 2.6f, 7.0f),
                                 Vec3(0.25f, 2.6f, 7.2f), 0x1E2126, 6));
    scene.blocks.push_back(Block(Vec3(7.2f, 2.6f, 7.0f),
                                 Vec3(0.25f, 2.6f, 7.2f), 0x1E2126, 6));
    scene.blocks.push_back(Block(Vec3(0.0f, 2.6f, 14.3f),
                                 Vec3(7.2f, 2.6f, 0.25f), 0x1B1E23, 6));

    // 雨棚与路缘
    scene.blocks.push_back(Block(Vec3(0.6f, 2.85f, 1.35f),
                                 Vec3(1.9f, 0.08f, 1.25f), 0x5C2530, 5));
    scene.blocks.push_back(Block(Vec3(0.0f, 0.13f, 2.5f),
                                 Vec3(7.0f, 0.12f, 0.12f), 0x3A3D42, 6, false));

    scene.props.push_back(Prop("PROP_NEON_BAR", Vec3(0.6f, 2.55f, -0.35f), 0.0f));
    scene.props.push_back(Prop("PROP_DOOR_FRAME", Vec3(0.6f, 0.0f, -0.05f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_CAR", Vec3(-4.3f, 0.0f, 8.6f), 96.0f));
    scene.props.push_back(Prop("PROP_BIN", Vec3(5.5f, 0.0f, 2.6f), 12.0f));
    scene.props.push_back(Prop("PROP_BIN", Vec3(6.1f, 0.0f, 3.3f), -20.0f));
    scene.props.push_back(Prop("PROP_LAMPPOST", Vec3(5.2f, 0.0f, 9.4f), 0.0f));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(-2.0f, 0.02f, 6.2f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(3.2f, 0.02f, 4.4f), 30.0f, 1.2f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_CRATE_S", Vec3(-6.4f, 0.0f, 12.4f), -14.0f));

    scene.lights.push_back(Light(Vec3(0.6f, 2.45f, 1.35f), 0xFFC785, 2.4f, 7.0f));
    scene.lights.push_back(Light(Vec3(2.5f, 2.55f, 0.9f), 0xFF2F7A, 1.5f, 7.5f, 0.55f));
    scene.lights.push_back(Light(Vec3(5.2f, 3.7f, 10.15f), 0xFFD8A0, 0.9f, 9.0f));
    scene.lights.push_back(Light(Vec3(-4.3f, 0.8f, 8.6f), 0xFFC46B, 0.7f, 4.5f));

    scene.interactions.push_back(
        Interact("bar_entrance", Vec3(0.6f, 1.2f, 0.85f), 1.7f,
                 "[E] 进入余烬酒吧"));
    scene.interactions.push_back(
        Interact("car", Vec3(-4.3f, 1.1f, 8.6f), 2.1f, "[E] 上车前往铁港"));
    scene.interactions.push_back(
        Interact("street_sign", Vec3(2.2f, 1.3f, 0.9f), 1.9f, "[E] 看看招牌"));

    scene.cameras.push_back(CameraZone(
        Vec3(-7.0f, 0.0f, 0.0f), Vec3(7.0f, 4.0f, 14.0f),
        Vec3(5.4f, 3.7f, 12.8f), Vec3(-0.8f, 1.35f, 3.6f), 52.0f));
    return scene;
}

SceneDef BuildInterior()
{
    SceneDef scene;
    scene.id = SceneId::BAR_INTERIOR;
    scene.displayName = "旧城区 · 余烬酒吧";
    scene.fogColor = ColorFromHex(0x0C0708);
    scene.fogNear = 5.0f;
    scene.fogFar = 28.0f;
    scene.fogDensity = 0.5f;
    scene.ambient = ColorFromHex(0x343C4E);
    scene.rain = false;
    scene.outdoor = false;
    scene.playerSpawn = Vec3(0.6f, 0.0f, 4.2f);
    scene.playerYawDegrees = 180.0f;

    scene.blocks.push_back(Block(Vec3(0.0f, -0.1f, 0.0f),
                                 Vec3(7.0f, 0.1f, 5.0f), 0x3A2A20, 2, false));
    scene.blocks.push_back(Block(Vec3(0.0f, 3.5f, 0.0f),
                                 Vec3(7.0f, 0.12f, 5.0f), 0x1A1416, 6, false));

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

    // 长吧台：台体 + 台面 + 黄铜压边
    scene.blocks.push_back(Block(Vec3(-1.8f, 0.55f, -2.35f),
                                 Vec3(3.3f, 0.55f, 0.3f), 0x4A3220, 2));
    scene.blocks.push_back(Block(Vec3(-1.8f, 1.12f, -2.35f),
                                 Vec3(3.45f, 0.06f, 0.42f), 0x8C6A2E, 0));
    scene.blocks.push_back(Block(Vec3(-1.8f, 1.02f, -2.06f),
                                 Vec3(3.45f, 0.05f, 0.05f), 0xC79A4A, 0));
    // 吧台后置物架
    scene.blocks.push_back(Block(Vec3(-1.8f, 1.75f, -4.55f),
                                 Vec3(3.2f, 1.0f, 0.18f), 0x3A2A1E, 2));

    scene.props.push_back(Prop("PROP_BAR_SHELF", Vec3(-1.8f, 1.1f, -4.4f), 0.0f));
    scene.props.push_back(Prop("PROP_STOOL", Vec3(-3.2f, 0.0f, -1.5f), 0.0f));
    scene.props.push_back(Prop("PROP_STOOL", Vec3(-1.8f, 0.0f, -1.5f), 0.0f));
    scene.props.push_back(Prop("PROP_STOOL", Vec3(-0.4f, 0.0f, -1.5f), 0.0f));
    scene.props.push_back(Prop("PROP_BOOTH", Vec3(4.7f, 0.0f, -3.3f), 180.0f));
    scene.props.push_back(Prop("PROP_BOOTH", Vec3(-5.3f, 0.0f, 1.4f), 90.0f));
    scene.props.push_back(Prop("PROP_TABLE", Vec3(2.4f, 0.0f, 1.4f), 0.0f));
    scene.props.push_back(Prop("PROP_TABLE", Vec3(-3.6f, 0.0f, 2.0f), 20.0f));
    scene.props.push_back(Prop("PROP_JUKEBOX", Vec3(6.1f, 0.0f, -0.4f), -90.0f));
    scene.props.push_back(Prop("PROP_TERMINAL", Vec3(4.9f, 0.0f, -4.4f), 0.0f));
    scene.props.push_back(Prop("PROP_SPEAKER", Vec3(-6.2f, 0.0f, -0.6f), 90.0f));
    scene.props.push_back(Prop("PROP_SPEAKER", Vec3(-6.2f, 0.0f, 2.6f), 90.0f));
    scene.props.push_back(Prop("PROP_CRATE_S", Vec3(6.3f, 0.0f, 3.9f), 18.0f));
    scene.props.push_back(Prop("PROP_DOOR_FRAME", Vec3(0.6f, 0.0f, 5.05f), 180.0f, 1.0f, 0xFFFFFF, false));

    scene.lights.push_back(Light(Vec3(-1.8f, 2.85f, -2.35f), 0xFFA04C, 3.0f, 8.5f));
    scene.lights.push_back(Light(Vec3(0.6f, 2.9f, 4.6f), 0xFFC785, 1.8f, 7.0f));
    scene.lights.push_back(Light(Vec3(-6.0f, 2.3f, 1.0f), 0xCC301A, 1.7f, 6.0f));
    scene.lights.push_back(Light(Vec3(-5.3f, 1.7f, 1.4f), 0x66E0D0, 0.9f, 4.5f));
    scene.lights.push_back(Light(Vec3(6.1f, 1.4f, -0.4f), 0xFF3D8B, 0.8f, 4.0f));

    scene.interactions.push_back(
        Interact("bartender", Vec3(-1.8f, 1.2f, -3.3f), 1.9f, "[E] 和酒保聊聊"));
    scene.interactions.push_back(
        Interact("bigsister", Vec3(4.7f, 1.2f, -2.2f), 1.7f, "[E] 掀开门帘"));
    scene.interactions.push_back(
        Interact("merchant", Vec3(-5.3f, 1.2f, 2.5f), 1.7f, "[E] 找东子"));
    scene.interactions.push_back(
        Interact("jukebox", Vec3(6.1f, 1.0f, -0.4f), 1.5f, "[E] 查看点唱机"));
    scene.interactions.push_back(
        Interact("terminal", Vec3(4.9f, 1.0f, -4.4f), 1.5f, "[E] 查看账本终端"));
    scene.interactions.push_back(
        Interact("bar_exit", Vec3(0.6f, 1.2f, 4.7f), 1.6f, "[E] 离开酒吧"));

    scene.cameras.push_back(CameraZone(
        Vec3(-7.0f, 0.0f, -5.0f), Vec3(7.0f, 3.4f, 5.0f),
        Vec3(5.6f, 2.95f, 4.35f), Vec3(-1.4f, 1.15f, -1.9f), 58.0f));
    return scene;
}

SceneDef BuildHarbor()
{
    SceneDef scene;
    scene.id = SceneId::IRON_HARBOR;
    scene.displayName = "铁港 · 仓库区";
    scene.fogColor = ColorFromHex(0x070B10);
    scene.fogNear = 6.0f;
    scene.fogFar = 34.0f;
    scene.fogDensity = 0.78f;
    scene.ambient = ColorFromHex(0x333C4C);
    scene.rain = false;
    scene.outdoor = false;
    scene.playerSpawn = Vec3(-11.0f, 0.0f, 7.0f);
    scene.playerYawDegrees = 90.0f;

    scene.blocks.push_back(Block(Vec3(0.0f, -0.1f, 0.0f),
                                 Vec3(12.0f, 0.1f, 10.0f), 0x2B3037, 6, false));
    scene.blocks.push_back(Block(Vec3(0.0f, 6.0f, 0.0f),
                                 Vec3(12.0f, 0.1f, 10.0f), 0x23282E, 6, false));
    scene.blocks.push_back(Block(Vec3(0.0f, 3.5f, -10.2f),
                                 Vec3(12.2f, 3.6f, 0.25f), 0x232A31, 3));
    scene.blocks.push_back(Block(Vec3(0.0f, 3.5f, 10.2f),
                                 Vec3(12.2f, 3.6f, 0.25f), 0x232A31, 3));
    scene.blocks.push_back(Block(Vec3(12.2f, 3.5f, 0.0f),
                                 Vec3(0.25f, 3.6f, 10.2f), 0x232A31, 3));
    scene.blocks.push_back(Block(Vec3(-12.2f, 3.5f, -1.8f),
                                 Vec3(0.25f, 3.6f, 8.2f), 0x232A31, 3));
    scene.blocks.push_back(Block(Vec3(-12.2f, 3.5f, 8.9f),
                                 Vec3(0.25f, 3.6f, 1.3f), 0x232A31, 3));
    scene.blocks.push_back(Block(Vec3(-12.2f, 2.9f, 7.0f),
                                 Vec3(0.25f, 0.7f, 0.9f), 0x232A31, 3));

    // 屋顶桁架与吊灯轨道
    for (int i = -2; i <= 2; ++i) {
        scene.blocks.push_back(Block(Vec3(static_cast<float>(i) * 5.0f, 5.6f, 0.0f),
                                     Vec3(0.12f, 0.12f, 9.6f), 0x3A4148, 3, false));
    }
    scene.blocks.push_back(Block(Vec3(0.0f, 5.7f, -3.0f),
                                 Vec3(11.6f, 0.1f, 0.16f), 0x3A4148, 3, false));

    // 卷帘门（东侧）与出口（西侧）
    scene.props.push_back(Prop("PROP_ROLLER_DOOR", Vec3(11.9f, 0.0f, 0.0f), -90.0f));
    scene.props.push_back(Prop("PROP_DOOR_FRAME", Vec3(-11.9f, 0.0f, 7.0f), 90.0f, 1.0f, 0xFFFFFF, false));

    // 集装箱与货堆
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
    scene.props.push_back(Prop("PROP_BARREL", Vec3(3.8f, 0.0f, 7.4f), 0.0f));
    scene.props.push_back(Prop("PROP_BARREL", Vec3(4.6f, 0.0f, 7.0f), 0.0f));
    scene.props.push_back(Prop("PROP_FORKLIFT", Vec3(8.2f, 0.0f, 7.8f), -35.0f));
    scene.props.push_back(Prop("PROP_PALLET", Vec3(0.0f, 0.0f, 0.0f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_CARGO", Vec3(0.0f, 0.1f, 0.0f), 0.0f));
    scene.props.push_back(Prop("PROP_LAMP_HANG", Vec3(-6.0f, 5.4f, 0.0f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_LAMP_HANG", Vec3(0.0f, 5.4f, -2.0f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_LAMP_HANG", Vec3(6.0f, 5.4f, 1.5f), 0.0f, 1.0f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(-2.2f, 0.02f, 7.6f), 24.0f, 1.4f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PUDDLE", Vec3(4.2f, 0.02f, -2.2f), -10.0f, 1.2f, 0xFFFFFF, false));
    scene.props.push_back(Prop("PROP_PART", Vec3(9.6f, 0.0f, 6.8f), 18.0f, 1.0f, 0xFFFFFF, false));

    scene.lights.push_back(Light(Vec3(-6.0f, 4.9f, 0.0f), 0xFFB266, 2.1f, 11.0f, 0.25f));
    scene.lights.push_back(Light(Vec3(0.0f, 4.9f, -2.0f), 0xFFC98C, 2.0f, 11.0f, 0.18f));
    scene.lights.push_back(Light(Vec3(6.0f, 4.9f, 1.5f), 0xFFB266, 2.0f, 11.0f, 0.22f));
    scene.lights.push_back(Light(Vec3(11.0f, 2.8f, 0.0f), 0xFF2440, 0.0f, 9.0f, 0.0f));

    scene.interactions.push_back(
        Interact("cargo", Vec3(0.0f, 1.2f, 0.0f), 2.2f, "[E] 搬起货物"));
    scene.interactions.push_back(
        Interact("part", Vec3(9.6f, 1.0f, 6.8f), 1.5f, "[E] 拾取旧零件"));
    scene.interactions.push_back(
        Interact("warehouse_exit", Vec3(-11.2f, 1.2f, 7.0f), 1.9f, "[E] 返回旧城"));

    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, Vec3(-4.0f, 0.0f, -1.6f), 180.0f));
    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, Vec3(3.4f, 0.0f, -4.2f), 180.0f));
    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, Vec3(6.6f, 0.0f, 1.2f), 200.0f));
    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, Vec3(-1.6f, 0.0f, 5.4f), 140.0f));

    scene.cameras.push_back(CameraZone(
        Vec3(-12.2f, 0.0f, -10.0f), Vec3(-3.2f, 8.0f, 10.0f),
        Vec3(-9.4f, 4.55f, 8.6f), Vec3(-5.6f, 1.1f, 1.6f), 56.0f));
    scene.cameras.push_back(CameraZone(
        Vec3(-3.2f, 0.0f, -10.0f), Vec3(3.2f, 8.0f, 10.0f),
        Vec3(0.8f, 4.7f, 8.8f), Vec3(-0.6f, 1.0f, 0.2f), 56.0f));
    scene.cameras.push_back(CameraZone(
        Vec3(3.2f, 0.0f, -10.0f), Vec3(12.2f, 8.0f, 10.0f),
        Vec3(9.8f, 4.55f, 8.4f), Vec3(6.2f, 1.1f, 1.4f), 56.0f));
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
