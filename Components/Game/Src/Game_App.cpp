#include "Game_App.hpp"

#include "Platform_Input.hpp"
#include "Shared_Log.hpp"
#include "Shared_Math.hpp"
#include "World_SceneData.hpp"

#include <algorithm>
#include <cmath>
#include <climits>
#include <string>

namespace fc {

namespace {

const Color WHITE = Color(1.0f, 1.0f, 1.0f, 1.0f);
const Color BONE = Rgba(232, 227, 214);
const Color CYAN = Rgba(57, 224, 208);
const Color AMBER = Rgba(255, 179, 71);
const Color MAGENTA = Rgba(255, 61, 139);
const Color RED = Rgba(220, 60, 72);
const Color DIM = Rgba(132, 152, 154);

DialogueNode SimpleNode(const char* speaker, const char* portrait,
                        const char* text)
{
    DialogueNode node;
    node.speaker = speaker != nullptr ? speaker : "";
    node.portrait = portrait != nullptr ? portrait : "";
    node.text = text != nullptr ? text : "";
    return node;
}

} // namespace

GameApp::~GameApp()
{
    Shutdown();
}

bool GameApp::Initialize(HWND hwnd, int width, int height,
                         const std::vector<uint8_t>& artPack, bool muted)
{
    m_muted = muted;
    if (!m_device.Initialize(hwnd, width, height)) {
        return false;
    }
    if (!m_device.LoadArtPack(artPack)) {
        return false;
    }
    if (!m_text.Initialize(&m_device)) {
        return false;
    }
    if (!m_renderer.Initialize(&m_device, &m_text)) {
        return false;
    }
    if (!m_ui.Initialize(&m_device, &m_text)) {
        return false;
    }
    m_audio.Initialize();
    m_audio.SetMuted(m_muted);
    m_audio.SetScene(1, true);

    m_mode = GameMode::TITLE;
    m_hasScene = false;
    m_time = 0.0f;
    m_rng.Seed(0xC0FFEEu);
    LogInfo("GameApp initialized");
    return true;
}

void GameApp::Shutdown()
{
    m_audio.Shutdown();
    m_text.Shutdown();
    m_device.Shutdown();
}

void GameApp::Resize(int width, int height)
{
    m_device.Resize(width, height);
}

bool GameApp::Capture(const std::string& path)
{
    return m_device.CaptureOffscreen(path);
}

void GameApp::Present(bool vsync)
{
    m_device.Present(vsync);
}

void GameApp::Update(float dt)
{
    dt = Clamp(dt, 0.0f, 0.05f);
    m_time += dt;
    m_damageFlash = std::max(0.0f, m_damageFlash - dt * 2.4f);
    if (m_shakeTimer > 0.0f) {
        m_shakeTimer = std::max(0.0f, m_shakeTimer - dt);
        const float f = m_shakeDuration > 0.0f
                            ? m_shakeTimer / m_shakeDuration
                            : 0.0f;
        m_shakeOffset = Vec2(m_rng.Float(-1.0f, 1.0f) * m_shakeIntensity * f,
                             m_rng.Float(-1.0f, 1.0f) * m_shakeIntensity * f);
    } else {
        m_shakeOffset = Vec2();
    }
    if (m_noGearToastCooldown > 0) {
        --m_noGearToastCooldown;
    }
    UpdateToasts(dt);
    UpdateLocation(dt);

    Input& input = Input::Get();
    switch (m_mode) {
    case GameMode::TITLE:
        if (input.Pressed(VK_RETURN) || input.Pressed(VK_SPACE) ||
            input.MousePressed(0)) {
            StartNewGame();
        } else if (input.Pressed(VK_ESCAPE)) {
            m_quit = true;
        }
        break;
    case GameMode::PLAYING:
        UpdatePlaying(dt);
        break;
    case GameMode::DIALOGUE:
        UpdateDialogue(dt);
        break;
    case GameMode::SHOP:
        UpdateShop(dt);
        break;
    case GameMode::JOURNAL:
        if (input.Pressed(VK_TAB) || input.Pressed(VK_ESCAPE)) {
            m_mode = GameMode::PLAYING;
        }
        break;
    case GameMode::PAUSED:
        if (input.Pressed(VK_ESCAPE)) {
            m_mode = GameMode::PLAYING;
        } else if (input.Pressed('Q')) {
            m_mode = GameMode::TITLE;
            m_hasScene = false;
        }
        break;
    case GameMode::DEAD:
        if (input.Pressed(VK_RETURN)) {
            RespawnAfterDeath();
        } else if (input.Pressed(VK_ESCAPE)) {
            m_mode = GameMode::TITLE;
            m_hasScene = false;
        }
        break;
    case GameMode::EPILOGUE:
        if (input.Pressed(VK_RETURN)) {
            StartNewGame();
        } else if (input.Pressed(VK_ESCAPE)) {
            m_mode = GameMode::TITLE;
            m_hasScene = false;
        }
        break;
    case GameMode::TRANSITION:
        UpdateTransition(dt);
        break;
    default:
        break;
    }

    if (input.Pressed('M')) {
        m_muted = !m_muted;
        m_audio.SetMuted(m_muted);
    }
}

void GameApp::StartNewGame()
{
    m_inventory = Inventory();
    m_quest = QuestState();
    m_player = Player();
    m_player.hp = PLAYER_MAX_HP;
    m_shop = ShopState();
    m_endingChoice = EndingChoice::NONE;
    m_enemies.clear();
    m_bullets.clear();
    m_particles.clear();
    m_pickups.clear();
    m_rain.clear();
    m_toasts.clear();
    m_alarm = false;
    m_damageFlash = 0.0f;
    m_shakeTimer = 0.0f;
    m_transitionActive = false;
    m_fadeAlpha = 0.0f;
    m_prompt.clear();
    m_hasPrompt = false;
    m_time = 0.0f;
    m_hasScene = false;
    m_rng.Seed(0xC0FFEEu);

    LoadScene(SceneId::BAR_EXTERIOR, Vec2(392.0f, 216.0f));
    m_mode = GameMode::DIALOGUE;
    StartDialogue(m_story.BuildIntro(), DialogueContext::INTRO);
    m_audio.PlaySfx(SfxId::UI);
    LogInfo("New game started");
}

void GameApp::LoadScene(SceneId scene, Vec2 spawn)
{
    const SceneDefinition def = BuildScene(scene);
    if (!m_world.Load(def, &m_device)) {
        LogError("Failed to load scene %d", static_cast<int>(scene));
        return;
    }

    m_hasScene = true;
    m_currentScene = scene;
    if (spawn.x < 0.0f || spawn.y < 0.0f) {
        spawn = def.playerSpawn;
    }
    m_checkpointSpawn = spawn;
    m_player.position = spawn;
    m_player.aim = Vec2(0.0f, 1.0f);
    m_player.aimAngle = 1.5708f;
    m_player.facingDir = 0;
    m_player.moving = false;
    m_player.reloading = false;
    m_player.usingMedkit = false;
    m_player.reloadTimer = 0.0f;
    m_player.medkitTimer = 0.0f;
    m_player.fireCooldown = 0.0f;
    m_player.muzzleTimer = 0.0f;
    m_player.invulnerableTimer = 0.0f;
    m_player.hitFlash = 0.0f;

    m_enemies.clear();
    m_bullets.clear();
    m_particles.clear();
    m_pickups.clear();
    m_prompt.clear();
    m_hasPrompt = false;
    m_alarm = false;

    m_camera.following = def.cameraFollow;
    m_camera.viewWidth = INTERNAL_WIDTH;
    m_camera.viewHeight = INTERNAL_HEIGHT;
    if (def.cameraFollow) {
        m_camera.position = m_player.position - Vec2(240.0f, 150.0f);
    } else {
        m_camera.position = Vec2();
    }
    m_camera.ClampToMap(def.PixelWidth(), def.PixelHeight());

    ApplySceneState();

    if (scene == SceneId::IRON_HARBOR) {
        if (m_quest.main == MainStage::FIND_CARGO) {
            for (const EnemySpawnDef& spawnDef : def.enemies) {
                SpawnEnemy(spawnDef.type, Vec2(spawnDef.x, spawnDef.y), false);
            }
        } else if (m_quest.main == MainStage::DEFEAT_AGENTS) {
            SpawnAmbush();
            m_alarm = true;
        }
    }

    if (def.raining) {
        InitRain();
    } else {
        m_rain.clear();
    }

    if (scene == SceneId::BAR_INTERIOR) {
        m_audio.SetScene(0, false);
    } else if (scene == SceneId::BAR_EXTERIOR) {
        m_audio.SetScene(1, true);
    } else {
        m_audio.SetScene(2, true);
    }
    m_audio.SetCombat(false);

    m_locationName = def.displayName;
    m_locationTimer = 2.2f;
    LogInfo("Loaded scene: %s", def.displayName.c_str());
}

void GameApp::ApplySceneState()
{
    if (m_currentScene == SceneId::IRON_HARBOR) {
        if (m_quest.cargoTaken) {
            m_world.HideProp("PROP_CARGO");
            if (InteractInstance* interact = m_world.FindInteract("cargo")) {
                interact->active = false;
            }
        }
        const bool partAvailable = m_quest.side == SideStage::ACCEPTED &&
                                   !m_inventory.hasPart;
        if (!partAvailable) {
            m_world.HideProp("PROP_PART");
            if (InteractInstance* interact = m_world.FindInteract("part")) {
                interact->active = false;
            }
        }
    }
    if (m_currentScene == SceneId::BAR_INTERIOR && m_quest.jukeboxRepaired) {
        m_world.ReplacePropSprite("PROP_JUKEBOX_BROKEN", "PROP_JUKEBOX",
                                  &m_device);
    }
}

void GameApp::UpdatePlaying(float dt)
{
    Input& input = Input::Get();
    if (input.Pressed(VK_ESCAPE)) {
        m_mode = GameMode::PAUSED;
        return;
    }
    if (input.Pressed(VK_TAB)) {
        m_mode = GameMode::JOURNAL;
        return;
    }

    const Vec2 mouseInternal = m_device.ScreenToInternal(input.MousePosition());
    const Vec2 mouseWorld = mouseInternal + m_camera.position;
    Vec2 aim = mouseWorld - m_player.position;
    if (Length(aim) < 0.001f) {
        aim = Vec2(0.0f, 1.0f);
    }
    m_player.aim = Normalize(aim);
    m_player.aimAngle = std::atan2(m_player.aim.y, m_player.aim.x);
    m_player.facingDir = DirectionFromAngle(m_player.aimAngle);

    Vec2 move;
    if (input.Down('W') || input.Down(VK_UP)) {
        move.y -= 1.0f;
    }
    if (input.Down('S') || input.Down(VK_DOWN)) {
        move.y += 1.0f;
    }
    if (input.Down('A') || input.Down(VK_LEFT)) {
        move.x -= 1.0f;
    }
    if (input.Down('D') || input.Down(VK_RIGHT)) {
        move.x += 1.0f;
    }
    if (Length(move) > 0.0f) {
        move = Normalize(move);
        float speed = PLAYER_SPEED;
        if (m_player.usingMedkit) {
            speed *= 0.5f;
        }
        const Vec2 before = m_player.position;
        m_world.MoveCircle(m_player.position, move * speed * dt, PLAYER_RADIUS);
        m_player.moving = Distance(before, m_player.position) > 0.01f;
        if (m_player.moving) {
            m_player.animTime += dt;
        }
    } else {
        m_player.moving = false;
    }

    m_player.fireCooldown = std::max(0.0f, m_player.fireCooldown - dt);
    m_player.muzzleTimer = std::max(0.0f, m_player.muzzleTimer - dt);
    m_player.invulnerableTimer =
        std::max(0.0f, m_player.invulnerableTimer - dt);
    m_player.hitFlash = std::max(0.0f, m_player.hitFlash - dt);

    if (m_player.reloading) {
        m_player.reloadTimer -= dt;
        if (m_player.reloadTimer <= 0.0f) {
            m_inventory.Reload();
            m_player.reloading = false;
        }
    }
    if (m_player.usingMedkit) {
        m_player.medkitTimer -= dt;
        if (m_player.medkitTimer <= 0.0f) {
            m_inventory.UseMedkit(m_player.hp, PLAYER_MAX_HP, MEDKIT_HEAL);
            m_player.usingMedkit = false;
        }
    }

    if (input.Pressed('R')) {
        StartReload();
    }
    if (input.Pressed('F')) {
        StartMedkit();
    }

    UpdatePrompt();
    if (input.Pressed('E') && m_hasPrompt) {
        float distance = 0.0f;
        InteractInstance* interact = NearestInteract(distance);
        if (interact != nullptr) {
            HandleInteraction(interact->id);
            if (m_mode != GameMode::PLAYING) {
                return;
            }
        }
    }

    if (input.MouseDown(0)) {
        FirePlayerWeapon();
    }

    UpdateEnemies(dt);
    UpdateBullets(dt);
    UpdateParticles(dt);
    UpdatePickups(dt);
    UpdateRain(dt);
    UpdateCamera(dt);
    UpdatePrompt();
    CheckCombatProgress();

    bool alerted = m_alarm;
    for (const Enemy& enemy : m_enemies) {
        if (!enemy.dead && enemy.alerted) {
            alerted = true;
            break;
        }
    }
    m_audio.SetCombat(alerted);

    if (m_player.hp <= 0 && m_mode == GameMode::PLAYING) {
        m_player.hp = 0;
        m_mode = GameMode::DEAD;
    }
}

void GameApp::UpdateDialogue(float dt)
{
    m_dialogue.Update(dt);
    DialogueEvent event = DialogueEvent::NONE;
    while ((event = m_dialogue.ConsumeEvent()) != DialogueEvent::NONE) {
        HandleDialogueEvent(event);
    }

    Input& input = Input::Get();
    if (m_dialogue.IsWaitingForChoice()) {
        if (input.Pressed('W') || input.Pressed(VK_UP)) {
            m_dialogue.MoveSelection(-1);
        }
        if (input.Pressed('S') || input.Pressed(VK_DOWN)) {
            m_dialogue.MoveSelection(1);
        }
        if (input.Pressed('E') || input.Pressed(VK_RETURN)) {
            m_dialogue.Confirm();
        }
    } else if (input.Pressed(VK_SPACE) || input.Pressed(VK_RETURN) ||
               input.MousePressed(0) || input.Pressed('E')) {
        m_dialogue.Advance();
    }

    if (m_dialogue.IsFinished()) {
        HandleDialogueFinished();
        return;
    }
    if (m_hasScene) {
        UpdateRain(dt);
    }
}

void GameApp::UpdateShop(float dt)
{
    Input& input = Input::Get();
    if (input.Pressed(VK_ESCAPE) || input.Pressed('Q')) {
        CloseShop();
        return;
    }

    if (input.Pressed('W') || input.Pressed(VK_UP)) {
        m_shop.selected = (m_shop.selected + 3) % 4;
    }
    if (input.Pressed('S') || input.Pressed(VK_DOWN)) {
        m_shop.selected = (m_shop.selected + 1) % 4;
    }

    m_shop.messageTimer = std::max(0.0f, m_shop.messageTimer - dt);
    if (m_shop.messageTimer <= 0.0f) {
        m_shop.message.clear();
    }

    if (input.Pressed('E') || input.Pressed(VK_RETURN)) {
        if (m_shop.browseOnly) {
            m_shop.message = "今晚这单是大姐头请的，先看看就好。";
            m_shop.messageTimer = 2.2f;
            m_audio.PlaySfx(SfxId::DENY);
            return;
        }
        switch (m_shop.selected) {
        case 0:
            if (m_inventory.ammoReserve >= WEAPON_RESERVE_MAX) {
                m_shop.message = "备弹已满。";
                m_audio.PlaySfx(SfxId::DENY);
            } else if (!m_inventory.CanAfford(18)) {
                m_shop.message = "余额不足。";
                m_audio.PlaySfx(SfxId::DENY);
            } else {
                m_inventory.BuyAmmo(18, 12);
                ++m_shop.purchaseCount;
                m_shop.message = "已购买 9mm 弹药 ×12。";
                m_audio.PlaySfx(SfxId::BUY);
            }
            break;
        case 1:
            if (m_inventory.medkits >= MEDKIT_MAX) {
                m_shop.message = "医疗包已满。";
                m_audio.PlaySfx(SfxId::DENY);
            } else if (!m_inventory.CanAfford(35)) {
                m_shop.message = "余额不足。";
                m_audio.PlaySfx(SfxId::DENY);
            } else {
                m_inventory.BuyMedkit(35);
                ++m_shop.purchaseCount;
                m_shop.message = "已购买 医疗包。";
                m_audio.PlaySfx(SfxId::BUY);
            }
            break;
        case 2:
            if (m_player.hp >= PLAYER_MAX_HP) {
                m_shop.message = "你现在不需要。";
                m_audio.PlaySfx(SfxId::DENY);
            } else if (!m_inventory.CanAfford(12)) {
                m_shop.message = "余额不足。";
                m_audio.PlaySfx(SfxId::DENY);
            } else {
                m_inventory.money -= 12;
                m_player.hp = std::min(PLAYER_MAX_HP, m_player.hp + 20);
                ++m_shop.purchaseCount;
                m_shop.message = "喝完了。精神了一些。";
                m_audio.PlaySfx(SfxId::BUY);
            }
            break;
        case 3:
        default:
            m_shop.message = "这东西不是你现在买得起的。";
            m_audio.PlaySfx(SfxId::DENY);
            break;
        }
        m_shop.messageTimer = 2.2f;
    }
}

void GameApp::CloseShop()
{
    m_mode = GameMode::PLAYING;
    if (m_dialogueContext == DialogueContext::MERCHANT_FIRST &&
        !m_inventory.hasGear) {
        m_inventory.GiveStarterKit();
        m_quest.starterKitGiven = true;
        m_quest.main = MainStage::GO_WAREHOUSE;
        AddToast("获得：手枪 / 9mm 弹药×24 / 医疗包×1", AMBER);
        AddToast("目标更新：前往铁港仓库", CYAN);
        m_audio.PlaySfx(SfxId::BUY);
    }
    m_dialogueContext = DialogueContext::NONE;
    m_shop.message.clear();
}

void GameApp::UpdateTransition(float dt)
{
    m_transitionTimer += dt;
    const float half = 0.27f;
    const float total = 0.54f;
    if (!m_transitionLoaded && m_transitionTimer >= half) {
        LoadScene(m_transitionScene, m_transitionSpawn);
        m_transitionLoaded = true;
    }
    if (m_transitionTimer >= total) {
        m_fadeAlpha = 0.0f;
        m_transitionActive = false;
        m_mode = m_modeAfterTransition;
    } else if (m_transitionTimer < half) {
        m_fadeAlpha = m_transitionTimer / half;
    } else {
        m_fadeAlpha = 1.0f - (m_transitionTimer - half) / (total - half);
    }
}

void GameApp::StartTransition(SceneId scene, Vec2 spawn)
{
    m_transitionActive = true;
    m_transitionLoaded = false;
    m_transitionTimer = 0.0f;
    m_transitionScene = scene;
    m_transitionSpawn = spawn;
    m_modeAfterTransition = GameMode::PLAYING;
    m_mode = GameMode::TRANSITION;
    m_audio.PlaySfx(SfxId::DOOR);
    m_fadeAlpha = 0.0f;
    m_prompt.clear();
    m_hasPrompt = false;
    m_player.moving = false;
}

void GameApp::StartDialogue(const Dialogue& dialogue, DialogueContext context)
{
    m_dialogue.Start(dialogue);
    m_dialogueContext = context;
    m_dialogueCinematic = dialogue.cinematic;
    m_mode = GameMode::DIALOGUE;
    m_prompt.clear();
    m_hasPrompt = false;
    m_player.moving = false;
}

void GameApp::HandleDialogueEvent(DialogueEvent event)
{
    switch (event) {
    case DialogueEvent::SIDE_ACCEPT:
        m_quest.side = SideStage::ACCEPTED;
        AddToast("支线已接受：坏掉的点唱机", CYAN);
        break;
    case DialogueEvent::SIDE_DECLINE:
        m_quest.side = SideStage::DECLINED;
        AddToast("支线已关闭", DIM);
        break;
    case DialogueEvent::EPILOGUE_ACCEPT:
        m_endingChoice = EndingChoice::ACCEPT;
        break;
    case DialogueEvent::EPILOGUE_WAIT:
        m_endingChoice = EndingChoice::WAIT;
        break;
    case DialogueEvent::REPAIR_JUKEBOX:
        m_quest.jukeboxRepaired = true;
        break;
    default:
        break;
    }
}

void GameApp::HandleDialogueFinished()
{
    const DialogueContext context = m_dialogueContext;
    m_dialogueContext = DialogueContext::NONE;
    switch (context) {
    case DialogueContext::INTRO:
        m_quest.main = MainStage::ENTER_BAR;
        AddToast("旧城区 · 余烬酒吧外", AMBER);
        m_mode = GameMode::PLAYING;
        break;
    case DialogueContext::BARTENDER_FIRST:
        m_quest.main = MainStage::TALK_BIGSISTER;
        AddToast("目标更新：去后排卡座找大美", CYAN);
        m_mode = GameMode::PLAYING;
        break;
    case DialogueContext::BIGSISTER_FIRST:
        m_quest.main = MainStage::GET_GEAR;
        AddToast("目标更新：找东子领取装备", CYAN);
        m_mode = GameMode::PLAYING;
        break;
    case DialogueContext::BARTENDER_SIDE_COMPLETE:
        m_quest.side = SideStage::COMPLETED;
        m_quest.jukeboxRepaired = true;
        m_inventory.AddMoney(60);
        m_inventory.AddMedkit(1);
        m_audio.PlaySfx(SfxId::BUY);
        if (m_currentScene == SceneId::BAR_INTERIOR) {
            m_world.ReplacePropSprite("PROP_JUKEBOX_BROKEN", "PROP_JUKEBOX",
                                      &m_device);
        }
        AddToast("支线完成：点唱机修好了", AMBER);
        m_mode = GameMode::PLAYING;
        break;
    case DialogueContext::BIGSISTER_RETURN:
        m_inventory.AddMoney(180);
        m_quest.main = MainStage::COMPLETE;
        if (m_endingChoice == EndingChoice::NONE) {
            m_endingChoice = EndingChoice::WAIT;
        }
        m_mode = GameMode::EPILOGUE;
        break;
    case DialogueContext::MERCHANT_FIRST:
    case DialogueContext::MERCHANT_SHOP:
        m_shop.browseOnly = !m_inventory.hasGear;
        m_shop.selected = 0;
        m_shop.message.clear();
        m_shop.messageTimer = 0.0f;
        // 保留上下文，供关闭商店时判断是否发放初始装备。
        m_dialogueContext = context;
        m_mode = GameMode::SHOP;
        break;
    case DialogueContext::BARTENDER_SIDE_OFFER:
    case DialogueContext::BARTENDER_IDLE:
    case DialogueContext::BIGSISTER_IDLE:
    case DialogueContext::CAR_LOCKED:
    case DialogueContext::BAR_EXIT_LOCKED:
    case DialogueContext::JUKEBOX:
    case DialogueContext::BACKDOOR:
    case DialogueContext::STREET_SIGN:
    case DialogueContext::NONE:
    default:
        m_mode = GameMode::PLAYING;
        break;
    }
}

void GameApp::HandleInteraction(const std::string& id)
{
    if (id == "bar_entrance") {
        if (m_quest.main == MainStage::ENTER_BAR) {
            m_quest.main = MainStage::TALK_BARTENDER;
        }
        StartTransition(SceneId::BAR_INTERIOR, Vec2(270.0f, 224.0f));
        return;
    }
    if (id == "bar_exit") {
        if (m_quest.main < MainStage::GET_GEAR) {
            StartDialogue(m_story.BuildBarExitLocked(),
                          DialogueContext::BAR_EXIT_LOCKED);
            return;
        }
        StartTransition(SceneId::BAR_EXTERIOR, Vec2(328.0f, 104.0f));
        return;
    }
    if (id == "car") {
        const bool returnForPart = m_quest.main == MainStage::RETURN_BAR &&
                                   m_quest.side == SideStage::ACCEPTED &&
                                   !m_inventory.hasPart;
        const bool canTravel = m_quest.main == MainStage::GO_WAREHOUSE ||
                               m_quest.main == MainStage::FIND_CARGO ||
                               m_quest.main == MainStage::DEFEAT_AGENTS ||
                               returnForPart;
        if (canTravel) {
            if (m_quest.main == MainStage::GO_WAREHOUSE) {
                m_quest.main = MainStage::FIND_CARGO;
            }
            StartTransition(SceneId::IRON_HARBOR, Vec2(280.0f, 240.0f));
        } else if (m_quest.main == MainStage::RETURN_BAR) {
            AddToast("先把货带回酒吧交差。", AMBER);
        } else {
            StartDialogue(m_story.BuildCarLocked(),
                          DialogueContext::CAR_LOCKED);
        }
        return;
    }
    if (id == "warehouse_exit") {
        StartTransition(SceneId::BAR_EXTERIOR, Vec2(392.0f, 216.0f));
        return;
    }
    if (id == "bartender") {
        if (m_quest.main == MainStage::TALK_BARTENDER) {
            StartDialogue(m_story.BuildBartenderFirst(),
                          DialogueContext::BARTENDER_FIRST);
        } else if (m_quest.side == SideStage::HAVE_PART) {
            StartDialogue(m_story.BuildBartenderSideComplete(),
                          DialogueContext::BARTENDER_SIDE_COMPLETE);
        } else if (m_quest.side == SideStage::NOT_STARTED &&
                   m_quest.main >= MainStage::GET_GEAR &&
                   m_quest.main < MainStage::COMPLETE) {
            StartDialogue(m_story.BuildBartenderSideOffer(),
                          DialogueContext::BARTENDER_SIDE_OFFER);
        } else {
            StartDialogue(m_story.BuildBartenderIdle(m_quest),
                          DialogueContext::BARTENDER_IDLE);
        }
        return;
    }
    if (id == "bigsister") {
        if (m_quest.main < MainStage::TALK_BIGSISTER) {
            AddToast("她正和客人说话。先问问酒保。", AMBER);
            return;
        }
        if (m_quest.main == MainStage::TALK_BIGSISTER) {
            StartDialogue(m_story.BuildBigSisterFirst(),
                          DialogueContext::BIGSISTER_FIRST);
        } else if (m_quest.main == MainStage::RETURN_BAR) {
            StartDialogue(m_story.BuildBigSisterReturn(),
                          DialogueContext::BIGSISTER_RETURN);
        } else {
            StartDialogue(m_story.BuildBigSisterIdle(m_quest),
                          DialogueContext::BIGSISTER_IDLE);
        }
        return;
    }
    if (id == "merchant") {
        if (m_quest.main < MainStage::GET_GEAR) {
            AddToast("东子正低头摆弄平板。先去找大美。", AMBER);
            return;
        }
        if (m_quest.main == MainStage::GET_GEAR && !m_inventory.hasGear) {
            StartDialogue(m_story.BuildMerchantFirst(),
                          DialogueContext::MERCHANT_FIRST);
        } else {
            StartDialogue(m_story.BuildMerchantShop(m_shop.purchaseCount),
                          DialogueContext::MERCHANT_SHOP);
        }
        return;
    }
    if (id == "jukebox") {
        StartDialogue(m_story.BuildJukebox(m_quest.jukeboxRepaired),
                      DialogueContext::JUKEBOX);
        return;
    }
    if (id == "backdoor") {
        StartDialogue(m_story.BuildBackdoor(), DialogueContext::BACKDOOR);
        return;
    }
    if (id == "street_sign") {
        StartDialogue(m_story.BuildStreetSign(), DialogueContext::STREET_SIGN);
        return;
    }
    if (id == "cargo") {
        if (m_quest.main != MainStage::FIND_CARGO || m_quest.cargoTaken) {
            AddToast("箱子已经搬起来了。", DIM);
            return;
        }
        m_quest.cargoTaken = true;
        m_inventory.hasCargo = true;
        m_quest.main = MainStage::DEFEAT_AGENTS;
        m_world.HideProp("PROP_CARGO");
        if (InteractInstance* interact = m_world.FindInteract("cargo")) {
            interact->active = false;
        }
        SpawnAmbush();
        m_alarm = true;
        TriggerShake(4.0f, 0.35f);
        m_audio.PlaySfx(SfxId::ALARM);
        AddToast("货物已搬起。警报响了。", MAGENTA);

        Dialogue warning;
        warning.cinematic = true;
        warning.nodes.push_back(
            SimpleNode("", "", "东侧的卷帘门亮起刺眼的红光。"));
        warning.nodes.push_back(
            SimpleNode("特工", "", "目标确认。交出资产。"));
        warning.nodes.push_back(
            SimpleNode("特工", "", "封锁已生效。"));
        for (size_t i = 0; i + 1 < warning.nodes.size(); ++i) {
            warning.nodes[i].next = static_cast<int>(i + 1);
        }
        StartDialogue(warning, DialogueContext::NONE);
        return;
    }
    if (id == "part") {
        if (m_quest.side == SideStage::ACCEPTED) {
            m_quest.side = SideStage::HAVE_PART;
            m_inventory.hasPart = true;
            m_world.HideProp("PROP_PART");
            if (InteractInstance* interact = m_world.FindInteract("part")) {
                interact->active = false;
            }
            AddToast("获得：点唱机零件", CYAN);
            SpawnSparks(m_player.position, CYAN);
        } else if (m_quest.side == SideStage::DECLINED) {
            AddToast("一块旧零件。小帅说自己会来拿。", DIM);
        } else {
            AddToast("一块旧零件。现在用不上。", DIM);
        }
        return;
    }
}

void GameApp::UpdateEnemies(float dt)
{
    for (Enemy& enemy : m_enemies) {
        if (enemy.dead) {
            enemy.deathTimer = std::max(0.0f, enemy.deathTimer - dt);
            continue;
        }
        enemy.shootTimer = std::max(0.0f, enemy.shootTimer - dt);
        enemy.muzzleTimer = std::max(0.0f, enemy.muzzleTimer - dt);
        enemy.hitFlash = std::max(0.0f, enemy.hitFlash - dt);

        const Vec2 toPlayer = m_player.position - enemy.position;
        const float distance = Length(toPlayer);
        const Vec2 direction = Normalize(toPlayer);
        const bool lineOfSight =
            !m_world.IsLineBlocked(enemy.position, m_player.position);
        if (!enemy.alerted && distance < 135.0f && lineOfSight) {
            enemy.alerted = true;
        }
        if (!enemy.alerted) {
            enemy.moving = false;
            continue;
        }

        enemy.facingDir =
            DirectionFromAngle(std::atan2(direction.y, direction.x));
        Vec2 desired;
        if (distance > 150.0f) {
            desired = direction;
        } else if (distance < 80.0f) {
            desired = direction * -1.0f;
        } else {
            Vec2 side(-direction.y, direction.x);
            desired = side * 0.30f;
        }
        if (Length(desired) > 0.0f) {
            desired = Normalize(desired);
            const Vec2 before = enemy.position;
            Vec2 next = enemy.position;
            bool moved = m_world.MoveCircle(next, desired * enemy.speed * dt,
                                            enemy.radius);
            if (!moved) {
                const Vec2 side(-desired.y, desired.x);
                next = enemy.position;
                moved = m_world.MoveCircle(next, side * enemy.speed * dt * 0.8f,
                                           enemy.radius);
            }
            enemy.position = next;
            enemy.moving = Distance(before, enemy.position) > 0.01f;
            if (enemy.moving) {
                enemy.animTime += dt;
            }
        } else {
            enemy.moving = false;
        }

        if (lineOfSight && distance < 240.0f && enemy.shootTimer <= 0.0f &&
            m_player.hp > 0) {
            FireEnemyWeapon(enemy);
            enemy.shootTimer = enemy.type == EnemyType::AGENT ? 0.65f : 1.30f;
        }
    }

    // 简单分离，避免敌人完全重叠。
    for (size_t i = 0; i < m_enemies.size(); ++i) {
        if (m_enemies[i].dead) {
            continue;
        }
        for (size_t j = i + 1; j < m_enemies.size(); ++j) {
            if (m_enemies[j].dead) {
                continue;
            }
            const Vec2 delta = m_enemies[i].position - m_enemies[j].position;
            const float dist = Length(delta);
            if (dist > 0.001f && dist < 12.0f) {
                const Vec2 push = Normalize(delta) * (12.0f - dist) * 0.5f;
                Vec2 nextA = m_enemies[i].position + push;
                Vec2 nextB = m_enemies[j].position - push;
                if (!m_world.IsBlockedCircle(nextA, m_enemies[i].radius)) {
                    m_enemies[i].position = nextA;
                }
                if (!m_world.IsBlockedCircle(nextB, m_enemies[j].radius)) {
                    m_enemies[j].position = nextB;
                }
            }
        }
    }

    m_enemies.erase(
        std::remove_if(m_enemies.begin(), m_enemies.end(),
                       [](const Enemy& enemy) {
                           return enemy.dead && enemy.deathTimer <= 0.0f;
                       }),
        m_enemies.end());
}

void GameApp::UpdateBullets(float dt)
{
    for (Bullet& bullet : m_bullets) {
        if (!bullet.active) {
            continue;
        }
        const float speed = Length(bullet.velocity);
        const int steps = std::max(1, static_cast<int>(std::ceil(speed * dt / 4.0f)));
        const float stepTime = dt / static_cast<float>(steps);
        for (int step = 0; step < steps && bullet.active; ++step) {
            bullet.position += bullet.velocity * stepTime;
            if (m_world.IsPointBlocked(bullet.position)) {
                SpawnSparks(bullet.position, Rgba(255, 180, 90));
                bullet.active = false;
                break;
            }
            if (bullet.hostile) {
                if (Distance(bullet.position, m_player.position) < 8.0f) {
                    DamagePlayer(static_cast<int>(bullet.damage));
                    bullet.active = false;
                    break;
                }
            } else {
                for (size_t i = 0; i < m_enemies.size(); ++i) {
                    Enemy& enemy = m_enemies[i];
                    if (enemy.dead) {
                        continue;
                    }
                    if (Distance(bullet.position, enemy.position) < 9.0f) {
                        DamageEnemy(i, static_cast<int>(bullet.damage));
                        bullet.active = false;
                        break;
                    }
                }
            }
        }
        bullet.life -= dt;
        if (bullet.life <= 0.0f) {
            bullet.active = false;
        }
    }
    m_bullets.erase(
        std::remove_if(m_bullets.begin(), m_bullets.end(),
                       [](const Bullet& bullet) { return !bullet.active; }),
        m_bullets.end());
}

void GameApp::UpdateParticles(float dt)
{
    for (Particle& particle : m_particles) {
        particle.life -= dt;
        particle.position += particle.velocity * dt;
        particle.velocity *= std::max(0.0f, 1.0f - 3.4f * dt);
        if (particle.smoke) {
            particle.velocity.y -= 5.0f * dt;
        }
    }
    m_particles.erase(
        std::remove_if(m_particles.begin(), m_particles.end(),
                       [](const Particle& particle) {
                           return particle.life <= 0.0f;
                       }),
        m_particles.end());
}

void GameApp::UpdatePickups(float dt)
{
    for (Pickup& pickup : m_pickups) {
        if (!pickup.active) {
            continue;
        }
        pickup.bob += dt * 2.0f;
        if (Distance(pickup.position, m_player.position) > 14.0f) {
            continue;
        }
        switch (pickup.type) {
        case PickupType::AMMO: {
            const int added = m_inventory.AddAmmo(pickup.amount);
            if (added > 0) {
                AddToast("+" + std::to_string(added) + " 发 9mm 弹药", BONE);
                m_audio.PlaySfx(SfxId::PICKUP);
                pickup.active = false;
            }
            break;
        }
        case PickupType::MEDKIT: {
            if (m_inventory.AddMedkit(1) > 0) {
                AddToast("获得：医疗包", BONE);
                m_audio.PlaySfx(SfxId::PICKUP);
                pickup.active = false;
            }
            break;
        }
        case PickupType::MONEY:
            m_inventory.AddMoney(pickup.amount);
            AddToast("+" + std::to_string(pickup.amount) + " 信用点", AMBER);
            m_audio.PlaySfx(SfxId::PICKUP);
            pickup.active = false;
            break;
        case PickupType::PART:
            m_quest.side = SideStage::HAVE_PART;
            m_inventory.hasPart = true;
            pickup.active = false;
            AddToast("获得：点唱机零件", CYAN);
            m_audio.PlaySfx(SfxId::PICKUP);
            break;
        }
    }
    m_pickups.erase(
        std::remove_if(m_pickups.begin(), m_pickups.end(),
                       [](const Pickup& pickup) { return !pickup.active; }),
        m_pickups.end());
}

void GameApp::UpdateRain(float dt)
{
    if (m_rain.empty()) {
        return;
    }
    for (RainDrop& drop : m_rain) {
        drop.y += drop.speed * dt;
        drop.x += 26.0f * dt;
        if (drop.y > static_cast<float>(INTERNAL_HEIGHT) + 4.0f) {
            drop.y = -drop.length;
            drop.x = m_rng.Float(0.0f, static_cast<float>(INTERNAL_WIDTH));
        }
        if (drop.x > static_cast<float>(INTERNAL_WIDTH)) {
            drop.x -= static_cast<float>(INTERNAL_WIDTH);
        }
    }
}

void GameApp::UpdateToasts(float dt)
{
    for (Toast& toast : m_toasts) {
        toast.remaining -= dt;
    }
    m_toasts.erase(
        std::remove_if(m_toasts.begin(), m_toasts.end(),
                       [](const Toast& toast) {
                           return toast.remaining <= 0.0f;
                       }),
        m_toasts.end());
}

void GameApp::UpdateLocation(float dt)
{
    if (m_locationTimer > 0.0f) {
        m_locationTimer -= dt;
    }
}

void GameApp::UpdateCamera(float dt)
{
    if (!m_hasScene) {
        return;
    }
    if (m_camera.following) {
        const Vec2 target = m_player.position - Vec2(240.0f, 150.0f);
        const float t = 1.0f - std::exp(-8.0f * dt);
        m_camera.position.x += (target.x - m_camera.position.x) * t;
        m_camera.position.y += (target.y - m_camera.position.y) * t;
    } else {
        m_camera.position = Vec2();
    }
    m_camera.ClampToMap(m_world.PixelWidth(), m_world.PixelHeight());
}

void GameApp::UpdatePrompt()
{
    m_hasPrompt = false;
    m_prompt.clear();
    if (m_mode != GameMode::PLAYING) {
        return;
    }
    float distance = 0.0f;
    InteractInstance* interact = NearestInteract(distance);
    if (interact != nullptr) {
        m_hasPrompt = true;
        m_prompt = interact->prompt;
        m_promptPosition = interact->position;
    }
}

InteractInstance* GameApp::NearestInteract(float& outDistance)
{
    InteractInstance* best = nullptr;
    float bestDistance = 1.0e9f;
    for (InteractInstance& interact : m_world.Interacts()) {
        if (!interact.active) {
            continue;
        }
        const float distance = Distance(m_player.position, interact.position);
        if (distance <= interact.radius && distance < bestDistance) {
            best = &interact;
            bestDistance = distance;
        }
    }
    outDistance = bestDistance;
    return best;
}

void GameApp::SpawnEnemy(EnemyType type, Vec2 position, bool alerted)
{
    Enemy enemy;
    enemy.type = type;
    enemy.position = position;
    if (type == EnemyType::AGENT) {
        enemy.hp = 70.0f;
        enemy.maxHp = 70.0f;
        enemy.speed = 66.0f;
        enemy.radius = 6.0f;
    } else {
        enemy.hp = 45.0f;
        enemy.maxHp = 45.0f;
        enemy.speed = 52.0f;
        enemy.radius = 6.0f;
    }
    enemy.alerted = alerted;
    enemy.facingDir = 3;
    enemy.shootTimer = m_rng.Float(0.2f, 0.9f);
    m_enemies.push_back(enemy);
}

void GameApp::SpawnAmbush()
{
    SpawnEnemy(EnemyType::AGENT, Vec2(648.0f, 240.0f), true);
    SpawnEnemy(EnemyType::AGENT, Vec2(616.0f, 272.0f), true);
    SpawnEnemy(EnemyType::AGENT, Vec2(584.0f, 240.0f), true);
}

void GameApp::InitRain()
{
    m_rain.clear();
    m_rain.reserve(150);
    for (int i = 0; i < 150; ++i) {
        RainDrop drop;
        drop.x = m_rng.Float(0.0f, static_cast<float>(INTERNAL_WIDTH));
        drop.y = m_rng.Float(0.0f, static_cast<float>(INTERNAL_HEIGHT));
        drop.speed = m_rng.Float(170.0f, 310.0f);
        drop.length = m_rng.Float(4.0f, 11.0f);
        drop.alpha = m_rng.Float(0.08f, 0.30f);
        m_rain.push_back(drop);
    }
}

void GameApp::RespawnAfterDeath()
{
    m_player.hp = 60;
    m_inventory.ammoMag = 12;
    if (m_inventory.ammoReserve < 12) {
        m_inventory.ammoReserve = 12;
    }
    m_player.reloading = false;
    m_player.usingMedkit = false;
    m_player.invulnerableTimer = 1.0f;
    m_bullets.clear();
    m_particles.clear();
    LoadScene(m_currentScene, m_checkpointSpawn);
    m_mode = GameMode::PLAYING;
    AddToast("重新连接……", CYAN);
}

void GameApp::FirePlayerWeapon()
{
    if (m_player.fireCooldown > 0.0f || m_player.reloading) {
        return;
    }
    if (!m_inventory.hasGear) {
        if (m_noGearToastCooldown <= 0) {
            AddToast("还没有武器。先去东子那里领装备。", AMBER);
            m_noGearToastCooldown = 90;
        }
        m_player.fireCooldown = 0.4f;
        return;
    }
    if (m_inventory.ammoMag <= 0) {
        if (m_inventory.ammoReserve > 0) {
            StartReload();
        } else if (m_noGearToastCooldown <= 0) {
            AddToast("没有弹药了。", RED);
            m_noGearToastCooldown = 90;
        }
        m_player.fireCooldown = 0.4f;
        return;
    }

    m_inventory.ConsumeRound();
    Bullet bullet;
    bullet.position = m_player.position + m_player.aim * 10.0f;
    bullet.velocity = m_player.aim * PLAYER_BULLET_SPEED;
    bullet.damage = static_cast<float>(PLAYER_BULLET_DAMAGE);
    bullet.life = 0.9f;
    bullet.hostile = false;
    m_bullets.push_back(bullet);

    m_player.fireCooldown = PLAYER_FIRE_INTERVAL;
    m_player.muzzleTimer = 0.06f;
    m_audio.PlaySfx(SfxId::SHOOT);
    TriggerShake(1.2f, 0.08f);
    WakeEnemies(260.0f);

    const Vec2 muzzle = m_player.position + m_player.aim * 12.0f;
    SpawnSparks(muzzle, Rgba(255, 210, 120));
    Particle shell;
    shell.position = m_player.position + Vec2(6.0f, -10.0f);
    shell.velocity = Vec2(m_rng.Float(-20.0f, 20.0f), -30.0f);
    shell.life = 0.35f;
    shell.maxLife = 0.35f;
    shell.size = 2.0f;
    shell.color = Rgba(210, 170, 80);
    shell.additive = false;
    m_particles.push_back(shell);
}

void GameApp::FireEnemyWeapon(Enemy& enemy)
{
    const Vec2 direction = Normalize(m_player.position - enemy.position);
    const float spread = enemy.type == EnemyType::AGENT ? 0.06f : 0.12f;
    const float angle = std::atan2(direction.y, direction.x) +
                        m_rng.Float(-spread, spread);
    const Vec2 velocity(std::cos(angle) * 240.0f, std::sin(angle) * 240.0f);
    Bullet bullet;
    bullet.position = enemy.position + direction * 10.0f;
    bullet.velocity = velocity;
    bullet.damage = enemy.type == EnemyType::AGENT ? 10.0f : 8.0f;
    bullet.life = 1.3f;
    bullet.hostile = true;
    m_bullets.push_back(bullet);
    enemy.muzzleTimer = 0.05f;
    m_audio.PlaySfx(SfxId::SHOOT);
    SpawnSparks(bullet.position, MAGENTA);
}

void GameApp::StartReload()
{
    if (m_player.reloading || m_player.usingMedkit) {
        return;
    }
    if (m_inventory.ammoMag >= WEAPON_MAGAZINE_SIZE) {
        return;
    }
    if (m_inventory.ammoReserve <= 0) {
        AddToast("没有备用弹药。", RED);
        return;
    }
    m_player.reloading = true;
    m_player.reloadTimer = RELOAD_TIME;
    m_audio.PlaySfx(SfxId::RELOAD);
}

void GameApp::StartMedkit()
{
    if (m_player.usingMedkit) {
        return;
    }
    if (m_inventory.medkits <= 0) {
        AddToast("没有医疗包。", RED);
        return;
    }
    if (m_player.hp >= PLAYER_MAX_HP) {
        AddToast("生命值已满。", DIM);
        return;
    }
    m_player.usingMedkit = true;
    m_player.medkitTimer = MEDKIT_TIME;
    m_audio.PlaySfx(SfxId::MEDKIT);
}

void GameApp::WakeEnemies(float radius)
{
    for (Enemy& enemy : m_enemies) {
        if (!enemy.dead && Distance(enemy.position, m_player.position) <= radius) {
            enemy.alerted = true;
        }
    }
}

void GameApp::DamagePlayer(int amount)
{
    if (m_player.invulnerableTimer > 0.0f || m_mode == GameMode::DEAD) {
        return;
    }
    m_player.hp = std::max(0, m_player.hp - amount);
    m_player.invulnerableTimer = PLAYER_INVULNERABLE_TIME;
    m_player.hitFlash = 0.18f;
    m_damageFlash = 0.65f;
    TriggerShake(3.0f, 0.18f);
    SpawnBlood(m_player.position);
    m_audio.PlaySfx(SfxId::HIT);
    if (m_player.hp <= 0) {
        m_player.hp = 0;
        m_audio.PlaySfx(SfxId::DEATH);
        m_mode = GameMode::DEAD;
    }
}

void GameApp::DamageEnemy(size_t index, int amount)
{
    if (index >= m_enemies.size()) {
        return;
    }
    Enemy& enemy = m_enemies[index];
    if (enemy.dead) {
        return;
    }
    enemy.hp -= static_cast<float>(amount);
    enemy.hitFlash = 0.12f;
    SpawnBlood(enemy.position);
    m_audio.PlaySfx(SfxId::HIT);
    if (enemy.hp <= 0.0f) {
        enemy.hp = 0.0f;
        enemy.dead = true;
        enemy.deathTimer = 0.30f;
        SpawnBlood(enemy.position);
        Particle smoke;
        smoke.position = enemy.position + Vec2(0.0f, -10.0f);
        smoke.velocity = Vec2(0.0f, -8.0f);
        smoke.life = 0.5f;
        smoke.maxLife = 0.5f;
        smoke.size = 8.0f;
        smoke.color = Rgba(90, 90, 90, 160);
        smoke.smoke = true;
        m_particles.push_back(smoke);

        if (enemy.type == EnemyType::AGENT) {
            if (m_rng.Chance(70)) {
                SpawnPickup(PickupType::MONEY, enemy.position,
                            m_rng.Range(12, 24));
            }
            if (m_rng.Chance(30)) {
                SpawnPickup(PickupType::AMMO, enemy.position,
                            m_rng.Range(8, 12));
            }
        } else {
            if (m_rng.Chance(55)) {
                SpawnPickup(PickupType::AMMO, enemy.position,
                            m_rng.Range(6, 10));
            }
            if (m_rng.Chance(22)) {
                SpawnPickup(PickupType::MEDKIT, enemy.position, 1);
            }
            if (m_rng.Chance(18)) {
                SpawnPickup(PickupType::MONEY, enemy.position,
                            m_rng.Range(5, 12));
            }
        }
    }
}

void GameApp::CheckCombatProgress()
{
    if (m_quest.main != MainStage::DEFEAT_AGENTS) {
        return;
    }
    bool anyAlive = false;
    for (const Enemy& enemy : m_enemies) {
        if (enemy.type == EnemyType::AGENT && !enemy.dead) {
            anyAlive = true;
            break;
        }
    }
    if (!anyAlive) {
        m_quest.main = MainStage::RETURN_BAR;
        m_quest.agentsCleared = true;
        m_alarm = false;
        AddToast("公司特工已清理", CYAN);
        AddToast("目标更新：带着货物返回酒吧", AMBER);
    }
}

void GameApp::AddToast(const std::string& text, Color color)
{
    Toast toast;
    toast.text = text;
    toast.remaining = 2.8f;
    toast.color = color;
    m_toasts.insert(m_toasts.begin(), toast);
    while (m_toasts.size() > 4) {
        m_toasts.pop_back();
    }
}

void GameApp::TriggerShake(float intensity, float duration)
{
    m_shakeIntensity = std::max(m_shakeIntensity, intensity);
    m_shakeDuration = std::max(m_shakeDuration, duration);
    m_shakeTimer = std::max(m_shakeTimer, duration);
}

void GameApp::SpawnBlood(Vec2 position)
{
    for (int i = 0; i < 7; ++i) {
        Particle particle;
        particle.position = position + Vec2(0.0f, -10.0f);
        particle.velocity = Vec2(m_rng.Float(-40.0f, 40.0f),
                                 m_rng.Float(-50.0f, 10.0f));
        particle.life = m_rng.Float(0.2f, 0.45f);
        particle.maxLife = particle.life;
        particle.size = m_rng.Float(2.0f, 4.0f);
        particle.color = Rgba(150, 26, 40, 220);
        particle.additive = false;
        m_particles.push_back(particle);
    }
}

void GameApp::SpawnSparks(Vec2 position, Color color)
{
    for (int i = 0; i < 6; ++i) {
        Particle particle;
        particle.position = position;
        particle.velocity = Vec2(m_rng.Float(-70.0f, 70.0f),
                                 m_rng.Float(-70.0f, 20.0f));
        particle.life = m_rng.Float(0.10f, 0.25f);
        particle.maxLife = particle.life;
        particle.size = m_rng.Float(2.0f, 4.0f);
        particle.color = color;
        particle.additive = true;
        m_particles.push_back(particle);
    }
}

void GameApp::SpawnPickup(PickupType type, Vec2 position, int amount)
{
    Pickup pickup;
    pickup.type = type;
    pickup.position = position;
    pickup.amount = amount;
    pickup.bob = m_rng.Float(0.0f, 6.28f);
    m_pickups.push_back(pickup);
}

void GameApp::Render()
{
    m_device.BeginFrame();
    SpriteBatch& batch = m_device.Batch();
    batch.Begin(INTERNAL_WIDTH, INTERNAL_HEIGHT);

    if (m_mode == GameMode::TITLE) {
        m_ui.DrawTitle(m_time, m_muted);
    } else if (m_mode == GameMode::EPILOGUE) {
        m_ui.DrawEpilogue(m_endingChoice, m_time);
    } else if (m_hasScene) {
        m_renderer.DrawWorld(m_world, m_player, m_enemies, m_bullets,
                             m_particles, m_pickups, m_camera, m_shakeOffset,
                             m_time, m_alarm);
        if (!m_rain.empty()) {
            m_renderer.DrawRain(m_rain);
        }
        m_renderer.DrawPostOverlay(m_damageFlash);

        switch (m_mode) {
        case GameMode::PLAYING: {
            float screenX = m_promptPosition.x - m_camera.position.x;
            float screenY = m_promptPosition.y - m_camera.position.y;
            m_ui.DrawHUD(m_player, m_inventory, m_quest,
                         m_hasPrompt ? m_prompt : std::string(), screenX,
                         screenY, m_device.ScreenToInternal(
                                       Input::Get().MousePosition()));
            break;
        }
        case GameMode::DIALOGUE:
            m_ui.DrawDialogue(m_dialogue, m_dialogueCinematic, m_time);
            break;
        case GameMode::SHOP:
            m_ui.DrawShop(m_inventory, m_shop, m_time);
            break;
        case GameMode::JOURNAL:
            m_ui.DrawJournal(m_player, m_inventory, m_quest);
            break;
        case GameMode::DEAD:
            m_ui.DrawDeath(m_time);
            break;
        case GameMode::PAUSED:
            m_ui.DrawPause(m_inventory, m_quest);
            break;
        case GameMode::TRANSITION:
        default:
            break;
        }

        if (m_mode == GameMode::PLAYING || m_mode == GameMode::DIALOGUE ||
            m_mode == GameMode::TRANSITION) {
            m_ui.DrawToasts(m_toasts);
        }
        if (m_mode == GameMode::PLAYING || m_mode == GameMode::DIALOGUE) {
            const float locationAlpha =
                Clamp(m_locationTimer / 0.6f, 0.0f, 1.0f);
            if (m_locationTimer > 0.0f) {
                m_ui.DrawLocationCard(m_locationName, locationAlpha);
            }
        }
        if (m_mode == GameMode::TRANSITION) {
            m_ui.DrawFade(m_fadeAlpha);
        }
    } else {
        m_renderer.DrawRect(RectF(0.0f, 0.0f, 480.0f, 270.0f),
                            Rgba(6, 8, 12));
    }

    batch.End();
    m_device.EndFrame();
}

void GameApp::DebugLoadScene(SceneId scene)
{
    m_inventory = Inventory();
    m_inventory.GiveStarterKit();
    m_quest = QuestState();
    m_quest.side = SideStage::NOT_STARTED;
    m_endingChoice = EndingChoice::NONE;
    m_player = Player();
    m_player.hp = PLAYER_MAX_HP;
    m_enemies.clear();
    m_bullets.clear();
    m_particles.clear();
    m_pickups.clear();
    m_toasts.clear();
    m_alarm = false;
    m_shop = ShopState();
    m_dialogueContext = DialogueContext::NONE;
    m_damageFlash = 0.0f;
    m_shakeTimer = 0.0f;

    if (scene == SceneId::BAR_EXTERIOR) {
        m_quest.main = MainStage::GO_WAREHOUSE;
    } else if (scene == SceneId::BAR_INTERIOR) {
        m_quest.main = MainStage::TALK_BIGSISTER;
    } else {
        m_quest.main = MainStage::FIND_CARGO;
        m_quest.side = SideStage::ACCEPTED;
    }
    LoadScene(scene, Vec2(-1.0f, -1.0f));
    m_mode = GameMode::PLAYING;
}

void GameApp::DebugSetMode(GameMode mode)
{
    m_mode = mode;
}

void GameApp::DebugSetQuestStage(int main, int side)
{
    const int mainValue = ClampInt(main, 0, 8);
    const int sideValue = ClampInt(side, 0, 4);
    m_quest.main = static_cast<MainStage>(mainValue);
    m_quest.side = static_cast<SideStage>(sideValue);
}

void GameApp::DebugSetPlayerPosition(float x, float y)
{
    m_player.position = Vec2(x, y);
    if (m_camera.following) {
        m_camera.position = m_player.position - Vec2(240.0f, 150.0f);
        m_camera.ClampToMap(m_world.PixelWidth(), m_world.PixelHeight());
    }
}

void GameApp::DebugShowDialogue()
{
    DebugLoadScene(SceneId::BAR_INTERIOR);
    m_quest.main = MainStage::RETURN_BAR;
    m_inventory.hasCargo = true;
    m_inventory.money = 220;
    StartDialogue(m_story.BuildBigSisterReturn(),
                  DialogueContext::BIGSISTER_RETURN);
    DebugAdvanceDialogue(60);
}

void GameApp::DebugShowShop()
{
    DebugLoadScene(SceneId::BAR_INTERIOR);
    m_inventory.money = 400;
    m_shop = ShopState();
    m_shop.selected = 0;
    m_shop.browseOnly = false;
    m_dialogueContext = DialogueContext::MERCHANT_SHOP;
    m_mode = GameMode::SHOP;
}

void GameApp::DebugShowJournal()
{
    DebugLoadScene(SceneId::BAR_INTERIOR);
    m_quest.side = SideStage::ACCEPTED;
    m_inventory.hasPart = false;
    m_mode = GameMode::JOURNAL;
}

void GameApp::DebugShowEnding(bool accept)
{
    m_endingChoice = accept ? EndingChoice::ACCEPT : EndingChoice::WAIT;
    m_mode = GameMode::EPILOGUE;
}

void GameApp::DebugAdvanceDialogue(int steps)
{
    for (int i = 0; i < steps; ++i) {
        if (m_dialogue.IsFinished()) {
            break;
        }
        m_dialogue.Advance();
    }
}

void GameApp::DebugStartNewGame()
{
    StartNewGame();
}

void GameApp::DebugInteract(const std::string& id)
{
    HandleInteraction(id);
}

void GameApp::DebugChooseDialogue(int option)
{
    if (!m_dialogue.IsWaitingForChoice()) {
        return;
    }
    m_dialogue.SelectOption(option);
    m_dialogue.Confirm();
}

void GameApp::DebugFinishDialogue()
{
    for (int i = 0; i < 300; ++i) {
        if (m_dialogue.IsFinished() || m_dialogue.IsWaitingForChoice()) {
            break;
        }
        m_dialogue.Advance();
    }
}

void GameApp::DebugCloseShop()
{
    if (m_mode == GameMode::SHOP) {
        CloseShop();
    }
}

void GameApp::DebugKillEnemies()
{
    m_enemies.clear();
    m_bullets.clear();
}

int GameApp::DebugAliveEnemies() const
{
    int count = 0;
    for (const Enemy& enemy : m_enemies) {
        if (!enemy.dead) {
            ++count;
        }
    }
    return count;
}

} // namespace fc
