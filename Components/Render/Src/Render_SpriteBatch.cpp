#include "Render_SpriteBatch.hpp"

#include "Shared_Log.hpp"

#include <cstring>

namespace fc {

bool SpriteBatch::Initialize(ID3D11Device* device, ID3D11DeviceContext* context,
                             const SpritePipeline& pipeline)
{
    m_device = device;
    m_context = context;
    m_pipeline = pipeline;
    if (m_device == nullptr || m_context == nullptr) {
        return false;
    }

    m_vertices.reserve(static_cast<size_t>(MAX_QUADS) * 4);

    D3D11_BUFFER_DESC vertexDesc = {};
    vertexDesc.Usage = D3D11_USAGE_DYNAMIC;
    vertexDesc.ByteWidth = static_cast<UINT>(sizeof(Vertex) * MAX_QUADS * 4);
    vertexDesc.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    vertexDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(m_device->CreateBuffer(&vertexDesc, nullptr,
                                      m_vertexBuffer.GetAddressOf()))) {
        LogError("SpriteBatch: failed to create vertex buffer");
        return false;
    }

    std::vector<uint32_t> indices(static_cast<size_t>(MAX_QUADS) * 6);
    for (int i = 0; i < MAX_QUADS; ++i) {
        const uint32_t base = static_cast<uint32_t>(i * 4);
        indices[static_cast<size_t>(i) * 6 + 0] = base + 0;
        indices[static_cast<size_t>(i) * 6 + 1] = base + 1;
        indices[static_cast<size_t>(i) * 6 + 2] = base + 2;
        indices[static_cast<size_t>(i) * 6 + 3] = base + 0;
        indices[static_cast<size_t>(i) * 6 + 4] = base + 2;
        indices[static_cast<size_t>(i) * 6 + 5] = base + 3;
    }

    D3D11_BUFFER_DESC indexDesc = {};
    indexDesc.Usage = D3D11_USAGE_IMMUTABLE;
    indexDesc.ByteWidth = static_cast<UINT>(indices.size() * sizeof(uint32_t));
    indexDesc.BindFlags = D3D11_BIND_INDEX_BUFFER;
    D3D11_SUBRESOURCE_DATA indexData = {};
    indexData.pSysMem = indices.data();
    if (FAILED(m_device->CreateBuffer(&indexDesc, &indexData,
                                      m_indexBuffer.GetAddressOf()))) {
        LogError("SpriteBatch: failed to create index buffer");
        return false;
    }

    D3D11_BUFFER_DESC cbDesc = {};
    cbDesc.Usage = D3D11_USAGE_DYNAMIC;
    cbDesc.ByteWidth = 64;
    cbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    cbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    if (FAILED(m_device->CreateBuffer(&cbDesc, nullptr,
                                      m_constantBuffer.GetAddressOf()))) {
        LogError("SpriteBatch: failed to create constant buffer");
        return false;
    }

    return true;
}

