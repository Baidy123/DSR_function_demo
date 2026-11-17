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

const char* SCENE_SHADER = R"(
cbuffer FrameCB : register(b0)
{
    row_major float4x4 uViewProj;
    float4 uCameraPos;
    float4 uAmbient;
    float4 uFogColor;
    float4 uFogParams;
    float4 uLightPosRange[8];
    float4 uLightColorIntensity[8];
    float4 uLightCount;
};

cbuffer ObjectCB : register(b1)
{
    row_major float4x4 uWorld;
    float4 uTint;
    float4 uEmission;
};

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float3 color : COLOR0;
    float pattern : TEXCOORD0;
};

struct VSOutput
{
    float4 position : SV_POSITION;
    float3 world : TEXCOORD1;
    float3 normal : NORMAL;
    float3 color : COLOR0;
    float pattern : TEXCOORD0;
};

VSOutput VSMain(VSInput input)
{
    VSOutput output;
    float4 worldPos = mul(float4(input.position, 1.0), uWorld);
    output.position = mul(worldPos, uViewProj);
    output.world = worldPos.xyz;
    output.normal = mul(float4(input.normal, 0.0), uWorld).xyz;
    output.color = input.color;
    output.pattern = input.pattern;
    return output;
}

float Hash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float Noise2(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = Hash21(i);
    float b = Hash21(i + float2(1.0, 0.0));
    float c = Hash21(i + float2(0.0, 1.0));
    float d = Hash21(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float3 ApplyPattern(float3 base, float2 uv, float pattern)
{
    if (pattern < 0.5 || pattern > 7.5)
    {
        return base;
    }
    if (pattern < 1.5)
    {
        float2 g = uv * float2(2.4, 4.2);
        float row = floor(g.y);
        g.x += frac(row * 0.5);
        float2 f = frac(g);
        float mortar = step(f.x, 0.07) + step(f.y, 0.14);
        float shade = 0.84 + 0.16 * Noise2(uv * 7.0);
        return base * shade * (1.0 - 0.38 * saturate(mortar));
    }
    if (pattern < 2.5)
    {
        float2 g = uv * float2(1.4, 6.5);
        float seam = step(frac(g.y), 0.06);
        float grain = 0.9 + 0.1 * sin(uv.x * 26.0 + Noise2(uv * 3.0) * 6.0);
        return base * grain * (1.0 - 0.42 * seam);
    }
    if (pattern < 3.5)
    {
        float rib = 0.86 + 0.14 * step(0.5, frac(uv.x * 9.0));
        return base * rib * (0.94 + 0.06 * Noise2(uv * 6.0));
    }
    if (pattern < 4.5)
    {
        float n = Noise2(uv * 4.5) * 0.65 + Noise2(uv * 13.0) * 0.35;
        float patch = smoothstep(0.52, 0.82, n);
        float3 rust = float3(0.34, 0.15, 0.07);
        return lerp(base * (0.82 + 0.26 * n), rust, patch * 0.7);
    }
    if (pattern < 5.5)
    {
        float weave = 0.93 + 0.07 * sin(uv.x * 70.0) * sin(uv.y * 70.0);
        return base * weave;
    }
    float n = Noise2(uv * 2.6) * 0.62 + Noise2(uv * 9.0) * 0.38;
    return base * (0.84 + 0.24 * n);
}

float4 PSMain(VSOutput input) : SV_TARGET
{
    float3 N = normalize(input.normal);
    float3 V = normalize(uCameraPos.xyz - input.world);

    float3 axis = abs(N);
    float2 uv;
    if (axis.y > 0.6)
    {
        uv = input.world.xz;
    }
    else if (axis.x > axis.z)
    {
        uv = input.world.zy;
    }
    else
    {
        uv = input.world.xy;
    }

    float3 albedo = ApplyPattern(input.color * uTint.rgb, uv * 0.5, input.pattern);
    float3 ambient = uAmbient.rgb * (0.52 + 0.48 * saturate(N.y * 0.5 + 0.5));
    float3 color = albedo * ambient;

    int count = (int)uLightCount.x;
    [loop]
    for (int i = 0; i < 8; ++i)
    {
        if (i >= count)
        {
            break;
        }
        float3 lightPos = uLightPosRange[i].xyz;
        float range = max(uLightPosRange[i].w, 0.001);
        float3 delta = lightPos - input.world;
        float dist = length(delta);
        if (dist >= range)
        {
            continue;
        }
        float atten = saturate(1.0 - dist / range);
        atten *= atten;
        float3 L = delta / max(dist, 0.001);
        float ndl = saturate(dot(N, L) * 0.5 + 0.5);
        float3 lightColor = uLightColorIntensity[i].rgb;
        float intensity = uLightColorIntensity[i].a;
        color += albedo * lightColor * intensity * atten * ndl;
    }

    float rim = pow(1.0 - saturate(dot(N, V)), 3.0);
    color += rim * uAmbient.rgb * 0.45;

    // 材质编号 8 及以上表示自发光表面（霓虹、屏幕、灯罩）。
    float emissive = input.pattern > 7.5 ? 1.6 : 0.0;
    color += albedo * emissive;
    color += uEmission.rgb * (0.55 + 0.45 * saturate(dot(N, V)));

    float dist = length(uCameraPos.xyz - input.world);
    float fog = saturate((dist - uFogParams.x) / max(uFogParams.y - uFogParams.x, 0.001));
    color = lerp(color, uFogColor.rgb, fog * uFogParams.z);

    return float4(saturate(color), uTint.a);
}
)";

const char* POST_SHADER = R"(
cbuffer PostCB : register(b0)
{
    float4 uResolution;
    float4 uParams;
};

Texture2D uTexture : register(t0);
SamplerState uSampler : register(s0);

struct VSOutput
{
    float4 position : SV_POSITION;
    float2 uv : TEXCOORD0;
};

VSOutput VSMain(uint vertexId : SV_VertexID)
{
    float2 uv = float2((vertexId << 1) & 2, vertexId & 2);
    VSOutput output;
    output.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    output.uv = uv;
    return output;
}

float Bayer4(int x, int y)
{
    const float table[16] = {
        0.0, 8.0, 2.0, 10.0,
        12.0, 4.0, 14.0, 6.0,
        3.0, 11.0, 1.0, 9.0,
        15.0, 7.0, 13.0, 5.0
    };
    return table[(y & 3) * 4 + (x & 3)] / 16.0;
}

float Hash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float4 PSMain(VSOutput input) : SV_TARGET
{
    float2 uv = input.uv;
    float2 centered = uv - 0.5;
    float time = uParams.x;
    float damage = uParams.y;
    float fade = uParams.z;
    float glitch = uParams.w;

    float aberration = 0.0012 + glitch * 0.004;
    float2 dir = normalize(centered + float2(0.0001, 0.0001)) * aberration;
    float3 color;
    color.r = uTexture.Sample(uSampler, uv + dir).r;
    color.g = uTexture.Sample(uSampler, uv).g;
    color.b = uTexture.Sample(uSampler, uv - dir).b;

    if (glitch > 0.001)
    {
        float slice = floor(uv.y * 32.0);
        float offset = (frac(sin(slice * 12.9898 + floor(time * 12.0)) * 43758.5453) - 0.5) * 0.03 * glitch;
        float3 shifted = uTexture.Sample(uSampler, uv + float2(offset, 0.0)).rgb;
        color = lerp(color, shifted, 0.7);
    }

    int2 pixel = int2(uv * uResolution.xy);
    float threshold = Bayer4(pixel.x, pixel.y);
    const float levels = 24.0;
    color = floor(color * levels + threshold) / levels;

    float scan = 0.93 + 0.07 * sin(uv.y * uResolution.y * 6.28318);
    color *= scan;

    float vig = smoothstep(0.92, 0.28, length(centered * float2(1.08, 1.0)));
    color *= lerp(0.62, 1.0, vig);

    float grain = Hash21(float2(pixel) + floor(time * 60.0)) - 0.5;
    color += grain * 0.022;

    color = lerp(color, float3(0.46, 0.05, 0.07), damage * 0.5);
    color = lerp(color, float3(0.0, 0.0, 0.0), fade);

    return float4(saturate(color), 1.0);
}
)";

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

