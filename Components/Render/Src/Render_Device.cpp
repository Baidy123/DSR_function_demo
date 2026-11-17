#include "Render_Device.hpp"

#include "Shared_Log.hpp"
#include "Shared_Math.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <d3dcompiler.h>

#include <algorithm>
#include <cstring>
#include <fstream>
#include <vector>

namespace fc {

namespace {

const char* SPRITE_SHADER = R"(
cbuffer CB : register(b0)
{
    row_major float4x4 uProjection;
};

struct VSInput
{
    float2 position : POSITION;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

struct VSOutput
{
    float4 position : SV_POSITION;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

VSOutput VSMain(VSInput input)
{
    VSOutput output;
    output.position = mul(float4(input.position, 0.0f, 1.0f), uProjection);
    output.uv = input.uv;
    output.color = input.color;
    return output;
}

Texture2D uTexture : register(t0);
SamplerState uSampler : register(s0);

float4 PSMain(VSOutput input) : SV_TARGET
{
    return uTexture.Sample(uSampler, input.uv) * input.color;
}
)";

void WriteU16(std::ofstream& file, uint16_t value)
{
    const uint8_t bytes[2] = {
        static_cast<uint8_t>(value & 0xFF),
        static_cast<uint8_t>((value >> 8) & 0xFF)
    };
    file.write(reinterpret_cast<const char*>(bytes), 2);
}

void WriteU32(std::ofstream& file, uint32_t value)
{
    const uint8_t bytes[4] = {
        static_cast<uint8_t>(value & 0xFF),
        static_cast<uint8_t>((value >> 8) & 0xFF),
        static_cast<uint8_t>((value >> 16) & 0xFF),
        static_cast<uint8_t>((value >> 24) & 0xFF)
    };
    file.write(reinterpret_cast<const char*>(bytes), 4);
}

uint16_t ReadU16(const uint8_t* data)
{
    return static_cast<uint16_t>(data[0] | (static_cast<uint16_t>(data[1]) << 8));
}

uint32_t ReadU32(const uint8_t* data)
{
    return static_cast<uint32_t>(data[0]) |
           (static_cast<uint32_t>(data[1]) << 8) |
           (static_cast<uint32_t>(data[2]) << 16) |
           (static_cast<uint32_t>(data[3]) << 24);
}

} // namespace

RenderDevice::~RenderDevice()
{
    Shutdown();
}

bool RenderDevice::Initialize(HWND hwnd, int width, int height)
{
    m_hwnd = hwnd;
    m_windowWidth = width > 0 ? width : WINDOW_WIDTH;
    m_windowHeight = height > 0 ? height : WINDOW_HEIGHT;

    DXGI_SWAP_CHAIN_DESC swapDesc = {};
    swapDesc.BufferCount = 2;
    swapDesc.BufferDesc.Width = static_cast<UINT>(m_windowWidth);
    swapDesc.BufferDesc.Height = static_cast<UINT>(m_windowHeight);
    swapDesc.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    swapDesc.BufferDesc.RefreshRate.Numerator = 60;
    swapDesc.BufferDesc.RefreshRate.Denominator = 1;
    swapDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swapDesc.OutputWindow = hwnd;
    swapDesc.SampleDesc.Count = 1;
    swapDesc.SampleDesc.Quality = 0;
    swapDesc.Windowed = TRUE;
    swapDesc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0
    };
    D3D_FEATURE_LEVEL featureLevel = D3D_FEATURE_LEVEL_10_0;
    const UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;

    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels,
        static_cast<UINT>(sizeof(levels) / sizeof(levels[0])),
        D3D11_SDK_VERSION, &swapDesc, m_swapChain.GetAddressOf(),
        m_device.GetAddressOf(), &featureLevel, m_context.GetAddressOf());
    if (FAILED(hr)) {
        LogWarn("Hardware D3D11 device failed (0x%08X), trying WARP",
                static_cast<unsigned int>(hr));
        m_swapChain.Reset();
        m_device.Reset();
        m_context.Reset();
        hr = D3D11CreateDeviceAndSwapChain(
            nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags, levels,
            static_cast<UINT>(sizeof(levels) / sizeof(levels[0])),
            D3D11_SDK_VERSION, &swapDesc, m_swapChain.GetAddressOf(),
            m_device.GetAddressOf(), &featureLevel, m_context.GetAddressOf());
    }
    if (FAILED(hr)) {
        LogError("D3D11CreateDeviceAndSwapChain failed: 0x%08X",
                 static_cast<unsigned int>(hr));
        return false;
    }

