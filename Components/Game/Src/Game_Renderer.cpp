#include "Game_Renderer.hpp"

#include "Render_Device.hpp"
#include "Render_Text.hpp"
#include "Shared_Log.hpp"
#include "Shared_Math.hpp"

#include <algorithm>
#include <cmath>
#include <string>

namespace fc {

namespace {

const Color WHITE = Color(1.0f, 1.0f, 1.0f, 1.0f);

float Flicker(float time, float seed, float low, float high)
{
    const float wave = 0.5f + 0.5f * std::sin(time * 7.0f + seed);
    return low + (high - low) * wave;
}

} // namespace

bool GameRenderer::Initialize(RenderDevice* device, TextRenderer* text)
{
    m_device = device;
    m_text = text;
    return m_device != nullptr;
}

std::string GameRenderer::ActorSprite(const char* prefix, int facingDir,
                                      float animTime, bool moving) const
{
    static const char* DIRS[4] = {"S", "N", "E", "W"};
    const int dir = ClampInt(facingDir, 0, 3);
    std::string name = prefix;
    name += "_";
    name += DIRS[dir];
    if (moving) {
        const int frame = static_cast<int>(animTime * 8.0f) % 4;
        name += "_";
        name += std::to_string(frame);
    } else {
        name += "_IDLE";
    }
    return name;
}

void GameRenderer::DrawRect(const RectF& rect, Color color)
{
    if (m_device == nullptr) {
        return;
    }
    m_device->Batch().DrawSprite(m_device->WhiteSprite(), rect.x, rect.y,
                                 rect.w, rect.h, color);
}

void GameRenderer::DrawSprite(const char* name, float x, float y, float w,
                              float h, Color tint, bool additive)
{
    if (m_device == nullptr) {
        return;
    }
    const Sprite* sprite = m_device->FindSprite(name);
    if (sprite != nullptr && sprite->texture != nullptr) {
        m_device->Batch().DrawSprite(*sprite, x, y, w, h, tint, false, additive);
    }
}

void GameRenderer::DrawWorld(const WorldMap& map, const Player& player,
                             const std::vector<Enemy>& enemies,
                             const std::vector<Bullet>& bullets,
                             const std::vector<Particle>& particles,
                             const std::vector<Pickup>& pickups,
                             const Camera& camera, Vec2 shake, float time,
                             bool alarm)
{
    if (m_device == nullptr) {
        return;
    }
    SpriteBatch& batch = m_device->Batch();
    const int camX = static_cast<int>(std::floor(camera.position.x + shake.x));
    const int camY = static_cast<int>(std::floor(camera.position.y + shake.y));

    const int startX = std::max(0, camX / TILE_SIZE);
    const int startY = std::max(0, camY / TILE_SIZE);
    const int endX = std::min(map.Definition().widthTiles - 1,
                              (camX + INTERNAL_WIDTH) / TILE_SIZE);
    const int endY = std::min(map.Definition().heightTiles - 1,
                              (camY + INTERNAL_HEIGHT) / TILE_SIZE);

    for (int y = startY; y <= endY; ++y) {
        for (int x = startX; x <= endX; ++x) {
            const std::string& name = map.TileSpriteName(x, y);
            const Sprite* sprite = m_device->FindSprite(name.c_str());
            if (sprite != nullptr && sprite->texture != nullptr) {
                batch.DrawSprite(*sprite,
                                 static_cast<float>(x * TILE_SIZE - camX),
                                 static_cast<float>(y * TILE_SIZE - camY),
                                 static_cast<float>(TILE_SIZE),
                                 static_cast<float>(TILE_SIZE), WHITE);
            }
        }
    }

    std::vector<DrawItem> items;
    items.reserve(map.Props().size() + enemies.size() + pickups.size() + 8);
    AddPropItems(map, static_cast<float>(camX), static_cast<float>(camY), items);
    AddActorItems(player, enemies, pickups, static_cast<float>(camX),
                  static_cast<float>(camY), items);

    std::stable_sort(items.begin(), items.end(),
                     [](const DrawItem& a, const DrawItem& b) {
                         if (a.baseline == b.baseline) {
                             return a.order < b.order;
                         }
                         return a.baseline < b.baseline;
                     });

    for (const DrawItem& item : items) {
        if (item.sprite == nullptr || item.sprite->texture == nullptr) {
            continue;
        }
        batch.DrawSprite(*item.sprite, item.x, item.y, item.w, item.h,
                         item.tint, false, item.additive);
    }

    // 枪口焰
    if (player.muzzleTimer > 0.0f) {
        const float mx = player.position.x - static_cast<float>(camX) - 8.0f +
                         player.aim.x * 13.0f;
        const float my = player.position.y - static_cast<float>(camY) - 13.0f +
                         player.aim.y * 10.0f;
        const char* frame = player.muzzleTimer > 0.03f ? "FX_MUZZLE_0" : "FX_MUZZLE_1";
        DrawSprite(frame, mx, my, 16.0f, 16.0f, WHITE, true);
    }
    for (const Enemy& enemy : enemies) {
        if (enemy.muzzleTimer > 0.0f && !enemy.dead) {
            const Vec2 dir = Normalize(player.position - enemy.position);
            const float mx = enemy.position.x - static_cast<float>(camX) - 8.0f +
                             dir.x * 13.0f;
            const float my = enemy.position.y - static_cast<float>(camY) - 13.0f +
                             dir.y * 10.0f;
            DrawSprite("FX_MUZZLE_1", mx, my, 12.0f, 12.0f,
                       Color(1.0f, 0.6f, 0.4f, 0.9f), true);
        }
    }

    // 子弹
    for (const Bullet& bullet : bullets) {
        if (!bullet.active) {
            continue;
        }
        const float x = bullet.position.x - static_cast<float>(camX);
        const float y = bullet.position.y - static_cast<float>(camY);
        const Color tint = bullet.hostile ? Color(1.0f, 0.35f, 0.45f, 0.95f)
                                          : Color(0.55f, 0.95f, 1.0f, 0.95f);
        DrawSprite("FX_GLOW", x - 5.0f, y - 5.0f, 10.0f, 10.0f,
                   Color(tint.r, tint.g, tint.b, 0.28f), true);
        DrawSprite("FX_BULLET", x - 3.0f, y - 1.0f, 6.0f, 2.0f, tint, false);
    }

    // 粒子
    for (const Particle& particle : particles) {
        if (particle.life <= 0.0f) {
            continue;
        }
        const float t = Clamp(particle.life / std::max(0.001f, particle.maxLife),
                              0.0f, 1.0f);
        Color tint = particle.color;
        tint.a *= t;
        const char* spriteName = particle.smoke
                                     ? "FX_SMOKE"
                                     : (particle.additive ? "FX_SPARK" : "FX_BLOOD");
        const float size = particle.size * (particle.smoke ? (2.0f - t) : 1.0f);
        DrawSprite(spriteName, particle.position.x - static_cast<float>(camX) -
                                   size * 0.5f,
                   particle.position.y - static_cast<float>(camY) - size * 0.5f,
                   size, size, tint, particle.additive);
    }

    DrawLights(map, static_cast<float>(camX), static_cast<float>(camY), time,
               alarm);
}

void GameRenderer::AddPropItems(const WorldMap& map, float camX, float camY,
                                std::vector<DrawItem>& items)
{
    int order = 0;
    for (const PropInstance& prop : map.Props()) {
        if (!prop.visible || prop.sprite == nullptr) {
            ++order;
            continue;
        }
        DrawItem item;
        item.baseline = prop.position.y + static_cast<float>(prop.sprite->height);
        item.order = order++;
        item.sprite = prop.sprite;
        item.x = prop.position.x - camX;
        item.y = prop.position.y - camY;
        item.w = static_cast<float>(prop.sprite->width);
        item.h = static_cast<float>(prop.sprite->height);
        item.tint = WHITE;
        items.push_back(item);
    }
}

void GameRenderer::AddActorItems(const Player& player,
                                 const std::vector<Enemy>& enemies,
                                 const std::vector<Pickup>& pickups, float camX,
                                 float camY, std::vector<DrawItem>& items)
{
    int order = 1000;
    {
        const std::string name = ActorSprite("CHAR_PLAYER", player.facingDir,
                                             player.animTime, player.moving);
        const Sprite* sprite = m_device->FindSprite(name.c_str());
        DrawItem item;
        item.baseline = player.position.y;
        item.order = order++;
        item.sprite = sprite;
        item.x = player.position.x - 8.0f - camX;
        item.y = player.position.y - 24.0f - camY;
        item.w = 16.0f;
        item.h = 24.0f;
        item.tint = player.hitFlash > 0.0f
                        ? Color(1.0f, 0.55f, 0.55f, 1.0f)
                        : WHITE;
        items.push_back(item);
    }

    for (const Enemy& enemy : enemies) {
        const char* prefix = enemy.type == EnemyType::AGENT ? "CHAR_AGENT"
                                                            : "CHAR_SCAVENGER";
        const std::string name = ActorSprite(prefix, enemy.facingDir,
                                             enemy.animTime, enemy.moving);
        const Sprite* sprite = m_device->FindSprite(name.c_str());
        DrawItem item;
        item.baseline = enemy.position.y;
        item.order = order++;
        item.sprite = sprite;
        item.x = enemy.position.x - 8.0f - camX;
        item.y = enemy.position.y - 24.0f - camY;
        item.w = 16.0f;
        item.h = 24.0f;
        item.tint = WHITE;
        if (enemy.hitFlash > 0.0f) {
            item.tint = Color(1.0f, 0.4f, 0.4f, 1.0f);
        }
        if (enemy.dead) {
            item.tint.a = Clamp(enemy.deathTimer / 0.30f, 0.0f, 1.0f);
        }
        items.push_back(item);
    }

    for (const Pickup& pickup : pickups) {
        if (!pickup.active) {
            continue;
        }
        const char* icon = "UI_ICON_AMMO";
        switch (pickup.type) {
        case PickupType::AMMO: icon = "UI_ICON_AMMO"; break;
        case PickupType::MEDKIT: icon = "UI_ICON_MEDKIT"; break;
        case PickupType::MONEY: icon = "UI_ICON_CREDIT"; break;
        case PickupType::PART: icon = "UI_ICON_PART"; break;
        }
        const Sprite* sprite = m_device->FindSprite(icon);
        DrawItem item;
        item.baseline = pickup.position.y;
        item.order = order++;
        item.sprite = sprite;
        item.x = pickup.position.x - 6.0f - camX;
        item.y = pickup.position.y - 12.0f - camY +
                 std::sin(pickup.bob * 4.0f) * 2.0f;
        item.w = 12.0f;
        item.h = 12.0f;
        item.tint = WHITE;
        item.additive = false;
        items.push_back(item);

        DrawItem glow;
        glow.baseline = pickup.position.y - 0.1f;
        glow.order = order++;
        glow.sprite = m_device->FindSprite("FX_GLOW");
        glow.x = pickup.position.x - 10.0f - camX;
        glow.y = pickup.position.y - 16.0f - camY;
        glow.w = 20.0f;
        glow.h = 20.0f;
        glow.tint = Color(0.4f, 0.9f, 0.85f, 0.30f);
        glow.additive = true;
        items.push_back(glow);
    }
}

void GameRenderer::DrawLights(const WorldMap& map, float camX, float camY,
                              float time, bool alarm)
{
    const Sprite* glow = m_device->FindSprite("FX_GLOW");
    if (glow == nullptr || glow->texture == nullptr) {
        return;
    }
    SpriteBatch& batch = m_device->Batch();

    auto drawGlow = [&](float cx, float cy, float radius, Color color) {
        batch.DrawSprite(*glow, cx - radius, cy - radius, radius * 2.0f,
                         radius * 2.0f, color, false, true);
    };

    for (const PropInstance& prop : map.Props()) {
        if (!prop.visible || prop.sprite == nullptr) {
            continue;
        }
        const std::string& name = prop.name;
        const float cx = prop.position.x + prop.sprite->width * 0.5f - camX;
        const float cy = prop.position.y + prop.sprite->height * 0.5f - camY;
        if (name.find("LAMP_PENDANT") != std::string::npos) {
            drawGlow(cx, cy + 4.0f, 42.0f,
                     Color(1.0f, 0.65f, 0.28f,
                           Flicker(time, prop.position.x, 0.10f, 0.20f)));
        } else if (name.find("NEON") != std::string::npos) {
            drawGlow(cx, cy, 52.0f,
                     Color(1.0f, 0.25f, 0.55f,
                           Flicker(time, 7.0f, 0.10f, 0.22f)));
        } else if (name.find("WINDOW_LIT") != std::string::npos) {
            drawGlow(cx, cy, 26.0f, Color(1.0f, 0.62f, 0.25f, 0.13f));
        } else if (name.find("JUKEBOX") != std::string::npos) {
            drawGlow(cx - 4.0f, cy, 26.0f,
                     Color(0.3f, 0.9f, 0.85f, 0.14f));
            drawGlow(cx + 4.0f, cy, 26.0f,
                     Color(1.0f, 0.3f, 0.6f, 0.10f));
        } else if (name.find("MERCHANT_SIT") != std::string::npos) {
            drawGlow(cx, cy + 8.0f, 22.0f, Color(0.3f, 0.9f, 0.85f, 0.10f));
        } else if (name.find("CARGO") != std::string::npos) {
            drawGlow(cx, cy, 24.0f,
                     Color(0.3f, 0.9f, 0.85f,
                           Flicker(time, 3.0f, 0.08f, 0.16f)));
        } else if (name.find("PART") != std::string::npos) {
            drawGlow(cx, cy, 16.0f, Color(0.35f, 0.9f, 0.8f, 0.16f));
        } else if (name.find("ALARM") != std::string::npos && alarm) {
            const float pulse = 0.10f + 0.12f * (0.5f + 0.5f * std::sin(time * 6.0f));
            drawGlow(cx, cy, 40.0f, Color(1.0f, 0.15f, 0.25f, pulse));
        }
    }
}

void GameRenderer::DrawRain(const std::vector<RainDrop>& drops)
{
    if (m_device == nullptr) {
        return;
    }
    for (const RainDrop& drop : drops) {
        DrawSprite("FX_RAIN", drop.x, drop.y, 1.5f, drop.length,
                   Color(0.55f, 0.78f, 0.82f, drop.alpha), false);
    }
}

void GameRenderer::DrawPostOverlay(float damageFlash)
{
    if (m_device == nullptr) {
        return;
    }
    DrawSprite("UI_VIGNETTE", 0.0f, 0.0f, INTERNAL_WIDTH, INTERNAL_HEIGHT,
               Color(1.0f, 1.0f, 1.0f, 0.85f));
    for (int y = 0; y < INTERNAL_HEIGHT; y += 3) {
        DrawRect(RectF(0.0f, static_cast<float>(y),
                       static_cast<float>(INTERNAL_WIDTH), 1.0f),
                 Color(0.0f, 0.0f, 0.0f, 0.045f));
    }
    if (damageFlash > 0.001f) {
        DrawRect(RectF(0.0f, 0.0f, static_cast<float>(INTERNAL_WIDTH),
                       static_cast<float>(INTERNAL_HEIGHT)),
                 Color(0.7f, 0.05f, 0.08f, Clamp(damageFlash, 0.0f, 0.5f)));
    }
}

} // namespace fc