struct FrameConstants {
    float viewProj[16];
    float cameraPos[4];
    float ambient[4];
    float fogColor[4];
    float fogParams[4];
    float lightPosRange[MAX_POINT_LIGHTS * 4];
    float lightColorIntensity[MAX_POINT_LIGHTS * 4];
    float lightCount[4];
};

struct ObjectConstants {
    float world[16];
    float tint[4];
    float emission[4];
};

struct PostConstants {
    float resolution[4];
    float params[4];
};

void PushU16(std::ofstream& file, uint16_t value)
{
    const uint8_t bytes[2] = {static_cast<uint8_t>(value & 0xFF),
                              static_cast<uint8_t>((value >> 8) & 0xFF)};
    file.write(reinterpret_cast<const char*>(bytes), 2);
}

void PushU32(std::ofstream& file, uint32_t value)
{
    const uint8_t bytes[4] = {static_cast<uint8_t>(value & 0xFF),
                              static_cast<uint8_t>((value >> 8) & 0xFF),
                              static_cast<uint8_t>((value >> 16) & 0xFF),
                              static_cast<uint8_t>((value >> 24) & 0xFF)};
    file.write(reinterpret_cast<const char*>(bytes), 4);
}

HRESULT CompileShader(const char* source, const char* entry, const char* target,
                      ComPtr<ID3DBlob>& blob)
{
    ComPtr<ID3DBlob> errors;
    const UINT flags = D3DCOMPILE_ENABLE_STRICTNESS | D3DCOMPILE_OPTIMIZATION_LEVEL3;
    const HRESULT hr = D3DCompile(source, std::strlen(source), "inline", nullptr,
                                  nullptr, entry, target, flags, 0,
                                  blob.GetAddressOf(), errors.GetAddressOf());
    if (FAILED(hr) && errors) {
        LogError("Shader compile failed (%s): %s", entry,
                 static_cast<const char*>(errors->GetBufferPointer()));
    }
    return hr;
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
    swapDesc.Windowed = TRUE;
    swapDesc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0,
                                        D3D_FEATURE_LEVEL_10_1,
                                        D3D_FEATURE_LEVEL_10_0};
    D3D_FEATURE_LEVEL featureLevel = D3D_FEATURE_LEVEL_10_0;
    const UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;

    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels, 3,
        D3D11_SDK_VERSION, &swapDesc, m_swapChain.GetAddressOf(),
        m_device.GetAddressOf(), &featureLevel, m_context.GetAddressOf());
    if (FAILED(hr)) {
        LogWarn("Hardware D3D11 device failed (0x%08X), trying WARP",
                static_cast<unsigned int>(hr));
        m_swapChain.Reset();
        m_device.Reset();
        m_context.Reset();
        hr = D3D11CreateDeviceAndSwapChain(
            nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags, levels, 3,
            D3D11_SDK_VERSION, &swapDesc, m_swapChain.GetAddressOf(),
            m_device.GetAddressOf(), &featureLevel, m_context.GetAddressOf());
    }
    if (FAILED(hr)) {
        LogError("D3D11CreateDeviceAndSwapChain failed: 0x%08X",
                 static_cast<unsigned int>(hr));
        return false;
    }

    if (!CreateBackBufferViews()) {
        return false;
    }
    if (!CreateShaders()) {
        return false;
    }
    if (!CreateStates()) {
        return false;
    }
    if (!CreateInternalTargets()) {
        return false;
    }

    // 白色纹理与辉光纹理都由代码生成，不依赖任何图片文件。
    const uint8_t white[4] = {255, 255, 255, 255};
    if (!m_whiteTexture.Create(m_device.Get(), white, 1, 1, false, "White")) {
        return false;
    }

    const int glowSize = 64;
    std::vector<uint8_t> glow(static_cast<size_t>(glowSize) * glowSize * 4, 0);
    for (int y = 0; y < glowSize; ++y) {
        for (int x = 0; x < glowSize; ++x) {
            const float dx = (x + 0.5f) / glowSize * 2.0f - 1.0f;
            const float dy = (y + 0.5f) / glowSize * 2.0f - 1.0f;
            const float d = std::sqrt(dx * dx + dy * dy);
            float a = Clamp(1.0f - d, 0.0f, 1.0f);
            a = a * a * a;
            const size_t index = (static_cast<size_t>(y) * glowSize + x) * 4;
            glow[index + 0] = 255;
            glow[index + 1] = 255;
            glow[index + 2] = 255;
            glow[index + 3] = static_cast<uint8_t>(a * 255.0f);
        }
    }
    if (!m_glowTexture.Create(m_device.Get(), glow.data(), glowSize, glowSize,
                              true, "Glow")) {
        return false;
    }

    if (!m_batch.Initialize(m_device.Get(), m_context.Get(), m_spritePipeline)) {
        return false;
    }

    UpdateLetterbox();
    LogInfo("RenderDevice initialized (%dx%d, scale %d, internal %dx%d)",
            m_windowWidth, m_windowHeight, m_scale, INTERNAL_WIDTH,
            INTERNAL_HEIGHT);
    return true;
}

