#include "Game_UI.hpp"

#include "Render_Device.hpp"
#include "Render_Text.hpp"
#include "Shared_Math.hpp"

#include <algorithm>
#include <climits>
#include <cmath>

namespace fc {

namespace {

const Color BONE = Rgba(232, 227, 214);
const Color DIM = Rgba(132, 152, 154);
const Color CYAN = Rgba(57, 224, 208);
const Color AMBER = Rgba(255, 179, 71);
const Color MAGENTA = Rgba(255, 61, 139);
const Color RED = Rgba(220, 60, 72);
const Color PANEL_FILL = Rgba(7, 10, 15, 178);
const Color PANEL_BORDER = Rgba(57, 224, 208, 90);

struct ShopRow {
    const char* name;
    const char* description;
    const char* icon;
    int price;
};

const ShopRow SHOP_ROWS[4] = {
    {"9mm 弹药 ×12", "补充备弹，最多携带 99 发。", "UI_ICON_AMMO", 18},
    {"医疗包", "恢复 40 生命，最多携带 3 个。", "UI_ICON_MEDKIT", 35},
    {"能量饮料", "立刻恢复 20 生命。", "UI_ICON_HEALTH", 12},
    {"思维接入装置", "未登记神经桥。接入自由城网络。", "UI_ICON_JACK", 1500}
};

} // namespace

bool GameUI::Initialize(RenderDevice* device, TextRenderer* text)
{
    m_device = device;
    m_text = text;
    return m_device != nullptr && m_text != nullptr;
}

void GameUI::Panel(const RectF& rect, Color fill, Color border)
{
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), rect.x, rect.y,
                                 rect.w, rect.h, fill);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), rect.x, rect.y,
                                 rect.w, 1.0f, border);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), rect.x,
                                 rect.Bottom() - 1.0f, rect.w, 1.0f, border);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), rect.x, rect.y,
                                 1.0f, rect.h, border);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(),
                                 rect.Right() - 1.0f, rect.y, 1.0f, rect.h,
                                 border);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), rect.x + 2.0f,
                                 rect.y + 2.0f, 7.0f, 1.0f, CYAN);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), rect.x + 2.0f,
                                 rect.y + 2.0f, 1.0f, 7.0f, CYAN);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(),
                                 rect.Right() - 9.0f, rect.y + 2.0f, 7.0f,
                                 1.0f, CYAN);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(),
                                 rect.Right() - 3.0f, rect.y + 2.0f, 1.0f,
                                 7.0f, CYAN);
}

void GameUI::Text(const std::string& utf8, float x, float y, int px,
                  int maxWidth, Color color, int visibleUnits, bool shadow)
{
    const TextBlock* block = m_text->Get(utf8, px, maxWidth);
    if (block == nullptr) {
        return;
    }
    m_text->Draw(m_device->Batch(), *block, x, y, color, visibleUnits, shadow);
}

int GameUI::TextHeight(const std::string& utf8, int px, int maxWidth)
{
    const TextBlock* block = m_text->Get(utf8, px, maxWidth);
    return block != nullptr ? block->height : 0;
}

int GameUI::TextWidth(const std::string& utf8, int px, int maxWidth)
{
    const TextBlock* block = m_text->Get(utf8, px, maxWidth);
    return block != nullptr ? block->width : 0;
}

void GameUI::TextCentered(const std::string& utf8, float centerX, float y,
                          int px, int maxWidth, Color color)
{
    const int width = TextWidth(utf8, px, maxWidth);
    Text(utf8, centerX - static_cast<float>(width) * 0.5f, y, px, maxWidth,
         color);
}

void GameUI::DrawItemIcon(const char* name, float x, float y)
{
    const Sprite* sprite = m_device->FindSprite(name);
    if (sprite != nullptr && sprite->texture != nullptr) {
        m_device->Batch().DrawSprite(*sprite, x, y, 12.0f, 12.0f,
                                     Color(1.0f, 1.0f, 1.0f, 1.0f));
    }
}

Color GameUI::SpeakerColor(const std::string& speaker) const
{
    if (speaker == "大美") {
        return AMBER;
    }
    if (speaker == "东子") {
        return Rgba(230, 200, 90);
    }
    if (speaker == "小帅") {
        return Rgba(230, 222, 205);
    }
    if (speaker == "特工") {
        return MAGENTA;
    }
    if (speaker == "小明") {
        return Rgba(127, 216, 207);
    }
    return DIM;
}