    if (FAILED(m_swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D),
                                      reinterpret_cast<void**>(
                                          m_backBuffer.GetAddressOf())))) {
        LogError("Failed to get swap chain back buffer");
        return false;
    }
    if (FAILED(m_device->CreateRenderTargetView(m_backBuffer.Get(), nullptr,
                                                m_backBufferRTV.GetAddressOf()))) {
        LogError("Failed to create back buffer RTV");
        return false;
    }

    if (!CreatePipeline()) {
        return false;
    }
    if (!CreateOffscreenTarget()) {
        return false;
    }
    CreateWhiteAndMissing();
    UpdateLetterbox();
    LogInfo("RenderDevice initialized (%dx%d, scale %d)", m_windowWidth,
            m_windowHeight, m_scale);
    return true;
}

bool RenderDevice::CreatePipeline()
{
    ComPtr<ID3DBlob> vertexBlob;
    ComPtr<ID3DBlob> pixelBlob;
    ComPtr<ID3DBlob> errorBlob;

    UINT compileFlags = D3DCOMPILE_ENABLE_STRICTNESS;
    HRESULT hr = D3DCompile(SPRITE_SHADER, std::strlen(SPRITE_SHADER), "SpriteShader",
                            nullptr, nullptr, "VSMain", "vs_5_0", compileFlags, 0,
                            vertexBlob.GetAddressOf(), errorBlob.GetAddressOf());
    if (FAILED(hr)) {
        if (errorBlob) {
            LogError("Vertex shader compile failed: %s",
                     static_cast<const char*>(errorBlob->GetBufferPointer()));
        }
        return false;
    }

    hr = D3DCompile(SPRITE_SHADER, std::strlen(SPRITE_SHADER), "SpriteShader",
                    nullptr, nullptr, "PSMain", "ps_5_0", compileFlags, 0,
                    pixelBlob.GetAddressOf(), errorBlob.GetAddressOf());
    if (FAILED(hr)) {
        if (errorBlob) {
            LogError("Pixel shader compile failed: %s",
                     static_cast<const char*>(errorBlob->GetBufferPointer()));
        }
        return false;
    }

    if (FAILED(m_device->CreateVertexShader(vertexBlob->GetBufferPointer(),
                                            vertexBlob->GetBufferSize(), nullptr,
                                            m_vertexShader.GetAddressOf()))) {
        LogError("CreateVertexShader failed");
        return false;
    }
    if (FAILED(m_device->CreatePixelShader(pixelBlob->GetBufferPointer(),
                                           pixelBlob->GetBufferSize(), nullptr,
                                           m_pixelShader.GetAddressOf()))) {
        LogError("CreatePixelShader failed");
        return false;
    }

    const D3D11_INPUT_ELEMENT_DESC layout[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0,
         D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 8,
         D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"COLOR", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 16,
         D3D11_INPUT_PER_VERTEX_DATA, 0}
    };
    if (FAILED(m_device->CreateInputLayout(layout, 3,
                                           vertexBlob->GetBufferPointer(),
                                           vertexBlob->GetBufferSize(),
                                           m_inputLayout.GetAddressOf()))) {
        LogError("CreateInputLayout failed");
        return false;
    }

    D3D11_BUFFER_DESC cbDesc = {};
    cbDesc.Usage = D3D11_USAGE_DYNAMIC;
    cbDesc.ByteWidth = 64;
    cbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    cbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(m_device->CreateBuffer(&cbDesc, nullptr,
                                      m_projectionBuffer.GetAddressOf()))) {
        LogError("CreateBuffer (projection) failed");
        return false;
    }

    D3D11_SAMPLER_DESC samplerDesc = {};
    samplerDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
    samplerDesc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    samplerDesc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    samplerDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    samplerDesc.ComparisonFunc = D3D11_COMPARISON_NEVER;
    samplerDesc.MinLOD = 0.0f;
    samplerDesc.MaxLOD = D3D11_FLOAT32_MAX;
    if (FAILED(m_device->CreateSamplerState(&samplerDesc,
                                            m_pointSampler.GetAddressOf()))) {
        return false;
    }

    samplerDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    if (FAILED(m_device->CreateSamplerState(&samplerDesc,
                                            m_linearSampler.GetAddressOf()))) {
        return false;
    }

    if (!CreateBlendStates()) {
        return false;
    }

    D3D11_RASTERIZER_DESC rasterDesc = {};
    rasterDesc.FillMode = D3D11_FILL_SOLID;
    rasterDesc.CullMode = D3D11_CULL_NONE;
    rasterDesc.DepthClipEnable = FALSE;
    rasterDesc.ScissorEnable = FALSE;
    rasterDesc.MultisampleEnable = FALSE;
    rasterDesc.AntialiasedLineEnable = FALSE;
    if (FAILED(m_device->CreateRasterizerState(&rasterDesc,
                                               m_rasterizer.GetAddressOf()))) {
        LogError("CreateRasterizerState failed");
        return false;
    }

    m_pipeline.vertexShader = m_vertexShader.Get();
    m_pipeline.pixelShader = m_pixelShader.Get();
    m_pipeline.inputLayout = m_inputLayout.Get();
    m_pipeline.constantBuffer = m_projectionBuffer.Get();
    m_pipeline.pointSampler = m_pointSampler.Get();
    m_pipeline.linearSampler = m_linearSampler.Get();
    m_pipeline.alphaBlend = m_alphaBlend.Get();
    m_pipeline.additiveBlend = m_additiveBlend.Get();
    m_pipeline.rasterizer = m_rasterizer.Get();

    if (!m_batch.Initialize(m_device.Get(), m_context.Get(), m_pipeline)) {
        return false;
    }
    return true;
}

