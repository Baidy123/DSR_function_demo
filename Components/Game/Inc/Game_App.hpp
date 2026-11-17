#ifndef __GAME_APP_HPP__
#define __GAME_APP_HPP__

#include "Audio_System.hpp"
#include "Game_Dialogue.hpp"
#include "Game_Inventory.hpp"
#include "Game_Quest.hpp"
#include "Game_Renderer.hpp"
#include "Game_Story.hpp"
#include "Game_Types.hpp"
#include "Game_UI.hpp"
#include "Render_Device.hpp"
#include "Render_Text.hpp"
#include "Shared_Random.hpp"
#include "World_Map.hpp"

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
     * @brief 初始化渲染、资源、界面与初始状态。
     * @param [IN] hwnd 窗口句柄。
     * @param [IN] width 客户区宽度。
     * @param [IN] height 客户区高度。
     * @param [IN] artPack FCPK 资产包。
     * @param [IN] muted 是否静音启动。
     * @return 成功返回 true。
     */
    bool Initialize(HWND hwnd, int width, int height,
                    const std::vector<uint8_t>& artPack, bool muted = false);

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
     * @brief 渲染一帧到离屏目标。
     */
    void Render();

    /**
     * @brief 呈现到窗口。
     * @param [IN] vsync 是否垂直同步。
     */
    void Present(bool vsync);

    /**
     * @brief 调整客户区尺寸。
     * @param [IN] width 宽度。
     * @param [IN] height 高度。
     */
    void Resize(int width, int height);

    /**
     * @brief 是否请求退出。
     * @return 请求退出返回 true。
     */
    bool ShouldQuit() const { return m_quit; }

    /**
     * @brief 将当前离屏画面保存为 BMP。
     * @param [IN] path 输出路径。
     * @return 成功返回 true。
     */
    bool Capture(const std::string& path);

    /**
     * @brief 无头测试入口：加载指定场景并进入可操作状态。
     * @param [IN] scene 场景 ID。
     */
    void DebugLoadScene(SceneId scene);

    /**
     * @brief 无头测试入口：设置游戏模式。
     * @param [IN] mode 模式。
     */
    void DebugSetMode(GameMode mode);

    /**
     * @brief 无头测试入口：设置任务阶段。
     * @param [IN] main 主线阶段数值。
     * @param [IN] side 支线阶段数值。
     */
    void DebugSetQuestStage(int main, int side);

    /**
     * @brief 无头测试入口：设置玩家位置。
     * @param [IN] x 世界 x。
     * @param [IN] y 世界 y。
     */
    void DebugSetPlayerPosition(float x, float y);

    /**
     * @brief 无头测试入口：显示结局对话。
     */
    void DebugShowDialogue();

    /**
     * @brief 无头测试入口：显示商店。
     */
    void DebugShowShop();

    /**
     * @brief 无头测试入口：显示任务日志。
     */
    void DebugShowJournal();

    /**
     * @brief 无头测试入口：显示结局界面。
     * @param [IN] accept true 表示选择接入。
     */
    void DebugShowEnding(bool accept);

    /**
     * @brief 无头测试入口：快速推进对话节点。
     * @param [IN] steps 推进次数。
     */
    void DebugAdvanceDialogue(int steps);

    /** @brief 无头测试入口：开始新游戏。 */
    void DebugStartNewGame();

    /**
     * @brief 无头测试入口：直接执行交互。
     * @param [IN] id 交互 ID。
     */
    void DebugInteract(const std::string& id);

    /**
     * @brief 无头测试入口：选择对话选项。
     * @param [IN] option 选项索引。
     */
    void DebugChooseDialogue(int option);

    /** @brief 无头测试入口：推进到当前对话结束或选项等待。 */
    void DebugFinishDialogue();

    /** @brief 无头测试入口：关闭商店。 */
    void DebugCloseShop();

    /** @brief 无头测试入口：清除全部敌人。 */
    void DebugKillEnemies();

    /** @brief 调试查询：主线阶段。 */
    MainStage DebugMainStage() const { return m_quest.main; }

    /** @brief 调试查询：支线阶段。 */
    SideStage DebugSideStage() const { return m_quest.side; }

    /** @brief 调试查询：当前模式。 */
    GameMode DebugMode() const { return m_mode; }

    /** @brief 调试查询：当前场景。 */
    SceneId DebugScene() const { return m_currentScene; }

    /** @brief 调试查询：结局选择。 */
    EndingChoice DebugEndingChoice() const { return m_endingChoice; }

    /** @brief 调试查询：存活敌人数量。 */
    int DebugAliveEnemies() const;

    /** @brief 调试查询：信用点。 */
    int DebugMoney() const { return m_inventory.money; }

    /** @brief 调试查询：是否持有装备。 */
    bool DebugHasGear() const { return m_inventory.hasGear; }

    /** @brief 调试查询：是否持有零件。 */
    bool DebugHasPart() const { return m_inventory.hasPart; }