void GameUI::DrawHUD(const Player& player, const Inventory& inventory,
                     const QuestState& quest, const std::string& prompt,
                     float promptX, float promptY, Vec2 mouse)
{
    const std::string mainObjective = MainObjective(quest);
    const std::string sideObjective = SideObjective(quest);
    const int mainHeight = TextHeight(mainObjective, 11, 266);
    const int sideHeight = sideObjective.empty()
                               ? 0
                               : TextHeight(sideObjective, 10, 266);
    const float panelHeight = 14.0f + static_cast<float>(mainHeight) +
                              (sideHeight > 0 ? 14.0f + sideHeight : 0.0f) +
                              10.0f;
    Panel(RectF(6.0f, 6.0f, 292.0f, panelHeight), PANEL_FILL, PANEL_BORDER);
    Text("当前目标", 14.0f, 9.0f, 9, 200, AMBER);
    Text(mainObjective, 14.0f, 21.0f, 11, 266, BONE);
    if (!sideObjective.empty()) {
        const float sideY = 23.0f + static_cast<float>(mainHeight);
        Text("支线", 14.0f, sideY, 9, 200, CYAN);
        Text(sideObjective, 14.0f, sideY + 10.0f, 10, 266,
             Rgba(150, 210, 205));
    }

    Panel(RectF(480.0f - 108.0f, 6.0f, 102.0f, 22.0f), PANEL_FILL,
          PANEL_BORDER);
    DrawItemIcon("UI_ICON_CREDIT", 480.0f - 102.0f, 11.0f);
    Text(std::to_string(inventory.money), 480.0f - 86.0f, 9.0f, 11, 80,
         Rgba(240, 205, 120));

    Panel(RectF(6.0f, 204.0f, 216.0f, 62.0f), PANEL_FILL, PANEL_BORDER);
    const Sprite* portrait = m_device->FindSprite("PORTRAIT_PLAYER");
    if (portrait != nullptr && portrait->texture != nullptr) {
        m_device->Batch().DrawSprite(*portrait, 10.0f, 210.0f, 48.0f, 48.0f,
                                     Color(1.0f, 1.0f, 1.0f, 1.0f));
    }
    Text("小明", 64.0f, 208.0f, 10, 80, Rgba(127, 216, 207));
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 64.0f, 224.0f, 122.0f,
                                 6.0f, Rgba(30, 38, 44, 220));
    const float hpRatio = Clamp(static_cast<float>(player.hp) /
                                    static_cast<float>(PLAYER_MAX_HP),
                                0.0f, 1.0f);
    const Color hpColor = hpRatio < 0.3f ? RED : Rgba(70, 200, 160);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 65.0f, 225.0f,
                                 120.0f * hpRatio, 4.0f, hpColor);
    Text(std::to_string(player.hp) + "/" + std::to_string(PLAYER_MAX_HP),
         184.0f, 216.0f, 9, 38, DIM);
    DrawItemIcon("UI_ICON_AMMO", 64.0f, 236.0f);
    Text(std::to_string(inventory.ammoMag) + " / " +
             std::to_string(inventory.ammoReserve),
         80.0f, 234.0f, 10, 80, BONE);
    DrawItemIcon("UI_ICON_MEDKIT", 150.0f, 236.0f);
    Text("×" + std::to_string(inventory.medkits), 166.0f, 234.0f, 10, 40,
         BONE);

    if (player.reloading) {
        Text("装填中……", 64.0f, 247.0f, 9, 100, AMBER);
    } else if (player.usingMedkit) {
        Text("使用医疗包……", 64.0f, 247.0f, 9, 100, AMBER);
    } else if (!inventory.hasGear) {
        Text("尚未装备武器", 64.0f, 247.0f, 9, 100, DIM);
    }

    if (!prompt.empty()) {
        const int width = TextWidth(prompt, 10, 200) + 16;
        float x = promptX - static_cast<float>(width) * 0.5f;
        x = Clamp(x, 4.0f, 476.0f - static_cast<float>(width));
        const float y = Clamp(promptY - 36.0f, 6.0f, 230.0f);
        Panel(RectF(x, y, static_cast<float>(width), 20.0f),
              Rgba(5, 10, 14, 226), Rgba(255, 179, 71, 110));
        Text(prompt, x + 8.0f, y + 4.0f, 10, 200, AMBER);
    }

    DrawCrosshair(mouse, !prompt.empty());
}

