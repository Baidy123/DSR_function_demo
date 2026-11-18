#ifndef __GAME_APP_HPP__
#define __GAME_APP_HPP__

#include "Audio_System.hpp"
#include "Game_Characters.hpp"
#include "Game_Dialogue.hpp"
#include "Game_Inventory.hpp"
#include "Game_Quest.hpp"
#include "Game_Renderer.hpp"
#include "Game_Story.hpp"
#include "Game_Types.hpp"
#include "Game_UI.hpp"
#include "Render_Device.hpp"
#include "Render_Mesh.hpp"
#include "Render_Text.hpp"
#include "Shared_Random.hpp"
#include "World_Collision.hpp"
#include "World_Types.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace fc {

/**
 * @brief 游戏总编排：状态机、输入、场景、实体、剧情与渲染。
 */
class GameApp {
public:
    GameApp() = default;
    ~GameApp();

    /**
     * @brief 初始化全部子系统。
     * @param [IN] hwnd 窗口句柄。
     * @param [IN] width 客户区宽度。
     * @param [IN] height 客户区高度。
     * @param [IN] meshLibraryText 拼接后的 `.fcm` 文本。
     * @param [IN] muted 是否静音启动。
     * @return 成功返回 true。
     */
    bool Initialize(HWND hwnd, int width, int height,
                    const std::string& meshLibraryText, bool muted = false);

    /**
     * @brief 释放资源。
     */
    void Shutdown();

    /**
     * @brief 推进一帧逻辑。
     * @param [IN] dt 帧间隔（秒）。
     */
    void Update(float dt);

    /**
     * @brief 渲染一帧。
     */
    void Render();

    /**
     * @brief 呈现到窗口。
     * @param [IN] vsync 是否垂直同步。
     */
    void Present(bool vsync);

    /**
     * @brief 调整客户区尺寸。
     * @param [IN] width 宽。
     * @param [IN] height 高。
     */
    void Resize(int width, int height);

    /**
     * @brief 是否请求退出。
     * @return 请求退出返回 true。
     */
    bool ShouldQuit() const { return m_quit; }

    /**
     * @brief 将当前画面保存为 BMP。
     * @param [IN] path 输出路径。
     * @return 成功返回 true。
     */
    bool Capture(const std::string& path);

    /**
     * @brief 开启/关闭截图模式。
     *
     * 开启后渲染会进入离屏大尺寸目标（含 UI），因此在隐藏窗口或无窗口焦点
     * 的情况下也能得到完整画面。
     * @param [IN] enabled 是否开启。
     */
    void SetCaptureMode(bool enabled) { m_device.SetCaptureMode(enabled); }

    // ---- 无头测试入口 ----
    void DebugLoadScene(SceneId scene);
    void DebugSetMode(GameMode mode);
    void DebugSetQuestStage(int main, int side);
    void DebugSetPlayerPosition(float x, float z);
    void DebugShowDialogue();
    void DebugShowShop();
    void DebugShowJournal();
    void DebugShowEnding(bool accept);
    void DebugAdvanceDialogue(int steps);
    void DebugFinishDialogue();
    void DebugChooseDialogue(int option);
    void DebugStartNewGame();
    void DebugInteract(const std::string& id);
    void DebugCloseShop();
    void DebugKillEnemies();
    void DebugSetTitleMode();
    void DebugSetWalkPose(bool enabled) { m_debugWalkPose = enabled; }
    void DebugSetAimPose(bool enabled) { m_debugAimPose = enabled; }
    void DebugSetMeleePose(bool enabled) { m_debugMeleePose = enabled; }

    MainStage DebugMainStage() const { return m_quest.main; }
    SideStage DebugSideStage() const { return m_quest.side; }
    GameMode DebugMode() const { return m_mode; }
    SceneId DebugScene() const { return m_scene.id; }
    EndingChoice DebugEndingChoice() const { return m_endingChoice; }
    int DebugAliveEnemies() const;
    int DebugMoney() const { return m_inventory.money; }
    bool DebugHasGear() const { return m_inventory.hasGear; }
    bool DebugHasPart() const { return m_inventory.hasPart; }
    bool DebugHasCargo() const { return m_inventory.hasCargo; }

private:
    void StartNewGame();
    void LoadScene(SceneId id, Vec3 spawn, float yawDegrees);
    void StartTransition(SceneId id, Vec3 spawn, float yawDegrees);
    void StartDialogue(const Dialogue& dialogue, DialogueContext context);
    void HandleDialogueEvent(DialogueEvent event);
    void HandleDialogueFinished();
    void HandleInteraction(const std::string& id);
    void CloseShop();
    void BuildNpcs();
    void RefreshLights();