bool RenderDevice::CreateBlendStates()
{
    D3D11_BLEND_DESC blendDesc = {};
    blendDesc.RenderTarget[0].BlendEnable = TRUE;
    blendDesc.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
    blendDesc.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
    blendDesc.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
    blendDesc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
    blendDesc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA;
    blendDesc.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
    blendDesc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    if (FAILED(m_device->CreateBlendState(&blendDesc,
                                          m_alphaBlend.GetAddressOf()))) {
        LogError("CreateBlendState (alpha) failed");
        return false;
    }

    blendDesc.RenderTarget[0].DestBlend = D3D11_BLEND_ONE;
    blendDesc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ONE;
    if (FAILED(m_device->CreateBlendState(&blendDesc,
                                          m_additiveBlend.GetAddressOf()))) {
        LogError("CreateBlendState (additive) failed");
        return false;
    }
    return true;
}

bool RenderDevice::CreateOffscreenTarget()
{
    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = INTERNAL_WIDTH;
    desc.Height = INTERNAL_HEIGHT;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(m_device->CreateTexture2D(&desc, nullptr,
                                         m_offscreenRaw.GetAddressOf()))) {
        LogError("Failed to create offscreen texture");
        return false;
    }
    if (FAILED(m_device->CreateRenderTargetView(m_offscreenRaw.Get(), nullptr,
                                                m_offscreenRTV.GetAddressOf()))) {
        LogError("Failed to create offscreen RTV");
        return false;
    }
    if (!m_offscreenTexture.Attach(m_device.Get(), m_offscreenRaw.Get(),
                                   "OffscreenColor")) {
        LogError("Failed to wrap offscreen texture");
        return false;
    }
    return true;
}