private:
    void StartNewGame();
    void LoadScene(SceneId scene, Vec2 spawn);
    void StartTransition(SceneId scene, Vec2 spawn);
    void StartDialogue(const Dialogue& dialogue, DialogueContext context);
    void HandleDialogueEvent(DialogueEvent event);
    void HandleDialogueFinished();
    void HandleInteraction(const std::string& id);

    void UpdatePlaying(float dt);
    void UpdateDialogue(float dt);
    void UpdateShop(float dt);
    void UpdateTransition(float dt);
    void UpdateEnemies(float dt);
    void UpdateBullets(float dt);
    void UpdateParticles(float dt);
    void UpdatePickups(float dt);
    void UpdateRain(float dt);
    void UpdateToasts(float dt);
    void UpdateCamera(float dt);
    void UpdatePrompt();
    void UpdateLocation(float dt);
    void CloseShop();

    void SpawnEnemy(EnemyType type, Vec2 position, bool alerted);
    void SpawnAmbush();
    void ApplySceneState();
    void InitRain();
    void RespawnAfterDeath();

    void FirePlayerWeapon();
    void FireEnemyWeapon(Enemy& enemy);
    void StartReload();
    void StartMedkit();
    void WakeEnemies(float radius);
    void DamagePlayer(int amount);
    void DamageEnemy(size_t index, int amount);
    void CheckCombatProgress();

    void AddToast(const std::string& text, Color color);
    void TriggerShake(float intensity, float duration);
    void SpawnBlood(Vec2 position);
    void SpawnSparks(Vec2 position, Color color);
    void SpawnPickup(PickupType type, Vec2 position, int amount);

    InteractInstance* NearestInteract(float& outDistance);

    RenderDevice m_device;
    TextRenderer m_text;
    AudioSystem m_audio;
    GameRenderer m_renderer;
    GameUI m_ui;
    Story m_story;
    WorldMap m_world;

    DialogueController m_dialogue;
    DialogueContext m_dialogueContext = DialogueContext::NONE;
    bool m_dialogueCinematic = true;

    Inventory m_inventory;
    QuestState m_quest;
    ShopState m_shop;
    EndingChoice m_endingChoice = EndingChoice::NONE;

    Player m_player;
    std::vector<Enemy> m_enemies;
    std::vector<Bullet> m_bullets;
    std::vector<Particle> m_particles;
    std::vector<Pickup> m_pickups;
    std::vector<RainDrop> m_rain;
    std::vector<Toast> m_toasts;

    Camera m_camera;
    GameMode m_mode = GameMode::TITLE;
    SceneId m_currentScene = SceneId::BAR_EXTERIOR;
    Vec2 m_checkpointSpawn;
    bool m_hasScene = false;
    bool m_alarm = false;
    bool m_quit = false;
    bool m_muted = false;

    std::string m_prompt;
    Vec2 m_promptPosition;
    bool m_hasPrompt = false;

    std::string m_locationName;
    float m_locationTimer = 0.0f;

    float m_time = 0.0f;
    float m_damageFlash = 0.0f;
    float m_shakeTimer = 0.0f;
    float m_shakeDuration = 0.0f;
    float m_shakeIntensity = 0.0f;
    Vec2 m_shakeOffset;

    bool m_transitionActive = false;
    bool m_transitionLoaded = false;
    float m_transitionTimer = 0.0f;
    float m_fadeAlpha = 0.0f;
    SceneId m_transitionScene = SceneId::BAR_EXTERIOR;
    Vec2 m_transitionSpawn;
    GameMode m_modeAfterTransition = GameMode::PLAYING;

    Rng m_rng{0xC0FFEEu};
    int m_noGearToastCooldown = 0;
};

} // namespace fc

#endif // __GAME_APP_HPP__
