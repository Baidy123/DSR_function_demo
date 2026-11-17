#ifndef __GAME_RENDERER_HPP__
#define __GAME_RENDERER_HPP__

#include "Game_Types.hpp"
#include "Shared_Types.hpp"
#include "World_Map.hpp"

#include <string>
#include <vector>

namespace fc {

class RenderDevice;
class TextRenderer;

/**
 * @brief 世界渲染器：瓷砖、道具、角色、子弹、粒子、灯光与后处理。
 *
 * 调用前必须由 GameApp 执行 SpriteBatch::Begin；本类不负责 Present。
 */
class GameRenderer {
public:
    /**
     * @brief 初始化。
     * @param [IN] device 渲染设备。
     * @param [IN] text 文字渲染器（当前未直接使用，保留扩展）。
     * @return 成功返回 true。
     */
    bool Initialize(RenderDevice* device, TextRenderer* text);

    /**
     * @brief 绘制世界。
     * @param [IN] map 地图。
     * @param [IN] player 玩家。
     * @param [IN] enemies 敌人列表。
     * @param [IN] bullets 子弹列表。
     * @param [IN] particles 粒子列表。
     * @param [IN] pickups 掉落物列表。
     * @param [IN] camera 摄像机。
     * @param [IN] shake 屏幕震动偏移。
     * @param [IN] time 累计时间（秒）。
     * @param [IN] alarm 是否处于警报状态。
     */
    void DrawWorld(const WorldMap& map, const Player& player,
                   const std::vector<Enemy>& enemies,
                   const std::vector<Bullet>& bullets,
                   const std::vector<Particle>& particles,
                   const std::vector<Pickup>& pickups, const Camera& camera,
                   Vec2 shake, float time, bool alarm);

    /**
     * @brief 绘制雨滴（屏幕空间）。
     * @param [IN] drops 雨滴列表。
     */
    void DrawRain(const std::vector<RainDrop>& drops);

    /**
     * @brief 绘制暗角、扫描线与受伤红闪。
     * @param [IN] damageFlash 受伤红闪强度（0–1）。
     */
    void DrawPostOverlay(float damageFlash);

    /**
     * @brief 绘制纯色矩形（白纹理着色）。
     * @param [IN] rect 目标矩形。
     * @param [IN] color 颜色。
     */
    void DrawRect(const RectF& rect, Color color);

    /**
     * @brief 绘制图标精灵。
     * @param [IN] name 资产名。
     * @param [IN] x 左上角 x。
     * @param [IN] y 左上角 y。
     * @param [IN] w 宽度。
     * @param [IN] h 高度。
     * @param [IN] tint 颜色。
     * @param [IN] additive 是否加色。
     */
    void DrawSprite(const char* name, float x, float y, float w, float h,
                    Color tint, bool additive = false);

    /**
     * @brief 获取渲染设备。
     * @return 渲染设备指针。
     */
    RenderDevice* Device() const { return m_device; }

private:
    struct DrawItem {
        float baseline = 0.0f;
        int order = 0;
        const Sprite* sprite = nullptr;
        float x = 0.0f;
        float y = 0.0f;
        float w = 0.0f;
        float h = 0.0f;
        Color tint;
        bool additive = false;
    };

    void AddPropItems(const WorldMap& map, float camX, float camY,
                      std::vector<DrawItem>& items);
    void AddActorItems(const Player& player, const std::vector<Enemy>& enemies,
                       const std::vector<Pickup>& pickups, float camX, float camY,
                       std::vector<DrawItem>& items);
    void DrawLights(const WorldMap& map, float camX, float camY, float time,
                    bool alarm);
    std::string ActorSprite(const char* prefix, int facingDir, float animTime,
                            bool moving) const;

    RenderDevice* m_device = nullptr;
    TextRenderer* m_text = nullptr;
};

} // namespace fc

#endif // __GAME_RENDERER_HPP__