void RenderDevice::CreateWhiteAndMissing()
{
    const uint8_t white[4] = {255, 255, 255, 255};
    if (m_whiteTexture.Create(m_device.Get(), white, 1, 1, false, "White")) {
        m_whiteSprite.texture = &m_whiteTexture;
        m_whiteSprite.width = 1;
        m_whiteSprite.height = 1;
        m_whiteSprite.u0 = 0.0f;
        m_whiteSprite.v0 = 0.0f;
        m_whiteSprite.u1 = 1.0f;
        m_whiteSprite.v1 = 1.0f;
    }

    uint8_t missing[4 * 4 * 4];
    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            const bool magenta = ((x + y) & 1) == 0;
            const size_t index = (static_cast<size_t>(y) * 4 + x) * 4;
            missing[index + 0] = magenta ? 255 : 0;
            missing[index + 1] = 0;
            missing[index + 2] = magenta ? 255 : 0;
            missing[index + 3] = 255;
        }
    }
    if (m_missingTexture.Create(m_device.Get(), missing, 4, 4, false, "Missing")) {
        m_missingSprite.texture = &m_missingTexture;
        m_missingSprite.width = 4;
        m_missingSprite.height = 4;
        m_missingSprite.u0 = 0.0f;
        m_missingSprite.v0 = 0.0f;
        m_missingSprite.u1 = 1.0f;
        m_missingSprite.v1 = 1.0f;
    }
}

bool RenderDevice::Resize(int width, int height)
{
    if (m_swapChain == nullptr || width <= 0 || height <= 0) {
        return false;
    }
    if (width == m_windowWidth && height == m_windowHeight) {
        return true;
    }
    m_windowWidth = width;
    m_windowHeight = height;
    m_backBufferRTV.Reset();
    m_backBuffer.Reset();
    if (FAILED(m_swapChain->ResizeBuffers(0, static_cast<UINT>(width),
                                          static_cast<UINT>(height),
                                          DXGI_FORMAT_UNKNOWN, 0))) {
        LogError("ResizeBuffers failed");
        return false;
    }
    if (FAILED(m_swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D),
                                      reinterpret_cast<void**>(
                                          m_backBuffer.GetAddressOf())))) {
        LogError("GetBuffer after resize failed");
        return false;
    }
    if (FAILED(m_device->CreateRenderTargetView(m_backBuffer.Get(), nullptr,
                                                m_backBufferRTV.GetAddressOf()))) {
        LogError("CreateRenderTargetView after resize failed");
        return false;
    }
    UpdateLetterbox();
    return true;
}

void RenderDevice::UpdateLetterbox()
{
    const int scaleX = m_windowWidth / INTERNAL_WIDTH;
    const int scaleY = m_windowHeight / INTERNAL_HEIGHT;
    m_scale = scaleX < scaleY ? scaleX : scaleY;
    if (m_scale < 1) {
        m_scale = 1;
    }
    const float drawW = static_cast<float>(INTERNAL_WIDTH * m_scale);
    const float drawH = static_cast<float>(INTERNAL_HEIGHT * m_scale);
    m_letterbox.x = (static_cast<float>(m_windowWidth) - drawW) * 0.5f;
    m_letterbox.y = (static_cast<float>(m_windowHeight) - drawH) * 0.5f;
    m_letterbox.w = drawW;
    m_letterbox.h = drawH;
}

void RenderDevice::BeginFrame()
{
    if (m_context == nullptr || m_offscreenRTV == nullptr) {
        return;
    }
    ID3D11RenderTargetView* rtv = m_offscreenRTV.Get();
    m_context->OMSetRenderTargets(1, &rtv, nullptr);
    D3D11_VIEWPORT viewport = {};
    viewport.TopLeftX = 0.0f;
    viewport.TopLeftY = 0.0f;
    viewport.Width = static_cast<float>(INTERNAL_WIDTH);
    viewport.Height = static_cast<float>(INTERNAL_HEIGHT);
    viewport.MinDepth = 0.0f;
    viewport.MaxDepth = 1.0f;
    m_context->RSSetViewports(1, &viewport);
    const float clear[4] = {0.02f, 0.03f, 0.045f, 1.0f};
    m_context->ClearRenderTargetView(m_offscreenRTV.Get(), clear);
}

