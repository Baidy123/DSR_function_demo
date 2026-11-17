#include "World_SceneData.hpp"

#include <algorithm>

namespace fc {

namespace {

PropDef Prop(const char* sprite, float x, float y, bool blocking)
{
    PropDef def;
    def.sprite = sprite;
    def.x = x;
    def.y = y;
    def.blocking = blocking;
    return def;
}

InteractDef Interact(const char* id, float x, float y, float radius,
                     const char* prompt)
{
    InteractDef def;
    def.id = id;
    def.x = x;
    def.y = y;
    def.radius = radius;
    def.prompt = prompt;
    return def;
}

EnemySpawnDef Spawn(EnemyType type, float x, float y)
{
    EnemySpawnDef def;
    def.type = type;
    def.x = x;
    def.y = y;
    return def;
}

SceneDefinition BuildExterior()
{
    SceneDefinition scene;
    scene.id = SceneId::BAR_EXTERIOR;
    scene.theme = SceneTheme::STREET;
    scene.widthTiles = 30;
    scene.heightTiles = 17;
    scene.raining = true;
    scene.cameraFollow = false;
    scene.displayName = "旧城区 · 余烬酒吧外";
    scene.playerSpawn = Vec2(392.0f, 216.0f);

    scene.tiles.assign(scene.heightTiles, std::string(scene.widthTiles, '.'));
    for (int x = 0; x < scene.widthTiles; ++x) {
        for (int y = 0; y < 4; ++y) {
            scene.tiles[static_cast<size_t>(y)][static_cast<size_t>(x)] = '#';
        }
        scene.tiles[16][static_cast<size_t>(x)] = '#';
    }
    for (int y = 0; y < scene.heightTiles; ++y) {
        scene.tiles[static_cast<size_t>(y)][0] = '#';
        scene.tiles[static_cast<size_t>(y)][29] = '#';
    }
    const int windowCells[][2] = {
        {6, 1}, {7, 1}, {20, 1}, {21, 1},
        {10, 2}, {11, 2}, {26, 2}, {27, 2}
    };
    for (const auto& cell : windowCells) {
        scene.tiles[static_cast<size_t>(cell[1])][static_cast<size_t>(cell[0])] = 'W';
    }
    scene.tiles[15][3] = 'C';
    scene.tiles[15][4] = 'C';
    scene.tiles[15][5] = 'C';

    scene.props.push_back(Prop("PROP_NEON_AFTERGLOW", 300.0f, 8.0f, false));
    scene.props.push_back(Prop("PROP_DOOR", 320.0f, 40.0f, false));
    scene.props.push_back(Prop("PROP_WINDOW_LIT", 144.0f, 24.0f, false));
    scene.props.push_back(Prop("PROP_WINDOW_LIT", 384.0f, 24.0f, false));
    scene.props.push_back(Prop("PROP_WINDOW_LIT", 300.0f, 56.0f, false));
    scene.props.push_back(Prop("PROP_LAMP_PENDANT", 360.0f, 20.0f, false));
    scene.props.push_back(Prop("PROP_CAR", 400.0f, 176.0f, true));
    scene.props.push_back(Prop("PROP_BARREL", 296.0f, 184.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_S", 320.0f, 184.0f, true));
    scene.props.push_back(Prop("PROP_PUDDLE", 120.0f, 224.0f, false));
    scene.props.push_back(Prop("PROP_PUDDLE", 320.0f, 224.0f, false));
    scene.props.push_back(Prop("PROP_PUDDLE", 360.0f, 210.0f, false));

    scene.interactions.push_back(Interact("bar_entrance", 328.0f, 88.0f, 28.0f,
                                          "[E] 推门进入余烬酒吧"));
    scene.interactions.push_back(Interact("car", 424.0f, 210.0f, 30.0f,
                                          "[E] 上车前往铁港"));
    scene.interactions.push_back(Interact("street_sign", 330.0f, 28.0f, 22.0f,
                                          "[E] 看看招牌"));
    return scene;
}

SceneDefinition BuildInterior()
{
    SceneDefinition scene;
    scene.id = SceneId::BAR_INTERIOR;
    scene.theme = SceneTheme::BAR;
    scene.widthTiles = 30;
    scene.heightTiles = 17;
    scene.raining = false;
    scene.cameraFollow = false;
    scene.displayName = "旧城区 · 余烬酒吧";
    scene.playerSpawn = Vec2(270.0f, 224.0f);

    scene.tiles = {
        "##############################",
        "#SSSS#WW#....................#",
        "#....#..#....................#",
        "#...................~~~~~~~~~#",
        "#...................~~~~~~~~~#",
        "#...................~~~~~~~~~#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "##############################"
    };

    scene.props.push_back(Prop("PROP_NEON_AFTERGLOW", 200.0f, 0.0f, false));
    scene.props.push_back(Prop("PROP_LAMP_PENDANT", 120.0f, 16.0f, false));
    scene.props.push_back(Prop("PROP_LAMP_PENDANT", 280.0f, 16.0f, false));
    scene.props.push_back(Prop("PROP_LAMP_PENDANT", 400.0f, 16.0f, false));
    scene.props.push_back(Prop("PROP_BAR_COUNTER", 96.0f, 112.0f, true));
    scene.props.push_back(Prop("PROP_BAR_COUNTER", 144.0f, 112.0f, true));
    scene.props.push_back(Prop("PROP_BAR_COUNTER", 192.0f, 112.0f, true));
    scene.props.push_back(Prop("CHAR_BARTENDER_S_IDLE", 152.0f, 96.0f, true));
    scene.props.push_back(Prop("PROP_BOOTH", 336.0f, 32.0f, true));
    scene.props.push_back(Prop("CHAR_BIGSISTER_SIT", 344.0f, 58.0f, true));
    scene.props.push_back(Prop("PROP_BOOTH", 32.0f, 88.0f, true));
    scene.props.push_back(Prop("CHAR_MERCHANT_SIT", 40.0f, 114.0f, true));
    scene.props.push_back(Prop("PROP_JUKEBOX_BROKEN", 432.0f, 40.0f, true));
    scene.props.push_back(Prop("PROP_TABLE_ROUND", 160.0f, 160.0f, true));
    scene.props.push_back(Prop("PROP_CHAIR", 148.0f, 164.0f, true));
    scene.props.push_back(Prop("PROP_CHAIR", 176.0f, 164.0f, true));
    scene.props.push_back(Prop("PROP_TABLE_ROUND", 240.0f, 168.0f, true));
    scene.props.push_back(Prop("PROP_CHAIR", 228.0f, 172.0f, true));
    scene.props.push_back(Prop("PROP_CHAIR", 256.0f, 172.0f, true));
    scene.props.push_back(Prop("PROP_TABLE_ROUND", 320.0f, 152.0f, true));
    scene.props.push_back(Prop("PROP_CHAIR", 308.0f, 156.0f, true));
    scene.props.push_back(Prop("PROP_DOOR", 224.0f, 240.0f, false));
    scene.props.push_back(Prop("PROP_DOOR", 456.0f, 240.0f, false));

    scene.interactions.push_back(Interact("bartender", 168.0f, 132.0f, 32.0f,
                                          "[E] 和酒保聊聊"));
    scene.interactions.push_back(Interact("bigsister", 356.0f, 88.0f, 30.0f,
                                          "[E] 掀开门帘"));
    scene.interactions.push_back(Interact("merchant", 52.0f, 144.0f, 30.0f,
                                          "[E] 找东子"));
    scene.interactions.push_back(Interact("jukebox", 440.0f, 84.0f, 26.0f,
                                          "[E] 查看点唱机"));
    scene.interactions.push_back(Interact("bar_exit", 232.0f, 250.0f, 28.0f,
                                          "[E] 离开酒吧"));
    scene.interactions.push_back(Interact("backdoor", 464.0f, 250.0f, 22.0f,
                                          "[E] 查看后门"));
    return scene;
}

SceneDefinition BuildHarbor()
{
    SceneDefinition scene;
    scene.id = SceneId::IRON_HARBOR;
    scene.theme = SceneTheme::HARBOR;
    scene.widthTiles = 44;
    scene.heightTiles = 26;
    scene.raining = true;
    scene.cameraFollow = true;
    scene.displayName = "铁港 · 仓库区";
    scene.playerSpawn = Vec2(280.0f, 240.0f);

    scene.tiles.assign(scene.heightTiles, std::string(scene.widthTiles, '.'));
    for (int x = 0; x < scene.widthTiles; ++x) {
        scene.tiles[0][static_cast<size_t>(x)] = '#';
        scene.tiles[25][static_cast<size_t>(x)] = '#';
    }
    for (int y = 0; y < scene.heightTiles; ++y) {
        scene.tiles[static_cast<size_t>(y)][0] = '#';
        scene.tiles[static_cast<size_t>(y)][43] = '#';
    }
    for (int x = 34; x < 43; ++x) {
        scene.tiles[10][static_cast<size_t>(x)] = 'D';
        scene.tiles[11][static_cast<size_t>(x)] = 'D';
        scene.tiles[12][static_cast<size_t>(x)] = 'D';
    }
    for (int y = 10; y <= 12; ++y) {
        for (int x = 20; x <= 24; ++x) {
            scene.tiles[static_cast<size_t>(y)][static_cast<size_t>(x)] = ';';
        }
    }

    scene.props.push_back(Prop("PROP_DOOR", 16.0f, 176.0f, false));
    scene.props.push_back(Prop("PROP_CONTAINER", 80.0f, 32.0f, true));
    scene.props.push_back(Prop("PROP_CONTAINER", 240.0f, 32.0f, true));
    scene.props.push_back(Prop("PROP_CONTAINER", 400.0f, 32.0f, true));
    scene.props.push_back(Prop("PROP_CONTAINER", 560.0f, 32.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_L", 160.0f, 128.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_L", 192.0f, 128.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_S", 224.0f, 144.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_L", 440.0f, 112.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_S", 472.0f, 144.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_L", 120.0f, 288.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_S", 152.0f, 272.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_L", 480.0f, 288.0f, true));
    scene.props.push_back(Prop("PROP_CRATE_S", 512.0f, 304.0f, true));
    scene.props.push_back(Prop("PROP_BARREL", 600.0f, 112.0f, true));
    scene.props.push_back(Prop("PROP_BARREL", 608.0f, 136.0f, true));
    scene.props.push_back(Prop("PROP_FORKLIFT", 544.0f, 336.0f, true));
    scene.props.push_back(Prop("PROP_CARGO", 336.0f, 168.0f, true));
    scene.props.push_back(Prop("PROP_PART", 544.0f, 80.0f, false));
    scene.props.push_back(Prop("PROP_LAMP_PENDANT", 200.0f, 64.0f, false));
    scene.props.push_back(Prop("PROP_LAMP_PENDANT", 400.0f, 64.0f, false));
    scene.props.push_back(Prop("PROP_LAMP_PENDANT", 600.0f, 64.0f, false));
    scene.props.push_back(Prop("PROP_ALARM_OFF", 656.0f, 112.0f, false));
    scene.props.push_back(Prop("PROP_ALARM_OFF", 656.0f, 160.0f, false));
    scene.props.push_back(Prop("PROP_ALARM_OFF", 656.0f, 208.0f, false));
    scene.props.push_back(Prop("PROP_PUDDLE", 240.0f, 240.0f, false));
    scene.props.push_back(Prop("PROP_PUDDLE", 448.0f, 248.0f, false));
    scene.props.push_back(Prop("PROP_PUDDLE", 352.0f, 112.0f, false));

    scene.interactions.push_back(Interact("warehouse_exit", 40.0f, 192.0f,
                                          30.0f, "[E] 返回旧城"));
    scene.interactions.push_back(Interact("cargo", 352.0f, 200.0f, 30.0f,
                                          "[E] 搬起货物"));
    scene.interactions.push_back(Interact("part", 550.0f, 96.0f, 24.0f,
                                          "[E] 拾取旧零件"));

    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, 200.0f, 120.0f));
    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, 320.0f, 96.0f));
    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, 480.0f, 200.0f));
    scene.enemies.push_back(Spawn(EnemyType::SCAVENGER, 420.0f, 336.0f));
    return scene;
}

} // namespace

SceneDefinition BuildBarExteriorScene()
{
    return BuildExterior();
}

SceneDefinition BuildBarInteriorScene()
{
    return BuildInterior();
}

SceneDefinition BuildIronHarborScene()
{
    return BuildHarbor();
}

SceneDefinition BuildScene(SceneId id)
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