void SpriteBatch::Begin(int width, int height)
{
    if (m_vertices.size() > 0) {
        m_vertices.clear();
    }
    m_quadCount = 0;
    m_width = width > 0 ? width : 1;
    m_height = height > 0 ? height : 1;
    m_inFrame = true;
    m_currentTexture = nullptr;
    m_currentAdditive = false;
    m_currentLinear = false;

    // 行主序正交投影，y 向下。
    const float w = static_cast<float>(m_width);
    const float h = static_cast<float>(m_height);
    float matrix[16] = {
        2.0f / w, 0.0f, 0.0f, 0.0f,
        0.0f, -2.0f / h, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        -1.0f, 1.0f, 0.0f, 1.0f
    };

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    if (SUCCEEDED(m_context->Map(m_constantBuffer.Get(), 0,
                                 D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
        std::memcpy(mapped.pData, matrix, sizeof(matrix));
        m_context->Unmap(m_constantBuffer.Get(), 0);
    }
}

void SpriteBatch::End()
{
    Flush();
    m_inFrame = false;
}

void SpriteBatch::DrawSprite(const Sprite& sprite, float x, float y, float w,
                             float h, Color tint, bool flipX, bool additive)
{
    if (sprite.texture == nullptr) {
        return;
    }
    const Texture* texture = reinterpret_cast<const Texture*>(sprite.texture);
    const float drawW = w > 0.0f ? w : static_cast<float>(sprite.width);
    const float drawH = h > 0.0f ? h : static_cast<float>(sprite.height);
    AppendQuad(*texture, x, y, drawW, drawH, sprite.u0, sprite.v0,
               sprite.u1, sprite.v1, tint, flipX, additive, false);
}

void SpriteBatch::DrawTexture(const Texture& texture, float x, float y, float w,
                              float h, Color tint, bool additive, bool linear)
{
    const RectF src(0.0f, 0.0f, static_cast<float>(texture.Width()),
                    static_cast<float>(texture.Height()));
    DrawTextureRegion(texture, x, y, w, h, src, tint, false, additive, linear);
}

void SpriteBatch::DrawTextureRegion(const Texture& texture, float x, float y,
                                    float w, float h, const RectF& src,
                                    Color tint, bool flipX, bool additive,
                                    bool linear)
{
    if (!texture.IsValid() || w <= 0.0f || h <= 0.0f) {
        return;
    }
    const float tw = static_cast<float>(texture.Width());
    const float th = static_cast<float>(texture.Height());
    const float u0 = src.x / tw;
    const float v0 = src.y / th;
    const float u1 = (src.x + src.w) / tw;
    const float v1 = (src.y + src.h) / th;
    AppendQuad(texture, x, y, w, h, u0, v0, u1, v1, tint, flipX, additive,
               linear);
}

void SpriteBatch::AppendQuad(const Texture& texture, float x, float y, float w,
                             float h, float u0, float v0, float u1, float v1,
                             Color tint, bool flipX, bool additive, bool linear)
{
    if (!m_inFrame || !texture.IsValid() || w <= 0.0f || h <= 0.0f) {
        return;
    }
    if (flipX) {
        const float temp = u0;
        u0 = u1;
        u1 = temp;
    }

    if (m_currentTexture != &texture || m_currentAdditive != additive ||
        m_currentLinear != linear || m_quadCount >= MAX_QUADS) {
        Flush();
        m_currentTexture = &texture;
        m_currentAdditive = additive;
        m_currentLinear = linear;
    }

    const Vertex quad[4] = {
        {x, y, u0, v0, tint.r, tint.g, tint.b, tint.a},
        {x + w, y, u1, v0, tint.r, tint.g, tint.b, tint.a},
        {x + w, y + h, u1, v1, tint.r, tint.g, tint.b, tint.a},
        {x, y + h, u0, v1, tint.r, tint.g, tint.b, tint.a}
    };
    m_vertices.insert(m_vertices.end(), quad, quad + 4);
    ++m_quadCount;
}

void SpriteBatch::Flush()
{
    if (m_quadCount <= 0 || m_currentTexture == nullptr || m_context == nullptr) {
        return;
    }

    D3D11_MAPPED_SUBRESOURCE mapped = {};
    if (FAILED(m_context->Map(m_vertexBuffer.Get(), 0, D3D11_MAP_WRITE_DISCARD,
                              0, &mapped))) {
        LogError("SpriteBatch: failed to map vertex buffer");
        return;
    }
    const size_t bytes = m_vertices.size() * sizeof(Vertex);
    std::memcpy(mapped.pData, m_vertices.data(), bytes);
    m_context->Unmap(m_vertexBuffer.Get(), 0);

    const UINT stride = sizeof(Vertex);
    const UINT offset = 0;
    ID3D11Buffer* vertexBuffer = m_vertexBuffer.Get();
    m_context->IASetInputLayout(m_pipeline.inputLayout);
    m_context->IASetVertexBuffers(0, 1, &vertexBuffer, &stride, &offset);
    m_context->IASetIndexBuffer(m_indexBuffer.Get(), DXGI_FORMAT_R32_UINT, 0);
    m_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    m_context->VSSetShader(m_pipeline.vertexShader, nullptr, 0);
    ID3D11Buffer* constantBuffer = m_constantBuffer.Get();
    m_context->VSSetConstantBuffers(0, 1, &constantBuffer);
    m_context->PSSetShader(m_pipeline.pixelShader, nullptr, 0);

    ID3D11ShaderResourceView* srv = m_currentTexture->SRV();
    m_context->PSSetShaderResources(0, 1, &srv);
    ID3D11SamplerState* sampler = m_currentLinear
                                      ? m_pipeline.linearSampler
                                      : m_pipeline.pointSampler;
    m_context->PSSetSamplers(0, 1, &sampler);

    ID3D11BlendState* blend = m_currentAdditive ? m_pipeline.additiveBlend
                                                : m_pipeline.alphaBlend;
    const float blendFactor[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    m_context->OMSetBlendState(blend, blendFactor, 0xFFFFFFFF);
    m_context->RSSetState(m_pipeline.rasterizer);

    m_context->DrawIndexed(static_cast<UINT>(m_quadCount * 6), 0, 0);

    m_vertices.clear();
    m_quadCount = 0;
}

} // namespace fc