bool RenderDevice::CreateBackBufferViews()
{
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
    return true;
}

bool RenderDevice::CreateShaders()
{
    ComPtr<ID3DBlob> vsBlob;
    ComPtr<ID3DBlob> psBlob;
    if (FAILED(CompileShader(SCENE_SHADER, "VSMain", "vs_5_0", vsBlob)) ||
        FAILED(CompileShader(SCENE_SHADER, "PSMain", "ps_5_0", psBlob))) {
        return false;
    }
    if (FAILED(m_device->CreateVertexShader(vsBlob->GetBufferPointer(),
                                            vsBlob->GetBufferSize(), nullptr,
                                            m_sceneVS.GetAddressOf())) ||
        FAILED(m_device->CreatePixelShader(psBlob->GetBufferPointer(),
                                           psBlob->GetBufferSize(), nullptr,
                                           m_scenePS.GetAddressOf()))) {
        return false;
    }

    const D3D11_INPUT_ELEMENT_DESC layout[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0,
         D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12,
         D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"COLOR", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 24,
         D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"TEXCOORD", 0, DXGI_FORMAT_R32_FLOAT, 0, 36,
         D3D11_INPUT_PER_VERTEX_DATA, 0}};
    if (FAILED(m_device->CreateInputLayout(layout, 4,
                                           vsBlob->GetBufferPointer(),
                                           vsBlob->GetBufferSize(),
                                           m_sceneLayout.GetAddressOf()))) {
        LogError("CreateInputLayout (scene) failed");
        return false;
    }

    D3D11_BUFFER_DESC cbDesc = {};
    cbDesc.Usage = D3D11_USAGE_DYNAMIC;
    cbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    cbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    cbDesc.ByteWidth = sizeof(FrameConstants);
    if (FAILED(m_device->CreateBuffer(&cbDesc, nullptr,
                                      m_frameCB.GetAddressOf()))) {
        return false;
    }
    cbDesc.ByteWidth = sizeof(ObjectConstants);
    if (FAILED(m_device->CreateBuffer(&cbDesc, nullptr,
                                      m_objectCB.GetAddressOf()))) {
        return false;
    }

    ComPtr<ID3DBlob> postVS;
    ComPtr<ID3DBlob> postPS;
    if (FAILED(CompileShader(POST_SHADER, "VSMain", "vs_5_0", postVS)) ||
        FAILED(CompileShader(POST_SHADER, "PSMain", "ps_5_0", postPS))) {
        return false;
    }
    if (FAILED(m_device->CreateVertexShader(postVS->GetBufferPointer(),
                                            postVS->GetBufferSize(), nullptr,
                                            m_postVS.GetAddressOf())) ||
        FAILED(m_device->CreatePixelShader(postPS->GetBufferPointer(),
                                           postPS->GetBufferSize(), nullptr,
                                           m_postPS.GetAddressOf()))) {
        return false;
    }
    cbDesc.ByteWidth = sizeof(PostConstants);
    if (FAILED(m_device->CreateBuffer(&cbDesc, nullptr,
                                      m_postCB.GetAddressOf()))) {
        return false;
    }

    // 2D 精灵管线复用 sprite 着色器。
    ComPtr<ID3DBlob> spriteVS;
    ComPtr<ID3DBlob> spritePS;
    if (FAILED(CompileShader(SPRITE_SHADER, "VSMain", "vs_5_0", spriteVS)) ||
        FAILED(CompileShader(SPRITE_SHADER, "PSMain", "ps_5_0", spritePS))) {
        return false;
    }
    ComPtr<ID3D11VertexShader> spriteVertex;
    ComPtr<ID3D11PixelShader> spritePixel;
    if (FAILED(m_device->CreateVertexShader(spriteVS->GetBufferPointer(),
                                            spriteVS->GetBufferSize(), nullptr,
                                            spriteVertex.GetAddressOf())) ||
        FAILED(m_device->CreatePixelShader(spritePS->GetBufferPointer(),
                                           spritePS->GetBufferSize(), nullptr,
                                           spritePixel.GetAddressOf()))) {
        return false;
    }
    const D3D11_INPUT_ELEMENT_DESC spriteLayout[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0,
         D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 8,
         D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"COLOR", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 16,
         D3D11_INPUT_PER_VERTEX_DATA, 0}};
    ComPtr<ID3D11InputLayout> spriteLayoutObject;
    if (FAILED(m_device->CreateInputLayout(
            spriteLayout, 3, spriteVS->GetBufferPointer(),
            spriteVS->GetBufferSize(), spriteLayoutObject.GetAddressOf()))) {
        return false;
    }

    D3D11_BUFFER_DESC spriteCB = {};
    spriteCB.Usage = D3D11_USAGE_DYNAMIC;
    spriteCB.ByteWidth = 64;
    spriteCB.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    spriteCB.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    ComPtr<ID3D11Buffer> spriteConstant;
    if (FAILED(m_device->CreateBuffer(&spriteCB, nullptr,
                                      spriteConstant.GetAddressOf()))) {
        return false;
    }

    m_spritePipeline.vertexShader = spriteVertex.Get();
    m_spritePipeline.pixelShader = spritePixel.Get();
    m_spritePipeline.inputLayout = spriteLayoutObject.Get();
    m_spritePipeline.constantBuffer = spriteConstant.Get();

    // SpriteBatch 只保存裸指针，因此由设备持有这些对象。
    m_spriteVertexShader.Attach(spriteVertex.Detach());
    m_spritePixelShader.Attach(spritePixel.Detach());
    m_spriteLayout.Attach(spriteLayoutObject.Detach());
    m_spriteConstantBuffer.Attach(spriteConstant.Detach());
    return true;
}

