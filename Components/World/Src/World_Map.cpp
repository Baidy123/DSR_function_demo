#include "World_Map.hpp"

#include "Render_Device.hpp"
#include "Shared_Log.hpp"
#include "Shared_Math.hpp"

#include <algorithm>
#include <cmath>

namespace fc {

namespace {

bool IsBlockingCell(char cell)
{
    switch (cell) {
    case '#':
    case '=':
    case 'W':
    case 'S':
    case 'D':
    case ' ':
        return true;
    default:
        return false;
    }
}

} // namespace

bool WorldMap::Load(const SceneDefinition& definition, RenderDevice* renderer)
{
    Clear();
    m_definition = definition;
    m_renderer = renderer;
    if (definition.widthTiles <= 0 || definition.heightTiles <= 0) {
        return false;
    }

    m_tileSprites.assign(static_cast<size_t>(definition.widthTiles) *
                             definition.heightTiles,
                         std::string());
    m_blocked.assign(static_cast<size_t>(definition.widthTiles) *
                         definition.heightTiles,
                     0);

    for (int y = 0; y < definition.heightTiles; ++y) {
        const std::string row = (static_cast<size_t>(y) < definition.tiles.size())
                                    ? definition.tiles[static_cast<size_t>(y)]
                                    : std::string();
        if (static_cast<int>(row.size()) != definition.widthTiles) {
            LogWarn("Scene row %d has width %zu, expected %d", y, row.size(),
                    definition.widthTiles);
        }
        for (int x = 0; x < definition.widthTiles; ++x) {
            char cell = ' ';
            if (x < static_cast<int>(row.size())) {
                cell = row[static_cast<size_t>(x)];
            }
            const size_t index = static_cast<size_t>(y) * definition.widthTiles + x;
            m_tileSprites[index] = MapTileSprite(cell);
            m_blocked[index] = IsBlockingCell(cell) ? 1 : 0;
        }
    }

    m_props.clear();
    m_props.reserve(definition.props.size());
    for (const PropDef& def : definition.props) {
        PropInstance prop;
        prop.name = def.sprite;
        prop.sprite = renderer != nullptr ? renderer->FindSprite(def.sprite.c_str())
                                          : nullptr;
        prop.position = Vec2(def.x, def.y);
        prop.blocking = def.blocking;
        if (prop.sprite != nullptr) {
            prop.collision = RectF(def.x, def.y,
                                   static_cast<float>(prop.sprite->width),
                                   static_cast<float>(prop.sprite->height));
        } else {
            prop.collision = RectF(def.x, def.y, 16.0f, 16.0f);
        }
        m_props.push_back(prop);
    }

    m_interacts.clear();
    m_interacts.reserve(definition.interactions.size());
    for (const InteractDef& def : definition.interactions) {
        InteractInstance interact;
        interact.id = def.id;
        interact.position = Vec2(def.x, def.y);
        interact.radius = def.radius;
        interact.prompt = def.prompt;
        interact.active = true;
        m_interacts.push_back(interact);
    }

    LogInfo("WorldMap loaded: %s (%dx%d tiles, %zu props, %zu interacts)",
            definition.displayName.c_str(), definition.widthTiles,
            definition.heightTiles, m_props.size(), m_interacts.size());
    return true;
}

void WorldMap::Clear()
{
    m_tileSprites.clear();
    m_blocked.clear();
    m_props.clear();
    m_interacts.clear();
    m_renderer = nullptr;
}

std::string WorldMap::MapTileSprite(char cell) const
{
    switch (m_definition.theme) {
    case SceneTheme::BAR:
        switch (cell) {
        case '#': return "TILE_BAR_WALL_A";
        case '=': return "TILE_BAR_WALL_B";
        case 'W': return "TILE_BAR_WALL_WINDOW";
        case 'S': return "TILE_BAR_WALL_SHELF";
        case '~': return "TILE_BAR_CARPET_A";
        case ';': return "TILE_BAR_FLOOR_C";
        case ',': return "TILE_BAR_FLOOR_B";
        case '.': return "TILE_BAR_FLOOR_A";
        default: return "TILE_VOID";
        }
    case SceneTheme::STREET:
        switch (cell) {
        case '#': return "TILE_STREET_WALL_A";
        case '=': return "TILE_STREET_WALL_B";
        case 'W': return "TILE_BAR_WALL_WINDOW";
        case 'S': return "TILE_STREET_WALL_B";
        case 'C': return "TILE_STREET_CURB";
        case ',': return "TILE_STREET_FLOOR_B";
        case '.': return "TILE_STREET_FLOOR_A";
        default: return "TILE_VOID";
        }
    case SceneTheme::HARBOR:
    default:
        switch (cell) {
        case '#': return "TILE_HARBOR_WALL_A";
        case '=': return "TILE_HARBOR_WALL_B";
        case 'W': return "TILE_BAR_WALL_WINDOW";
        case 'S': return "TILE_HARBOR_WALL_B";
        case 'D': return "TILE_HARBOR_DOOR";
        case ';': return "TILE_HARBOR_FLOOR_C";
        case ',': return "TILE_HARBOR_FLOOR_B";
        case '.': return "TILE_HARBOR_FLOOR_A";
        default: return "TILE_VOID";
        }
    }
}

const std::string& WorldMap::TileSpriteName(int tileX, int tileY) const
{
    static const std::string empty;
    if (tileX < 0 || tileY < 0 || tileX >= m_definition.widthTiles ||
        tileY >= m_definition.heightTiles) {
        return empty;
    }
    const size_t index = static_cast<size_t>(tileY) * m_definition.widthTiles +
                         static_cast<size_t>(tileX);
    return m_tileSprites[index];
}

bool WorldMap::IsTileBlocked(int tileX, int tileY) const
{
    if (tileX < 0 || tileY < 0 || tileX >= m_definition.widthTiles ||
        tileY >= m_definition.heightTiles) {
        return true;
    }
    const size_t index = static_cast<size_t>(tileY) * m_definition.widthTiles +
                         static_cast<size_t>(tileX);
    return m_blocked[index] != 0;
}

bool WorldMap::IsPointBlocked(const Vec2& point) const
{
    const int tx = static_cast<int>(std::floor(point.x / TILE_SIZE));
    const int ty = static_cast<int>(std::floor(point.y / TILE_SIZE));
    if (IsTileBlocked(tx, ty)) {
        return true;
    }
    for (const PropInstance& prop : m_props) {
        if (prop.visible && prop.blocking &&
            PointInRect(prop.collision, point)) {
            return true;
        }
    }
    return false;
}

bool WorldMap::IsBlockedCircle(const Vec2& center, float radius) const
{
    if (center.x - radius < 0.0f || center.y - radius < 0.0f ||
        center.x + radius > static_cast<float>(PixelWidth()) ||
        center.y + radius > static_cast<float>(PixelHeight())) {
        return true;
    }

    const int minX = static_cast<int>(std::floor((center.x - radius) / TILE_SIZE));
    const int maxX = static_cast<int>(std::floor((center.x + radius) / TILE_SIZE));
    const int minY = static_cast<int>(std::floor((center.y - radius) / TILE_SIZE));
    const int maxY = static_cast<int>(std::floor((center.y + radius) / TILE_SIZE));
    for (int y = minY; y <= maxY; ++y) {
        for (int x = minX; x <= maxX; ++x) {
            if (!IsTileBlocked(x, y)) {
                continue;
            }
            const RectF rect(static_cast<float>(x * TILE_SIZE),
                             static_cast<float>(y * TILE_SIZE),
                             static_cast<float>(TILE_SIZE),
                             static_cast<float>(TILE_SIZE));
            if (CircleIntersectsRect(center, radius, rect)) {
                return true;
            }
        }
    }

    for (const PropInstance& prop : m_props) {
        if (prop.visible && prop.blocking &&
            CircleIntersectsRect(center, radius, prop.collision)) {
            return true;
        }
    }
    return false;
}

bool WorldMap::MoveCircle(Vec2& position, Vec2 delta, float radius) const
{
    bool moved = false;
    if (delta.x != 0.0f) {
        Vec2 next = position;
        next.x += delta.x;
        if (!IsBlockedCircle(next, radius)) {
            position = next;
            moved = true;
        }
    }
    if (delta.y != 0.0f) {
        Vec2 next = position;
        next.y += delta.y;
        if (!IsBlockedCircle(next, radius)) {
            position = next;
            moved = true;
        }
    }
    return moved;
}

bool WorldMap::IsLineBlocked(const Vec2& from, const Vec2& to) const
{
    const Vec2 delta = to - from;
    const float length = Length(delta);
    if (length <= 0.001f) {
        return IsPointBlocked(from);
    }
    const int steps = static_cast<int>(std::ceil(length / 6.0f));
    for (int i = 1; i <= steps; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(steps);
        if (IsPointBlocked(Vec2(from.x + delta.x * t, from.y + delta.y * t))) {
            return true;
        }
    }
    return false;
}

InteractInstance* WorldMap::FindInteract(const char* id)
{
    if (id == nullptr) {
        return nullptr;
    }
    for (InteractInstance& interact : m_interacts) {
        if (interact.id == id) {
            return &interact;
        }
    }
    return nullptr;
}

void WorldMap::HideProp(const std::string& spriteName)
{
    for (PropInstance& prop : m_props) {
        if (prop.name == spriteName) {
            prop.visible = false;
        }
    }
}

bool WorldMap::ReplacePropSprite(const std::string& oldSpriteName,
                                 const std::string& newSpriteName,
                                 RenderDevice* renderer)
{
    if (renderer == nullptr) {
        return false;
    }
    bool replaced = false;
    for (PropInstance& prop : m_props) {
        if (prop.name == oldSpriteName) {
            prop.name = newSpriteName;
            prop.sprite = renderer->FindSprite(newSpriteName.c_str());
            if (prop.sprite != nullptr) {
                prop.collision.w = static_cast<float>(prop.sprite->width);
                prop.collision.h = static_cast<float>(prop.sprite->height);
            }
            replaced = true;
        }
    }
    return replaced;
}

} // namespace fc
