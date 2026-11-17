#ifndef __RENDER_TEXTURE_HPP__
#define __RENDER_TEXTURE_HPP__

#include "Shared_ComPtr.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <d3d11.h>

#include <cstdint>

namespace fc {

/**
 * @brief D3D11 纹理与着色器资源视图的轻量封装。
 */
class Texture {
public:
    /**
     * @brief 从 BGRA8 像素数据创建纹理。
     * @param [IN] device D3D11 设备。
     * @param [IN] bgra 像素数据，长度必须为 width * height * 4。
     * @param [IN] width 宽度。
     * @param [IN] height 高度。
     * @param [IN] linear 是否使用线性采样（文字为 true）。
     * @param [IN] debugName 调试名称，可为空。
     * @return 成功返回 true。
     */
    bool Create(ID3D11Device* device, const uint8_t* bgra, int width, int height,
                bool linear, const char* debugName);

    /**
     * @brief 包装一个已有纹理并创建 SRV（会增加引用计数）。
     * @param [IN] device D3D11 设备。
     * @param [IN] texture 已有纹理。
     * @param [IN] debugName 调试名称。
     * @return 成功返回 true。
     */
    bool Attach(ID3D11Device* device, ID3D11Texture2D* texture,
                const char* debugName);

    /**
     * @brief 释放纹理。
     */
    void Reset();

    int Width() const { return m_width; }
    int Height() const { return m_height; }
    ID3D11ShaderResourceView* SRV() const { return m_srv.Get(); }
    ID3D11Texture2D* Raw() const { return m_texture.Get(); }
    bool IsValid() const { return m_texture != nullptr && m_srv != nullptr; }

private:
    ComPtr<ID3D11Texture2D> m_texture;
    ComPtr<ID3D11ShaderResourceView> m_srv;
    int m_width = 0;
    int m_height = 0;
};

} // namespace fc

#endif // __RENDER_TEXTURE_HPP__
