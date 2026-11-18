#include "Game_UI.hpp"

#include "Render_Device.hpp"
#include "Render_Text.hpp"
#include "Shared_Math.hpp"

#include <algorithm>
#include <cmath>

namespace fc {

namespace {

const Color BONE = Rgba(232, 227, 214);
const Color DIM = Rgba(172, 190, 190);
const Color CYAN = Rgba(57, 224, 208);
const Color AMBER = Rgba(255, 179, 71);
const Color MAGENTA = Rgba(255, 61, 139);
const Color RED = Rgba(220, 60, 72);
const Color PANEL_FILL = Rgba(6, 9, 13, 196);
const Color PANEL_BORDER = Rgba(57, 224, 208, 95);

struct ShopRow {
    const char* name;
    const char* description;
    int price;
    int icon;
};

const ShopRow SHOP_ROWS[4] = {
    {"9mm 弹药 ×12", "补充备弹，最多携带 99 发。", 18, 0},
    {"医疗包", "恢复 40 生命，最多携带 3 个。", 35, 1},
    {"能量饮料", "立刻恢复 20 生命。", 12, 2},
    {"思维接入装置", "未登记神经桥。接入自由城网络。", 500, 3}
};

CharacterId PortraitCharacter(const std::string& portrait)
{
    if (portrait == "PORTRAIT_PLAYER") {
        return CharacterId::PLAYER;
    }
    if (portrait == "PORTRAIT_BIGSISTER") {
        return CharacterId::BIGSISTER;
    }
    if (portrait == "PORTRAIT_MERCHANT") {
        return CharacterId::MERCHANT;
    }
    if (portrait == "PORTRAIT_BARTENDER") {
        return CharacterId::BARTENDER;
    }
    return CharacterId::PLAYER;
}

} // namespace

bool GameUI::Initialize(RenderDevice* device, TextRenderer* text,
                        GameRenderer* renderer)
{
    m_device = device;
    m_text = text;
    m_renderer = renderer;
    return m_device != nullptr && m_text != nullptr;
}

void GameUI::Panel(const RectF& rect, Color fill, Color border)
{
    SpriteBatch& batch = m_device->Batch();
    const Texture& white = m_device->White();
    batch.DrawTexture(white, rect.x, rect.y, rect.w, rect.h, fill);
    batch.DrawTexture(white, rect.x, rect.y, rect.w, 1.0f, border);
    batch.DrawTexture(white, rect.x, rect.Bottom() - 1.0f, rect.w, 1.0f, border);
    batch.DrawTexture(white, rect.x, rect.y, 1.0f, rect.h, border);
    batch.DrawTexture(white, rect.Right() - 1.0f, rect.y, 1.0f, rect.h, border);
    // 终端角标
    const Color corner = Color(CYAN.r, CYAN.g, CYAN.b, 0.75f);
    batch.DrawTexture(white, rect.x + 2.0f, rect.y + 2.0f, 7.0f, 1.0f, corner);
    batch.DrawTexture(white, rect.x + 2.0f, rect.y + 2.0f, 1.0f, 7.0f, corner);
    batch.DrawTexture(white, rect.Right() - 9.0f, rect.y + 2.0f, 7.0f, 1.0f,
                      corner);
    batch.DrawTexture(white, rect.Right() - 3.0f, rect.y + 2.0f, 1.0f, 7.0f,
                      corner);
}

void GameUI::Text(const std::string& utf8, float x, float y, int px,
                  int maxWidth, Color color, int visibleUnits)
{
    const TextBlock* block = m_text->Get(utf8, px, maxWidth);
    if (block == nullptr) {
        return;
    }
    m_text->Draw(m_device->Batch(), *block, x, y, color, visibleUnits, true);
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

void GameUI::DrawIcon(int type, float x, float y, float size, Color color)
{
    SpriteBatch& batch = m_device->Batch();
    const Texture& white = m_device->White();
    const float u = size / 12.0f;
    auto rect = [&](float rx, float ry, float rw, float rh) {
        batch.DrawTexture(white, x + rx * u, y + ry * u, rw * u, rh * u, color);
    };
    switch (type) {
    case 0:  // 弹药
        rect(4, 1, 4, 7);
        rect(5, 1, 2, 2);
        rect(3, 8, 6, 2);
        break;
    case 1:  // 医疗包
        rect(2, 3, 8, 7);
        rect(4, 5, 4, 3);
        rect(5, 4, 2, 5);
        break;
    case 2:  // 能量饮料
        rect(4, 1, 4, 2);
        rect(3, 3, 6, 8);
        rect(4, 5, 4, 2);
        break;
    case 3:  // 接入装置
        rect(2, 4, 8, 5);
        rect(5, 1, 2, 2);
        rect(5, 9, 2, 2);
        rect(3, 5, 6, 3);
        break;
    case 4:  // 信用点
        rect(3, 3, 6, 6);
        rect(4, 2, 4, 8);
        break;
    default:
        break;
    }
}

void GameUI::DrawPortrait(const std::string& portrait, float x, float y,
                          float size, const GameRenderer& renderer)
{
    const CharacterId id = PortraitCharacter(portrait);
    const Texture* texture = renderer.Portrait(id);
    SpriteBatch& batch = m_device->Batch();
    if (texture != nullptr && texture->IsValid()) {
        batch.DrawTexture(*texture, x, y, size, size,
                          Color(1.0f, 1.0f, 1.0f, 1.0f), false, false);
    } else {
        batch.DrawTexture(m_device->White(), x, y, size, size,
                          Color(0.15f, 0.16f, 0.18f, 1.0f));
    }
    batch.DrawTexture(m_device->White(), x, y + size, size, 1.0f,
                      Color(CYAN.r, CYAN.g, CYAN.b, 0.6f));
}

void GameUI::DrawHUD(const Player& player, const Inventory& inventory,
                     const QuestState& quest, const std::string& prompt,
                     Vec2 promptScreen, Vec2 mouse,
                     const std::vector<Enemy>& enemies,
                     const CameraRuntime& camera, const GameRenderer& renderer)
{
    const std::string mainObjective = MainObjective(quest);
    const std::string sideObjective = SideObjective(quest);
    const int mainHeight = TextHeight(mainObjective, 11, 268);
    const int sideHeight =
        sideObjective.empty() ? 0 : TextHeight(sideObjective, 10, 268);
    const float panelHeight = 16.0f + static_cast<float>(mainHeight) +
                              (sideHeight > 0 ? 15.0f + sideHeight : 0.0f) +
                              8.0f;
    Panel(RectF(6.0f, 6.0f, 292.0f, panelHeight), PANEL_FILL, PANEL_BORDER);
    Text("当前目标", 14.0f, 9.0f, 9, 200, AMBER);
    Text(mainObjective, 14.0f, 21.0f, 11, 268, BONE);
    if (!sideObjective.empty()) {
        const float sideY = 23.0f + static_cast<float>(mainHeight);
        Text("支线", 14.0f, sideY, 9, 200, CYAN);
        Text(sideObjective, 14.0f, sideY + 10.0f, 10, 268,
             Rgba(150, 210, 205));
    }

    Panel(RectF(372.0f, 6.0f, 102.0f, 22.0f), PANEL_FILL, PANEL_BORDER);
    DrawIcon(4, 378.0f, 10.0f, 14.0f, Rgba(240, 205, 120));
    Text(std::to_string(inventory.money), 394.0f, 9.0f, 11, 80,
         Rgba(240, 205, 120));

    // 敌人血条
    for (const Enemy& enemy : enemies) {
        if (enemy.dead || (!enemy.alerted && enemy.hp >= enemy.maxHp)) {
            continue;
        }
        Vec2 screen;
        if (!renderer.WorldToScreen(camera,
                                    enemy.position + Vec3(0.0f, 1.95f, 0.0f),
                                    screen)) {
            continue;
        }
        const float ratio = Clamp(enemy.hp / std::max(1.0f, enemy.maxHp), 0.0f,
                                  1.0f);
        SpriteBatch& batch = m_device->Batch();
        batch.DrawTexture(m_device->White(), screen.x - 14.0f, screen.y, 28.0f,
                          3.0f, Color(0.05f, 0.05f, 0.06f, 0.9f));
        const Color barColor = enemy.type == EnemyType::AGENT
                                   ? Color(CYAN.r, CYAN.g, CYAN.b, 0.95f)
                                   : Color(0.85f, 0.4f, 0.25f, 0.95f);
        batch.DrawTexture(m_device->White(), screen.x - 13.0f, screen.y + 1.0f,
                          26.0f * ratio, 1.0f, barColor);
    }

    Panel(RectF(6.0f, 200.0f, 220.0f, 66.0f), PANEL_FILL, PANEL_BORDER);
    DrawPortrait("PORTRAIT_PLAYER", 10.0f, 206.0f, 54.0f, renderer);
    Text("小明", 70.0f, 204.0f, 10, 80, Rgba(127, 216, 207));
    SpriteBatch& batch = m_device->Batch();
    batch.DrawTexture(m_device->White(), 70.0f, 219.0f, 140.0f, 6.0f,
                      Rgba(26, 32, 38, 230));
    const float hpRatio = Clamp(static_cast<float>(player.hp) /
                                    static_cast<float>(PLAYER_MAX_HP),
                                0.0f, 1.0f);
    const Color hpColor = hpRatio < 0.3f ? RED : Rgba(70, 200, 160);
    batch.DrawTexture(m_device->White(), 71.0f, 220.0f, 138.0f * hpRatio, 4.0f,
                      hpColor);
    Text(std::to_string(player.hp) + "/" + std::to_string(PLAYER_MAX_HP),
         214.0f, 214.0f, 9, 40, DIM);
    DrawIcon(0, 70.0f, 232.0f, 14.0f, Rgba(230, 190, 100));
    Text(std::to_string(inventory.ammoMag) + " / " +
             std::to_string(inventory.ammoReserve),
         88.0f, 231.0f, 10, 80, BONE);
    DrawIcon(1, 152.0f, 232.0f, 14.0f, Rgba(230, 235, 220));
    Text("×" + std::to_string(inventory.medkits), 170.0f, 231.0f, 10, 40,
         BONE);

    // 武器槽：显示当前手里拿的是什么，并提示滚轮切换。
    {
        const bool armed = player.slot == WeaponSlot::PISTOL;
        Panel(RectF(232.0f, 226.0f, 108.0f, 24.0f), PANEL_FILL,
              armed ? PANEL_BORDER : Rgba(120, 130, 140, 70));
        DrawIcon(0, 238.0f, 231.0f, 14.0f,
                 armed ? Rgba(230, 190, 100) : Rgba(120, 130, 140));
        Text(armed ? "手枪" : "空手", 258.0f, 231.0f, 10, 40,
             armed ? BONE : DIM);
        Text("滚轮", 300.0f, 232.0f, 8, 32, DIM);
    }

    if (player.reloading) {
        Text("装填中……", 70.0f, 248.0f, 9, 120, AMBER);
    } else if (player.usingMedkit) {
        Text("使用医疗包……", 70.0f, 248.0f, 9, 120, AMBER);
    } else if (inventory.hasGear && player.slot == WeaponSlot::FISTS) {
        Text("空手：左键近战（滚轮切枪）", 70.0f, 248.0f, 9, 150, DIM);
    } else if (!inventory.hasGear) {
        Text("尚未装备武器", 70.0f, 248.0f, 9, 120, DIM);
    } else if (hpRatio < 0.3f) {
        Text("生命危险", 70.0f, 248.0f, 9, 120, RED);
    }

    if (!prompt.empty()) {
        const int width = TextWidth(prompt, 10, 200) + 16;
        float x = promptScreen.x - static_cast<float>(width) * 0.5f;
        x = Clamp(x, 4.0f, 476.0f - static_cast<float>(width));
        const float y = Clamp(promptScreen.y - 26.0f, 6.0f, 226.0f);
        Panel(RectF(x, y, static_cast<float>(width), 20.0f),
              Rgba(5, 9, 12, 226), Rgba(255, 179, 71, 120));
        Text(prompt, x + 8.0f, y + 4.0f, 10, 200, AMBER);
    }

    DrawCrosshair(mouse, !prompt.empty());
}

void GameUI::DrawDialogue(const DialogueController& dialogue, bool cinematic,
                          float time, const GameRenderer& renderer,
                          float skipProgress, bool skipping)
{
    const DialogueNode* node = dialogue.Current();
    if (node == nullptr) {
        return;
    }
    if (cinematic) {
        SpriteBatch& batch = m_device->Batch();
        batch.DrawTexture(m_device->White(), 0.0f, 0.0f, 480.0f, 14.0f,
                          Rgba(0, 0, 0, 200));
        batch.DrawTexture(m_device->White(), 0.0f, 256.0f, 480.0f, 14.0f,
                          Rgba(0, 0, 0, 200));
    }

    const bool hasPortrait = !node->portrait.empty();
    const float textX = hasPortrait ? 76.0f : 20.0f;
    const int maxWidth = static_cast<int>(472.0f - textX);
    const int textHeight = TextHeight(node->text, 12, maxWidth);
    const int optionCount = static_cast<int>(node->options.size());
    const int optionsHeight = optionCount > 0 ? 6 + optionCount * 16 : 0;
    float boxHeight = 34.0f + static_cast<float>(textHeight) +
                      static_cast<float>(optionsHeight) + 10.0f;
    boxHeight = Clamp(boxHeight, 82.0f, 172.0f);
    const float boxBottom = cinematic ? 254.0f : 264.0f;
    const float boxY = boxBottom - boxHeight;
    const float boxX = 6.0f;
    const float boxW = 468.0f;

    Panel(RectF(boxX, boxY, boxW, boxHeight), Rgba(5, 8, 12, 236),
          Rgba(57, 224, 208, 130));

    if (hasPortrait) {
        DrawPortrait(node->portrait, boxX + 10.0f, boxY + 10.0f, 56.0f,
                     renderer);
    }

    float textY = boxY + 8.0f;
    if (!node->speaker.empty()) {
        Text(node->speaker, textX, boxY + 7.0f, 12, maxWidth,
             SpeakerColor(node->speaker));
        textY = boxY + 24.0f;
    }
    Text(node->text, textX, textY, 12, maxWidth, BONE,
         dialogue.VisibleUnits());

    if (dialogue.IsTextComplete() && optionCount > 0) {
        const float optionY = textY + static_cast<float>(textHeight) + 4.0f;
        for (int i = 0; i < optionCount; ++i) {
            const float rowY = optionY + static_cast<float>(i) * 16.0f;
            const bool selected = i == dialogue.SelectedOption();
            if (selected) {
                m_device->Batch().DrawTexture(
                    m_device->White(), boxX + 12.0f, rowY - 2.0f, boxW - 24.0f,
                    15.0f, Rgba(255, 179, 71, 36));
                Text(">", boxX + 14.0f, rowY, 11, 10, AMBER);
            }
            Text(node->options[static_cast<size_t>(i)].text, boxX + 26.0f,
                 rowY, 11, static_cast<int>(boxW - 44.0f),
                 selected ? AMBER : BONE);
        }
        Text("W/S 选择   E 确认", boxX + 14.0f,
             boxY + boxHeight - 14.0f, 9, 130, DIM);
    } else if (dialogue.IsTextComplete()) {
        const float blink = 0.60f + 0.40f * std::sin(time * 6.0f);
        Text("▼", boxX + boxW - 24.0f, boxY + 6.0f, 12, 20,
             Color(1.0f, 0.75f, 0.35f, blink));
    }

    // 快进提示：按住 Ctrl 时进度条逐渐填满，满格后进入快进。
    {
        const float labelX = boxX + boxW - 152.0f;
        const float labelY = boxY + boxHeight - 15.0f;
        const float barX = labelX + 78.0f;
        const float barY = labelY + 3.0f;
        const float barW = 58.0f;
        const float barH = 5.0f;
        SpriteBatch& batch = m_device->Batch();
        const Color label = skipping ? AMBER : DIM;
        Text(skipping ? "快进中" : "按住 Ctrl 快进", labelX, labelY, 9, 90, label);
        batch.DrawTexture(m_device->White(), barX, barY, barW, barH,
                          Rgba(16, 20, 24, 220));
        const float filled = Clamp(skipProgress, 0.0f, 1.0f) * barW;
        if (filled > 0.0f) {
            batch.DrawTexture(m_device->White(), barX, barY, filled, barH,
                              skipping ? AMBER : Rgba(120, 190, 205, 230));
        }
        batch.DrawTexture(m_device->White(), barX, barY, barW, 1.0f,
                          Rgba(90, 120, 130, 160));
        batch.DrawTexture(m_device->White(), barX, barY + barH - 1.0f, barW,
                          1.0f, Rgba(90, 120, 130, 160));
    }
}

void GameUI::DrawShop(const Inventory& inventory, const ShopState& shop,
                      float time, const GameRenderer& renderer)
{
    m_device->Batch().DrawTexture(m_device->White(), 0.0f, 0.0f, 480.0f, 270.0f,
                                  Rgba(0, 0, 0, 150));
    Panel(RectF(18.0f, 12.0f, 444.0f, 246.0f), PANEL_FILL, PANEL_BORDER);

    DrawPortrait("PORTRAIT_MERCHANT", 28.0f, 22.0f, 56.0f, renderer);
    Text("东子", 94.0f, 26.0f, 14, 120, Rgba(230, 200, 90));
    Text("地下商人 · 旧城区", 94.0f, 46.0f, 9, 200, DIM);
    DrawIcon(4, 350.0f, 26.0f, 14.0f, Rgba(240, 205, 120));
    Text(std::to_string(inventory.money), 368.0f, 25.0f, 12, 90,
         Rgba(240, 205, 120));
    Text("信用点", 368.0f, 41.0f, 9, 90, DIM);
    if (shop.browseOnly) {
        Text("首次交易：仅可浏览", 300.0f, 58.0f, 9, 160, AMBER);
    }

    m_device->Batch().DrawTexture(m_device->White(), 28.0f, 82.0f, 424.0f, 1.0f,
                                  Rgba(57, 224, 208, 70));

    const int selected = ClampInt(shop.selected, 0, 3);
    for (int i = 0; i < 4; ++i) {
        const float rowY = 88.0f + static_cast<float>(i) * 34.0f;
        if (i == selected) {
            m_device->Batch().DrawTexture(m_device->White(), 26.0f,
                                          rowY - 2.0f, 428.0f, 32.0f,
                                          Rgba(255, 179, 71, 28));
            m_device->Batch().DrawTexture(m_device->White(), 26.0f,
                                          rowY - 2.0f, 3.0f, 32.0f, AMBER);
        }
        DrawIcon(SHOP_ROWS[i].icon, 38.0f, rowY + 1.0f, 14.0f,
                 i == selected ? BONE : Rgba(190, 190, 180));
        Text(SHOP_ROWS[i].name, 60.0f, rowY, 12, 250,
             i == selected ? BONE : Rgba(190, 190, 180));
        Text(SHOP_ROWS[i].description, 60.0f, rowY + 15.0f, 9, 280, DIM);
        const std::string price = "₡ " + std::to_string(SHOP_ROWS[i].price);
        const bool affordable =
            inventory.CanAfford(SHOP_ROWS[i].price) && i != 3;
        Text(price, 424.0f - static_cast<float>(TextWidth(price, 11, 80)),
             rowY + 2.0f, 11, 80,
             affordable ? Rgba(240, 205, 120) : Rgba(210, 90, 90));
    }

    if (!shop.message.empty()) {
        const bool bad = shop.message.find("不足") != std::string::npos ||
                         shop.message.find("满") != std::string::npos ||
                         shop.message.find("不是") != std::string::npos;
        const Color color = bad ? RED : Rgba(90, 220, 160);
        const int width = TextWidth(shop.message, 10, 400);
        Text(shop.message, 240.0f - static_cast<float>(width) * 0.5f, 228.0f,
             10, 400, color);
    }

    Text("W/S 选择   E 购买   Esc 离开", 28.0f, 244.0f, 9, 300, DIM);
    const float pulse = 0.7f + 0.3f * std::sin(time * 4.0f);
    Text("东子：钱到位，什么都好说。", 300.0f, 244.0f, 9, 180,
         Color(0.9f, 0.8f, 0.4f, pulse));
}

void GameUI::DrawJournal(const Player& player, const Inventory& inventory,
                         const QuestState& quest)
{
    m_device->Batch().DrawTexture(m_device->White(), 0.0f, 0.0f, 480.0f, 270.0f,
                                  Rgba(0, 0, 0, 165));
    Panel(RectF(26.0f, 14.0f, 428.0f, 242.0f), PANEL_FILL, PANEL_BORDER);
    Text("任务日志", 42.0f, 24.0f, 14, 200, CYAN);

    Text("主线", 42.0f, 46.0f, 9, 100, AMBER);
    Text(MainObjective(quest), 42.0f, 57.0f, 11, 396, BONE);
    if (IsSideQuestVisible(quest)) {
        Text("支线", 42.0f, 80.0f, 9, 100, CYAN);
        Text(SideObjective(quest), 42.0f, 91.0f, 11, 396, Rgba(150, 210, 205));
    }

    m_device->Batch().DrawTexture(m_device->White(), 42.0f, 116.0f, 388.0f, 1.0f,
                                  Rgba(57, 224, 208, 60));
    Text("随身物品", 42.0f, 124.0f, 11, 160, AMBER);
    Text("信用点：" + std::to_string(inventory.money), 42.0f, 142.0f, 10, 200,
         Rgba(240, 205, 120));
    Text("9mm 弹药：" + std::to_string(inventory.ammoMag) + " / " +
             std::to_string(inventory.ammoReserve),
         42.0f, 156.0f, 10, 240, BONE);
    Text("医疗包：" + std::to_string(inventory.medkits), 42.0f, 170.0f, 10, 200,
         BONE);
    Text(inventory.hasCargo ? "货物：大姐头的箱子（已携带）" : "货物：尚未取得",
         42.0f, 184.0f, 10, 320,
         inventory.hasCargo ? Rgba(150, 210, 205) : DIM);
    Text(inventory.hasPart ? "旧零件：点唱机唱针组件" : "旧零件：未找到",
         42.0f, 198.0f, 10, 320,
         inventory.hasPart ? Rgba(150, 210, 205) : DIM);

    m_device->Batch().DrawTexture(m_device->White(), 42.0f, 216.0f, 388.0f, 1.0f,
                                  Rgba(57, 224, 208, 60));
    Text("操作", 42.0f, 222.0f, 9, 100, DIM);
    Text("WASD 移动   Shift 奔跑   鼠标瞄准   左键射击", 42.0f, 234.0f, 9, 396,
         BONE);
    Text("R 装填   E 交互   F 医疗包   Tab 日志   M 静音", 42.0f, 246.0f, 9,
         396, BONE);
    Text("生命 " + std::to_string(player.hp) + " / " +
             std::to_string(PLAYER_MAX_HP),
         360.0f, 124.0f, 10, 80, DIM);
}

void GameUI::DrawTitle(float time, bool muted)
{
    m_device->Batch().DrawTexture(m_device->White(), 0.0f, 0.0f, 480.0f, 270.0f,
                                  Rgba(2, 3, 5, 120));
    TextCentered("余烬自由城", 240.0f, 62.0f, 26, 420, BONE);
    TextCentered("EMBER OF FREE CITY", 240.0f, 100.0f, 11, 420,
                 Rgba(150, 200, 200));
    m_device->Batch().DrawTexture(m_device->White(), 150.0f, 118.0f, 180.0f, 1.0f,
                                  Rgba(57, 224, 208, 90));
    TextCentered("A LOW-POLY TALE OF THE FREE CITY", 240.0f, 126.0f, 8, 420,
                 DIM);
    const float blink = 0.72f + 0.28f * std::sin(time * 3.4f);
    TextCentered("按 Enter 开始", 240.0f, 196.0f, 13, 300,
                 Color(1.0f, 0.75f, 0.35f, blink));
    TextCentered("WASD 移动 · 鼠标瞄准 · E 交互 · M 静音", 240.0f, 226.0f, 9,
                 420, DIM);
    TextCentered("固定机位 · 低分辨率 · 程序化资产", 240.0f, 242.0f, 9, 420,
                 Rgba(110, 130, 135));
    if (muted) {
        Text("静音", 434.0f, 8.0f, 9, 40, MAGENTA);
    }
}

void GameUI::DrawEpilogue(EndingChoice choice, float time)
{
    m_device->Batch().DrawTexture(m_device->White(), 0.0f, 0.0f, 480.0f, 270.0f,
                                  Rgba(4, 3, 4, 150));
    TextCentered("DEMO 结束", 240.0f, 40.0f, 18, 360, BONE);
    TextCentered("余烬自由城", 240.0f, 66.0f, 13, 300, AMBER);
    m_device->Batch().DrawTexture(m_device->White(), 140.0f, 86.0f, 200.0f, 1.0f,
                                  Rgba(255, 179, 71, 90));

    const char* lines =
        (choice == EndingChoice::ACCEPT)
            ? "我把那枚东西攥在手里，很轻，像一枚硬币。\n从明天起，自由城会看见我。\n我只希望，它看见的仍然是我。"
            : "我把手收了回来。\n不是不想要。只是还没想好，要用什么来换。\n雨还在下。至少今晚，我还知道自己是谁。";
    Text(lines, 66.0f, 106.0f, 11, 348, BONE);
    const float blink = 0.72f + 0.28f * std::sin(time * 3.4f);
    TextCentered("Enter 重新开始　·　Esc 返回标题", 240.0f, 216.0f, 10, 420,
                 Color(1.0f, 0.75f, 0.35f, blink));
    TextCentered("感谢游玩", 240.0f, 238.0f, 9, 200, DIM);
}

void GameUI::DrawDeath(float time)
{
    m_device->Batch().DrawTexture(m_device->White(), 0.0f, 0.0f, 480.0f, 270.0f,
                                  Rgba(20, 2, 4, 170));
    TextCentered("连接中断", 240.0f, 74.0f, 22, 300, RED);
    TextCentered("你倒在了铁港的雨里。", 240.0f, 110.0f, 11, 400, BONE);
    const float blink = 0.72f + 0.28f * std::sin(time * 3.4f);
    TextCentered("Enter 从检查点重试", 240.0f, 164.0f, 11, 400,
                 Color(1.0f, 0.75f, 0.35f, blink));
    TextCentered("Esc 返回标题", 240.0f, 184.0f, 10, 300, DIM);
}

void GameUI::DrawPause(const Inventory& inventory, const QuestState& quest)
{
    m_device->Batch().DrawTexture(m_device->White(), 0.0f, 0.0f, 480.0f, 270.0f,
                                  Rgba(0, 0, 0, 160));
    Panel(RectF(88.0f, 40.0f, 304.0f, 190.0f), PANEL_FILL, PANEL_BORDER);
    TextCentered("暂停", 240.0f, 52.0f, 16, 200, BONE);
    Text("目标：" + MainObjective(quest), 106.0f, 82.0f, 10, 268, AMBER);
    Text("信用点：" + std::to_string(inventory.money), 106.0f, 100.0f, 10, 200,
         Rgba(240, 205, 120));
    Text("WASD 移动　Shift 奔跑　鼠标瞄准", 106.0f, 124.0f, 9, 268, BONE);
    Text("左键射击　R 装填　F 医疗包", 106.0f, 138.0f, 9, 268, BONE);
    Text("E 交互　Tab 日志　M 静音", 106.0f, 152.0f, 9, 268, BONE);
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
    m_device->Batch().DrawTexture(
        m_device->White(), 0.0f, 0.0f, 480.0f, 270.0f,
        Rgba(0, 0, 0, static_cast<int>(Clamp(alpha, 0.0f, 1.0f) * 255.0f)));
}

void GameUI::DrawCrosshair(Vec2 mouse, bool highlight)
{
    const Color color = highlight ? AMBER : Rgba(127, 216, 207, 220);
    SpriteBatch& batch = m_device->Batch();
    const Texture& white = m_device->White();
    batch.DrawTexture(white, mouse.x - 6.0f, mouse.y, 4.0f, 1.0f, color);
    batch.DrawTexture(white, mouse.x + 3.0f, mouse.y, 4.0f, 1.0f, color);
    batch.DrawTexture(white, mouse.x, mouse.y - 6.0f, 1.0f, 4.0f, color);
    batch.DrawTexture(white, mouse.x, mouse.y + 3.0f, 1.0f, 4.0f, color);
    batch.DrawTexture(white, mouse.x - 1.0f, mouse.y - 1.0f, 2.0f, 2.0f, color);
}

void GameUI::DrawLocationCard(const std::string& name, float alpha)
{
    if (alpha <= 0.0f || name.empty()) {
        return;
    }
    Color color = BONE;
    color.a = alpha;
    const int width = TextWidth(name, 15, 400);
    m_device->Batch().DrawTexture(m_device->White(), 0.0f, 60.0f, 480.0f, 26.0f,
                                  Color(0.0f, 0.0f, 0.0f, 0.35f * alpha));
    Text(name, 240.0f - static_cast<float>(width) * 0.5f, 63.0f, 15, 400,
         color);
}

void GameUI::DrawRain(const std::vector<RainDrop>& drops)
{
    SpriteBatch& batch = m_device->Batch();
    const Texture& white = m_device->White();
    for (const RainDrop& drop : drops) {
        batch.DrawTexture(white, drop.x, drop.y, 1.0f, drop.length,
                          Color(0.62f, 0.80f, 0.86f, drop.alpha));
        if (drop.alpha > 0.24f) {
            batch.DrawTexture(white, drop.x + 1.0f, drop.y + 1.0f, 1.0f,
                              drop.length * 0.7f,
                              Color(0.35f, 0.55f, 0.62f, drop.alpha * 0.4f));
        }
    }
}

void GameUI::DrawObjectiveMarker(Vec2 screen, float time,
                                 const std::string& label)
{
    const float bob = std::sin(time * 2.6f) * 2.0f;
    SpriteBatch& batch = m_device->Batch();
    const Texture& white = m_device->White();
    const Color color = Color(AMBER.r, AMBER.g, AMBER.b,
                              0.65f + 0.35f * std::sin(time * 3.0f));
    batch.DrawTexture(white, screen.x - 4.0f, screen.y - 12.0f + bob, 8.0f,
                      1.0f, color);
    batch.DrawTexture(white, screen.x - 3.0f, screen.y - 11.0f + bob, 1.0f,
                      7.0f, color);
    batch.DrawTexture(white, screen.x + 2.0f, screen.y - 11.0f + bob, 1.0f,
                      7.0f, color);
    if (!label.empty()) {
        const int width = TextWidth(label, 9, 200);
        Text(label, screen.x - static_cast<float>(width) * 0.5f,
             screen.y - 24.0f + bob, 9, 200, color);
    }
}

void GameUI::DrawDamageOverlay(float damage, float lowHealth)
{
    SpriteBatch& batch = m_device->Batch();
    if (damage > 0.001f) {
        batch.DrawTexture(m_device->White(), 0.0f, 0.0f, 480.0f, 270.0f,
                          Color(0.6f, 0.04f, 0.06f, damage * 0.35f));
    }
    if (lowHealth > 0.001f) {
        const Color color(0.5f, 0.0f, 0.02f, lowHealth * 0.22f);
        batch.DrawTexture(m_device->White(), 0.0f, 0.0f, 480.0f, 18.0f, color);
        batch.DrawTexture(m_device->White(), 0.0f, 252.0f, 480.0f, 18.0f, color);
    }
}

} // namespace fc
