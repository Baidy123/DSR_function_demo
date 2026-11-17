#ifndef __WORLD_MAP_HPP__
#define __WORLD_MAP_HPP__

#include "Shared_Types.hpp"
#include "World_Types.hpp"

#include <string>
#include <vector>

namespace fc {

class RenderDevice;

/**
 * @brief 运行时道具实例（含 NPC 精灵）。
 */
struct PropInstance {
    std::string name;
    const Sprite* sprite = nullptr;
    Vec2 position;
    RectF collision;
    bool blocking = true;
    bool visible = true;
};

/**
 * @brief 运行时交互点实例。
 */
struct InteractInstance {
    std::string id;
    Vec2 position;
    float radius = 28.0f;
    std::string prompt;
    bool active = true;
};

/**
 * @brief 世界地图：瓷砖、碰撞、道具与交互点。
 */
class WorldMap {
public:
    /**
     * @brief 从蓝本加载地图并解析精灵。
     * @param [IN] definition 场景蓝本。
     * @param [IN] renderer 渲染设备，用于解析精灵。
     * @return 成功返回 true。
     */
    bool Load(const SceneDefinition& definition, RenderDevice* renderer);

    /**
     * @brief 清空数据。
     */
    void Clear();

    /**
     * @brief 获取场景定义。
     * @return 场景定义引用。
     */
    const SceneDefinition& Definition() const { return m_definition; }

    /**
     * @brief 获取地图像素宽度。
     * @return 宽度。
     */
    int PixelWidth() const { return m_definition.PixelWidth(); }

    /**
     * @brief 获取地图像素高度。
     * @return 高度。
     */
    int PixelHeight() const { return m_definition.PixelHeight(); }

    /**
     * @brief 获取瓷砖精灵名。
     * @param [IN] tileX 瓷砖 x。
     * @param [IN] tileY 瓷砖 y。
     * @return 资产名；越界返回空串。
     */
    const std::string& TileSpriteName(int tileX, int tileY) const;

    /**
     * @brief 查询瓷砖是否阻挡。
     * @param [IN] tileX 瓷砖 x。
     * @param [IN] tileY 瓷砖 y。
     * @return 阻挡返回 true。
     */
    bool IsTileBlocked(int tileX, int tileY) const;

    /**
     * @brief 判断圆形是否与地图或阻挡道具相交。
     * @param [IN] center 圆心（脚底坐标）。
     * @param [IN] radius 半径。
     * @return 相交返回 true。
     */
    bool IsBlockedCircle(const Vec2& center, float radius) const;

    /**
     * @brief 点是否被阻挡。
     * @param [IN] point 世界坐标。
     * @return 阻挡返回 true。
     */
    bool IsPointBlocked(const Vec2& point) const;

    /**
     * @brief 轴分离移动圆形，遇阻时沿另一轴滑动。
     * @param [IN/OUT] position 位置，会被修改。
     * @param [IN] delta 位移。
     * @param [IN] radius 半径。
     * @return 发生移动返回 true。
     */
    bool MoveCircle(Vec2& position, Vec2 delta, float radius) const;

    /**
     * @brief 视线是否被墙体或道具阻挡。
     * @param [IN] from 起点。
     * @param [IN] to 终点。
     * @return 被阻挡返回 true。
     */
    bool IsLineBlocked(const Vec2& from, const Vec2& to) const;

    /**
     * @brief 获取道具列表。
     * @return 道具列表。
     */
    std::vector<PropInstance>& Props() { return m_props; }

    /**
     * @brief 获取只读道具列表。
     * @return 道具列表。
     */
    const std::vector<PropInstance>& Props() const { return m_props; }

    /**
     * @brief 获取交互点列表。
     * @return 交互点列表。
     */
    std::vector<InteractInstance>& Interacts() { return m_interacts; }

    /**
     * @brief 获取只读交互点列表。
     * @return 交互点列表。
     */
    const std::vector<InteractInstance>& Interacts() const { return m_interacts; }

    /**
     * @brief 按 ID 查找交互点。
     * @param [IN] id 交互 ID。
     * @return 找到返回指针。
     */
    InteractInstance* FindInteract(const char* id);

    /**
     * @brief 隐藏指定道具（按资产名）。
     * @param [IN] spriteName 资产名。
     */
    void HideProp(const std::string& spriteName);

    /**
     * @brief 替换指定道具的精灵（按资产名）。
     * @param [IN] oldSpriteName 旧资产名。
     * @param [IN] newSpriteName 新资产名。
     * @param [IN] renderer 渲染设备。
     * @return 找到并替换返回 true。
     */
    bool ReplacePropSprite(const std::string& oldSpriteName,
                           const std::string& newSpriteName,
                           RenderDevice* renderer);

private:
    std::string MapTileSprite(char cell) const;

    SceneDefinition m_definition;
    std::vector<std::string> m_tileSprites;
    std::vector<uint8_t> m_blocked;
    std::vector<PropInstance> m_props;
    std::vector<InteractInstance> m_interacts;
    RenderDevice* m_renderer = nullptr;
};

} // namespace fc

#endif // __WORLD_MAP_HPP__
