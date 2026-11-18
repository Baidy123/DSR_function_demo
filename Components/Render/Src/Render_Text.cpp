#include "Render_Text.hpp"

#include "Render_Device.hpp"
#include "Shared_Log.hpp"
#include "Shared_String.hpp"

#include <algorithm>
#include <climits>
#include <cstring>
#include <fstream>
#include <cwchar>

namespace fc {

TextRenderer::~TextRenderer()
{
    Shutdown();
}

bool TextRenderer::Initialize(RenderDevice* device)
{
    m_device = device;
    m_memoryDC = CreateCompatibleDC(nullptr);
    if (m_memoryDC == nullptr) {
        LogError("TextRenderer: CreateCompatibleDC failed");
        return false;
    }
    SetBkMode(m_memoryDC, TRANSPARENT);
    SetTextColor(m_memoryDC, RGB(255, 255, 255));
    LogInfo("TextRenderer initialized");
    return true;
}

void TextRenderer::Shutdown()
{
    ClearCache();
    for (auto& pair : m_fonts) {
        if (pair.second.font != nullptr) {
            DeleteObject(pair.second.font);
        }
    }
    m_fonts.clear();
    if (m_memoryDC != nullptr) {
        DeleteDC(m_memoryDC);
        m_memoryDC = nullptr;
    }
    m_device = nullptr;
}

void TextRenderer::SetPixelScale(int scale)
{
    if (scale < 1) {
        scale = 1;
    }
    if (scale > 8) {
        scale = 8;
    }
    if (scale == m_pixelScale) {
        return;
    }
    m_pixelScale = scale;
    // 密度变化后，旧纹理的像素密度不再匹配，必须重建。
    ClearCache();
    for (auto& pair : m_fonts) {
        if (pair.second.font != nullptr) {
            DeleteObject(pair.second.font);
        }
    }
    m_fonts.clear();
}

TextRenderer::FontRecord* TextRenderer::GetFont(int px)
{
    if (px < 6) {
        px = 6;
    }
    if (px > 256) {
        px = 256;
    }
    auto it = m_fonts.find(px);
    if (it != m_fonts.end()) {
        return &it->second;
    }

    LOGFONTW lf = {};
    lf.lfHeight = -px;
    lf.lfWeight = FW_NORMAL;
    lf.lfItalic = FALSE;
    lf.lfUnderline = FALSE;
    lf.lfStrikeOut = FALSE;
    lf.lfCharSet = DEFAULT_CHARSET;
    lf.lfOutPrecision = OUT_TT_PRECIS;
    lf.lfClipPrecision = CLIP_DEFAULT_PRECIS;
    lf.lfQuality = ANTIALIASED_QUALITY;
    lf.lfPitchAndFamily = DEFAULT_PITCH | FF_DONTCARE;
    std::wcscpy(lf.lfFaceName, L"Microsoft YaHei UI");

    HFONT font = CreateFontIndirectW(&lf);
    if (font == nullptr) {
        std::wcscpy(lf.lfFaceName, L"SimSun");
        font = CreateFontIndirectW(&lf);
    }
    if (font == nullptr) {
        LogError("TextRenderer: failed to create font at %dpx", px);
        return nullptr;
    }

    HGDIOBJ old = SelectObject(m_memoryDC, font);
    TEXTMETRICW metrics = {};
    GetTextMetricsW(m_memoryDC, &metrics);
    SelectObject(m_memoryDC, old);

    FontRecord record;
    record.font = font;
    record.px = px;
    record.lineHeight = std::max(px + 4,
                                 static_cast<int>(metrics.tmHeight +
                                                  metrics.tmExternalLeading + 2));
    auto inserted = m_fonts.emplace(px, record);
    return &inserted.first->second;
}

void TextRenderer::ClearCache()
{
    m_cache.clear();
}

const TextBlock* TextRenderer::Get(const std::string& text, int px, int maxWidth)
{
    if (m_memoryDC == nullptr) {
        return nullptr;
    }
    if (maxWidth <= 0) {
        maxWidth = INTERNAL_WIDTH;
    }
    if (px <= 0) {
        px = 12;
    }
    const std::string key = std::to_string(px) + "|" +
                            std::to_string(maxWidth) + "|" +
                            std::to_string(m_pixelScale) + "|" + text;
    auto it = m_cache.find(key);
    if (it != m_cache.end()) {
        return it->second.get();
    }
    if (m_cache.size() > 240) {
        ClearCache();
    }
    std::unique_ptr<TextBlock> block = Build(text, px, maxWidth);
    if (!block) {
        return nullptr;
    }
    const TextBlock* result = block.get();
    m_cache.emplace(key, std::move(block));
    return result;
}

int TextRenderer::MeasureHeight(const std::string& text, int px, int maxWidth)
{
    const TextBlock* block = Get(text, px, maxWidth);
    return block != nullptr ? block->height : 0;
}

std::unique_ptr<TextBlock> TextRenderer::Build(const std::string& text, int px,
                                               int maxWidth)
{
    // 逻辑字号乘像素密度得到实际光栅化字号；排版宽度同样放大。
    const int scale = m_pixelScale;
    FontRecord* font = GetFont(px * scale);
    if (font == nullptr) {
        return nullptr;
    }
    const int rasterMaxWidth = std::max(1, maxWidth * scale);

    std::unique_ptr<TextBlock> block(new TextBlock());
    block->pixelScale = scale;
    block->lineHeight = std::max(1, font->lineHeight / scale);

    const std::wstring wide = Utf8ToWide(text);
    const int unitCount = static_cast<int>(wide.size());
    block->unitCount = unitCount;
    if (unitCount <= 0) {
        return block;
    }

    HGDIOBJ oldFont = SelectObject(m_memoryDC, font->font);
    SetTextColor(m_memoryDC, RGB(255, 255, 255));
    SetBkMode(m_memoryDC, TRANSPARENT);

    struct RawLine {
        int start = 0;
        int length = 0;
        int width = 0;
    };
    std::vector<RawLine> rawLines;
    int maxLineWidth = 0;

    int pos = 0;
    while (pos <= unitCount) {
        const int start = pos;
        int end = pos;
        while (end < unitCount && wide[static_cast<size_t>(end)] != L'\n') {
            SIZE size = {};
            GetTextExtentPoint32W(m_memoryDC, wide.c_str() + start, end - start + 1,
                                  &size);
            if (size.cx > rasterMaxWidth && end > start) {
                break;
            }
            ++end;
        }
        RawLine line;
        line.start = start;
        line.length = end - start;
        if (line.length > 0) {
            SIZE size = {};
            GetTextExtentPoint32W(m_memoryDC, wide.c_str() + start, line.length,
                                  &size);
            line.width = size.cx;
            maxLineWidth = std::max(maxLineWidth, line.width);
        }
        rawLines.push_back(line);

        if (end < unitCount && wide[static_cast<size_t>(end)] == L'\n') {
            pos = end + 1;
            if (pos >= unitCount) {
                break;
            }
        } else {
            pos = end;
            if (pos >= unitCount) {
                break;
            }
        }
    }

    if (rawLines.empty()) {
        SelectObject(m_memoryDC, oldFont);
        return block;
    }

    const int textureWidth = std::max(1, maxLineWidth + 1);
    const int textureHeight = std::max(1, static_cast<int>(rawLines.size()) *
                                              font->lineHeight + 1);

    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = textureWidth;
    info.bmiHeader.biHeight = -textureHeight;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;

    void* bits = nullptr;
    HBITMAP bitmap = CreateDIBSection(m_memoryDC, &info, DIB_RGB_COLORS, &bits,
                                      nullptr, 0);
    if (bitmap == nullptr || bits == nullptr) {
        SelectObject(m_memoryDC, oldFont);
        LogError("TextRenderer: CreateDIBSection failed");
        return nullptr;
    }
    HGDIOBJ oldBitmap = SelectObject(m_memoryDC, bitmap);
    std::memset(bits, 0, static_cast<size_t>(textureWidth) * textureHeight * 4);

    block->lines.reserve(rawLines.size());
    for (size_t i = 0; i < rawLines.size(); ++i) {
        const RawLine& raw = rawLines[i];
        TextLine line;
        line.startUnit = raw.start;
        line.lengthUnits = raw.length;
        line.y = static_cast<int>(i) * block->lineHeight;
        line.height = block->lineHeight;
        line.width = std::max(1, raw.width / scale);
        line.charX.assign(static_cast<size_t>(raw.length) + 1, 0);
        for (int k = 1; k <= raw.length; ++k) {
            SIZE size = {};
            GetTextExtentPoint32W(m_memoryDC, wide.c_str() + raw.start, k, &size);
            line.charX[static_cast<size_t>(k)] = size.cx / scale;
        }
        if (raw.length > 0) {
            TextOutW(m_memoryDC, 0, static_cast<int>(i) * font->lineHeight + 1,
                     wide.c_str() + raw.start, raw.length);
        }
        block->lines.push_back(std::move(line));
    }
    GdiFlush();

    // GDI 不写 alpha；用亮度作为覆盖度，RGB 置白，便于着色。
    uint8_t* pixels = static_cast<uint8_t*>(bits);
    for (int i = 0; i < textureWidth * textureHeight; ++i) {
        uint8_t* p = pixels + static_cast<size_t>(i) * 4;
        const uint8_t alpha = std::max(std::max(p[0], p[1]), p[2]);
        p[0] = 255;
        p[1] = 255;
        p[2] = 255;
        p[3] = alpha;
    }

    // 必须在 DeleteObject 之前复制像素，否则 DIB 内存会被释放。
    std::vector<uint8_t> pixelCopy(
        pixels, pixels + static_cast<size_t>(textureWidth) * textureHeight * 4);

    SelectObject(m_memoryDC, oldBitmap);
    DeleteObject(bitmap);
    SelectObject(m_memoryDC, oldFont);

    if (m_device != nullptr) {
        if (!m_device->CreateTexture(pixelCopy.data(), textureWidth,
                                     textureHeight, "TextBlock",
                                     block->texture)) {
            LogError("TextRenderer: failed to upload text texture");
            return nullptr;
        }
    }

    block->width = std::max(1, textureWidth / scale);
    block->height = std::max(1, textureHeight / scale);
    return block;
}

void TextRenderer::Draw(SpriteBatch& batch, const TextBlock& block, float x,
                        float y, Color tint, int visibleUnits, bool shadow)
{
    if (!block.texture.IsValid() || block.lines.empty()) {
        return;
    }
    const int limit = visibleUnits < 0 ? INT_MAX : visibleUnits;

    for (const TextLine& line : block.lines) {
        if (line.startUnit >= limit) {
            break;
        }
        int count = line.lengthUnits;
        if (limit != INT_MAX) {
            const int remaining = limit - line.startUnit;
            count = std::min(count, remaining);
        }
        if (count <= 0) {
            continue;
        }
        int sourceWidth = line.width;
        if (count < line.lengthUnits &&
            static_cast<size_t>(count) < line.charX.size()) {
            sourceWidth = line.charX[static_cast<size_t>(count)];
        }
        if (sourceWidth <= 0) {
            continue;
        }
        const float pixelScale = static_cast<float>(block.pixelScale);
        const RectF source(0.0f, static_cast<float>(line.y) * pixelScale,
                           static_cast<float>(sourceWidth) * pixelScale,
                           static_cast<float>(line.height) * pixelScale);
        const float destinationY = y + static_cast<float>(line.y);
        if (shadow) {
            batch.DrawTextureRegion(block.texture, x + 1.0f, destinationY + 1.0f,
                                    static_cast<float>(sourceWidth),
                                    static_cast<float>(line.height), source,
                                    Color(0.02f, 0.03f, 0.05f, 0.75f),
                                    false, false, true);
        }
        batch.DrawTextureRegion(block.texture, x, destinationY,
                                static_cast<float>(sourceWidth),
                                static_cast<float>(line.height), source, tint,
                                false, false, true);
    }
}

bool TextRenderer::GetCaretPosition(const TextBlock& block, int visibleUnits,
                                    int& outLine, int& outX) const
{
    outLine = 0;
    outX = 0;
    if (block.lines.empty() || visibleUnits <= 0) {
        return false;
    }
    for (size_t i = 0; i < block.lines.size(); ++i) {
        const TextLine& line = block.lines[i];
        if (visibleUnits <= line.startUnit + line.lengthUnits) {
            const int offset = std::max(0, visibleUnits - line.startUnit);
            const size_t index = static_cast<size_t>(
                std::min(offset, line.lengthUnits));
            outLine = static_cast<int>(i);
            outX = line.charX.empty() ? 0 : line.charX[index];
            return true;
        }
    }
    const TextLine& line = block.lines.back();
    outLine = static_cast<int>(block.lines.size()) - 1;
    outX = line.width;
    return true;
}

} // namespace fc