void GameUI::DrawDialogue(const DialogueController& dialogue, bool cinematic,
                          float time)
{
    const DialogueNode* node = dialogue.Current();
    if (node == nullptr) {
        return;
    }

    if (cinematic) {
        m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 0.0f,
                                     480.0f, 16.0f, Rgba(0, 0, 0, 210));
        m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 254.0f,
                                     480.0f, 16.0f, Rgba(0, 0, 0, 210));
    }

    const bool hasPortrait = !node->portrait.empty();
    const float textX = hasPortrait ? 74.0f : 20.0f;
    const int maxWidth = static_cast<int>(480.0f - 16.0f - textX);
    const int textHeight = TextHeight(node->text, 12, maxWidth);
    const int optionCount = static_cast<int>(node->options.size());
    const int optionsHeight = optionCount > 0 ? 6 + optionCount * 16 : 0;
    float boxHeight = 36.0f + static_cast<float>(textHeight) +
                      static_cast<float>(optionsHeight) + 12.0f;
    boxHeight = Clamp(boxHeight, 88.0f, 178.0f);
    const float boxBottom = cinematic ? 252.0f : 262.0f;
    const float boxY = boxBottom - boxHeight;
    const float boxX = 8.0f;
    const float boxW = 464.0f;

    Panel(RectF(boxX, boxY, boxW, boxHeight), Rgba(6, 10, 14, 238),
          Rgba(57, 224, 208, 130));

    if (hasPortrait) {
        const Sprite* portrait = m_device->FindSprite(node->portrait.c_str());
        if (portrait != nullptr && portrait->texture != nullptr) {
            m_device->Batch().DrawSprite(*portrait, boxX + 10.0f, boxY + 10.0f,
                                         48.0f, 48.0f,
                                         Color(1.0f, 1.0f, 1.0f, 1.0f));
        }
    }

    float textY = boxY + 10.0f;
    if (!node->speaker.empty()) {
        Text(node->speaker, textX, boxY + 7.0f, 12, maxWidth,
             SpeakerColor(node->speaker));
        textY = boxY + 25.0f;
    }
    Text(node->text, textX, textY, 12, maxWidth, BONE,
         dialogue.VisibleUnits(), true);

    if (dialogue.IsTextComplete() && optionCount > 0) {
        const float optionY = textY + static_cast<float>(textHeight) + 4.0f;
        for (int i = 0; i < optionCount; ++i) {
            const float rowY = optionY + static_cast<float>(i) * 16.0f;
            if (i == dialogue.SelectedOption()) {
                m_device->Batch().DrawSprite(m_device->WhiteSprite(), boxX + 14.0f,
                                             rowY - 2.0f, boxW - 28.0f, 15.0f,
                                             Rgba(255, 179, 71, 38));
                Text(">", boxX + 16.0f, rowY, 11, 10, AMBER);
            }
            Text(node->options[static_cast<size_t>(i)].text, boxX + 28.0f,
                 rowY, 11, static_cast<int>(boxW - 48.0f),
                 i == dialogue.SelectedOption() ? AMBER : BONE);
        }
        Text("W/S 选择   E 确认", boxX + boxW - 132.0f,
             boxY + boxHeight - 14.0f, 9, 130, DIM);
    } else if (dialogue.IsTextComplete()) {
        const float blink = 0.55f + 0.45f * std::sin(time * 6.0f);
        Text("▼", boxX + boxW - 24.0f, boxY + boxHeight - 20.0f, 12, 20,
             Color(1.0f, 0.75f, 0.35f, blink));
    }
}