    void UpdatePlaying(float dt);
    void UpdateDialogue(float dt);
    void UpdateShop(float dt);
    void UpdateTransition(float dt);
    void UpdateTitle(float dt);
    void UpdateEnemies(float dt);
    void UpdateBullets(float dt);
    void UpdateParticles(float dt);
    void UpdatePickups(float dt);
    void UpdateRain(float dt);
    void UpdateToasts(float dt);
    void UpdateCamera(float dt);
    void UpdatePrompt();

    void FirePlayerWeapon();
    void MeleeAttack();
    void FireEnemyWeapon(Enemy& enemy);
    void StartReload();
    void StartMedkit();
    void WakeEnemies(float radius);
    void DamagePlayer(int amount);
    void DamageEnemy(size_t index, int amount);
    void CheckCombatProgress();

    void SpawnEnemy(EnemyType type, Vec3 position, float yawDegrees, bool alerted);
    void SpawnAmbush();
    void SpawnBlood(Vec3 position);
    void SpawnSparks(Vec3 position, Color color);
    void SpawnPickup(PickupType type, Vec3 position, int amount);
    void AddToast(const std::string& text, Color color);
    void TriggerShake(float intensity, float duration);
    void InitRain();
    void RespawnAfterDeath();

    Vec3 ScreenRayDirection(Vec2 screen) const;
    Vec3 AimPointFromMouse(Vec2 mouse) const;
    bool HasLineOfSight(const Vec3& from, const Vec3& to) const;
    const InteractDef* NearestInteract(float& outDistance) const;
    bool ObjectiveWorldPosition(Vec3& out) const;

    RenderDevice m_device;
    TextRenderer m_text;
    AudioSystem m_audio;
    MeshLibrary m_meshes;
    CharacterLibrary m_characters;
    GameRenderer m_renderer;
    GameUI m_ui;
    Story m_story;
    CollisionWorld m_collision;

    SceneDef m_scene;
    std::vector<LightDef> m_lights;
    std::vector<NpcInstance> m_npcs;
    std::vector<InteractDef> m_interactions;

    Player m_player;
    std::vector<Enemy> m_enemies;
    std::vector<Bullet> m_bullets;
    std::vector<Particle> m_particles;
    std::vector<Pickup> m_pickups;
    std::vector<RainDrop> m_rain;
    std::vector<Toast> m_toasts;

    Inventory m_inventory;
    QuestState m_quest;
    ShopState m_shop;
    EndingChoice m_endingChoice = EndingChoice::NONE;

    DialogueController m_dialogue;
    DialogueContext m_dialogueContext = DialogueContext::NONE;
    bool m_dialogueCinematic = true;
    float m_skipHold = 0.0f;       ///< Ctrl 按住累计时间。
    float m_skipTick = 0.0f;       ///< 快进推进间隔计时。
    bool m_skipActive = false;     ///< 是否已进入快进。

    CameraRuntime m_camera;
    CameraPose m_cameraStart;
    CameraPose m_cameraTarget;
    Vec3 m_cameraFollow;
    float m_cameraBlend = 1.0f;
    int m_cameraZone = -1;

    GameMode m_mode = GameMode::TITLE;
    GameMode m_modeAfterTransition = GameMode::PLAYING;
    bool m_transitionActive = false;
    bool m_transitionLoaded = false;
    float m_transitionTimer = 0.0f;
    float m_fadeAlpha = 0.0f;
    SceneId m_transitionScene = SceneId::BAR_EXTERIOR;
    Vec3 m_transitionSpawn;
    float m_transitionYaw = 180.0f;

    Vec3 m_checkpointSpawn;
    float m_checkpointYaw = 180.0f;

    std::string m_prompt;
    Vec2 m_promptScreen;
    bool m_hasPrompt = false;

    std::string m_locationName;
    float m_locationTimer = 0.0f;

    float m_time = 0.0f;
    float m_damageFlash = 0.0f;
    bool m_alarm = false;
    bool m_quit = false;
    bool m_muted = false;
    bool m_titleScene = false;
    bool m_hasScene = false;
    bool m_hidePlayer = false;
    bool m_debugWalkPose = false;
    bool m_debugAimPose = false;
    bool m_debugMeleePose = false;

    int m_noGearToastCooldown = 0;
    Rng m_rng{0x51EEDu};
};

} // namespace fc

#endif // __GAME_APP_HPP__
