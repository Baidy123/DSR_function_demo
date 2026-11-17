#ifndef __RENDER_SPRITEBATCH_HPP__
#define __RENDER_SPRITEBATCH_HPP__

#include "Render_Texture.hpp"
#include "Shared_Types.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <d3d11.h>

#include <vector>

namespace fc {

/**
 * @brief SpriteBatch 所需的共享管线对象，由 RenderDevice 创建并持有。
 */
struct SpritePipeline {
    ID3D11VertexShader* vertexShader = nullptr;
    ID3D11PixelShader* pixelShader = nullptr;
    ID3D11InputLayout* inputLayout = nullptr;
    ID3D11Buffer* constantBuffer = nullptr;
    ID3D11SamplerState* pointSampler = nullptr;
    ID3D11SamplerState* linearSampler = nullptr;
    ID3D11BlendState* alphaBlend = nullptr;
    ID3D11BlendState* additiveBlend = nullptr;
    ID3D11RasterizerState* rasterizer = nullptr;
    ID3D11DepthStencilState* depthDisabled = nullptr;
};

/**
 * @brief 2D 精灵批处理：按纹理、采样器与混合模式自动分批。
 */
class SpriteBatch {
public:
    SpriteBatch() = default;
    ~SpriteBatch() = default;

    /**
     * @brief 初始化动态缓冲与管线引用。
     * @param [IN] device D3D11 设备。
     * @param [IN] context 设备上下文。
     * @param [IN] pipeline 共享管线对象。
     * @return 成功返回 true。
     */
    bool Initialize(ID3D11Device* device, ID3D11DeviceContext* context,
                    const SpritePipeline& pipeline);

    /**
     * @brief 开始一批绘制。
     * @param [IN] width 目标宽度（像素）。
     * @param [IN] height 目标高度（像素）。
     */
    void Begin(int width, int height);

    /**
     * @brief 结束并提交剩余绘制。
     */
    void End();

    /**
     * @brief 绘制整张纹理。
     * @param [IN] texture 纹理。
     * @param [IN] x 目标左上角 x。
     * @param [IN] y 目标左上角 y。
     * @param [IN] w 目标宽度。
     * @param [IN] h 目标高度。
     * @param [IN] tint 颜色乘数。
     * @param [IN] additive 是否加色混合。
     * @param [IN] linear 是否线性采样。
     */
    void DrawTexture(const Texture& texture, float x, float y, float w, float h,
                     Color tint, bool additive = false, bool linear = false);

    /**
     * @brief 绘制纹理的指定源区域。
     * @param [IN] texture 纹理。
     * @param [IN] x 目标左上角 x。
     * @param [IN] y 目标左上角 y。
     * @param [IN] w 目标宽度。
     * @param [IN] h 目标高度。
     * @param [IN] src 源像素矩形。
     * @param [IN] tint 颜色乘数。
     * @param [IN] flipX 是否水平翻转。
     * @param [IN] additive 是否加色混合。
     * @param [IN] linear 是否线性采样。
     */
    void DrawTextureRegion(const Texture& texture, float x, float y, float w,
                           float h, const RectF& src, Color tint,
                           bool flipX = false, bool additive = false,
                           bool linear = false);

    /**
     * @brief 刷新当前批次。
     */
    void Flush();

private:
    struct Vertex {
        float x;
        float y;
        float u;
        float v;
        float r;
        float g;
        float b;
        float a;
    };

    static constexpr int MAX_QUADS = 8192;

    void AppendQuad(const Texture& texture, float x, float y, float w, float h,
                    float u0, float v0, float u1, float v1, Color tint,
                    bool flipX, bool additive, bool linear);

    ID3D11Device* m_device = nullptr;
    ID3D11DeviceContext* m_context = nullptr;
    SpritePipeline m_pipeline;

    ComPtr<ID3D11Buffer> m_vertexBuffer;
    ComPtr<ID3D11Buffer> m_indexBuffer;
    ComPtr<ID3D11Buffer> m_constantBuffer;

    std::vector<Vertex> m_vertices;
    const Texture* m_currentTexture = nullptr;
    bool m_currentAdditive = false;
    bool m_currentLinear = false;
    int m_quadCount = 0;
    int m_width = 0;
    int m_height = 0;
    bool m_inFrame = false;
};

} // namespace fc

#endif // __RENDER_SPRITEBATCH_HPP__