bool RenderDevice::CreateStates()
{
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
        return false;
    }
    blendDesc.RenderTarget[0].DestBlend = D3D11_BLEND_ONE;
    blendDesc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ONE;
    if (FAILED(m_device->CreateBlendState(&blendDesc,
                                          m_additiveBlend.GetAddressOf()))) {
        return false;
    }

    D3D11_DEPTH_STENCIL_DESC depthDesc = {};
    depthDesc.DepthEnable = TRUE;
    depthDesc.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL;
    depthDesc.DepthFunc = D3D11_COMPARISON_LESS_EQUAL;
    if (FAILED(m_device->CreateDepthStencilState(
            &depthDesc, m_depthState.GetAddressOf()))) {
        return false;
    }

    D3D11_DEPTH_STENCIL_DESC noDepthDesc = {};
    noDepthDesc.DepthEnable = FALSE;
    noDepthDesc.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO;
    noDepthDesc.DepthFunc = D3D11_COMPARISON_ALWAYS;
    noDepthDesc.StencilEnable = FALSE;
    if (FAILED(m_device->CreateDepthStencilState(
            &noDepthDesc, m_depthDisabled.GetAddressOf()))) {
        return false;
    }

    D3D11_RASTERIZER_DESC rasterDesc = {};
    rasterDesc.FillMode = D3D11_FILL_SOLID;
    rasterDesc.CullMode = D3D11_CULL_BACK;
    rasterDesc.DepthClipEnable = TRUE;
    rasterDesc.MultisampleEnable = FALSE;
    if (FAILED(m_device->CreateRasterizerState(&rasterDesc,
                                               m_rasterizer.GetAddressOf()))) {
        return false;
    }
    rasterDesc.CullMode = D3D11_CULL_NONE;
    if (FAILED(m_device->CreateRasterizerState(
            &rasterDesc, m_rasterizerNoCull.GetAddressOf()))) {
        return false;
    }

    m_spritePipeline.pointSampler = m_pointSampler.Get();
    m_spritePipeline.linearSampler = m_linearSampler.Get();
    m_spritePipeline.alphaBlend = m_alphaBlend.Get();
    m_spritePipeline.additiveBlend = m_additiveBlend.Get();
    m_spritePipeline.rasterizer = m_rasterizerNoCull.Get();
    m_spritePipeline.depthDisabled = m_depthDisabled.Get();
    return true;
}

