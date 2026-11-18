#ifndef __GAME_UI_HPP__
#define __GAME_UI_HPP__

#include "Game_Dialogue.hpp"
#include "Game_Inventory.hpp"
#include "Game_Quest.hpp"
#include "Game_Renderer.hpp"
#include "Game_Types.hpp"
#include "Shared_Types.hpp"

#include <string>
#include <vector>

namespace fc {

class RenderDevice;
class TextRenderer;

/**
 * @brief 低分辨率终端风 UI：HUD、对话、商店、日志、标题与结局。
 *
 * 所有图形由矩形与文字拼装，不依赖任何图片资产；角色头像由 3D 胸像
 * 渲染到纹理后复用。
 */
class GameUI {
public:
    /**
     * @brief 初始化。
     * @param [IN] device 渲染设备。
     * @param [IN] text 文字渲染器。
     * @param [IN] renderer 场景渲染器（用于头像）。
     * @return 成功返回 true。
     */
    bool Initialize(RenderDevice* device, TextRenderer* text,
                    GameRenderer* renderer);

    /** @brief 绘制 HUD。 */
    void DrawHUD(const Player& player, const Inventory& inventory,
                 const QuestState& quest, const std::string& prompt,
                 Vec2 promptScreen, Vec2 mouse,
                 const std::vector<Enemy>& enemies,
                 const CameraRuntime& camera, const GameRenderer& renderer);

    /**
     * @brief 绘制对话框。
     * @param [IN] dialogue 对话控制器。
     * @param [IN] cinematic 是否显示上下黑边。
     * @param [IN] time 累计时间。
     * @param [IN] renderer 场景渲染器（头像）。
     * @param [IN] skipProgress 按住 Ctrl 的进度（0–1）。
     * @param [IN] skipping 是否已经处于快进状态。
     */
    void DrawDialogue(const DialogueController& dialogue, bool cinematic,
                      float time, const GameRenderer& renderer,
                      float skipProgress = 0.0f, bool skipping = false);

    /** @brief 绘制商店。 */
    void DrawShop(const Inventory& inventory, const ShopState& shop,
                  float time, const GameRenderer& renderer);

    /** @brief 绘制任务日志。 */
    void DrawJournal(const Player& player, const Inventory& inventory,
                     const QuestState& quest);

    /** @brief 绘制标题。 */
    void DrawTitle(float time, bool muted);

    /** @brief 绘制结局。 */
    void DrawEpilogue(EndingChoice choice, float time);

    /** @brief 绘制死亡界面。 */
    void DrawDeath(float time);

    /** @brief 绘制暂停界面。 */
    void DrawPause(const Inventory& inventory, const QuestState& quest);

    /** @brief 绘制提示队列。 */
    void DrawToasts(const std::vector<Toast>& toasts);

    /** @brief 绘制淡入淡出。 */
    void DrawFade(float alpha);

    /** @brief 绘制准星。 */
    void DrawCrosshair(Vec2 mouse, bool highlight);

    /** @brief 绘制地点卡片。 */
    void DrawLocationCard(const std::string& name, float alpha);

    /** @brief 绘制雨幕（屏幕空间）。 */
    void DrawRain(const std::vector<RainDrop>& drops);

    /** @brief 绘制交互目标标记。 */
    void DrawObjectiveMarker(Vec2 screen, float time, const std::string& label);

    /** @brief 绘制受击红闪与暗角（后处理之外的低频叠加）。 */
    void DrawDamageOverlay(float damage, float lowHealth);

private:
    void Panel(const RectF& rect, Color fill, Color border);
    void Text(const std::string& utf8, float x, float y, int px, int maxWidth,
              Color color, int visibleUnits = 0x7FFFFFFF);
    int TextHeight(const std::string& utf8, int px, int maxWidth);
    int TextWidth(const std::string& utf8, int px, int maxWidth);
    void TextCentered(const std::string& utf8, float centerX, float y, int px,
                      int maxWidth, Color color);
    Color SpeakerColor(const std::string& speaker) const;
    void DrawIcon(int type, float x, float y, float size, Color color);
    void DrawPortrait(const std::string& portrait, float x, float y, float size,
                      const GameRenderer& renderer);

    RenderDevice* m_device = nullptr;
    TextRenderer* m_text = nullptr;
    GameRenderer* m_renderer = nullptr;
};

} // namespace fc

#endif // __GAME_UI_HPP__