void RenderDevice::EndFrame()
{
}

void RenderDevice::Present(bool vsync)
{
    if (m_swapChain == nullptr || m_context == nullptr ||
        m_backBufferRTV == nullptr) {
        return;
    }
    ID3D11RenderTargetView* rtv = m_backBufferRTV.Get();
    m_context->OMSetRenderTargets(1, &rtv, nullptr);
    D3D11_VIEWPORT viewport = {};
    viewport.Width = static_cast<float>(m_windowWidth);
    viewport.Height = static_cast<float>(m_windowHeight);
    viewport.MinDepth = 0.0f;
    viewport.MaxDepth = 1.0f;
    m_context->RSSetViewports(1, &viewport);
    const float clear[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    m_context->ClearRenderTargetView(m_backBufferRTV.Get(), clear);

    m_batch.Begin(m_windowWidth, m_windowHeight);
    m_batch.DrawTexture(m_offscreenTexture, m_letterbox.x, m_letterbox.y,
                        m_letterbox.w, m_letterbox.h, Color(1.0f, 1.0f, 1.0f, 1.0f),
                        false, false);
    m_batch.End();

    m_swapChain->Present(vsync ? 1 : 0, 0);
}

Vec2 RenderDevice::ScreenToInternal(Vec2 screen) const
{
    const float scale = static_cast<float>(m_scale);
    if (scale <= 0.0f) {
        return Vec2();
    }
    return Vec2((screen.x - m_letterbox.x) / scale,
                (screen.y - m_letterbox.y) / scale);
}

bool RenderDevice::LoadArtPack(const std::vector<uint8_t>& packData)
{
    if (!m_device) {
        return false;
    }
    if (packData.size() < 8 ||
        std::memcmp(packData.data(), "FCPK", 4) != 0) {
        LogError("Art pack: bad magic");
        return false;
    }
    const uint16_t version = ReadU16(&packData[4]);
    const uint16_t count = ReadU16(&packData[6]);
    if (version != 1) {
        LogError("Art pack: unsupported version %u", version);
        return false;
    }
    const size_t entrySize = 44;
    const size_t headerSize = 8;
    if (packData.size() < headerSize + entrySize * count) {
        LogError("Art pack: truncated header");
        return false;
    }

    struct Entry {
        std::string name;
        uint16_t width = 0;
        uint16_t height = 0;
        uint32_t offset = 0;
        uint32_t size = 0;
    };
    std::vector<Entry> entries;
    entries.reserve(count);
    for (uint16_t i = 0; i < count; ++i) {
        const uint8_t* base = packData.data() + headerSize + i * entrySize;
        Entry entry;
        char name[33] = {0};
        std::memcpy(name, base, 32);
        entry.name = name;
        entry.width = ReadU16(base + 32);
        entry.height = ReadU16(base + 34);
        entry.offset = ReadU32(base + 36);
        entry.size = ReadU32(base + 40);
        if (entry.offset + entry.size > packData.size()) {
            LogWarn("Art pack: entry %s out of bounds", entry.name.c_str());
            continue;
        }
        if (entry.size != static_cast<uint32_t>(entry.width) * entry.height * 4u) {
            LogWarn("Art pack: entry %s has invalid size", entry.name.c_str());
            continue;
        }
        entries.push_back(entry);
    }

    m_sprites.clear();
    m_ownedTextures.clear();
    m_atlas.Reset();

    constexpr int ATLAS_SIZE = 2048;
    std::vector<uint8_t> atlas(static_cast<size_t>(ATLAS_SIZE) * ATLAS_SIZE * 4, 0);

    struct Placement {
        bool atlas = false;
        int x = 0;
        int y = 0;
        int individual = -1;
    };
    std::vector<Placement> placements(entries.size());

    int cursorX = 1;
    int cursorY = 1;
    int rowHeight = 0;
    int atlasAssetCount = 0;

    for (size_t i = 0; i < entries.size(); ++i) {
        const Entry& entry = entries[i];
        const int w = entry.width;
        const int h = entry.height;
        if (w <= 0 || h <= 0) {
            continue;
        }
        if (w > 512 || h > 512) {
            std::unique_ptr<Texture> texture(new Texture());
            if (texture->Create(m_device.Get(),
                                packData.data() + entry.offset, w, h, false,
                                entry.name.c_str())) {
                placements[i].individual = static_cast<int>(m_ownedTextures.size());
                m_ownedTextures.push_back(std::move(texture));
            }
            continue;
        }

        if (cursorX + w + 1 >= ATLAS_SIZE) {
            cursorX = 1;
            cursorY += rowHeight + 1;
            rowHeight = 0;
        }
        if (cursorY + h + 1 >= ATLAS_SIZE) {
            std::unique_ptr<Texture> texture(new Texture());
            if (texture->Create(m_device.Get(),
                                packData.data() + entry.offset, w, h, false,
                                entry.name.c_str())) {
                placements[i].individual = static_cast<int>(m_ownedTextures.size());
                m_ownedTextures.push_back(std::move(texture));
            }
            continue;
        }

        placements[i].atlas = true;
        placements[i].x = cursorX;
        placements[i].y = cursorY;
        for (int y = 0; y < h; ++y) {
            const uint8_t* src = packData.data() + entry.offset +
                                 static_cast<size_t>(y) * w * 4;
            uint8_t* dst = atlas.data() +
                           (static_cast<size_t>(cursorY + y) * ATLAS_SIZE +
                            cursorX) * 4;
            std::memcpy(dst, src, static_cast<size_t>(w) * 4);
        }
        cursorX += w + 2;
        rowHeight = std::max(rowHeight, h);
        ++atlasAssetCount;
    }

    if (atlasAssetCount > 0) {
        if (!m_atlas.Create(m_device.Get(), atlas.data(), ATLAS_SIZE, ATLAS_SIZE,
                            false, "ArtAtlas")) {
            LogError("Art pack: failed to create atlas texture");
            return false;
        }
    }

    for (size_t i = 0; i < entries.size(); ++i) {
        const Entry& entry = entries[i];
        Sprite sprite;
        sprite.width = entry.width;
        sprite.height = entry.height;
        if (placements[i].atlas) {
            sprite.texture = &m_atlas;
            sprite.u0 = static_cast<float>(placements[i].x) / ATLAS_SIZE;
            sprite.v0 = static_cast<float>(placements[i].y) / ATLAS_SIZE;
            sprite.u1 = static_cast<float>(placements[i].x + entry.width) / ATLAS_SIZE;
            sprite.v1 = static_cast<float>(placements[i].y + entry.height) / ATLAS_SIZE;
        } else if (placements[i].individual >= 0) {
            sprite.texture = m_ownedTextures[static_cast<size_t>(placements[i].individual)].get();
            sprite.u0 = 0.0f;
            sprite.v0 = 0.0f;
            sprite.u1 = 1.0f;
            sprite.v1 = 1.0f;
        } else {
            continue;
        }
        if (m_sprites.find(entry.name) != m_sprites.end()) {
            LogWarn("Art pack: duplicate asset %s", entry.name.c_str());
            continue;
        }
        m_sprites.emplace(entry.name, sprite);
    }

    LogInfo("Art pack loaded: %zu entries, %d atlas assets, %zu individual",
            entries.size(), atlasAssetCount, m_ownedTextures.size());
    return true;
}

bool RenderDevice::CreateTexture(const uint8_t* bgra, int width, int height,
                                 bool linear, Texture& texture,
                                 const char* debugName)
{
    return texture.Create(m_device.Get(), bgra, width, height, linear, debugName);
}

const Sprite* RenderDevice::FindSprite(const char* name) const
{
    if (name == nullptr) {
        return &m_missingSprite;
    }
    const auto it = m_sprites.find(name);
    if (it == m_sprites.end()) {
        return &m_missingSprite;
    }
    return &it->second;
}

bool RenderDevice::CaptureOffscreen(const std::string& path)
{
    if (!m_device || !m_context || m_offscreenRaw == nullptr) {
        return false;
    }
    D3D11_TEXTURE2D_DESC desc = {};
    m_offscreenRaw->GetDesc(&desc);
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;

    ComPtr<ID3D11Texture2D> staging;
    if (FAILED(m_device->CreateTexture2D(&desc, nullptr,
                                         staging.GetAddressOf()))) {
        LogError("Capture: failed to create staging texture");
        return false;
    }
    m_context->CopyResource(staging.Get(), m_offscreenRaw.Get());
    D3D11_MAPPED_SUBRESOURCE mapped = {};
    if (FAILED(m_context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
        LogError("Capture: failed to map staging texture");
        return false;
    }

    const int w = static_cast<int>(desc.Width);
    const int h = static_cast<int>(desc.Height);
    std::vector<uint8_t> pixels(static_cast<size_t>(w) * h * 4);
    for (int y = 0; y < h; ++y) {
        std::memcpy(pixels.data() + static_cast<size_t>(y) * w * 4,
                    static_cast<const uint8_t*>(mapped.pData) +
                        static_cast<size_t>(y) * mapped.RowPitch,
                    static_cast<size_t>(w) * 4);
    }
    m_context->Unmap(staging.Get(), 0);

    return WriteBmp(path, pixels.data(), w, h, w * 4);
}

bool RenderDevice::WriteBmp(const std::string& path, const uint8_t* bgra,
                            int width, int height, int pitch)
{
    if (bgra == nullptr || width <= 0 || height <= 0) {
        return false;
    }
    const int rowSize = ((width * 3) + 3) & ~3;
    const uint32_t imageSize = static_cast<uint32_t>(rowSize * height);
    const uint32_t fileSize = 54 + imageSize;

    std::ofstream file(path, std::ios::binary);
    if (!file) {
        LogError("Capture: cannot open %s", path.c_str());
        return false;
    }
    file.put('B');
    file.put('M');
    WriteU32(file, fileSize);
    WriteU16(file, 0);
    WriteU16(file, 0);
    WriteU32(file, 54);
    WriteU32(file, 40);
    WriteU32(file, static_cast<uint32_t>(width));
    WriteU32(file, static_cast<uint32_t>(height));
    WriteU16(file, 1);
    WriteU16(file, 24);
    WriteU32(file, 0);
    WriteU32(file, imageSize);
    WriteU32(file, 2835);
    WriteU32(file, 2835);
    WriteU32(file, 0);
    WriteU32(file, 0);

    std::vector<uint8_t> row(static_cast<size_t>(rowSize), 0);
    for (int y = height - 1; y >= 0; --y) {
        const uint8_t* source = bgra + static_cast<size_t>(y) * pitch;
        for (int x = 0; x < width; ++x) {
            row[static_cast<size_t>(x) * 3 + 0] = source[x * 4 + 0];
            row[static_cast<size_t>(x) * 3 + 1] = source[x * 4 + 1];
            row[static_cast<size_t>(x) * 3 + 2] = source[x * 4 + 2];
        }
        file.write(reinterpret_cast<const char*>(row.data()), rowSize);
    }
    return file.good();
}

void RenderDevice::Shutdown()
{
    m_sprites.clear();
    m_ownedTextures.clear();
    m_atlas.Reset();
    m_whiteTexture.Reset();
    m_missingTexture.Reset();
    m_offscreenTexture.Reset();
    m_offscreenRTV.Reset();
    m_offscreenRaw.Reset();
    m_backBufferRTV.Reset();
    m_backBuffer.Reset();
    m_swapChain.Reset();
    m_rasterizer.Reset();
    m_additiveBlend.Reset();
    m_alphaBlend.Reset();
    m_linearSampler.Reset();
    m_pointSampler.Reset();
    m_projectionBuffer.Reset();
    m_inputLayout.Reset();
    m_pixelShader.Reset();
    m_vertexShader.Reset();
    m_context.Reset();
    m_device.Reset();
}

} // namespace fc