bool RenderDevice::CreateInternalTargets()
{
    return CreateRenderTarget(INTERNAL_WIDTH, INTERNAL_HEIGHT, true, m_internal);
}

bool RenderDevice::CreateRenderTarget(int width, int height, bool withDepth,
                                      RenderTarget& target)
{
    target = RenderTarget();
    if (m_device == nullptr || width <= 0 || height <= 0) {
        return false;
    }
    target.width = width;
    target.height = height;

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = static_cast<UINT>(width);
    desc.Height = static_cast<UINT>(height);
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(m_device->CreateTexture2D(&desc, nullptr,
                                         target.colorTexture.GetAddressOf()))) {
        LogError("CreateTexture2D (color) failed");
        return false;
    }
    if (FAILED(m_device->CreateRenderTargetView(
            target.colorTexture.Get(), nullptr, target.rtv.GetAddressOf()))) {
        LogError("CreateRenderTargetView failed");
        return false;
    }
    if (FAILED(m_device->CreateShaderResourceView(
            target.colorTexture.Get(), nullptr, target.srv.GetAddressOf()))) {
        LogError("CreateShaderResourceView failed");
        return false;
    }
    if (!target.colorView.Attach(m_device.Get(), target.colorTexture.Get(),
                                 "ColorTarget")) {
        LogError("Texture::Attach failed");
        return false;
    }

    if (withDepth) {
        D3D11_TEXTURE2D_DESC depthDesc = {};
        depthDesc.Width = static_cast<UINT>(width);
        depthDesc.Height = static_cast<UINT>(height);
        depthDesc.MipLevels = 1;
        depthDesc.ArraySize = 1;
        depthDesc.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
        depthDesc.SampleDesc.Count = 1;
        depthDesc.Usage = D3D11_USAGE_DEFAULT;
        depthDesc.BindFlags = D3D11_BIND_DEPTH_STENCIL;
        if (FAILED(m_device->CreateTexture2D(
                &depthDesc, nullptr, target.depthTexture.GetAddressOf()))) {
            LogError("CreateTexture2D (depth) failed");
            return false;
        }
        if (FAILED(m_device->CreateDepthStencilView(
                target.depthTexture.Get(), nullptr, target.dsv.GetAddressOf()))) {
            LogError("CreateDepthStencilView failed");
            return false;
        }
    }
    return true;
}

