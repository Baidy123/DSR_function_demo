#include "Render_Texture.hpp"

#include "Shared_Log.hpp"

#include <cstring>

namespace fc {

bool Texture::Create(ID3D11Device* device, const uint8_t* bgra, int width,
                     int height, bool linear, const char* debugName)
{
    Reset();
    if (device == nullptr || bgra == nullptr || width <= 0 || height <= 0) {
        return false;
    }

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = static_cast<UINT>(width);
    desc.Height = static_cast<UINT>(height);
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    desc.Usage = D3D11_USAGE_IMMUTABLE;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    desc.CPUAccessFlags = 0;
    desc.MiscFlags = 0;

    D3D11_SUBRESOURCE_DATA initial = {};
    initial.pSysMem = bgra;
    initial.SysMemPitch = static_cast<UINT>(width * 4);
    initial.SysMemSlicePitch = 0;

    if (FAILED(device->CreateTexture2D(&desc, &initial,
                                       m_texture.GetAddressOf()))) {
        LogError("CreateTexture2D failed for %s",
                 debugName != nullptr ? debugName : "unknown");
        return false;
    }

    D3D11_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
    srvDesc.Format = desc.Format;
    srvDesc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    srvDesc.Texture2D.MipLevels = 1;
    srvDesc.Texture2D.MostDetailedMip = 0;
    if (FAILED(device->CreateShaderResourceView(m_texture.Get(), &srvDesc,
                                                m_srv.GetAddressOf()))) {
        LogError("CreateShaderResourceView failed for %s",
                 debugName != nullptr ? debugName : "unknown");
        Reset();
        return false;
    }

    (void)linear;
    m_width = width;
    m_height = height;
    if (debugName != nullptr) {
        m_texture->SetPrivateData(WKPDID_D3DDebugObjectName,
                                  static_cast<UINT>(strlen(debugName)),
                                  debugName);
    }
    return true;
}

bool Texture::Attach(ID3D11Device* device, ID3D11Texture2D* texture,
                     const char* debugName)
{
    Reset();
    if (device == nullptr || texture == nullptr) {
        return false;
    }

    D3D11_TEXTURE2D_DESC desc = {};
    texture->GetDesc(&desc);

    texture->AddRef();
    m_texture.Attach(texture);

    D3D11_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
    srvDesc.Format = desc.Format;
    srvDesc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
    srvDesc.Texture2D.MipLevels = 1;
    if (FAILED(device->CreateShaderResourceView(texture, &srvDesc,
                                                m_srv.GetAddressOf()))) {
        Reset();
        return false;
    }

    m_width = static_cast<int>(desc.Width);
    m_height = static_cast<int>(desc.Height);
    if (debugName != nullptr) {
        m_texture->SetPrivateData(WKPDID_D3DDebugObjectName,
                                  static_cast<UINT>(strlen(debugName)),
                                  debugName);
    }
    return true;
}

void Texture::Reset()
{
    m_srv.Reset();
    m_texture.Reset();
    m_width = 0;
    m_height = 0;
}

} // namespace fc