void GameUI::DrawShop(const Inventory& inventory, const ShopState& shop,
                      float time)
{
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 0.0f, 480.0f,
                                 270.0f, Rgba(0, 0, 0, 150));
    const RectF panel(20.0f, 14.0f, 440.0f, 242.0f);
    Panel(panel, PANEL_FILL, PANEL_BORDER);

    const Sprite* portrait = m_device->FindSprite("PORTRAIT_MERCHANT");
    if (portrait != nullptr && portrait->texture != nullptr) {
        m_device->Batch().DrawSprite(*portrait, 30.0f, 24.0f, 48.0f, 48.0f,
                                     Color(1.0f, 1.0f, 1.0f, 1.0f));
    }
    Text("东子", 88.0f, 28.0f, 14, 120, Rgba(230, 200, 90));
    Text("地下商人 · 旧城区", 88.0f, 48.0f, 9, 200, DIM);
    Text("₡ " + std::to_string(inventory.money), 350.0f, 30.0f, 12, 90,
         Rgba(240, 205, 120));
    Text("信用点", 350.0f, 46.0f, 9, 90, DIM);
    if (shop.browseOnly) {
        Text("首次交易：仅可浏览", 288.0f, 60.0f, 9, 160, AMBER);
    }

    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 30.0f, 80.0f, 420.0f,
                                 1.0f, Rgba(57, 224, 208, 70));

    const int selected = ClampInt(shop.selected, 0, 3);
    for (int i = 0; i < 4; ++i) {
        const float rowY = 86.0f + static_cast<float>(i) * 34.0f;
        if (i == selected) {
            m_device->Batch().DrawSprite(m_device->WhiteSprite(), 28.0f,
                                         rowY - 2.0f, 424.0f, 32.0f,
                                         Rgba(255, 179, 71, 26));
            m_device->Batch().DrawSprite(m_device->WhiteSprite(), 28.0f,
                                         rowY - 2.0f, 3.0f, 32.0f, AMBER);
        }
        DrawItemIcon(SHOP_ROWS[i].icon, 38.0f, rowY + 1.0f);
        Text(SHOP_ROWS[i].name, 58.0f, rowY, 12, 250,
             i == selected ? BONE : Rgba(190, 190, 180));
        Text(SHOP_ROWS[i].description, 58.0f, rowY + 15.0f, 9, 260, DIM);
        const std::string price = "₡ " + std::to_string(SHOP_ROWS[i].price);
        const bool affordable = inventory.CanAfford(SHOP_ROWS[i].price) &&
                                i != 3;
        Text(price, 420.0f - static_cast<float>(TextWidth(price, 11, 80)),
             rowY + 2.0f, 11, 80,
             affordable ? Rgba(240, 205, 120) : Rgba(210, 90, 90));
    }

    if (!shop.message.empty()) {
        const Color color = shop.message.find("不足") != std::string::npos ||
                                    shop.message.find("满") != std::string::npos ||
                                    shop.message.find("不是") != std::string::npos
                                ? RED
                                : Rgba(90, 220, 160);
        const int width = TextWidth(shop.message, 10, 380);
        Text(shop.message, 240.0f - static_cast<float>(width) * 0.5f,
             228.0f, 10, 400, color);
    }

    Text("W/S 选择   E 购买   Esc 离开", 28.0f, 244.0f, 9, 300, DIM);
    const float pulse = 0.7f + 0.3f * std::sin(time * 4.0f);
    Text("东子：钱到位，什么都好说。", 286.0f, 244.0f, 9, 180,
         Color(0.9f, 0.8f, 0.4f, pulse));
}

void GameUI::DrawJournal(const Player& player, const Inventory& inventory,
                         const QuestState& quest)
{
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 0.0f, 480.0f,
                                 270.0f, Rgba(0, 0, 0, 165));
    Panel(RectF(28.0f, 16.0f, 424.0f, 238.0f), PANEL_FILL, PANEL_BORDER);
    Text("任务日志", 44.0f, 26.0f, 14, 200, CYAN);

    Text("主线", 44.0f, 50.0f, 9, 100, AMBER);
    Text(MainObjective(quest), 44.0f, 61.0f, 11, 392, BONE);
    const std::string side = SideObjective(quest);
    if (IsSideQuestVisible(quest)) {
        Text("支线", 44.0f, 84.0f, 9, 100, CYAN);
        Text(side, 44.0f, 95.0f, 11, 392, Rgba(150, 210, 205));
    }

    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 44.0f, 118.0f, 384.0f,
                                 1.0f, Rgba(57, 224, 208, 60));
    Text("随身物品", 44.0f, 126.0f, 11, 160, AMBER);
    Text("信用点：" + std::to_string(inventory.money), 44.0f, 144.0f, 10, 180,
         Rgba(240, 205, 120));
    Text("9mm 弹药：" + std::to_string(inventory.ammoMag) + " / " +
             std::to_string(inventory.ammoReserve),
         44.0f, 158.0f, 10, 220, BONE);
    Text("医疗包：" + std::to_string(inventory.medkits), 44.0f, 172.0f, 10, 180,
         BONE);
    Text(inventory.hasCargo ? "货物：大姐头的箱子（在携带）" : "货物：尚未取得",
         44.0f, 186.0f, 10, 300,
         inventory.hasCargo ? Rgba(150, 210, 205) : DIM);
    Text(inventory.hasPart ? "旧零件：点唱机的唱针组件" : "旧零件：未找到",
         44.0f, 200.0f, 10, 300, inventory.hasPart ? Rgba(150, 210, 205) : DIM);

    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 44.0f, 218.0f, 384.0f,
                                 1.0f, Rgba(57, 224, 208, 60));
    Text("操作", 44.0f, 224.0f, 9, 100, DIM);
    Text("WASD 移动   鼠标瞄准   左键射击   R 装填   E 交互", 44.0f, 236.0f, 9,
         392, BONE);
    Text("F 医疗包   Tab 日志   M 静音   Esc 暂停", 44.0f, 248.0f, 9, 392,
         BONE);
    Text("生命 " + std::to_string(player.hp) + " / " +
             std::to_string(PLAYER_MAX_HP),
         360.0f, 126.0f, 10, 80, DIM);
}