void RenderDevice::BeginRenderTarget(RenderTarget& target, const Color& clearColor)
{
    m_currentTarget = &target;
    ID3D11RenderTargetView* rtv = target.rtv.Get();
    m_context->OMSetRenderTargets(1, &rtv, target.dsv.Get());
    D3D11_VIEWPORT viewport = {};
    viewport.Width = static_cast<float>(target.width);
    viewport.Height = static_cast<float>(target.height);
    viewport.MinDepth = 0.0f;
    viewport.MaxDepth = 1.0f;
    m_context->RSSetViewports(1, &viewport);
    const float clear[4] = {clearColor.r, clearColor.g, clearColor.b, clearColor.a};
    m_context->ClearRenderTargetView(target.rtv.Get(), clear);
    if (target.dsv) {
        m_context->ClearDepthStencilView(target.dsv.Get(),
                                         D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL,
                                         1.0f, 0);
    }
}

void RenderDevice::BeginInternalTarget()
{
    BeginRenderTarget(m_internal, m_frame.fogColor);
}



void RenderDevice::BeginFrame(const Color& fogColor)
{
    m_frame.fogColor = fogColor;
    BeginRenderTarget(m_internal, fogColor);
}

void RenderDevice::BeginScene3D(const SceneFrame& frame)
{
    m_frame = frame;
    RenderTarget& target = m_currentTarget != nullptr ? *m_currentTarget
                                                      : m_internal;
    ID3D11RenderTargetView* rtv = target.rtv.Get();
    m_context->OMSetRenderTargets(1, &rtv, target.dsv.Get());

    D3D11_VIEWPORT viewport = {};
    viewport.Width = static_cast<float>(target.width);
    viewport.Height = static_cast<float>(target.height);
    viewport.MinDepth = 0.0f;
    viewport.MaxDepth = 1.0f;
    m_context->RSSetViewports(1, &viewport);

    FrameConstants constants = {};
    std::memcpy(constants.viewProj, frame.viewProjection.m, sizeof(float) * 16);
    constants.cameraPos[0] = frame.cameraPosition.x;
    constants.cameraPos[1] = frame.cameraPosition.y;
    constants.cameraPos[2] = frame.cameraPosition.z;
    constants.cameraPos[3] = 1.0f;
    constants.ambient[0] = frame.ambient.r;
    constants.ambient[1] = frame.ambient.g;
    constants.ambient[2] = frame.ambient.b;
    constants.ambient[3] = frame.ambient.a;
    constants.fogColor[0] = frame.fogColor.r;
    constants.fogColor[1] = frame.fogColor.g;
    constants.fogColor[2] = frame.fogColor.b;
    constants.fogColor[3] = frame.fogColor.a;
    constants.fogParams[0] = frame.fogNear;
    constants.fogParams[1] = frame.fogFar;
    constants.fogParams[2] = frame.fogDensity;
    constants.fogParams[3] = frame.time;

    const int lightCount = ClampInt(frame.lightCount, 0, MAX_POINT_LIGHTS);
    for (int i = 0; i < lightCount; ++i) {
        const PointLight& light = frame.lights[i];
        constants.lightPosRange[i * 4 + 0] = light.position.x;
        constants.lightPosRange[i * 4 + 1] = light.position.y;
        constants.lightPosRange[i * 4 + 2] = light.position.z;
        constants.lightPosRange[i * 4 + 3] = light.range;
        constants.lightColorIntensity[i * 4 + 0] = light.color.r;
        constants.lightColorIntensity[i * 4 + 1] = light.color.g;
        constants.lightColorIntensity[i * 4 + 2] = light.color.b;
        constants.lightColorIntensity[i * 4 + 3] = light.intensity;
    }
    constants.lightCount[0] = static_cast<float>(lightCount);

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    if (SUCCEEDED(m_context->Map(m_frameCB.Get(), 0, D3D11_MAP_WRITE_DISCARD,
                                 0, &mapped))) {
        std::memcpy(mapped.pData, &constants, sizeof(constants));
        m_context->Unmap(m_frameCB.Get(), 0);
    }

    m_context->IASetInputLayout(m_sceneLayout.Get());
    m_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    m_context->VSSetShader(m_sceneVS.Get(), nullptr, 0);
    m_context->PSSetShader(m_scenePS.Get(), nullptr, 0);
    ID3D11Buffer* frameBuffer = m_frameCB.Get();
    m_context->VSSetConstantBuffers(0, 1, &frameBuffer);
    m_context->PSSetConstantBuffers(0, 1, &frameBuffer);
    ID3D11Buffer* objectBuffer = m_objectCB.Get();
    m_context->VSSetConstantBuffers(1, 1, &objectBuffer);
    m_context->PSSetConstantBuffers(1, 1, &objectBuffer);

    ID3D11SamplerState* sampler = m_pointSampler.Get();
    m_context->PSSetSamplers(0, 1, &sampler);
    m_context->OMSetDepthStencilState(m_depthState.Get(), 0);
    m_context->RSSetState(m_rasterizerNoCull.Get());
    const float blendFactor[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    m_context->OMSetBlendState(m_alphaBlend.Get(), blendFactor, 0xFFFFFFFF);
    m_depthEnabled = true;
}

void RenderDevice::DrawMesh(const Mesh& mesh, const Mat4& world,
                            const Color& tint, const Color& emission,
                            bool alphaBlend)
{
    if (!m_sceneVS || mesh.parts.empty()) {
        return;
    }
    if (alphaBlend) {
        const float blendFactor[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        m_context->OMSetBlendState(m_alphaBlend.Get(), blendFactor, 0xFFFFFFFF);
    }
    for (const MeshPart& part : mesh.parts) {
        DrawMeshPart(part, world, tint, emission);
    }
}

void RenderDevice::DrawMeshPart(const MeshPart& part, const Mat4& world,
                                const Color& tint, const Color& emission)
{
    if (part.vertexBuffer == nullptr || part.indexBuffer == nullptr ||
        part.indexCount == 0) {
        return;
    }
    ObjectConstants constants = {};
    std::memcpy(constants.world, world.m, sizeof(float) * 16);
    constants.tint[0] = tint.r;
    constants.tint[1] = tint.g;
    constants.tint[2] = tint.b;
    constants.tint[3] = tint.a;
    constants.emission[0] = emission.r;
    constants.emission[1] = emission.g;
    constants.emission[2] = emission.b;
    constants.emission[3] = emission.a;

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    if (SUCCEEDED(m_context->Map(m_objectCB.Get(), 0, D3D11_MAP_WRITE_DISCARD,
                                 0, &mapped))) {
        std::memcpy(mapped.pData, &constants, sizeof(constants));
        m_context->Unmap(m_objectCB.Get(), 0);
    }

    const UINT stride = sizeof(MeshVertex);
    const UINT offset = 0;
    ID3D11Buffer* vertexBuffer = part.vertexBuffer.Get();
    m_context->IASetVertexBuffers(0, 1, &vertexBuffer, &stride, &offset);
    m_context->IASetIndexBuffer(part.indexBuffer.Get(), DXGI_FORMAT_R32_UINT, 0);
    m_context->DrawIndexed(part.indexCount, 0, 0);
}

void RenderDevice::EndScene3D()
{
    // 2D 覆盖层不参与深度测试，并把混合恢复为普通 Alpha。
    m_context->OMSetDepthStencilState(nullptr, 0);
    m_context->RSSetState(m_rasterizerNoCull.Get());
    const float blendFactor[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    m_context->OMSetBlendState(m_alphaBlend.Get(), blendFactor, 0xFFFFFFFF);
    m_depthEnabled = false;
}

void RenderDevice::SetPostParams(float time, float damage, float fade,
                                 float glitch)
{
    m_postTime = time;
    m_postDamage = Clamp(damage, 0.0f, 1.0f);
    m_postFade = Clamp(fade, 0.0f, 1.0f);
    m_postGlitch = Clamp(glitch, 0.0f, 1.0f);
}

bool RenderDevice::RunPostPass(ID3D11RenderTargetView* target, int vpX, int vpY,
                               int vpW, int vpH)
{
    if (target == nullptr || !m_internal.srv) {
        return false;
    }
    ID3D11RenderTargetView* rtv = target;
    m_context->OMSetRenderTargets(1, &rtv, nullptr);
    D3D11_VIEWPORT viewport = {};
    viewport.TopLeftX = static_cast<float>(vpX);
    viewport.TopLeftY = static_cast<float>(vpY);
    viewport.Width = static_cast<float>(vpW);
    viewport.Height = static_cast<float>(vpH);
    viewport.MinDepth = 0.0f;
    viewport.MaxDepth = 1.0f;
    m_context->RSSetViewports(1, &viewport);

    PostConstants constants = {};
    constants.resolution[0] = static_cast<float>(INTERNAL_WIDTH);
    constants.resolution[1] = static_cast<float>(INTERNAL_HEIGHT);
    constants.params[0] = m_postTime;
    constants.params[1] = m_postDamage;
    constants.params[2] = m_postFade;
    constants.params[3] = m_postGlitch;

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    if (SUCCEEDED(m_context->Map(m_postCB.Get(), 0, D3D11_MAP_WRITE_DISCARD,
                                 0, &mapped))) {
        std::memcpy(mapped.pData, &constants, sizeof(constants));
        m_context->Unmap(m_postCB.Get(), 0);
    }

    m_context->IASetInputLayout(nullptr);
    m_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    m_context->VSSetShader(m_postVS.Get(), nullptr, 0);
    m_context->PSSetShader(m_postPS.Get(), nullptr, 0);
    ID3D11Buffer* postBuffer = m_postCB.Get();
    m_context->PSSetConstantBuffers(0, 1, &postBuffer);

    ID3D11ShaderResourceView* srv = m_internal.srv.Get();
    m_context->PSSetShaderResources(0, 1, &srv);
    ID3D11SamplerState* sampler = m_pointSampler.Get();
    m_context->PSSetSamplers(0, 1, &sampler);
    m_context->OMSetBlendState(nullptr, nullptr, 0xFFFFFFFF);
    m_context->OMSetDepthStencilState(nullptr, 0);
    m_context->Draw(3, 0);

    ID3D11ShaderResourceView* nullSrv = nullptr;
    m_context->PSSetShaderResources(0, 1, &nullSrv);
    return true;
}

void RenderDevice::Present(bool vsync)
{
    if (m_swapChain == nullptr) {
        return;
    }
    const float clear[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    m_context->ClearRenderTargetView(m_backBufferRTV.Get(), clear);
    RunPostPass(m_backBufferRTV.Get(),
                static_cast<int>(m_letterbox.x),
                static_cast<int>(m_letterbox.y),
                static_cast<int>(m_letterbox.w),
                static_cast<int>(m_letterbox.h));
    m_swapChain->Present(vsync ? 1 : 0, 0);
}

bool RenderDevice::CaptureOffscreen(const std::string& path)
{
    EnsureCaptureTarget();
    if (!m_capture.rtv) {
        return false;
    }
    const float clear[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    m_context->ClearRenderTargetView(m_capture.rtv.Get(), clear);
    if (!RunPostPass(m_capture.rtv.Get(), 0, 0, m_capture.width,
                     m_capture.height)) {
        return false;
    }

    D3D11_TEXTURE2D_DESC desc = {};
    m_capture.colorTexture->GetDesc(&desc);
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;

    ComPtr<ID3D11Texture2D> staging;
    if (FAILED(m_device->CreateTexture2D(&desc, nullptr,
                                         staging.GetAddressOf()))) {
        return false;
    }
    m_context->CopyResource(staging.Get(), m_capture.colorTexture.Get());
    D3D11_MAPPED_SUBRESOURCE mapped = {};
    if (FAILED(m_context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
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

void RenderDevice::EnsureCaptureTarget()
{
    if (m_capture.rtv != nullptr && m_capture.width == INTERNAL_WIDTH &&
        m_capture.height == INTERNAL_HEIGHT) {
        return;
    }
    CreateRenderTarget(INTERNAL_WIDTH, INTERNAL_HEIGHT, false, m_capture);
}

bool RenderDevice::CreateTexture(const uint8_t* bgra, int width, int height,
                                 const char* debugName, Texture& texture)
{
    return texture.Create(m_device.Get(), bgra, width, height, false, debugName);
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
    if (!CreateBackBufferViews()) {
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

Vec2 RenderDevice::ScreenToInternal(Vec2 screen) const
{
    const float scale = static_cast<float>(m_scale);
    if (scale <= 0.0f) {
        return Vec2();
    }
    return Vec2((screen.x - m_letterbox.x) / scale,
                (screen.y - m_letterbox.y) / scale);
}

Vec2 RenderDevice::InternalToScreen(Vec2 internal) const
{
    const float scale = static_cast<float>(m_scale);
    return Vec2(m_letterbox.x + internal.x * scale,
                m_letterbox.y + internal.y * scale);
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
    PushU32(file, fileSize);
    PushU16(file, 0);
    PushU16(file, 0);
    PushU32(file, 54);
    PushU32(file, 40);
    PushU32(file, static_cast<uint32_t>(width));
    PushU32(file, static_cast<uint32_t>(height));
    PushU16(file, 1);
    PushU16(file, 24);
    PushU32(file, 0);
    PushU32(file, imageSize);
    PushU32(file, 2835);
    PushU32(file, 2835);
    PushU32(file, 0);
    PushU32(file, 0);

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
    m_spriteConstantBuffer.Reset();
    m_spriteLayout.Reset();
    m_spritePixelShader.Reset();
    m_spriteVertexShader.Reset();
    m_whiteTexture.Reset();
    m_glowTexture.Reset();
    m_capture = RenderTarget();
    m_internal = RenderTarget();
    m_backBufferRTV.Reset();
    m_backBuffer.Reset();
    m_swapChain.Reset();
    m_rasterizerNoCull.Reset();
    m_rasterizer.Reset();
    m_depthState.Reset();
    m_additiveBlend.Reset();
    m_alphaBlend.Reset();
    m_linearSampler.Reset();
    m_pointSampler.Reset();
    m_postCB.Reset();
    m_postPS.Reset();
    m_postVS.Reset();
    m_objectCB.Reset();
    m_frameCB.Reset();
    m_sceneLayout.Reset();
    m_scenePS.Reset();
    m_sceneVS.Reset();
    m_context.Reset();
    m_device.Reset();
}

} // namespace fc
