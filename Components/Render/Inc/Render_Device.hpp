#ifndef __RENDER_DEVICE_HPP__
#define __RENDER_DEVICE_HPP__

#include "Render_SpriteBatch.hpp"
#include "Render_Texture.hpp"
#include "Shared_Types.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <d3d11.h>

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace fc {

/**
 * @brief D3D11 渲染设备：交换链、离屏目标、资产图谱与呈现。
 *
 * 游戏以 480×270 渲染到离屏纹理，再整数倍最近邻放大到窗口。
 */
class RenderDevice {
public:
    RenderDevice() = default;
    ~RenderDevice();

    /**
     * @brief 初始化设备、交换链、离屏目标与精灵管线。
     * @param [IN] hwnd 窗口句柄。
     * @param [IN] width 客户区宽度。
     * @param [IN] height 客户区高度。
     * @return 成功返回 true。
     */
    bool Initialize(HWND hwnd, int width, int height);

    /**
     * @brief 释放全部资源。
     */
    void Shutdown();

    /**
     * @brief 调整交换链尺寸。
     * @param [IN] width 新客户区宽度。
     * @param [IN] height 新客户区高度。
     * @return 成功返回 true。
     */
    bool Resize(int width, int height);

    /**
     * @brief 解析 FCPK 资产包并建立图集/精灵索引。
     * @param [IN] packData 资产包字节。
     * @return 成功返回 true。
     */
    bool LoadArtPack(const std::vector<uint8_t>& packData);

    /**
     * @brief 从 BGRA8 数据创建纹理。
     * @param [IN] bgra 像素数据。
     * @param [IN] width 宽度。
     * @param [IN] height 高度。
     * @param [IN] linear 是否线性采样（仅记录语义）。
     * @param [OUT] texture 输出纹理。
     * @param [IN] debugName 调试名称。
     * @return 成功返回 true。
     */
    bool CreateTexture(const uint8_t* bgra, int width, int height, bool linear,
                       Texture& texture, const char* debugName);

    /**
     * @brief 绑定离屏目标并清屏。
     */
    void BeginFrame();

    /**
     * @brief 结束场景绘制（保留接口）。
     */
    void EndFrame();

    /**
     * @brief 将离屏纹理放大呈现到窗口。
     * @param [IN] vsync 是否垂直同步。
     */
    void Present(bool vsync);

    /**
     * @brief 将离屏画面保存为 BMP（无头验证用）。
     * @param [IN] path 输出路径。
     * @return 成功返回 true。
     */
    bool CaptureOffscreen(const std::string& path);

    /**
     * @brief 按名称查找精灵。
     * @param [IN] name 资产名。
     * @return 找到返回指针；否则返回占位精灵。
     */
    const Sprite* FindSprite(const char* name) const;

    /**
     * @brief 获取 1×1 白色精灵（用于纯色矩形）。
     * @return 白色精灵。
     */
    const Sprite& WhiteSprite() const { return m_whiteSprite; }

    /**
     * @brief 获取精灵批处理。
     * @return 批处理引用。
     */
    SpriteBatch& Batch() { return m_batch; }

    /**
     * @brief 将窗口客户区坐标转换为内部 480×270 坐标。
     * @param [IN] screen 客户区坐标。
     * @return 内部坐标（可能超出边界）。
     */
    Vec2 ScreenToInternal(Vec2 screen) const;

    /**
     * @brief 当前整数缩放倍率。
     * @return 倍率。
     */
    int Scale() const { return m_scale; }

    /**
     * @brief 当前客户区尺寸。
     * @return 宽度。
     */
    int WindowWidth() const { return m_windowWidth; }

    /**
     * @brief 当前客户区尺寸。
     * @return 高度。
     */
    int WindowHeight() const { return m_windowHeight; }

    /**
     * @brief 离屏画面在窗口中的位置与尺寸。
     * @return 目标矩形。
     */
    const RectF& Letterbox() const { return m_letterbox; }

    /**
     * @brief 是否已初始化。
     * @return 就绪返回 true。
     */
    bool IsReady() const { return m_device != nullptr; }

    /**
     * @brief 获取离屏纹理（用于调试）。
     * @return 纹理引用。
     */
    const Texture& OffscreenTexture() const { return m_offscreenTexture; }

private:
    bool CreatePipeline();
    bool CreateOffscreenTarget();
    bool CreateBlendStates();
    void CreateWhiteAndMissing();
    bool UploadAtlas(const std::vector<uint8_t>& packData);
    void UpdateLetterbox();
    bool WriteBmp(const std::string& path, const uint8_t* bgra, int width,
                  int height, int pitch);

    HWND m_hwnd = nullptr;
    int m_windowWidth = 0;
    int m_windowHeight = 0;
    int m_scale = 1;
    RectF m_letterbox;

    ComPtr<ID3D11Device> m_device;
    ComPtr<ID3D11DeviceContext> m_context;
    ComPtr<IDXGISwapChain> m_swapChain;
    ComPtr<ID3D11RenderTargetView> m_backBufferRTV;
    ComPtr<ID3D11Texture2D> m_backBuffer;

    ComPtr<ID3D11Texture2D> m_offscreenRaw;
    ComPtr<ID3D11RenderTargetView> m_offscreenRTV;
    Texture m_offscreenTexture;

    ComPtr<ID3D11VertexShader> m_vertexShader;
    ComPtr<ID3D11PixelShader> m_pixelShader;
    ComPtr<ID3D11InputLayout> m_inputLayout;
    ComPtr<ID3D11Buffer> m_projectionBuffer;
    ComPtr<ID3D11SamplerState> m_pointSampler;
    ComPtr<ID3D11SamplerState> m_linearSampler;
    ComPtr<ID3D11BlendState> m_alphaBlend;
    ComPtr<ID3D11BlendState> m_additiveBlend;
    ComPtr<ID3D11RasterizerState> m_rasterizer;
    SpritePipeline m_pipeline;
    SpriteBatch m_batch;

    Texture m_atlas;
    std::vector<std::unique_ptr<Texture>> m_ownedTextures;
    std::unordered_map<std::string, Sprite> m_sprites;
    Sprite m_whiteSprite;
    Sprite m_missingSprite;
    Texture m_whiteTexture;
    Texture m_missingTexture;
};

} // namespace fc

#endif // __RENDER_DEVICE_HPP__