void GameUI::DrawTitle(float time, bool muted)
{
    const Sprite* background = m_device->FindSprite("UI_TITLE_BG");
    if (background != nullptr && background->texture != nullptr) {
        m_device->Batch().DrawSprite(*background, 0.0f, 0.0f, 480.0f, 270.0f,
                                     Color(1.0f, 1.0f, 1.0f, 1.0f));
    }
    const Sprite* logo = m_device->FindSprite("UI_TITLE_LOGO");
    if (logo != nullptr && logo->texture != nullptr) {
        m_device->Batch().DrawSprite(*logo, 120.0f, 64.0f, 240.0f, 64.0f,
                                     Color(1.0f, 1.0f, 1.0f, 1.0f));
    }
    TextCentered("余烬自由城", 240.0f, 138.0f, 16, 300, BONE);
    TextCentered("A FREE CITY STORY", 240.0f, 160.0f, 9, 300, DIM);
    const float blink = 0.80f + 0.20f * std::sin(time * 4.0f);
    TextCentered("按 Enter 开始", 240.0f, 220.0f, 12, 300,
                 Color(1.0f, 0.75f, 0.35f, blink));
    TextCentered("WASD 移动 · 鼠标瞄准 · E 交互 · M 静音", 240.0f, 246.0f, 9,
                 420, DIM);
    if (muted) {
        Text("静音", 430.0f, 8.0f, 9, 40, MAGENTA);
    }
}

void GameUI::DrawEpilogue(EndingChoice choice, float time)
{
    const Sprite* background = m_device->FindSprite("UI_ENDING_BG");
    if (background != nullptr && background->texture != nullptr) {
        m_device->Batch().DrawSprite(*background, 0.0f, 0.0f, 480.0f, 270.0f,
                                     Color(1.0f, 1.0f, 1.0f, 1.0f));
    }
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 0.0f, 480.0f,
                                 270.0f, Rgba(5, 6, 9, 110));
    TextCentered("DEMO 结束", 240.0f, 46.0f, 18, 360, BONE);
    TextCentered("余烬自由城", 240.0f, 72.0f, 13, 300, AMBER);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 140.0f, 92.0f, 200.0f,
                                 1.0f, Rgba(255, 179, 71, 90));

    const char* lines = (choice == EndingChoice::ACCEPT)
                            ? "我把那枚东西攥在手里，很轻，像一枚硬币。\n从明天起，自由城会看见我。\n我只希望，它看见的仍然是我。"
                            : "我把手收了回来。\n不是不想要。只是还没想好，要用什么来换。\n雨还在下。至少今晚，我还知道自己是谁。";
    Text(lines, 70.0f, 112.0f, 11, 340, BONE);
    const float blink = 0.80f + 0.20f * std::sin(time * 4.0f);
    TextCentered("Enter 重新开始　·　Esc 返回标题", 240.0f, 228.0f, 10, 420,
                 Color(1.0f, 0.75f, 0.35f, blink));
    TextCentered("感谢游玩", 240.0f, 244.0f, 9, 200, DIM);
}

