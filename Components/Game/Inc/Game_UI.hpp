#ifndef __GAME_UI_HPP__
#define __GAME_UI_HPP__

#include "Game_Dialogue.hpp"
#include "Game_Inventory.hpp"
#include "Game_Quest.hpp"
#include "Game_Types.hpp"
#include "Shared_Types.hpp"

#include <string>
#include <vector>

namespace fc {

class RenderDevice;
class TextRenderer;

/**
 * @brief 全部界面绘制：HUD、对话、商店、日志、标题、结局、提示。
 */
class GameUI {
public:
    /**
     * @brief 初始化。
     * @param [IN] device 渲染设备。
     * @param [IN] text 文字渲染器。
     * @return 成功返回 true。
     */
    bool Initialize(RenderDevice* device, TextRenderer* text);

    /**
     * @brief 绘制 HUD。
     * @param [IN] player 玩家。
     * @param [IN] inventory 背包。
     * @param [IN] quest 任务。
     * @param [IN] prompt 交互提示；空串表示不显示。
     * @param [IN] promptX 提示中心 x（内部坐标）。
     * @param [IN] promptY 提示中心 y（内部坐标）。
     * @param [IN] mouse 鼠标内部坐标。
     */
    void DrawHUD(const Player& player, const Inventory& inventory,
                 const QuestState& quest, const std::string& prompt,
                 float promptX, float promptY, Vec2 mouse);

    /**
     * @brief 绘制对话框。
     * @param [IN] dialogue 对话控制器。
     * @param [IN] cinematic 是否绘制黑边。
     * @param [IN] time 累计时间（用于闪烁）。
     */
    void DrawDialogue(const DialogueController& dialogue, bool cinematic,
                      float time);

    /**
     * @brief 绘制商店。
     * @param [IN] inventory 背包。
     * @param [IN] shop 商店状态。
     * @param [IN] time 累计时间。
     */
    void DrawShop(const Inventory& inventory, const ShopState& shop, float time);

    /**
     * @brief 绘制任务日志。
     * @param [IN] player 玩家。
     * @param [IN] inventory 背包。
     * @param [IN] quest 任务。
     */
    void DrawJournal(const Player& player, const Inventory& inventory,
                     const QuestState& quest);

    /**
     * @brief 绘制标题界面。
     * @param [IN] time 累计时间。
     * @param [IN] muted 是否静音。
     */
    void DrawTitle(float time, bool muted);

    /**
     * @brief 绘制结局界面。
     * @param [IN] choice 结局选择。
     * @param [IN] time 累计时间。
     */
    void DrawEpilogue(EndingChoice choice, float time);

    /**
     * @brief 绘制死亡界面。
     * @param [IN] time 累计时间。
     */
    void DrawDeath(float time);

    /**
     * @brief 绘制暂停界面。
     * @param [IN] inventory 背包。
     * @param [IN] quest 任务。
     */
    void DrawPause(const Inventory& inventory, const QuestState& quest);

    /**
     * @brief 绘制提示队列。
     * @param [IN] toasts 提示列表。
     */
    void DrawToasts(const std::vector<Toast>& toasts);

    /**
     * @brief 绘制淡入淡出遮罩。
     * @param [IN] alpha 不透明度（0–1）。
     */
    void DrawFade(float alpha);

    /**
     * @brief 绘制准星。
     * @param [IN] mouse 鼠标内部坐标。
     * @param [IN] highlight 是否高亮（靠近交互物）。
     */
    void DrawCrosshair(Vec2 mouse, bool highlight);

    /**
     * @brief 绘制场景地点卡片。
     * @param [IN] name 地点名。
     * @param [IN] alpha 不透明度。
     */
    void DrawLocationCard(const std::string& name, float alpha);

private:
    void Panel(const RectF& rect, Color fill, Color border);
    void Text(const std::string& utf8, float x, float y, int px, int maxWidth,
              Color color, int visibleUnits = 0x7FFFFFFF, bool shadow = true);
    int TextHeight(const std::string& utf8, int px, int maxWidth);
    int TextWidth(const std::string& utf8, int px, int maxWidth);
    void TextCentered(const std::string& utf8, float centerX, float y, int px,
                      int maxWidth, Color color);
    Color SpeakerColor(const std::string& speaker) const;
    void DrawItemIcon(const char* name, float x, float y);

    RenderDevice* m_device = nullptr;
    TextRenderer* m_text = nullptr;
};

} // namespace fc

#endif // __GAME_UI_HPP__
