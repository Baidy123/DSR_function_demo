#include "Game_App.hpp"

#include "Platform_Input.hpp"
#include "Shared_Log.hpp"
#include "Shared_Math.hpp"

#include <algorithm>
#include <cmath>
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

float SmoothStep(float t)
{
    t = Clamp(t, 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

CameraPose LerpPose(const CameraPose& a, const CameraPose& b, float t)
{
    CameraPose result;
    result.eye = Vec3(Lerp(a.eye.x, b.eye.x, t), Lerp(a.eye.y, b.eye.y, t),
                      Lerp(a.eye.z, b.eye.z, t));
    result.target =
        Vec3(Lerp(a.target.x, b.target.x, t), Lerp(a.target.y, b.target.y, t),
             Lerp(a.target.z, b.target.z, t));
    result.fovDegrees = Lerp(a.fovDegrees, b.fovDegrees, t);
    result.up = a.up;
    return result;
}

} // namespace

GameApp::~GameApp()
{
    Shutdown();
}

bool GameApp::Initialize(HWND hwnd, int width, int height,
                         const std::string& meshLibraryText, bool muted)
{
    m_muted = muted;
    if (!m_device.Initialize(hwnd, width, height)) {
        return false;
    }
    if (!m_text.Initialize(&m_device)) {
        return false;
    }
    m_meshes.Initialize(m_device.Device());
    const int meshCount = m_meshes.AddText(meshLibraryText);
    LogInfo("Mesh library parsed: %d meshes", meshCount);
    m_characters.Build(m_meshes);
    if (!m_renderer.Initialize(&m_device, &m_meshes, &m_characters)) {
        return false;
    }
    if (!m_ui.Initialize(&m_device, &m_text, &m_renderer)) {
        return false;
    }
    m_audio.Initialize();
    m_audio.SetMuted(m_muted);

    m_renderer.BuildPortraits();

    m_rng.Seed(0x51EEDu);
    m_time = 0.0f;
    m_mode = GameMode::TITLE;
    m_quest = QuestState();
    m_inventory = Inventory();
    m_player = Player();

    LoadScene(SceneId::BAR_EXTERIOR, Vec3(0.6f, 0.0f, 11.5f), 180.0f);
    m_hidePlayer = true;
    m_titleScene = true;
    m_mode = GameMode::TITLE;
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

void GameApp::BuildNpcs()
{
    m_npcs.clear();
    if (m_scene.id != SceneId::BAR_INTERIOR) {
        return;
    }
    NpcInstance bartender;
    bartender.id = CharacterId::BARTENDER;
    bartender.position = Vec3(-1.8f, 0.0f, -3.25f);
    bartender.yaw = 0.0f;
    m_npcs.push_back(bartender);

    NpcInstance sister;
    sister.id = CharacterId::BIGSISTER;
    sister.position = Vec3(4.7f, 0.0f, -3.0f);
    sister.yaw = 0.0f;
    m_npcs.push_back(sister);

    NpcInstance merchant;
    merchant.id = CharacterId::MERCHANT;
    merchant.position = Vec3(-5.3f, 0.0f, 2.4f);
    merchant.yaw = 90.0f;
    m_npcs.push_back(merchant);
}

void GameApp::RefreshLights()
{
    m_lights = m_scene.lights;
    if (m_scene.id == SceneId::IRON_HARBOR && m_alarm) {
        for (LightDef& light : m_lights) {
            if (light.color.r > 0.9f && light.color.g < 0.35f) {
                light.intensity = 2.6f;
            }
        }
    }
}

void GameApp::LoadScene(SceneId id, Vec3 spawn, float yawDegrees)
{
    m_scene = BuildScene(id);
    m_renderer.LoadScene(m_scene, m_collision);
    m_interactions = m_scene.interactions;
    BuildNpcs();
    m_alarm = false;

    m_player.position = spawn;
    m_player.yaw = yawDegrees * PI / 180.0f;
    m_player.facing = m_player.yaw;
    m_player.aimYaw = m_player.yaw;
    m_player.moving = false;
    m_player.walkAmp = 0.0f;
    m_player.reloading = false;
    m_player.usingMedkit = false;
    m_player.reloadTimer = 0.0f;
    m_player.medkitTimer = 0.0f;
    m_player.fireCooldown = 0.0f;
    m_player.invulnerableTimer = 0.4f;
    m_player.hitFlash = 0.0f;
    m_player.recoil = 0.0f;

    m_checkpointSpawn = spawn;
    m_checkpointYaw = yawDegrees;

    m_enemies.clear();
    m_bullets.clear();
    m_particles.clear();
    m_pickups.clear();
    m_prompt.clear();
    m_hasPrompt = false;
    m_hasScene = true;

    if (id == SceneId::IRON_HARBOR) {
        if (m_quest.cargoTaken) {
            m_renderer.HidePropsByMesh("PROP_CARGO");
            m_interactions.erase(
                std::remove_if(m_interactions.begin(), m_interactions.end(),
                               [](const InteractDef& def) {
                                   return def.id == "cargo";
                               }),
                m_interactions.end());
        }
        if (!(m_quest.side == SideStage::ACCEPTED && !m_inventory.hasPart)) {
            m_renderer.HidePropsByMesh("PROP_PART");
            m_interactions.erase(
                std::remove_if(m_interactions.begin(), m_interactions.end(),
                               [](const InteractDef& def) {
                                   return def.id == "part";
                               }),
                m_interactions.end());
        }
        if (m_quest.main == MainStage::FIND_CARGO && !m_quest.agentsCleared) {
            for (const EnemySpawnDef& spawnDef : m_scene.enemies) {
                SpawnEnemy(spawnDef.type, spawnDef.position,
                           spawnDef.yawDegrees, false);
            }
        } else if (m_quest.main == MainStage::DEFEAT_AGENTS &&
                   !m_quest.agentsCleared) {
            m_quest.ambushTriggered = true;
            SpawnEnemy(EnemyType::AGENT, Vec3(10.6f, 0.0f, 0.0f), 270.0f, true);
            SpawnEnemy(EnemyType::AGENT, Vec3(10.2f, 0.0f, 2.2f), 270.0f, true);
            SpawnEnemy(EnemyType::AGENT, Vec3(10.2f, 0.0f, -2.2f), 270.0f, true);
            m_alarm = true;
        }
    }

    RefreshLights();

    if (m_scene.cameras.empty()) {
        CameraZoneDef fallback;
        fallback.pose.eye = Vec3(0.0f, 6.0f, 10.0f);
        fallback.pose.target = Vec3(0.0f, 1.0f, 0.0f);
        fallback.pose.fovDegrees = 55.0f;
        fallback.bounds = AABB(Vec3(-30.0f, -2.0f, -30.0f),
                               Vec3(30.0f, 12.0f, 30.0f));
        m_scene.cameras.push_back(fallback);
    }
    m_cameraZone = -1;
    m_cameraBlend = 1.0f;
    m_camera.current = m_scene.cameras.front().pose;
    m_camera.target = m_camera.current;
    m_cameraStart = m_camera.current;
    m_cameraTarget = m_camera.current;
    UpdateCameraMatrices(m_camera,
                         static_cast<float>(INTERNAL_WIDTH) /
                             static_cast<float>(INTERNAL_HEIGHT));

    if (m_scene.rain) {
        InitRain();
    } else {
        m_rain.clear();
    }

    m_locationName = m_scene.displayName;
    m_locationTimer = 2.4f;

    if (id == SceneId::BAR_INTERIOR) {
        m_audio.SetScene(0, false);
    } else if (id == SceneId::IRON_HARBOR) {
        m_audio.SetScene(2, true);
    } else {
        m_audio.SetScene(1, true);
    }
    LogInfo("Scene loaded: %s", m_scene.displayName.c_str());
}

void GameApp::StartNewGame()
{
    m_inventory = Inventory();
    m_quest = QuestState();
    m_shop = ShopState();
    m_endingChoice = EndingChoice::NONE;
    m_player = Player();
    m_player.hp = PLAYER_MAX_HP;
    m_toasts.clear();
    m_rain.clear();
    m_particles.clear();
    m_bullets.clear();
    m_pickups.clear();
    m_enemies.clear();
    m_damageFlash = 0.0f;
    m_alarm = false;
    m_titleScene = false;
    m_hidePlayer = false;
    m_rng.Seed(0x51EEDu);

    LoadScene(SceneId::BAR_EXTERIOR, Vec3(0.6f, 0.0f, 11.5f), 180.0f);
    StartDialogue(m_story.BuildIntro(), DialogueContext::INTRO);
    m_audio.PlaySfx(SfxId::UI);
    LogInfo("New game started");
}

void GameApp::StartTransition(SceneId id, Vec3 spawn, float yawDegrees)
{
    m_transitionActive = true;
    m_transitionLoaded = false;
    m_transitionTimer = 0.0f;
    m_transitionScene = id;
    m_transitionSpawn = spawn;
    m_transitionYaw = yawDegrees;
    m_modeAfterTransition = GameMode::PLAYING;
    m_mode = GameMode::TRANSITION;
    m_fadeAlpha = 0.0f;
    m_prompt.clear();
    m_hasPrompt = false;
    m_audio.PlaySfx(SfxId::DOOR);
}

void GameApp::UpdateTransition(float dt)
{
    m_transitionTimer += dt;
    const float half = 0.30f;
    const float total = 0.62f;
    if (!m_transitionLoaded && m_transitionTimer >= half) {
        LoadScene(m_transitionScene, m_transitionSpawn, m_transitionYaw);
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

void GameApp::StartDialogue(const Dialogue& dialogue, DialogueContext context)
{
    m_dialogue.Start(dialogue);
    m_dialogueContext = context;
    m_dialogueCinematic = dialogue.cinematic;
    m_skipHold = 0.0f;
    m_skipTick = 0.0f;
    m_skipActive = false;
    m_mode = GameMode::DIALOGUE;
    m_prompt.clear();
    m_hasPrompt = false;
    m_player.moving = false;
}

void GameApp::Update(float dt)
{
    dt = Clamp(dt, 0.0f, 0.05f);
    m_time += dt;
    m_damageFlash = std::max(0.0f, m_damageFlash - dt * 2.2f);
    m_player.recoil = std::max(0.0f, m_player.recoil - dt * 8.0f);
    if (m_noGearToastCooldown > 0) {
        --m_noGearToastCooldown;
    }
    UpdateToasts(dt);
    if (m_locationTimer > 0.0f) {
        m_locationTimer -= dt;
    }

    Input& input = Input::Get();
    if (input.Pressed('M')) {
        m_muted = !m_muted;
        m_audio.SetMuted(m_muted);
    }

    switch (m_mode) {
    case GameMode::TITLE:
        UpdateTitle(dt);
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
            DebugSetTitleMode();
        }
        break;
    case GameMode::DEAD:
        if (input.Pressed(VK_RETURN)) {
            RespawnAfterDeath();
        } else if (input.Pressed(VK_ESCAPE)) {
            DebugSetTitleMode();
        }
        break;
    case GameMode::EPILOGUE:
        if (input.Pressed(VK_RETURN)) {
            StartNewGame();
        } else if (input.Pressed(VK_ESCAPE)) {
            DebugSetTitleMode();
        }
        break;
    case GameMode::TRANSITION:
        UpdateTransition(dt);
        break;
    default:
        break;
    }
}

void GameApp::UpdateTitle(float dt)
{
    Input& input = Input::Get();
    if (input.Pressed(VK_RETURN) || input.Pressed(VK_SPACE) ||
        input.MousePressed(0)) {
        StartNewGame();
        return;
    }
    if (input.Pressed(VK_ESCAPE)) {
        m_quit = true;
        return;
    }
    UpdateRain(dt);
    UpdateParticles(dt);
    m_camera.current = m_scene.cameras.front().pose;
    m_camera.current.eye.x += std::sin(m_time * 0.13f) * 0.35f;
    m_camera.current.eye.y += std::sin(m_time * 0.21f) * 0.10f;
    m_camera.current.target.x += std::sin(m_time * 0.17f) * 0.18f;
    UpdateCameraMatrices(m_camera,
                         static_cast<float>(INTERNAL_WIDTH) /
                             static_cast<float>(INTERNAL_HEIGHT));
    m_audio.SetCombat(false);
}

Vec3 GameApp::ScreenRayDirection(Vec2 screen) const
{
    const CameraPose& pose = m_camera.current;
    const Vec3 forward = Normalize(pose.target - pose.eye);
    Vec3 right = Cross(pose.up, forward);
    if (Length(right) < 0.001f) {
        right = Vec3(1.0f, 0.0f, 0.0f);
    }
    right = Normalize(right);
    const Vec3 up = Cross(forward, right);

    const float ndcX =
        (screen.x / static_cast<float>(UI_WIDTH)) * 2.0f - 1.0f;
    const float ndcY =
        1.0f - (screen.y / static_cast<float>(UI_HEIGHT)) * 2.0f;
    const float tanHalf = std::tan(pose.fovDegrees * PI / 180.0f * 0.5f);
    const float aspect = static_cast<float>(INTERNAL_WIDTH) /
                         static_cast<float>(INTERNAL_HEIGHT);
    const Vec3 direction = forward + right * (ndcX * tanHalf * aspect) +
                           up * (ndcY * tanHalf);
    return Normalize(direction);
}

Vec3 GameApp::AimPointFromMouse(Vec2 mouse) const
{
    const Vec3 origin = m_camera.current.eye;
    const Vec3 direction = ScreenRayDirection(mouse);
    Vec3 hit;
    if (RayPlaneY(origin, direction, 1.15f, hit)) {
        return hit;
    }
    return origin + direction * 20.0f;
}

bool GameApp::HasLineOfSight(const Vec3& from, const Vec3& to) const
{
    return !m_collision.LineBlocked(from, to);
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

    const Vec2 mouse = m_device.ScreenToInternal(input.MousePosition());
    const Vec3 aimPoint = AimPointFromMouse(mouse);
    const Vec3 toAim = aimPoint - m_player.position;
    m_player.yaw = YawFromDirection(toAim);
    m_player.aimYaw = m_player.yaw;
    m_player.aimPitch = 0.0f;
    // 只在开火或主动瞄准后短时间内举枪，否则安静站立。
    if (input.MouseDown(0)) {
        m_player.aimTimer = AIM_HOLD_TIME;
    }
    m_player.aimTimer = std::max(0.0f, m_player.aimTimer - dt);
    m_player.aiming = m_player.aimTimer > 0.0f || m_player.reloading ||
                      m_player.usingMedkit;
    m_player.time += dt;

    Vec3 forward = NormalizeXZ(m_camera.current.target - m_camera.current.eye);
    Vec3 right(forward.z, 0.0f, -forward.x);
    Vec3 move;
    if (input.Down('W') || input.Down(VK_UP)) {
        move += forward;
    }
    if (input.Down('S') || input.Down(VK_DOWN)) {
        move -= forward;
    }
    if (input.Down('D') || input.Down(VK_RIGHT)) {
        move += right;
    }
    if (input.Down('A') || input.Down(VK_LEFT)) {
        move -= right;
    }
    m_player.running = input.Down(VK_SHIFT);
    if (Length(move) > 0.001f) {
        move = NormalizeXZ(move);
        float speed = m_player.running ? PLAYER_RUN_SPEED : PLAYER_SPEED;
        if (m_player.usingMedkit) {
            speed *= 0.55f;
        }
        const Vec3 before = m_player.position;
        m_collision.Move(m_player.position, move * speed * dt, PLAYER_RADIUS);
        m_player.moving = DistanceXZ(before, m_player.position) > 0.01f;
        if (m_player.moving) {
            m_player.walkPhase += dt * (m_player.running ? 11.0f : 7.5f);
            // 身体转向移动方向；上半身随后再转向鼠标。
            m_player.facing = MoveTowardsAngle(
                m_player.facing, YawFromDirection(move), dt * 9.0f);
            m_player.walkAmp = MoveTowards(
                m_player.walkAmp, m_player.running ? 1.0f : 0.82f, dt * 4.8f);
        } else {
            m_player.walkAmp = MoveTowards(m_player.walkAmp, 0.0f, dt * 6.0f);
        }
    } else {
        m_player.moving = false;
        m_player.walkAmp = MoveTowards(m_player.walkAmp, 0.0f, dt * 6.0f);
        // 停下时缓慢把身体转回瞄准方向，避免突然甩头。
        m_player.facing =
            MoveTowardsAngle(m_player.facing, m_player.yaw, dt * 2.2f);
    }

    m_player.fireCooldown = std::max(0.0f, m_player.fireCooldown - dt);
    m_player.invulnerableTimer = std::max(0.0f, m_player.invulnerableTimer - dt);
    m_player.hitFlash = std::max(0.0f, m_player.hitFlash - dt * 3.0f);

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
            AddToast("伤口处理完毕", BONE);
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
        const InteractDef* interact = NearestInteract(distance);
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

    if (m_debugWalkPose) {
        // 无头验证时让角色原地"走"，方便检查骨骼摆动。
        m_player.walkAmp = 1.0f;
        m_player.walkPhase += dt * 7.5f;
    }

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
        m_audio.PlaySfx(SfxId::DEATH);
    }
}

void GameApp::UpdateDialogue(float dt)
{
    Input& input = Input::Get();

    // 按住 Ctrl 两秒进入快进；期间显示逐渐填满的进度条，松开即取消。
    const bool ctrlDown = input.Down(VK_CONTROL);
    if (ctrlDown) {
        m_skipHold = std::min(SKIP_HOLD_TIME, m_skipHold + dt);
        if (m_skipHold >= SKIP_HOLD_TIME) {
            m_skipActive = true;
        }
    } else {
        m_skipHold = 0.0f;
        m_skipActive = false;
        m_skipTick = 0.0f;
    }

    if (m_skipActive) {
        // 快进：先把当前节点文字瞬间补全，再按固定节奏跳到下一节点；
        // 遇到选项会停下，把选择权交还玩家。
        m_dialogue.Update(10.0f);
        if (!m_dialogue.IsWaitingForChoice()) {
            m_skipTick -= dt;
            if (m_skipTick <= 0.0f) {
                m_dialogue.Advance();
                m_dialogue.Update(10.0f);
                m_skipTick = SKIP_STEP_TIME;
            }
        }
    } else {
        m_dialogue.Update(dt);
    }

    DialogueEvent event = DialogueEvent::NONE;
    while ((event = m_dialogue.ConsumeEvent()) != DialogueEvent::NONE) {
        HandleDialogueEvent(event);
    }

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
        m_skipHold = 0.0f;
        m_skipActive = false;
        m_skipTick = 0.0f;
        HandleDialogueFinished();
        return;
    }
    UpdateRain(dt);
    UpdateParticles(dt);
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
    // 事件可能在本帧内刚产生；先全部派发，再收尾阶段。
    DialogueEvent pending = DialogueEvent::NONE;
    while ((pending = m_dialogue.ConsumeEvent()) != DialogueEvent::NONE) {
        HandleDialogueEvent(pending);
    }

    const DialogueContext context = m_dialogueContext;
    m_dialogueContext = DialogueContext::NONE;
    switch (context) {
    case DialogueContext::INTRO:
        m_quest.main = MainStage::ENTER_BAR;
        AddToast("目标更新：进入余烬酒吧", AMBER);
        m_mode = GameMode::PLAYING;
        break;
    case DialogueContext::BARTENDER_FIRST:
        m_quest.main = MainStage::TALK_BIGSISTER;
        AddToast("目标更新：去吧台后的卡座找大美", CYAN);
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
    case DialogueContext::BARTENDER_SIDE_OFFER:
        if (m_quest.side == SideStage::NOT_STARTED) {
            m_quest.side = SideStage::DECLINED;
        }
        m_mode = GameMode::PLAYING;
        break;
    case DialogueContext::MERCHANT_FIRST:
    case DialogueContext::MERCHANT_SHOP:
        m_shop.browseOnly = !m_inventory.hasGear;
        m_shop.selected = 0;
        m_shop.message.clear();
        m_shop.messageTimer = 0.0f;
        m_dialogueContext = context;
        m_mode = GameMode::SHOP;
        break;
    case DialogueContext::AMBUSH_WARNING:
        m_mode = GameMode::PLAYING;
        break;
    default:
        m_mode = GameMode::PLAYING;
        break;
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
            m_shop.message = "ACCESS DENIED：这东西不是你现在买得起的。";
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

void GameApp::UpdateEnemies(float dt)
{
    for (Enemy& enemy : m_enemies) {
        if (enemy.dead) {
            enemy.deathTimer = std::max(0.0f, enemy.deathTimer - dt);
            enemy.time += dt;
            continue;
        }
        enemy.time += dt;
        enemy.shootTimer = std::max(0.0f, enemy.shootTimer - dt);
        enemy.muzzleTimer = std::max(0.0f, enemy.muzzleTimer - dt);
        enemy.hitFlash = std::max(0.0f, enemy.hitFlash - dt * 4.0f);

        const Vec3 eye = enemy.position + Vec3(0.0f, 1.3f, 0.0f);
        const Vec3 playerEye = m_player.position + Vec3(0.0f, 1.25f, 0.0f);
        const bool los = HasLineOfSight(eye, playerEye);
        const float distance = DistanceXZ(enemy.position, m_player.position);

        if (!enemy.alerted && los && distance < 12.0f) {
            enemy.alerted = true;
        }
        if (m_alarm && distance < 22.0f) {
            enemy.alerted = true;
        }
        if (!enemy.alerted) {
            enemy.moving = false;
            enemy.aiming = false;
            continue;
        }

        const Vec3 toPlayer = NormalizeXZ(m_player.position - enemy.position);
        enemy.yaw = YawFromDirection(toPlayer);
        enemy.aiming = los && distance < 16.0f;

        Vec3 desired;
        if (distance > 6.5f) {
            desired = toPlayer;
        } else if (distance < 2.6f) {
            desired = toPlayer * -1.0f;
        } else {
            const Vec3 side(toPlayer.z, 0.0f, -toPlayer.x);
            desired = side * 0.6f;
        }
        if (Length(desired) > 0.001f) {
            desired = NormalizeXZ(desired);
            const Vec3 before = enemy.position;
            Vec3 next = enemy.position;
            bool moved = m_collision.Move(next, desired * enemy.speed * dt,
                                          enemy.radius);
            if (!moved) {
                const Vec3 side(desired.z, 0.0f, -desired.x);
                next = enemy.position;
                moved = m_collision.Move(next, side * enemy.speed * dt * 0.8f,
                                         enemy.radius);
            }
            enemy.position = next;
            enemy.moving = DistanceXZ(before, enemy.position) > 0.01f;
            if (enemy.moving) {
                enemy.walkPhase += dt * 7.0f;
            }
        } else {
            enemy.moving = false;
        }
        enemy.walkAmp = MoveTowards(enemy.walkAmp,
                                    enemy.moving ? 0.9f : 0.0f, dt * 5.0f);

        // 互相分离，避免叠在一起
        for (const Enemy& other : m_enemies) {
            if (&other == &enemy || other.dead) {
                continue;
            }
            const Vec3 delta = enemy.position - other.position;
            const float dist = DistanceXZ(enemy.position, other.position);
            if (dist > 0.001f && dist < 0.7f) {
                Vec3 push = NormalizeXZ(delta) * (0.7f - dist) * 0.5f;
                Vec3 next = enemy.position + push;
                if (!m_collision.Blocked(next, enemy.radius)) {
                    enemy.position = next;
                }
            }
        }

        if (los && distance < 15.0f && enemy.shootTimer <= 0.0f &&
            m_player.hp > 0) {
            FireEnemyWeapon(enemy);
            enemy.shootTimer = enemy.type == EnemyType::AGENT ? 0.85f : 1.35f;
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
        const Vec3 from = bullet.position;
        const Vec3 to = from + bullet.direction * (bullet.speed * dt);

        float wallT = 1.0f;
        if (m_collision.SegmentBlocked(from, to, wallT)) {
            const Vec3 hit = from + (to - from) * wallT;
            SpawnSparks(hit, Rgba(255, 190, 110));
            bullet.active = false;
            continue;
        }

        if (bullet.hostile) {
            const Vec3 chest = m_player.position + Vec3(0.0f, 1.15f, 0.0f);
            float distance = 0.0f;
            const Vec3 direction = NormalizeXZ(to - from);
            if (RayCircleXZ(from, direction, chest, 0.42f, distance) &&
                distance <= Distance(from, to) + 0.2f) {
                DamagePlayer(static_cast<int>(bullet.damage));
                bullet.active = false;
                continue;
            }
        } else {
            for (size_t i = 0; i < m_enemies.size(); ++i) {
                Enemy& enemy = m_enemies[i];
                if (enemy.dead) {
                    continue;
                }
                const Vec3 chest = enemy.position + Vec3(0.0f, 1.05f, 0.0f);
                float distance = 0.0f;
                const Vec3 direction = NormalizeXZ(to - from);
                if (RayCircleXZ(from, direction, chest, 0.44f, distance) &&
                    distance <= Distance(from, to) + 0.2f) {
                    DamageEnemy(i, static_cast<int>(bullet.damage));
                    bullet.active = false;
                    break;
                }
            }
        }
        if (!bullet.active) {
            continue;
        }
        bullet.position = to;
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
        particle.velocity = particle.velocity * (1.0f - 3.5f * dt);
        particle.velocity.y -= 4.5f * dt;
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
        if (DistanceXZ(pickup.position, m_player.position) > 0.9f) {
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
        case PickupType::MEDKIT:
            if (m_inventory.AddMedkit(1) > 0) {
                AddToast("获得：医疗包", BONE);
                m_audio.PlaySfx(SfxId::PICKUP);
                pickup.active = false;
            }
            break;
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
    for (RainDrop& drop : m_rain) {
        drop.y += drop.speed * dt;
        drop.x += 26.0f * dt;
        if (drop.y > static_cast<float>(UI_HEIGHT) + 6.0f) {
            drop.y = -drop.length;
            drop.x = m_rng.Float(0.0f, static_cast<float>(UI_WIDTH));
        }
        if (drop.x > static_cast<float>(UI_WIDTH)) {
            drop.x -= static_cast<float>(UI_WIDTH);
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

void GameApp::UpdateCamera(float dt)
{
    if (m_scene.cameras.empty()) {
        return;
    }

    int zone = -1;
    float bestDistance = 1.0e9f;
    for (size_t i = 0; i < m_scene.cameras.size(); ++i) {
        const CameraZoneDef& candidate = m_scene.cameras[i];
        const bool insideXZ =
            m_player.position.x >= candidate.bounds.min.x &&
            m_player.position.x <= candidate.bounds.max.x &&
            m_player.position.z >= candidate.bounds.min.z &&
            m_player.position.z <= candidate.bounds.max.z;
        if (insideXZ) {
            zone = static_cast<int>(i);
            break;
        }
        const Vec3 center((candidate.bounds.min.x + candidate.bounds.max.x) * 0.5f,
                          0.0f,
                          (candidate.bounds.min.z + candidate.bounds.max.z) * 0.5f);
        const float distance = DistanceXZ(center, m_player.position);
        if (distance < bestDistance) {
            bestDistance = distance;
            zone = static_cast<int>(i);
        }
    }
    if (zone < 0) {
        zone = 0;
    }

    const CameraZoneDef& selected = m_scene.cameras[static_cast<size_t>(zone)];

    // 机位跟随：固定构图仍然是主体，但会按玩家在区域内的位移做部分平移，
    // 这样走到角落交互时角色不会跑出画面。
    const Vec3 zoneCenter(
        (selected.bounds.min.x + selected.bounds.max.x) * 0.5f, 0.0f,
        (selected.bounds.min.z + selected.bounds.max.z) * 0.5f);
    Vec3 delta = m_player.position - zoneCenter;
    delta.y = 0.0f;
    delta.x = Clamp(delta.x * CAMERA_FOLLOW_RATIO, -CAMERA_FOLLOW_LIMIT,
                    CAMERA_FOLLOW_LIMIT);
    delta.z = Clamp(delta.z * CAMERA_FOLLOW_RATIO, -CAMERA_FOLLOW_LIMIT,
                    CAMERA_FOLLOW_LIMIT);
    const float followBlend = 1.0f - std::exp(-dt * 4.5f);
    m_cameraFollow.x += (delta.x - m_cameraFollow.x) * followBlend;
    m_cameraFollow.z += (delta.z - m_cameraFollow.z) * followBlend;

    CameraPose desired = selected.pose;
    desired.eye += m_cameraFollow;
    desired.target += m_cameraFollow * 0.75f;
    // 目标点还要向玩家靠拢，保证角色不会跑到画面外。
    const Vec3 lookAt = m_player.position + Vec3(0.0f, 1.05f, 0.0f);
    desired.target += (lookAt - desired.target) * CAMERA_TARGET_BIAS;
    // 相机必须留在房间内，否则会穿墙。
    desired.eye.x = Clamp(desired.eye.x, selected.bounds.min.x + 0.35f,
                          selected.bounds.max.x - 0.35f);
    desired.eye.z = Clamp(desired.eye.z, selected.bounds.min.z + 0.35f,
                          selected.bounds.max.z - 0.35f);

    m_cameraTarget = desired;
    if (zone != m_cameraZone) {
        m_cameraZone = zone;
        m_cameraStart = m_camera.current;
        m_cameraBlend = 0.0f;
    }
    if (m_cameraBlend < 1.0f) {
        m_cameraBlend = std::min(1.0f, m_cameraBlend + dt / 0.55f);
        const float t = SmoothStep(m_cameraBlend);
        m_camera.current = LerpPose(m_cameraStart, m_cameraTarget, t);
    } else {
        m_camera.current = m_cameraTarget;
    }

    if (m_camera.shakeTime > 0.0f) {
        m_camera.shakeTime = std::max(0.0f, m_camera.shakeTime - dt);
        const float f = m_camera.shakeDuration > 0.0f
                            ? m_camera.shakeTime / m_camera.shakeDuration
                            : 0.0f;
        m_camera.shakeOffset =
            Vec3(m_rng.Float(-1.0f, 1.0f) * m_camera.shakeIntensity * f,
                 m_rng.Float(-1.0f, 1.0f) * m_camera.shakeIntensity * f,
                 m_rng.Float(-1.0f, 1.0f) * m_camera.shakeIntensity * f);
    } else {
        m_camera.shakeOffset = Vec3();
    }

    CameraRuntime applied = m_camera;
    applied.current.eye += m_camera.shakeOffset;
    applied.current.target += m_camera.shakeOffset * 0.5f;
    UpdateCameraMatrices(applied,
                         static_cast<float>(INTERNAL_WIDTH) /
                             static_cast<float>(INTERNAL_HEIGHT));
    m_camera.view = applied.view;
    m_camera.projection = applied.projection;
    m_camera.viewProjection = applied.viewProjection;
}

void GameApp::UpdatePrompt()
{
    m_hasPrompt = false;
    m_prompt.clear();
    if (m_mode != GameMode::PLAYING) {
        return;
    }
    float distance = 0.0f;
    const InteractDef* interact = NearestInteract(distance);
    if (interact == nullptr) {
        return;
    }
    Vec2 screen;
    if (!m_renderer.WorldToScreen(m_camera,
                                  interact->position + Vec3(0.0f, 0.6f, 0.0f),
                                  screen)) {
        return;
    }
    m_hasPrompt = true;
    m_prompt = interact->prompt;
    m_promptScreen = screen;
}

const InteractDef* GameApp::NearestInteract(float& outDistance) const
{
    const InteractDef* best = nullptr;
    float bestDistance = 1.0e9f;
    for (const InteractDef& interact : m_interactions) {
        const float distance = DistanceXZ(m_player.position, interact.position);
        if (distance <= interact.radius && distance < bestDistance) {
            best = &interact;
            bestDistance = distance;
        }
    }
    outDistance = bestDistance;
    return best;
}

bool GameApp::ObjectiveWorldPosition(Vec3& out) const
{
    switch (m_quest.main) {
    case MainStage::ENTER_BAR:
        out = Vec3(0.6f, 1.7f, 0.9f);
        return true;
    case MainStage::TALK_BARTENDER:
        out = Vec3(-1.8f, 1.9f, -3.25f);
        return true;
    case MainStage::TALK_BIGSISTER:
        out = Vec3(4.7f, 1.9f, -2.8f);
        return true;
    case MainStage::GET_GEAR:
        out = Vec3(-5.3f, 1.9f, 2.2f);
        return true;
    case MainStage::GO_WAREHOUSE:
        out = Vec3(-4.3f, 1.7f, 8.6f);
        return true;
    case MainStage::FIND_CARGO:
        out = Vec3(0.0f, 1.9f, 0.0f);
        return true;
    case MainStage::DEFEAT_AGENTS:
        out = Vec3(11.0f, 2.0f, 0.0f);
        return true;
    case MainStage::RETURN_BAR:
        out = m_scene.id == SceneId::BAR_INTERIOR ? Vec3(4.7f, 1.9f, -2.8f)
                                                  : Vec3(0.6f, 1.7f, 0.9f);
        return true;
    default:
        return false;
    }
}

void GameApp::HandleInteraction(const std::string& id)
{
    if (id == "bar_entrance") {
        if (m_quest.main == MainStage::ENTER_BAR) {
            m_quest.main = MainStage::TALK_BARTENDER;
        }
        StartTransition(SceneId::BAR_INTERIOR, Vec3(0.6f, 0.0f, 4.2f), 180.0f);
        return;
    }
    if (id == "bar_exit") {
        if (m_quest.main < MainStage::GET_GEAR) {
            StartDialogue(m_story.BuildBarExitLocked(),
                          DialogueContext::BAR_EXIT_LOCKED);
            return;
        }
        StartTransition(SceneId::BAR_EXTERIOR, Vec3(0.6f, 0.0f, 1.6f), 0.0f);
        return;
    }
    if (id == "car") {
        const bool canTravel = m_quest.main == MainStage::GO_WAREHOUSE ||
                               m_quest.main == MainStage::FIND_CARGO ||
                               m_quest.main == MainStage::DEFEAT_AGENTS;
        if (canTravel) {
            if (m_quest.main == MainStage::GO_WAREHOUSE) {
                m_quest.main = MainStage::FIND_CARGO;
            }
            StartTransition(SceneId::IRON_HARBOR, Vec3(-11.0f, 0.0f, 7.0f),
                            90.0f);
        } else if (m_quest.main == MainStage::RETURN_BAR) {
            AddToast("先把货带回酒吧交差。", AMBER);
        } else {
            StartDialogue(m_story.BuildCarLocked(),
                          DialogueContext::CAR_LOCKED);
        }
        return;
    }
    if (id == "warehouse_exit") {
        StartTransition(SceneId::BAR_EXTERIOR, Vec3(0.6f, 0.0f, 7.5f), 180.0f);
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
    if (id == "terminal") {
        StartDialogue(m_story.BuildTerminal(), DialogueContext::TERMINAL);
        return;
    }
    if (id == "street_sign") {
        StartDialogue(m_story.BuildStreetSign(),
                      DialogueContext::STREET_SIGN);
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
        m_renderer.HidePropsByMesh("PROP_CARGO");
        m_interactions.erase(
            std::remove_if(m_interactions.begin(), m_interactions.end(),
                           [](const InteractDef& def) {
                               return def.id == "cargo";
                           }),
            m_interactions.end());
        SpawnAmbush();
        m_alarm = true;
        RefreshLights();
        TriggerShake(0.10f, 0.45f);
        m_audio.PlaySfx(SfxId::ALARM);
        AddToast("货物已搬起。警报响了。", MAGENTA);
        StartDialogue(m_story.BuildAmbushWarning(),
                      DialogueContext::AMBUSH_WARNING);
        return;
    }
    if (id == "part") {
        if (m_quest.side == SideStage::ACCEPTED) {
            m_quest.side = SideStage::HAVE_PART;
            m_inventory.hasPart = true;
            m_renderer.HidePropsByMesh("PROP_PART");
            m_interactions.erase(
                std::remove_if(m_interactions.begin(), m_interactions.end(),
                               [](const InteractDef& def) {
                                   return def.id == "part";
                               }),
                m_interactions.end());
            AddToast("获得：点唱机零件", CYAN);
            m_audio.PlaySfx(SfxId::PICKUP);
            SpawnSparks(m_player.position + Vec3(0.0f, 0.5f, 0.0f), CYAN);
        } else {
            AddToast("一块旧零件。现在用不上。", DIM);
        }
        return;
    }
}

void GameApp::CheckCombatProgress()
{
    if (m_quest.main != MainStage::DEFEAT_AGENTS) {
        return;
    }
    bool agentAlive = false;
    for (const Enemy& enemy : m_enemies) {
        if (enemy.type == EnemyType::AGENT && !enemy.dead) {
            agentAlive = true;
            break;
        }
    }
    if (!agentAlive) {
        m_quest.main = MainStage::RETURN_BAR;
        m_quest.agentsCleared = true;
        m_alarm = false;
        RefreshLights();
        AddToast("公司特工已清理", CYAN);
        AddToast("目标更新：带着货物返回酒吧", AMBER);
    }
}

void GameApp::SpawnEnemy(EnemyType type, Vec3 position, float yawDegrees,
                         bool alerted)
{
    Enemy enemy;
    enemy.type = type;
    enemy.character = type == EnemyType::AGENT ? CharacterId::AGENT
                                               : CharacterId::SCAVENGER;
    enemy.position = position;
    enemy.yaw = yawDegrees * PI / 180.0f;
    if (type == EnemyType::AGENT) {
        enemy.hp = 70.0f;
        enemy.maxHp = 70.0f;
        enemy.speed = 2.7f;
    } else {
        enemy.hp = 45.0f;
        enemy.maxHp = 45.0f;
        enemy.speed = 2.0f;
    }
    enemy.alerted = alerted;
    enemy.shootTimer = m_rng.Float(0.3f, 1.1f);
    m_enemies.push_back(enemy);
}

void GameApp::SpawnAmbush()
{
    if (m_quest.ambushTriggered) {
        return;
    }
    m_quest.ambushTriggered = true;
    SpawnEnemy(EnemyType::AGENT, Vec3(10.6f, 0.0f, 0.0f), 270.0f, true);
    SpawnEnemy(EnemyType::AGENT, Vec3(10.2f, 0.0f, 2.2f), 270.0f, true);
    SpawnEnemy(EnemyType::AGENT, Vec3(10.2f, 0.0f, -2.2f), 270.0f, true);
}

void GameApp::InitRain()
{
    m_rain.clear();
    m_rain.reserve(160);
    for (int i = 0; i < 160; ++i) {
        RainDrop drop;
        drop.x = m_rng.Float(0.0f, static_cast<float>(UI_WIDTH));
        drop.y = m_rng.Float(0.0f, static_cast<float>(UI_HEIGHT));
        drop.speed = m_rng.Float(170.0f, 320.0f);
        drop.length = m_rng.Float(5.0f, 12.0f);
        drop.alpha = m_rng.Float(0.05f, 0.18f);
        m_rain.push_back(drop);
    }
}

void GameApp::RespawnAfterDeath()
{
    m_player.hp = 60;
    m_inventory.ammoMag = WEAPON_MAGAZINE_SIZE;
    if (m_inventory.ammoReserve < 12) {
        m_inventory.ammoReserve = 12;
    }
    m_player.reloading = false;
    m_player.usingMedkit = false;
    m_player.invulnerableTimer = 1.0f;
    m_bullets.clear();
    m_particles.clear();
    m_pickups.clear();
    m_alarm = m_quest.main == MainStage::DEFEAT_AGENTS;
    LoadScene(m_scene.id, m_checkpointSpawn, m_checkpointYaw);
    m_mode = GameMode::PLAYING;
    AddToast("重新连接……", CYAN);
}

void GameApp::FirePlayerWeapon()
{
    if (m_player.fireCooldown > 0.0f || m_player.reloading ||
        m_player.usingMedkit) {
        return;
    }
    if (!m_inventory.hasGear) {
        if (m_noGearToastCooldown <= 0) {
            AddToast("还没有武器。先去东子那里领装备。", AMBER);
            m_noGearToastCooldown = 100;
        }
        m_player.fireCooldown = 0.4f;
        return;
    }
    if (m_inventory.ammoMag <= 0) {
        if (m_inventory.ammoReserve > 0) {
            StartReload();
        } else if (m_noGearToastCooldown <= 0) {
            AddToast("没有弹药了。", RED);
            m_noGearToastCooldown = 100;
        }
        m_player.fireCooldown = 0.4f;
        return;
    }

    m_inventory.ConsumeRound();
    m_player.aimTimer = AIM_HOLD_TIME;
    const Vec3 forward(std::sin(m_player.yaw), 0.0f, std::cos(m_player.yaw));
    Bullet bullet;
    bullet.position = m_player.position + Vec3(0.0f, 1.32f, 0.0f) +
                      forward * 0.55f;
    bullet.direction = forward;
    bullet.speed = PLAYER_BULLET_SPEED;
    bullet.damage = static_cast<float>(PLAYER_BULLET_DAMAGE);
    bullet.life = 1.1f;
    bullet.hostile = false;
    m_bullets.push_back(bullet);

    m_player.fireCooldown = PLAYER_FIRE_INTERVAL;
    m_player.recoil = 1.0f;
    m_audio.PlaySfx(SfxId::SHOOT);
    TriggerShake(0.012f, 0.07f);
    WakeEnemies(16.0f);
    SpawnSparks(bullet.position, Rgba(255, 210, 130));
}

void GameApp::FireEnemyWeapon(Enemy& enemy)
{
    const Vec3 muzzle = enemy.position + Vec3(0.0f, 1.28f, 0.0f) +
                        DirectionFromYaw(enemy.yaw) * 0.5f;
    Vec3 target = m_player.position + Vec3(0.0f, 1.15f, 0.0f);
    const float spread = enemy.type == EnemyType::AGENT ? 0.06f : 0.12f;
    target.x += m_rng.Float(-spread, spread) * 1.2f;
    target.z += m_rng.Float(-spread, spread) * 1.2f;
    Bullet bullet;
    bullet.position = muzzle;
    bullet.direction = NormalizeXZ(target - muzzle);
    bullet.speed = enemy.type == EnemyType::AGENT ? 26.0f : 20.0f;
    bullet.damage = enemy.type == EnemyType::AGENT ? 10.0f : 8.0f;
    bullet.life = 1.4f;
    bullet.hostile = true;
    m_bullets.push_back(bullet);
    enemy.muzzleTimer = 0.08f;
    m_audio.PlaySfx(SfxId::SHOOT);
    SpawnSparks(muzzle, MAGENTA);
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
        if (!enemy.dead && DistanceXZ(enemy.position, m_player.position) <= radius) {
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
    m_player.hitFlash = 0.25f;
    m_damageFlash = 0.75f;
    TriggerShake(0.055f, 0.16f);
    SpawnBlood(m_player.position + Vec3(0.0f, 1.1f, 0.0f));
    m_audio.PlaySfx(SfxId::HIT);
    if (m_player.hp <= 0) {
        m_player.hp = 0;
        m_mode = GameMode::DEAD;
        m_audio.PlaySfx(SfxId::DEATH);
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
    enemy.hitFlash = 0.14f;
    enemy.alerted = true;
    SpawnBlood(enemy.position + Vec3(0.0f, 1.0f, 0.0f));
    m_audio.PlaySfx(SfxId::HIT);
    if (enemy.hp <= 0.0f) {
        enemy.hp = 0.0f;
        enemy.dead = true;
        enemy.deathTimer = 0.8f;
        SpawnBlood(enemy.position + Vec3(0.0f, 0.9f, 0.0f));
        if (enemy.type == EnemyType::AGENT) {
            if (m_rng.Chance(60)) {
                SpawnPickup(PickupType::AMMO, enemy.position,
                            m_rng.Range(6, 12));
            }
            if (m_rng.Chance(45)) {
                SpawnPickup(PickupType::MONEY, enemy.position,
                            m_rng.Range(12, 26));
            }
        } else {
            if (m_rng.Chance(55)) {
                SpawnPickup(PickupType::AMMO, enemy.position,
                            m_rng.Range(5, 9));
            }
            if (m_rng.Chance(25)) {
                SpawnPickup(PickupType::MEDKIT, enemy.position, 1);
            }
            if (m_rng.Chance(30)) {
                SpawnPickup(PickupType::MONEY, enemy.position,
                            m_rng.Range(5, 14));
            }
        }
    }
}

void GameApp::SpawnBlood(Vec3 position)
{
    for (int i = 0; i < 8; ++i) {
        Particle particle;
        particle.position = position;
        particle.velocity = Vec3(m_rng.Float(-1.4f, 1.4f),
                                 m_rng.Float(0.2f, 1.6f),
                                 m_rng.Float(-1.4f, 1.4f));
        particle.life = m_rng.Float(0.25f, 0.55f);
        particle.maxLife = particle.life;
        particle.size = m_rng.Float(0.05f, 0.10f);
        particle.color = Rgba(140, 22, 34);
        particle.additive = false;
        m_particles.push_back(particle);
    }
}

void GameApp::SpawnSparks(Vec3 position, Color color)
{
    for (int i = 0; i < 6; ++i) {
        Particle particle;
        particle.position = position;
        particle.velocity = Vec3(m_rng.Float(-1.6f, 1.6f),
                                 m_rng.Float(0.1f, 1.4f),
                                 m_rng.Float(-1.6f, 1.6f));
        particle.life = m_rng.Float(0.12f, 0.3f);
        particle.maxLife = particle.life;
        particle.size = m_rng.Float(0.04f, 0.08f);
        particle.color = color;
        particle.additive = true;
        m_particles.push_back(particle);
    }
}

void GameApp::SpawnPickup(PickupType type, Vec3 position, int amount)
{
    Pickup pickup;
    pickup.type = type;
    pickup.position = position;
    pickup.amount = amount;
    pickup.bob = m_rng.Float(0.0f, 6.28f);
    m_pickups.push_back(pickup);
}

void GameApp::AddToast(const std::string& text, Color color)
{
    Toast toast;
    toast.text = text;
    toast.remaining = 3.0f;
    toast.color = color;
    m_toasts.insert(m_toasts.begin(), toast);
    while (m_toasts.size() > 4) {
        m_toasts.pop_back();
    }
}

void GameApp::TriggerShake(float intensity, float duration)
{
    m_camera.shakeIntensity = std::max(m_camera.shakeIntensity, intensity);
    m_camera.shakeDuration = std::max(m_camera.shakeDuration, duration);
    m_camera.shakeTime = std::max(m_camera.shakeTime, duration);
}

void GameApp::Render()
{
    // 后处理参数必须在覆盖层开始前设置，因为 BeginOverlay 会执行后处理。
    float glitch = m_player.hitFlash * 0.7f;
    if (m_mode == GameMode::DEAD) {
        glitch = 0.6f;
    } else if (m_alarm) {
        glitch = std::max(glitch, 0.08f);
    }
    m_device.SetPostParams(m_time, m_damageFlash, m_fadeAlpha, glitch);

    const Color clearColor = m_scene.fogColor;
    m_device.BeginFrame(clearColor);

    Player renderPlayer = m_player;
    std::vector<Enemy> emptyEnemies;
    const std::vector<Enemy>& enemies = m_hidePlayer ? emptyEnemies : m_enemies;
    const std::vector<NpcInstance> emptyNpcs;
    const std::vector<NpcInstance>& npcs = m_hidePlayer ? emptyNpcs : m_npcs;

    m_renderer.DrawScene(m_scene, renderPlayer, npcs, enemies, m_bullets,
                         m_particles, m_pickups, m_camera, m_lights, m_time,
                         !m_hidePlayer);

    SpriteBatch& batch = m_device.Batch();

    // 覆盖层：低清 3D 画面先放大到窗口，再在其上以屏幕像素密度绘制 UI。
    m_device.BeginOverlay();
    const int textScale =
        std::max(1, static_cast<int>(m_device.UiScale() + 0.5f));
    m_text.SetPixelScale(textScale);
    batch.Begin(UI_WIDTH, UI_HEIGHT, m_device.UiScale(), m_device.UiOffset(),
                m_device.UiTargetSize());

    m_renderer.DrawLightGlows(m_camera, m_lights, m_time, renderPlayer, m_alarm);
    if (!m_rain.empty()) {
        m_ui.DrawRain(m_rain);
    }

    switch (m_mode) {
    case GameMode::TITLE:
        m_ui.DrawTitle(m_time, m_muted);
        break;
    case GameMode::PLAYING: {
        m_ui.DrawHUD(m_player, m_inventory, m_quest,
                     m_hasPrompt ? m_prompt : std::string(), m_promptScreen,
                     m_device.ScreenToInternal(Input::Get().MousePosition()),
                     m_enemies, m_camera, m_renderer);
        Vec3 objective;
        Vec2 screen;
        if (ObjectiveWorldPosition(objective) &&
            m_renderer.WorldToScreen(m_camera, objective, screen)) {
            m_ui.DrawObjectiveMarker(screen, m_time, "");
        }
        float lowHealth = 0.0f;
        if (m_player.hp < PLAYER_MAX_HP * 0.35f) {
            lowHealth = 1.0f - static_cast<float>(m_player.hp) /
                                  (PLAYER_MAX_HP * 0.35f);
        }
        m_ui.DrawDamageOverlay(m_damageFlash, lowHealth * 0.8f);
        break;
    }
    case GameMode::DIALOGUE:
        m_ui.DrawDialogue(m_dialogue, m_dialogueCinematic, m_time, m_renderer,
                          Clamp(m_skipHold / SKIP_HOLD_TIME, 0.0f, 1.0f),
                          m_skipActive);
        m_ui.DrawDamageOverlay(m_damageFlash, 0.0f);
        break;
    case GameMode::SHOP:
        m_ui.DrawShop(m_inventory, m_shop, m_time, m_renderer);
        break;
    case GameMode::JOURNAL:
        m_ui.DrawJournal(m_player, m_inventory, m_quest);
        break;
    case GameMode::PAUSED:
        m_ui.DrawPause(m_inventory, m_quest);
        break;
    case GameMode::DEAD:
        m_ui.DrawDeath(m_time);
        break;
    case GameMode::EPILOGUE:
        m_ui.DrawEpilogue(m_endingChoice, m_time);
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
        if (m_locationTimer > 0.0f) {
            m_ui.DrawLocationCard(m_locationName,
                                  Clamp(m_locationTimer / 0.6f, 0.0f, 1.0f));
        }
    }
    if (m_mode == GameMode::TRANSITION) {
        m_ui.DrawFade(m_fadeAlpha);
    }

    batch.End();
}

void GameApp::DebugStartNewGame()
{
    StartNewGame();
}

void GameApp::DebugLoadScene(SceneId scene)
{
    m_inventory = Inventory();
    m_quest = QuestState();
    m_endingChoice = EndingChoice::NONE;
    m_player = Player();
    m_player.hp = PLAYER_MAX_HP;
    m_enemies.clear();
    m_bullets.clear();
    m_particles.clear();
    m_pickups.clear();
    m_toasts.clear();
    m_shop = ShopState();
    m_dialogueContext = DialogueContext::NONE;
    m_damageFlash = 0.0f;
    m_camera.shakeTime = 0.0f;
    m_titleScene = false;
    m_hidePlayer = false;

    if (scene == SceneId::BAR_EXTERIOR) {
        m_quest.main = MainStage::GO_WAREHOUSE;
        m_inventory.GiveStarterKit();
    } else if (scene == SceneId::BAR_INTERIOR) {
        m_quest.main = MainStage::TALK_BIGSISTER;
        m_inventory.GiveStarterKit();
    } else {
        m_quest.main = MainStage::FIND_CARGO;
        m_quest.side = SideStage::ACCEPTED;
        m_inventory.GiveStarterKit();
    }
    const SceneDef def = BuildScene(scene);
    LoadScene(scene, def.playerSpawn, def.playerYawDegrees);
    m_mode = GameMode::PLAYING;
}

void GameApp::DebugSetTitleMode()
{
    m_titleScene = true;
    m_hidePlayer = true;
    m_scene = BuildScene(SceneId::BAR_EXTERIOR);
    m_renderer.LoadScene(m_scene, m_collision);
    m_lights = m_scene.lights;
    m_camera.current = m_scene.cameras.front().pose;
    UpdateCameraMatrices(m_camera,
                         static_cast<float>(INTERNAL_WIDTH) /
                             static_cast<float>(INTERNAL_HEIGHT));
    m_mode = GameMode::TITLE;
}

void GameApp::DebugSetMode(GameMode mode)
{
    m_mode = mode;
}

void GameApp::DebugSetQuestStage(int main, int side)
{
    m_quest.main = static_cast<MainStage>(ClampInt(main, 0, 8));
    m_quest.side = static_cast<SideStage>(ClampInt(side, 0, 4));
}

void GameApp::DebugSetPlayerPosition(float x, float z)
{
    m_player.position = Vec3(x, 0.0f, z);
}

void GameApp::DebugShowDialogue()
{
    DebugLoadScene(SceneId::BAR_INTERIOR);
    m_quest.main = MainStage::TALK_BIGSISTER;
    StartDialogue(m_story.BuildBigSisterFirst(),
                  DialogueContext::BIGSISTER_FIRST);
    DebugAdvanceDialogue(2);
}

void GameApp::DebugShowShop()
{
    DebugLoadScene(SceneId::BAR_INTERIOR);
    m_inventory.money = 420;
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
        if (m_dialogue.IsWaitingForChoice()) {
            break;
        }
        m_dialogue.Advance();
        m_dialogue.Update(10.0f);
    }
}

void GameApp::DebugFinishDialogue()
{
    for (int i = 0; i < 400; ++i) {
        if (m_dialogue.IsFinished() || m_dialogue.IsWaitingForChoice()) {
            break;
        }
        m_dialogue.Update(10.0f);
        m_dialogue.Advance();
    }
    if (m_dialogue.IsFinished()) {
        HandleDialogueFinished();
    }
}

void GameApp::DebugChooseDialogue(int option)
{
    if (!m_dialogue.IsWaitingForChoice()) {
        return;
    }
    m_dialogue.SelectOption(option);
    m_dialogue.Confirm();
    m_dialogue.Update(10.0f);
}

void GameApp::DebugInteract(const std::string& id)
{
    HandleInteraction(id);
}

void GameApp::DebugCloseShop()
{
    if (m_mode == GameMode::SHOP) {
        CloseShop();
    }
}

void GameApp::DebugKillEnemies()
{
    for (Enemy& enemy : m_enemies) {
        enemy.dead = true;
        enemy.deathTimer = 0.01f;
    }
    m_enemies.clear();
    m_bullets.clear();
    CheckCombatProgress();
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