void GameUI::DrawDeath(float time)
{
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 0.0f, 480.0f,
                                 270.0f, Rgba(20, 2, 4, 175));
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 0.0f, 480.0f,
                                 270.0f, Rgba(120, 10, 20, 30));
    TextCentered("连接中断", 240.0f, 82.0f, 20, 300, RED);
    TextCentered("你倒在了铁港的雨里。", 240.0f, 116.0f, 11, 400, BONE);
    const float blink = 0.55f + 0.45f * std::sin(time * 4.0f);
    TextCentered("Enter 从检查点重试", 240.0f, 168.0f, 11, 400,
                 Color(1.0f, 0.75f, 0.35f, blink));
    TextCentered("Esc 返回标题", 240.0f, 186.0f, 10, 300, DIM);
}

void GameUI::DrawPause(const Inventory& inventory, const QuestState& quest)
{
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 0.0f, 480.0f,
                                 270.0f, Rgba(0, 0, 0, 160));
    Panel(RectF(90.0f, 44.0f, 300.0f, 182.0f), PANEL_FILL, PANEL_BORDER);
    TextCentered("暂停", 240.0f, 56.0f, 16, 200, BONE);
    Text("目标：" + MainObjective(quest), 108.0f, 86.0f, 10, 264, AMBER);
    Text("信用点：" + std::to_string(inventory.money), 108.0f, 104.0f, 10, 200,
         Rgba(240, 205, 120));
    Text("WASD 移动　鼠标瞄准　左键射击", 108.0f, 126.0f, 9, 264, BONE);
    Text("R 装填　E 交互　F 医疗包", 108.0f, 140.0f, 9, 264, BONE);
    Text("Tab 日志　M 静音　Esc 继续", 108.0f, 154.0f, 9, 264, BONE);
    TextCentered("Esc 继续　·　Q 返回标题", 240.0f, 196.0f, 10, 260, AMBER);
}

void GameUI::DrawToasts(const std::vector<Toast>& toasts)
{
    int drawn = 0;
    for (size_t i = 0; i < toasts.size() && drawn < 3; ++i, ++drawn) {
        const Toast& toast = toasts[i];
        float alpha = 1.0f;
        if (toast.remaining < 0.4f) {
            alpha = Clamp(toast.remaining / 0.4f, 0.0f, 1.0f);
        }
        Color color = toast.color;
        color.a *= alpha;
        const int width = TextWidth(toast.text, 10, 420) + 20;
        const float x = 240.0f - static_cast<float>(width) * 0.5f;
        const float y = 34.0f + static_cast<float>(drawn) * 20.0f;
        Panel(RectF(x, y, static_cast<float>(width), 18.0f),
              Color(0.03f, 0.05f, 0.07f, 0.86f * alpha),
              Color(0.22f, 0.85f, 0.78f, 0.55f * alpha));
        Text(toast.text, x + 10.0f, y + 3.0f, 10, 420, color);
    }
}

void GameUI::DrawFade(float alpha)
{
    if (alpha <= 0.0f) {
        return;
    }
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 0.0f, 480.0f,
                                 270.0f, Rgba(0, 0, 0, static_cast<int>(Clamp(alpha, 0.0f, 1.0f) * 255.0f)));
}

void GameUI::DrawCrosshair(Vec2 mouse, bool highlight)
{
    const Color color = highlight ? AMBER : Rgba(127, 216, 207, 220);
    const float x = mouse.x;
    const float y = mouse.y;
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), x - 5.0f, y, 3.0f,
                                 1.0f, color);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), x + 3.0f, y, 3.0f,
                                 1.0f, color);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), x, y - 5.0f, 1.0f,
                                 3.0f, color);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), x, y + 3.0f, 1.0f,
                                 3.0f, color);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), x - 1.0f, y - 1.0f,
                                 2.0f, 2.0f, color);
}

void GameUI::DrawLocationCard(const std::string& name, float alpha)
{
    if (alpha <= 0.0f || name.empty()) {
        return;
    }
    Color color = BONE;
    color.a = alpha;
    const int width = TextWidth(name, 16, 400);
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), 0.0f, 64.0f, 480.0f,
                                 26.0f, Color(0.0f, 0.0f, 0.0f, 0.32f * alpha));
    Text(name, 240.0f - static_cast<float>(width) * 0.5f, 68.0f, 16, 400,
         color);
}

} // namespace fc
