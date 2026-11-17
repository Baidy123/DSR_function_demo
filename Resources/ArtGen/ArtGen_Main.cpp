/**
 * @file ArtGen_Main.cpp
 * @brief 像素美术生成器：生成 Resources/Art 下的 PNG 与 Resources/ArtPack.bin。
 *
 * 该工具不属于游戏运行时，也不受 Tools/ 目录约束；它只依赖 C++ 标准库，
 * 使用自实现的 PNG（无压缩 Deflate）与 FCPK v1 资产包写出逻辑。
 *
 * 用法：
 *   g++ -std=c++17 -O2 Resources/ArtGen/ArtGen_Main.cpp -o Temp/ArtGen.exe
 *   Temp/ArtGen.exe Resources
 */

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

// ===========================================================================
// 基础类型
// ===========================================================================

struct Color {
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;
    uint8_t a = 0;
};

static Color RGBA(int r, int g, int b, int a = 255)
{
    Color c;
    c.r = static_cast<uint8_t>(r < 0 ? 0 : (r > 255 ? 255 : r));
    c.g = static_cast<uint8_t>(g < 0 ? 0 : (g > 255 ? 255 : g));
    c.b = static_cast<uint8_t>(b < 0 ? 0 : (b > 255 ? 255 : b));
    c.a = static_cast<uint8_t>(a < 0 ? 0 : (a > 255 ? 255 : a));
    return c;
}

static Color LerpColor(const Color& a, const Color& b, float t)
{
    return RGBA(
        static_cast<int>(a.r + (b.r - a.r) * t),
        static_cast<int>(a.g + (b.g - a.g) * t),
        static_cast<int>(a.b + (b.b - a.b) * t),
        static_cast<int>(a.a + (b.a - a.a) * t));
}

static Color Shade(const Color& c, float f)
{
    return RGBA(static_cast<int>(c.r * f), static_cast<int>(c.g * f),
                static_cast<int>(c.b * f), c.a);
}

static Color WithAlpha(const Color& c, int a)
{
    return RGBA(c.r, c.g, c.b, a);
}

// ===========================================================================
// 画布
// ===========================================================================

class Canvas {
public:
    int w = 0;
    int h = 0;
    std::vector<uint8_t> data;

    Canvas() = default;

    Canvas(int width, int height)
        : w(width), h(height), data(static_cast<size_t>(width) * height * 4, 0)
    {
    }

    void Clear(Color c)
    {
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                size_t i = (static_cast<size_t>(y) * w + x) * 4;
                data[i + 0] = c.r;
                data[i + 1] = c.g;
                data[i + 2] = c.b;
                data[i + 3] = c.a;
            }
        }
    }

    void Pixel(int x, int y, Color c)
    {
        if (x < 0 || y < 0 || x >= w || y >= h || c.a == 0) {
            return;
        }
        size_t i = (static_cast<size_t>(y) * w + x) * 4;
        uint8_t* p = &data[i];
        if (c.a == 255) {
            p[0] = c.r;
            p[1] = c.g;
            p[2] = c.b;
            p[3] = 255;
            return;
        }
        float sa = c.a / 255.0f;
        float da = p[3] / 255.0f;
        float oa = sa + da * (1.0f - sa);
        if (oa <= 0.0001f) {
            return;
        }
        p[0] = static_cast<uint8_t>((c.r * sa + p[0] * da * (1.0f - sa)) / oa);
        p[1] = static_cast<uint8_t>((c.g * sa + p[1] * da * (1.0f - sa)) / oa);
        p[2] = static_cast<uint8_t>((c.b * sa + p[2] * da * (1.0f - sa)) / oa);
        p[3] = static_cast<uint8_t>(oa * 255.0f);
    }

    void Add(int x, int y, Color c)
    {
        if (x < 0 || y < 0 || x >= w || y >= h || c.a == 0) {
            return;
        }
        size_t i = (static_cast<size_t>(y) * w + x) * 4;
        uint8_t* p = &data[i];
        int f = c.a;
        p[0] = static_cast<uint8_t>(std::min(255, p[0] + c.r * f / 255));
        p[1] = static_cast<uint8_t>(std::min(255, p[1] + c.g * f / 255));
        p[2] = static_cast<uint8_t>(std::min(255, p[2] + c.b * f / 255));
        p[3] = 255;
    }

    void FillRect(int x, int y, int rw, int rh, Color c)
    {
        for (int yy = y; yy < y + rh; ++yy) {
            for (int xx = x; xx < x + rw; ++xx) {
                Pixel(xx, yy, c);
            }
        }
    }

    void OutlineRect(int x, int y, int rw, int rh, Color c)
    {
        HLine(x, x + rw - 1, y, c);
        HLine(x, x + rw - 1, y + rh - 1, c);
        VLine(x, y, y + rh - 1, c);
        VLine(x + rw - 1, y, y + rh - 1, c);
    }

    void HLine(int x0, int x1, int y, Color c)
    {
        if (x0 > x1) {
            std::swap(x0, x1);
        }
        for (int x = x0; x <= x1; ++x) {
            Pixel(x, y, c);
        }
    }

    void VLine(int x, int y0, int y1, Color c)
    {
        if (y0 > y1) {
            std::swap(y0, y1);
        }
        for (int y = y0; y <= y1; ++y) {
            Pixel(x, y, c);
        }
    }

    void Line(int x0, int y0, int x1, int y1, Color c, int thickness = 1)
    {
        int dx = std::abs(x1 - x0);
        int dy = std::abs(y1 - y0);
        int sx = x0 < x1 ? 1 : -1;
        int sy = y0 < y1 ? 1 : -1;
        int err = dx - dy;
        while (true) {
            if (thickness <= 1) {
                Pixel(x0, y0, c);
            } else {
                FillRect(x0 - thickness / 2, y0 - thickness / 2,
                         thickness, thickness, c);
            }
            if (x0 == x1 && y0 == y1) {
                break;
            }
            int e2 = err * 2;
            if (e2 > -dy) {
                err -= dy;
                x0 += sx;
            }
            if (e2 < dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    void EllipseFill(int cx, int cy, int rx, int ry, Color c)
    {
        if (rx <= 0 || ry <= 0) {
            return;
        }
        for (int y = -ry; y <= ry; ++y) {
            for (int x = -rx; x <= rx; ++x) {
                long long v = static_cast<long long>(x) * x * ry * ry +
                              static_cast<long long>(y) * y * rx * rx;
                if (v <= static_cast<long long>(rx) * rx * ry * ry) {
                    Pixel(cx + x, cy + y, c);
                }
            }
        }
    }

    void EllipseLine(int cx, int cy, int rx, int ry, Color c)
    {
        if (rx <= 0 || ry <= 0) {
            return;
        }
        long long outer = static_cast<long long>(rx) * rx * ry * ry;
        long long inner = static_cast<long long>(std::max(0, rx - 1)) *
                              std::max(0, rx - 1) * std::max(0, ry - 1) *
                              std::max(0, ry - 1);
        for (int y = -ry; y <= ry; ++y) {
            for (int x = -rx; x <= rx; ++x) {
                long long v = static_cast<long long>(x) * x * ry * ry +
                              static_cast<long long>(y) * y * rx * rx;
                if (v <= outer && v >= inner) {
                    Pixel(cx + x, cy + y, c);
                }
            }
        }
    }

    void PolyFill(const std::vector<std::pair<int, int>>& pts, Color c)
    {
        if (pts.size() < 3) {
            return;
        }
        int minY = pts[0].second;
        int maxY = pts[0].second;
        for (const auto& p : pts) {
            minY = std::min(minY, p.second);
            maxY = std::max(maxY, p.second);
        }
        for (int y = minY; y <= maxY; ++y) {
            std::vector<int> xs;
            for (size_t i = 0; i < pts.size(); ++i) {
                const auto& a = pts[i];
                const auto& b = pts[(i + 1) % pts.size()];
                if ((a.second <= y && b.second > y) ||
                    (b.second <= y && a.second > y)) {
                    float t = static_cast<float>(y - a.second) /
                              static_cast<float>(b.second - a.second);
                    xs.push_back(static_cast<int>(a.first + (b.first - a.first) * t));
                }
            }
            std::sort(xs.begin(), xs.end());
            for (size_t i = 0; i + 1 < xs.size(); i += 2) {
                for (int x = xs[i]; x <= xs[i + 1]; ++x) {
                    Pixel(x, y, c);
                }
            }
        }
    }

    void Blit(const Canvas& src, int dx, int dy, int scale = 1)
    {
        for (int y = 0; y < src.h; ++y) {
            for (int x = 0; x < src.w; ++x) {
                size_t i = (static_cast<size_t>(y) * src.w + x) * 4;
                Color c = RGBA(src.data[i], src.data[i + 1],
                               src.data[i + 2], src.data[i + 3]);
                if (scale == 1) {
                    Pixel(dx + x, dy + y, c);
                } else {
                    FillRect(dx + x * scale, dy + y * scale, scale, scale, c);
                }
            }
        }
    }

    void BlitFlipX(const Canvas& src, int dx, int dy)
    {
        for (int y = 0; y < src.h; ++y) {
            for (int x = 0; x < src.w; ++x) {
                size_t i = (static_cast<size_t>(y) * src.w + x) * 4;
                Color c = RGBA(src.data[i], src.data[i + 1],
                               src.data[i + 2], src.data[i + 3]);
                Pixel(dx + (src.w - 1 - x), dy + y, c);
            }
        }
    }
};

// ===========================================================================
// 伪随机
// ===========================================================================

class Rng {
public:
    explicit Rng(uint32_t seed = 0x12345678u) : m_state(seed ? seed : 1u) {}

    uint32_t Next()
    {
        uint32_t x = m_state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        m_state = x;
        return x;
    }

    int Range(int lo, int hi)
    {
        if (hi <= lo) {
            return lo;
        }
        return lo + static_cast<int>(Next() % static_cast<uint32_t>(hi - lo + 1));
    }

    float Unit()
    {
        return (Next() & 0xFFFFFF) / 16777216.0f;
    }

private:
    uint32_t m_state;
};

// ===========================================================================
// 5x7 像素字体
// ===========================================================================

static bool GetGlyph(char ch, uint8_t out[7])
{
    if (ch >= 'a' && ch <= 'z') {
        ch = static_cast<char>(ch - 'a' + 'A');
    }
    switch (ch) {
    case 'A': { const uint8_t g[7] = {0x0E,0x11,0x11,0x1F,0x11,0x11,0x11}; std::memcpy(out,g,7); return true; }
    case 'B': { const uint8_t g[7] = {0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E}; std::memcpy(out,g,7); return true; }
    case 'C': { const uint8_t g[7] = {0x0E,0x11,0x10,0x10,0x10,0x11,0x0E}; std::memcpy(out,g,7); return true; }
    case 'D': { const uint8_t g[7] = {0x1E,0x11,0x11,0x11,0x11,0x11,0x1E}; std::memcpy(out,g,7); return true; }
    case 'E': { const uint8_t g[7] = {0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F}; std::memcpy(out,g,7); return true; }
    case 'F': { const uint8_t g[7] = {0x1F,0x10,0x10,0x1E,0x10,0x10,0x10}; std::memcpy(out,g,7); return true; }
    case 'G': { const uint8_t g[7] = {0x0E,0x11,0x10,0x17,0x11,0x11,0x0F}; std::memcpy(out,g,7); return true; }
    case 'H': { const uint8_t g[7] = {0x11,0x11,0x11,0x1F,0x11,0x11,0x11}; std::memcpy(out,g,7); return true; }
    case 'I': { const uint8_t g[7] = {0x1F,0x04,0x04,0x04,0x04,0x04,0x1F}; std::memcpy(out,g,7); return true; }
    case 'J': { const uint8_t g[7] = {0x07,0x02,0x02,0x02,0x02,0x12,0x0C}; std::memcpy(out,g,7); return true; }
    case 'K': { const uint8_t g[7] = {0x11,0x12,0x14,0x18,0x14,0x12,0x11}; std::memcpy(out,g,7); return true; }
    case 'L': { const uint8_t g[7] = {0x10,0x10,0x10,0x10,0x10,0x10,0x1F}; std::memcpy(out,g,7); return true; }
    case 'M': { const uint8_t g[7] = {0x11,0x1B,0x15,0x15,0x11,0x11,0x11}; std::memcpy(out,g,7); return true; }
    case 'N': { const uint8_t g[7] = {0x11,0x19,0x15,0x13,0x11,0x11,0x11}; std::memcpy(out,g,7); return true; }
    case 'O': { const uint8_t g[7] = {0x0E,0x11,0x11,0x11,0x11,0x11,0x0E}; std::memcpy(out,g,7); return true; }
    case 'P': { const uint8_t g[7] = {0x1E,0x11,0x11,0x1E,0x10,0x10,0x10}; std::memcpy(out,g,7); return true; }
    case 'Q': { const uint8_t g[7] = {0x0E,0x11,0x11,0x11,0x15,0x12,0x0D}; std::memcpy(out,g,7); return true; }
    case 'R': { const uint8_t g[7] = {0x1E,0x11,0x11,0x1E,0x14,0x12,0x11}; std::memcpy(out,g,7); return true; }
    case 'S': { const uint8_t g[7] = {0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E}; std::memcpy(out,g,7); return true; }
    case 'T': { const uint8_t g[7] = {0x1F,0x04,0x04,0x04,0x04,0x04,0x04}; std::memcpy(out,g,7); return true; }
    case 'U': { const uint8_t g[7] = {0x11,0x11,0x11,0x11,0x11,0x11,0x0E}; std::memcpy(out,g,7); return true; }
    case 'V': { const uint8_t g[7] = {0x11,0x11,0x11,0x11,0x11,0x0A,0x04}; std::memcpy(out,g,7); return true; }
    case 'W': { const uint8_t g[7] = {0x11,0x11,0x11,0x15,0x15,0x1B,0x11}; std::memcpy(out,g,7); return true; }
    case 'X': { const uint8_t g[7] = {0x11,0x11,0x0A,0x04,0x0A,0x11,0x11}; std::memcpy(out,g,7); return true; }
    case 'Y': { const uint8_t g[7] = {0x11,0x11,0x0A,0x04,0x04,0x04,0x04}; std::memcpy(out,g,7); return true; }
    case 'Z': { const uint8_t g[7] = {0x1F,0x01,0x02,0x04,0x08,0x10,0x1F}; std::memcpy(out,g,7); return true; }
    case '0': { const uint8_t g[7] = {0x0E,0x11,0x13,0x15,0x19,0x11,0x0E}; std::memcpy(out,g,7); return true; }
    case '1': { const uint8_t g[7] = {0x04,0x0C,0x04,0x04,0x04,0x04,0x0E}; std::memcpy(out,g,7); return true; }
    case '2': { const uint8_t g[7] = {0x0E,0x11,0x01,0x02,0x04,0x08,0x1F}; std::memcpy(out,g,7); return true; }
    case '3': { const uint8_t g[7] = {0x1F,0x02,0x04,0x02,0x01,0x11,0x0E}; std::memcpy(out,g,7); return true; }
    case '4': { const uint8_t g[7] = {0x02,0x06,0x0A,0x12,0x1F,0x02,0x02}; std::memcpy(out,g,7); return true; }
    case '5': { const uint8_t g[7] = {0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E}; std::memcpy(out,g,7); return true; }
    case '6': { const uint8_t g[7] = {0x06,0x08,0x10,0x1E,0x11,0x11,0x0E}; std::memcpy(out,g,7); return true; }
    case '7': { const uint8_t g[7] = {0x1F,0x01,0x02,0x04,0x08,0x08,0x08}; std::memcpy(out,g,7); return true; }
    case '8': { const uint8_t g[7] = {0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E}; std::memcpy(out,g,7); return true; }
    case '9': { const uint8_t g[7] = {0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C}; std::memcpy(out,g,7); return true; }
    case '-': { const uint8_t g[7] = {0x00,0x00,0x00,0x1F,0x00,0x00,0x00}; std::memcpy(out,g,7); return true; }
    case '.': { const uint8_t g[7] = {0x00,0x00,0x00,0x00,0x00,0x06,0x06}; std::memcpy(out,g,7); return true; }
    case ',': { const uint8_t g[7] = {0x00,0x00,0x00,0x00,0x06,0x06,0x0C}; std::memcpy(out,g,7); return true; }
    case ':': { const uint8_t g[7] = {0x00,0x06,0x06,0x00,0x06,0x06,0x00}; std::memcpy(out,g,7); return true; }
    case '/': { const uint8_t g[7] = {0x01,0x02,0x02,0x04,0x08,0x08,0x10}; std::memcpy(out,g,7); return true; }
    case '!': { const uint8_t g[7] = {0x04,0x04,0x04,0x04,0x04,0x00,0x04}; std::memcpy(out,g,7); return true; }
    case '?': { const uint8_t g[7] = {0x0E,0x11,0x01,0x02,0x04,0x00,0x04}; std::memcpy(out,g,7); return true; }
    case '+': { const uint8_t g[7] = {0x00,0x04,0x04,0x1F,0x04,0x04,0x00}; std::memcpy(out,g,7); return true; }
    case '\'': { const uint8_t g[7] = {0x04,0x04,0x00,0x00,0x00,0x00,0x00}; std::memcpy(out,g,7); return true; }
    case '"': { const uint8_t g[7] = {0x0A,0x0A,0x00,0x00,0x00,0x00,0x00}; std::memcpy(out,g,7); return true; }
    case '%': { const uint8_t g[7] = {0x19,0x1A,0x02,0x04,0x08,0x0B,0x13}; std::memcpy(out,g,7); return true; }
    case '*': { const uint8_t g[7] = {0x00,0x0A,0x04,0x1F,0x04,0x0A,0x00}; std::memcpy(out,g,7); return true; }
    case '_': { const uint8_t g[7] = {0x00,0x00,0x00,0x00,0x00,0x00,0x1F}; std::memcpy(out,g,7); return true; }
    case '>': { const uint8_t g[7] = {0x08,0x04,0x02,0x01,0x02,0x04,0x08}; std::memcpy(out,g,7); return true; }
    case '<': { const uint8_t g[7] = {0x02,0x04,0x08,0x10,0x08,0x04,0x02}; std::memcpy(out,g,7); return true; }
    case ' ': default:
        std::memset(out, 0, 7);
        return false;
    }
}

static int TextWidth(const std::string& text, int scale, int spacing)
{
    const int count = static_cast<int>(text.size());
    if (count <= 0) {
        return 0;
    }
    return count * (5 * scale + spacing) - spacing;
}

static void DrawText(Canvas& c, const std::string& text, int x, int y,
                     int scale, Color color, int spacing = 1)
{
    int cx = x;
    uint8_t glyph[7];
    for (char ch : text) {
        GetGlyph(ch, glyph);
        for (int gy = 0; gy < 7; ++gy) {
            for (int gx = 0; gx < 5; ++gx) {
                if (glyph[gy] & (1u << (4 - gx))) {
                    c.FillRect(cx + gx * scale, y + gy * scale,
                               scale, scale, color);
                }
            }
        }
        cx += 5 * scale + spacing;
    }
}

static void DrawTextGlow(Canvas& c, const std::string& text, int x, int y,
                         int scale, Color core, Color glow, int spacing = 1)
{
    static const int OFFSETS[12][2] = {
        {-2,0},{2,0},{0,-2},{0,2},{-1,-1},{1,-1},{-1,1},{1,1},
        {-1,0},{1,0},{0,-1},{0,1}
    };
    for (const auto& o : OFFSETS) {
        DrawText(c, text, x + o[0], y + o[1], scale, glow, spacing);
        if (scale > 1) {
            DrawText(c, text, x + o[0] * 2, y + o[1] * 2, scale,
                     WithAlpha(glow, glow.a / 2), spacing);
        }
    }
    DrawText(c, text, x, y, scale, core, spacing);
}

// ===========================================================================
// PNG 写出（无压缩 Deflate）
// ===========================================================================

static uint32_t Crc32(const uint8_t* data, size_t length)
{
    static uint32_t table[256];
    static bool ready = false;
    if (!ready) {
        for (uint32_t i = 0; i < 256; ++i) {
            uint32_t c = i;
            for (int k = 0; k < 8; ++k) {
                c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : (c >> 1);
            }
            table[i] = c;
        }
        ready = true;
    }
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < length; ++i) {
        crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFu;
}

static uint32_t Adler32(const std::vector<uint8_t>& data)
{
    uint32_t a = 1;
    uint32_t b = 0;
    for (uint8_t v : data) {
        a = (a + v) % 65521;
        b = (b + a) % 65521;
    }
    return (b << 16) | a;
}

static void PushU32BE(std::vector<uint8_t>& out, uint32_t v)
{
    out.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
    out.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
    out.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    out.push_back(static_cast<uint8_t>(v & 0xFF));
}

static void PushChunk(std::vector<uint8_t>& out, const char type[5],
                      const std::vector<uint8_t>& payload)
{
    PushU32BE(out, static_cast<uint32_t>(payload.size()));
    size_t typeStart = out.size();
    out.push_back(static_cast<uint8_t>(type[0]));
    out.push_back(static_cast<uint8_t>(type[1]));
    out.push_back(static_cast<uint8_t>(type[2]));
    out.push_back(static_cast<uint8_t>(type[3]));
    out.insert(out.end(), payload.begin(), payload.end());
    uint32_t crc = Crc32(&out[typeStart], 4 + payload.size());
    PushU32BE(out, crc);
}

static bool WritePNG(const fs::path& path, const Canvas& c)
{
    std::vector<uint8_t> raw;
    raw.reserve(static_cast<size_t>(c.h) * (1 + c.w * 4));
    for (int y = 0; y < c.h; ++y) {
        raw.push_back(0);
        size_t row = static_cast<size_t>(y) * c.w * 4;
        raw.insert(raw.end(), c.data.begin() + row,
                   c.data.begin() + row + static_cast<size_t>(c.w) * 4);
    }

    std::vector<uint8_t> z;
    z.push_back(0x78);
    z.push_back(0x01);
    size_t pos = 0;
    while (pos < raw.size()) {
        size_t n = std::min<size_t>(65535, raw.size() - pos);
        bool last = (pos + n == raw.size());
        z.push_back(last ? 1 : 0);
        z.push_back(static_cast<uint8_t>(n & 0xFF));
        z.push_back(static_cast<uint8_t>((n >> 8) & 0xFF));
        uint16_t nlen = static_cast<uint16_t>(~static_cast<uint16_t>(n));
        z.push_back(static_cast<uint8_t>(nlen & 0xFF));
        z.push_back(static_cast<uint8_t>((nlen >> 8) & 0xFF));
        z.insert(z.end(), raw.begin() + pos, raw.begin() + pos + n);
        pos += n;
    }
    uint32_t adler = Adler32(raw);
    z.push_back(static_cast<uint8_t>((adler >> 24) & 0xFF));
    z.push_back(static_cast<uint8_t>((adler >> 16) & 0xFF));
    z.push_back(static_cast<uint8_t>((adler >> 8) & 0xFF));
    z.push_back(static_cast<uint8_t>(adler & 0xFF));

    std::vector<uint8_t> png = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};

    std::vector<uint8_t> ihdr;
    PushU32BE(ihdr, static_cast<uint32_t>(c.w));
    PushU32BE(ihdr, static_cast<uint32_t>(c.h));
    ihdr.push_back(8);
    ihdr.push_back(6);
    ihdr.push_back(0);
    ihdr.push_back(0);
    ihdr.push_back(0);
    PushChunk(png, "IHDR", ihdr);
    PushChunk(png, "IDAT", z);
    PushChunk(png, "IEND", {});

    std::ofstream f(path, std::ios::binary);
    if (!f) {
        return false;
    }
    f.write(reinterpret_cast<const char*>(png.data()),
            static_cast<std::streamsize>(png.size()));
    return f.good();
}

// ===========================================================================
// 资产集合与资产包
// ===========================================================================

struct Asset {
    std::string name;
    Canvas canvas;
};

static std::vector<Asset> g_assets;

static void AddAsset(const std::string& name, Canvas&& canvas, bool inPack = true)
{
    Asset a;
    a.name = name;
    a.canvas = std::move(canvas);
    g_assets.push_back(std::move(a));
    if (!inPack) {
        // 标记：只有以 '_' 开头的资产不进入运行时包。
    }
}

static bool WritePack(const fs::path& path)
{
    std::vector<const Asset*> pack;
    for (const auto& a : g_assets) {
        if (!a.name.empty() && a.name[0] != '_') {
            pack.push_back(&a);
        }
    }
    if (pack.size() > 65535) {
        return false;
    }

    const uint32_t headerSize = 8;
    const uint32_t entrySize = 44;
    uint32_t dataOffset = headerSize + static_cast<uint32_t>(pack.size()) * entrySize;

    std::ofstream f(path, std::ios::binary);
    if (!f) {
        return false;
    }

    std::vector<uint8_t> header;
    header.push_back('F');
    header.push_back('C');
    header.push_back('P');
    header.push_back('K');
    header.push_back(1);
    header.push_back(0);
    header.push_back(static_cast<uint8_t>(pack.size() & 0xFF));
    header.push_back(static_cast<uint8_t>((pack.size() >> 8) & 0xFF));

    std::vector<uint8_t> entries;
    std::vector<uint8_t> data;

    for (const Asset* a : pack) {
        char nameBuf[32];
        std::memset(nameBuf, 0, sizeof(nameBuf));
        std::strncpy(nameBuf, a->name.c_str(), sizeof(nameBuf) - 1);
        entries.insert(entries.end(), nameBuf, nameBuf + 32);

        uint16_t w = static_cast<uint16_t>(a->canvas.w);
        uint16_t h = static_cast<uint16_t>(a->canvas.h);
        entries.push_back(static_cast<uint8_t>(w & 0xFF));
        entries.push_back(static_cast<uint8_t>((w >> 8) & 0xFF));
        entries.push_back(static_cast<uint8_t>(h & 0xFF));
        entries.push_back(static_cast<uint8_t>((h >> 8) & 0xFF));

        uint32_t size = static_cast<uint32_t>(a->canvas.w) * a->canvas.h * 4;
        uint32_t off = dataOffset + static_cast<uint32_t>(data.size());
        entries.push_back(static_cast<uint8_t>(off & 0xFF));
        entries.push_back(static_cast<uint8_t>((off >> 8) & 0xFF));
        entries.push_back(static_cast<uint8_t>((off >> 16) & 0xFF));
        entries.push_back(static_cast<uint8_t>((off >> 24) & 0xFF));
        entries.push_back(static_cast<uint8_t>(size & 0xFF));
        entries.push_back(static_cast<uint8_t>((size >> 8) & 0xFF));
        entries.push_back(static_cast<uint8_t>((size >> 16) & 0xFF));
        entries.push_back(static_cast<uint8_t>((size >> 24) & 0xFF));

        for (size_t i = 0; i < a->canvas.data.size(); i += 4) {
            data.push_back(a->canvas.data[i + 2]);
            data.push_back(a->canvas.data[i + 1]);
            data.push_back(a->canvas.data[i + 0]);
            data.push_back(a->canvas.data[i + 3]);
        }
    }

    f.write(reinterpret_cast<const char*>(header.data()),
            static_cast<std::streamsize>(header.size()));
    f.write(reinterpret_cast<const char*>(entries.data()),
            static_cast<std::streamsize>(entries.size()));
    f.write(reinterpret_cast<const char*>(data.data()),
            static_cast<std::streamsize>(data.size()));
    return f.good();
}

// ===========================================================================
// 通用绘制辅助
// ===========================================================================

static void Noise(Canvas& c, Rng& rng, Color color, int count)
{
    for (int i = 0; i < count; ++i) {
        c.Pixel(rng.Range(0, c.w - 1), rng.Range(0, c.h - 1), color);
    }
}

static void GlowCircle(Canvas& c, int cx, int cy, int radius, Color color)
{
    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            int d2 = x * x + y * y;
            if (d2 > radius * radius) {
                continue;
            }
            float t = 1.0f - std::sqrt(static_cast<float>(d2)) /
                                 static_cast<float>(radius);
            int alpha = static_cast<int>(color.a * t * t);
            if (alpha > 2) {
                c.Add(cx + x, cy + y, WithAlpha(color, alpha));
            }
        }
    }
}

static void Shadow(Canvas& c, int cx, int cy, int rx, int ry, int alpha = 90)
{
    c.EllipseFill(cx, cy, rx, ry, RGBA(0, 0, 0, alpha));
}

// ===========================================================================
// 瓷砖
// ===========================================================================

static Canvas MakeBarFloor(int variant, uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed + variant * 77);
    Color base[3] = {RGBA(74, 52, 38), RGBA(68, 47, 35), RGBA(80, 57, 42)};
    Color dark = RGBA(48, 33, 25);
    Color light = RGBA(104, 76, 54);
    c.Clear(base[variant]);
    for (int y = 0; y < 16; ++y) {
        for (int x = 0; x < 16; ++x) {
            int n = rng.Range(-5, 5);
            c.Pixel(x, y, RGBA(base[variant].r + n, base[variant].g + n,
                              base[variant].b + n));
        }
    }
    int seam = 7;
    c.HLine(0, 15, seam, dark);
    c.HLine(0, 15, 15, dark);
    c.HLine(0, 15, 0, Shade(dark, 0.8f));
    int jointA = 4 + variant * 5;
    int jointB = (11 + variant * 3) % 16;
    c.VLine(jointA, 1, seam - 1, Shade(dark, 1.05f));
    c.VLine(jointB, seam + 1, 14, Shade(dark, 1.05f));
    for (int i = 0; i < 6; ++i) {
        int y = rng.Range(1, 14);
        int x = rng.Range(0, 12);
        int len = rng.Range(2, 5);
        c.HLine(x, std::min(15, x + len), y, Shade(dark, 1.15f));
    }
    c.HLine(0, 15, 1, WithAlpha(light, 90));
    c.Pixel(jointA - 1, 2, RGBA(150, 120, 80, 180));
    c.Pixel(jointB, seam + 2, RGBA(150, 120, 80, 180));
    return c;
}

static Canvas MakeBarCarpet(int variant, uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed + variant * 131);
    Color base = variant == 0 ? RGBA(74, 32, 41) : RGBA(82, 37, 45);
    Color border = RGBA(104, 48, 58);
    Color dark = RGBA(52, 22, 30);
    c.Clear(base);
    for (int y = 0; y < 16; ++y) {
        for (int x = 0; x < 16; ++x) {
            if ((x < 2 || x > 13 || y < 2 || y > 13) && ((x + y) & 1)) {
                c.Pixel(x, y, WithAlpha(border, 200));
            }
        }
    }
    for (int y = 4; y < 13; y += 4) {
        for (int x = 4; x < 13; x += 4) {
            c.Pixel(x, y, WithAlpha(RGBA(120, 60, 68), 150));
            c.Pixel(x + 1, y + 1, WithAlpha(dark, 120));
        }
    }
    Noise(c, rng, WithAlpha(RGBA(140, 100, 80), 40), 18);
    for (int i = 0; i < 4; ++i) {
        int x = rng.Range(2, 12);
        int y = rng.Range(2, 12);
        c.HLine(x, x + rng.Range(1, 3), y, WithAlpha(RGBA(40, 18, 24), 120));
    }
    return c;
}

static Canvas MakeBarWall(int variant, uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed + variant * 211);
    Color brick = variant == 0 ? RGBA(42, 49, 56) : RGBA(48, 43, 48);
    Color mortar = RGBA(24, 28, 34);
    Color light = variant == 0 ? RGBA(58, 68, 76) : RGBA(64, 57, 62);
    c.Clear(brick);
    for (int row = 0; row < 2; ++row) {
        int y0 = row * 8;
        c.HLine(0, 15, y0, mortar);
        c.HLine(0, 15, y0 + 1, light);
        int offset = (row % 2) * 4 + variant * 2;
        for (int x = 0; x < 16; ++x) {
            if ((x + offset) % 8 == 0) {
                c.VLine(x, y0 + 1, y0 + 7, mortar);
            }
        }
        for (int i = 0; i < 3; ++i) {
            int x = rng.Range(0, 15);
            int y = rng.Range(y0 + 2, y0 + 6);
            c.Pixel(x, y, WithAlpha(light, 100));
        }
    }
    c.HLine(0, 15, 12, RGBA(30, 26, 24));
    c.HLine(0, 15, 13, RGBA(58, 47, 38));
    c.HLine(0, 15, 15, RGBA(20, 18, 20));
    for (int i = 0; i < 5; ++i) {
        c.Pixel(rng.Range(0, 15), rng.Range(14, 15), RGBA(92, 74, 54, 120));
    }
    return c;
}

static Canvas MakeBarShelf(uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed);
    c.Clear(RGBA(36, 27, 24));
    for (int y = 0; y < 16; ++y) {
        c.HLine(0, 15, y, WithAlpha(RGBA(46 + (y % 3), 34, 29), 255));
    }
    for (int shelf = 0; shelf < 3; ++shelf) {
        int y = 4 + shelf * 5;
        c.HLine(0, 15, y, RGBA(92, 66, 44));
        c.HLine(0, 15, y + 1, RGBA(30, 22, 18));
        for (int i = 0; i < 3; ++i) {
            int x = 1 + i * 5 + rng.Range(0, 1);
            int h = rng.Range(2, 3);
            Color bottle = (i == 0) ? RGBA(120, 160, 90)
                          : (i == 1) ? RGBA(150, 90, 50)
                                     : RGBA(70, 130, 150);
            c.FillRect(x, y - h, 2, h, bottle);
            c.Pixel(x, y - h, WithAlpha(RGBA(230, 240, 220), 160));
            c.Pixel(x + 1, y - h + 1, Shade(bottle, 0.7f));
        }
    }
    c.HLine(0, 15, 15, RGBA(20, 16, 16));
    return c;
}

static Canvas MakeBarWindow(uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed);
    c.Clear(RGBA(40, 46, 52));
    c.FillRect(1, 1, 14, 12, RGBA(24, 22, 26));
    c.FillRect(2, 2, 12, 10, RGBA(255, 179, 71, 230));
    c.FillRect(2, 2, 12, 3, RGBA(255, 205, 120, 240));
    c.VLine(8, 2, 11, RGBA(60, 42, 32));
    c.HLine(2, 13, 7, RGBA(60, 42, 32));
    for (int i = 0; i < 4; ++i) {
        int x = rng.Range(3, 12);
        c.VLine(x, rng.Range(3, 6), rng.Range(8, 11),
                WithAlpha(RGBA(120, 80, 50), 160));
    }
    c.HLine(1, 14, 12, RGBA(70, 52, 36));
    c.HLine(1, 14, 13, RGBA(30, 24, 22));
    return c;
}

static Canvas MakeStreetFloor(int variant, uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed + variant * 313);
    Color base = variant == 0 ? RGBA(27, 32, 40) : RGBA(30, 36, 44);
    c.Clear(base);
    for (int y = 0; y < 16; ++y) {
        for (int x = 0; x < 16; ++x) {
            int n = rng.Range(-4, 4);
            c.Pixel(x, y, RGBA(base.r + n, base.g + n, base.b + n));
        }
    }
    for (int i = 0; i < 3; ++i) {
        int x = rng.Range(0, 15);
        int y = rng.Range(0, 15);
        c.Line(x, y, x + rng.Range(-4, 4), y + rng.Range(2, 5),
               RGBA(16, 20, 26, 180));
    }
    if (variant == 1) {
        c.EllipseFill(5, 10, 4, 2, RGBA(36, 54, 64, 160));
        c.EllipseLine(5, 10, 4, 2, RGBA(80, 130, 140, 80));
        c.HLine(3, 7, 10, RGBA(110, 190, 190, 60));
    }
    c.Pixel(rng.Range(0, 15), rng.Range(0, 15), WithAlpha(RGBA(120, 180, 190), 80));
    return c;
}

static Canvas MakeStreetWall(int variant, uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed + variant * 401);
    Color base = variant == 0 ? RGBA(44, 46, 52) : RGBA(52, 44, 40);
    c.Clear(base);
    for (int row = 0; row < 2; ++row) {
        int y0 = row * 8;
        c.HLine(0, 15, y0, RGBA(26, 28, 34));
        int offset = (row % 2) * 4;
        for (int x = 0; x < 16; ++x) {
            if ((x + offset) % 8 == 0) {
                c.VLine(x, y0, y0 + 7, RGBA(28, 30, 36));
            }
        }
    }
    for (int i = 0; i < 12; ++i) {
        int x = rng.Range(0, 15);
        int y = rng.Range(0, 15);
        c.Pixel(x, y, WithAlpha(RGBA(70, 80, 86), 90));
    }
    c.HLine(0, 15, 13, RGBA(24, 26, 30));
    c.HLine(0, 15, 14, RGBA(60, 64, 68));
    c.HLine(0, 15, 15, RGBA(18, 20, 24));
    if (variant == 1) {
        c.Line(3, 5, 9, 3, RGBA(57, 224, 208, 70));
        c.Line(9, 3, 12, 7, RGBA(57, 224, 208, 50));
        c.Line(2, 8, 6, 6, RGBA(255, 61, 139, 50));
    }
    return c;
}

static Canvas MakeStreetCurb(uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed);
    c.Clear(RGBA(22, 26, 32));
    c.FillRect(0, 2, 16, 9, RGBA(58, 62, 68));
    c.HLine(0, 15, 2, RGBA(96, 104, 108));
    c.HLine(0, 15, 3, RGBA(74, 78, 84));
    c.HLine(0, 15, 11, RGBA(30, 34, 40));
    for (int i = 0; i < 10; ++i) {
        c.Pixel(rng.Range(0, 15), rng.Range(4, 10),
                WithAlpha(RGBA(40, 44, 48), 120));
    }
    return c;
}

static Canvas MakeHarborFloor(int variant, uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed + variant * 503);
    Color base = RGBA(45, 50, 56);
    c.Clear(base);
    for (int y = 0; y < 16; ++y) {
        for (int x = 0; x < 16; ++x) {
            int n = rng.Range(-4, 5);
            c.Pixel(x, y, RGBA(base.r + n, base.g + n, base.b + n));
        }
    }
    c.HLine(0, 15, 0, RGBA(30, 34, 38));
    c.VLine(0, 0, 15, RGBA(30, 34, 38));
    c.HLine(0, 15, 15, RGBA(52, 57, 62));
    if (variant == 1) {
        c.EllipseFill(6, 9, 5, 3, RGBA(24, 26, 30, 160));
        c.EllipseFill(8, 10, 3, 2, RGBA(18, 20, 24, 180));
        c.HLine(4, 10, 8, RGBA(90, 70, 50, 60));
    } else if (variant == 2) {
        for (int i = -16; i < 16; i += 6) {
            c.Line(i, 15, i + 15, 0, RGBA(180, 140, 40, 110), 2);
        }
        c.Line(0, 4, 15, 4, RGBA(30, 32, 36, 180));
    }
    Noise(c, rng, WithAlpha(RGBA(70, 76, 82), 80), 10);
    return c;
}

static Canvas MakeHarborWall(int variant, uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed + variant * 601);
    Color dark = RGBA(30, 34, 39);
    Color light = RGBA(56, 62, 68);
    Color rust = RGBA(122, 70, 48);
    c.Clear(dark);
    for (int x = 0; x < 16; ++x) {
        Color col = (x % 4 == 0) ? light :
                    (x % 4 == 1) ? RGBA(48, 54, 60) :
                    (x % 4 == 2) ? RGBA(42, 48, 54) : dark;
        c.VLine(x, 0, 15, col);
    }
    c.HLine(0, 15, 0, RGBA(20, 22, 26));
    c.HLine(0, 15, 15, RGBA(18, 20, 24));
    for (int i = 0; i < 16; ++i) {
        int x = rng.Range(0, 15);
        int y = rng.Range(0, 15);
        if (rng.Range(0, 2) == 0) {
            c.Pixel(x, y, WithAlpha(rust, 160));
            if (rng.Range(0, 2) == 0) {
                c.Pixel(x + 1, y, WithAlpha(Shade(rust, 0.8f), 120));
            }
        }
    }
    if (variant == 1) {
        c.FillRect(0, 11, 16, 2, RGBA(100, 74, 40));
        c.HLine(0, 15, 12, RGBA(170, 130, 60));
    }
    return c;
}

static Canvas MakeHarborDoor(uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed);
    c.Clear(RGBA(24, 26, 30));
    c.FillRect(1, 0, 14, 16, RGBA(60, 64, 68));
    for (int y = 1; y < 15; y += 3) {
        c.HLine(1, 14, y, RGBA(38, 41, 45));
        c.HLine(1, 14, y + 1, RGBA(78, 82, 86));
    }
    c.FillRect(1, 11, 14, 2, RGBA(180, 140, 40));
    for (int x = 2; x < 14; x += 4) {
        c.VLine(x, 11, 12, RGBA(30, 26, 20));
    }
    for (int i = 0; i < 6; ++i) {
        c.Pixel(rng.Range(2, 13), rng.Range(0, 10), RGBA(120, 70, 46, 140));
    }
    c.VLine(15, 0, 15, RGBA(16, 18, 20));
    return c;
}

static Canvas MakeVoid(uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed);
    c.Clear(RGBA(8, 10, 14));
    Noise(c, rng, RGBA(16, 19, 24, 120), 16);
    return c;
}

// ===========================================================================
// 道具
// ===========================================================================

static Canvas MakeBarCounter(uint32_t seed)
{
    Canvas c(48, 16);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(0, 2, 48, 14, RGBA(92, 64, 44));
    c.FillRect(0, 2, 48, 4, RGBA(126, 92, 62));
    c.HLine(0, 47, 2, RGBA(160, 120, 82));
    c.HLine(0, 47, 5, RGBA(70, 48, 34));
    for (int x = 0; x < 48; x += 8) {
        c.VLine(x, 6, 15, RGBA(64, 44, 32));
        c.VLine(x + 1, 6, 15, RGBA(110, 78, 52));
    }
    c.HLine(0, 47, 9, RGBA(58, 40, 30));
    c.FillRect(0, 12, 48, 1, RGBA(150, 118, 60));
    for (int i = 0; i < 10; ++i) {
        c.Pixel(rng.Range(1, 46), rng.Range(6, 11),
                WithAlpha(RGBA(60, 42, 30), 120));
    }
    c.FillRect(3, 0, 6, 3, RGBA(120, 150, 160, 200));
    c.FillRect(3, 0, 6, 1, RGBA(210, 230, 230, 200));
    return c;
}

static Canvas MakeBarShelfProp(uint32_t seed)
{
    Canvas c(32, 16);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(0, 2, 32, 14, RGBA(52, 36, 28));
    c.HLine(0, 31, 2, RGBA(96, 68, 46));
    for (int shelf = 0; shelf < 2; ++shelf) {
        int y = 6 + shelf * 5;
        c.HLine(0, 31, y, RGBA(104, 74, 48));
        c.HLine(0, 31, y + 1, RGBA(40, 26, 20));
        for (int i = 0; i < 6; ++i) {
            int x = 1 + i * 5;
            int h = rng.Range(2, 3);
            Color bottle = (i % 3 == 0) ? RGBA(90, 150, 120)
                          : (i % 3 == 1) ? RGBA(160, 90, 50)
                                         : RGBA(70, 110, 160);
            c.FillRect(x, y - h, 2, h, bottle);
            c.Pixel(x, y - h, RGBA(220, 230, 210, 180));
        }
    }
    c.HLine(0, 31, 15, RGBA(24, 18, 16));
    return c;
}

static Canvas MakeBooth(uint32_t seed)
{
    Canvas c(48, 32);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 24, 30, 20, 3, 100);
    c.FillRect(2, 6, 44, 18, RGBA(58, 38, 34));
    c.FillRect(3, 7, 42, 16, RGBA(86, 40, 48));
    for (int x = 6; x < 44; x += 8) {
        c.VLine(x, 8, 21, RGBA(62, 28, 34));
        c.VLine(x + 1, 9, 20, RGBA(108, 50, 58));
    }
    c.HLine(3, 44, 7, RGBA(140, 60, 70));
    c.HLine(3, 44, 22, RGBA(48, 22, 28));
    c.FillRect(7, 20, 34, 6, RGBA(80, 52, 36));
    c.HLine(7, 40, 20, RGBA(126, 90, 58));
    c.HLine(7, 40, 25, RGBA(50, 32, 24));
    c.FillRect(12, 16, 24, 5, RGBA(64, 42, 32));
    c.FillRect(14, 15, 20, 2, RGBA(110, 82, 54));
    c.HLine(14, 33, 15, RGBA(160, 120, 74));
    c.FillRect(17, 12, 4, 4, RGBA(60, 90, 90, 180));
    c.FillRect(17, 12, 4, 1, RGBA(150, 210, 200));
    c.FillRect(26, 12, 5, 4, RGBA(120, 80, 50));
    c.FillRect(26, 12, 5, 1, RGBA(190, 150, 90));
    for (int i = 0; i < 6; ++i) {
        c.Pixel(rng.Range(6, 41), rng.Range(9, 21),
                WithAlpha(RGBA(50, 22, 28), 100));
    }
    c.VLine(0, 8, 24, RGBA(34, 24, 22));
    c.VLine(47, 8, 24, RGBA(34, 24, 22));
    return c;
}

static Canvas MakeBoothCurtain(uint32_t seed)
{
    Canvas c(16, 32);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(1, 0, 14, 28, RGBA(70, 30, 38));
    for (int x = 2; x < 15; x += 3) {
        c.VLine(x, 1, 27, RGBA(96, 42, 50));
        c.VLine(x + 1, 2, 26, RGBA(50, 22, 28));
    }
    c.HLine(1, 14, 0, RGBA(120, 70, 56));
    for (int i = 0; i < 6; ++i) {
        c.Pixel(rng.Range(2, 13), rng.Range(1, 27),
                WithAlpha(RGBA(30, 16, 20), 120));
    }
    c.FillRect(1, 28, 14, 3, RGBA(46, 22, 26));
    return c;
}

static Canvas MakeRoundTable(uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 8, 14, 6, 2, 90);
    c.EllipseFill(8, 8, 7, 5, RGBA(82, 56, 38));
    c.EllipseLine(8, 8, 7, 5, RGBA(46, 30, 22));
    c.EllipseFill(7, 7, 5, 3, RGBA(112, 80, 52));
    c.FillRect(11, 4, 3, 3, RGBA(70, 110, 120, 200));
    c.FillRect(11, 4, 3, 1, RGBA(170, 220, 220));
    c.Pixel(4, 8, RGBA(200, 180, 140, 150));
    c.Pixel(5, 9, RGBA(200, 180, 140, 100));
    return c;
}

static Canvas MakeChair(uint32_t seed)
{
    Canvas c(12, 16);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 6, 14, 4, 2, 80);
    c.FillRect(2, 2, 8, 10, RGBA(74, 50, 34));
    c.FillRect(3, 3, 6, 8, RGBA(104, 74, 48));
    c.HLine(3, 8, 3, RGBA(140, 104, 66));
    c.FillRect(1, 12, 10, 2, RGBA(60, 42, 30));
    c.VLine(2, 13, 15, RGBA(40, 28, 22));
    c.VLine(9, 13, 15, RGBA(40, 28, 22));
    return c;
}

static Canvas MakeJukebox(bool broken, uint32_t seed)
{
    Canvas c(16, 24);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 8, 22, 6, 2, 100);
    c.FillRect(2, 4, 12, 19, RGBA(46, 30, 26));
    c.EllipseFill(8, 5, 6, 4, RGBA(64, 40, 32));
    c.FillRect(3, 5, 10, 17, RGBA(82, 52, 38));
    c.FillRect(4, 7, 8, 13, RGBA(26, 22, 24));
    Color tube = broken ? RGBA(70, 72, 70) : RGBA(57, 224, 208);
    c.VLine(4, 8, 18, tube);
    c.VLine(11, 8, 18, broken ? RGBA(70, 72, 70) : RGBA(255, 61, 139));
    c.HLine(4, 11, 8, tube);
    for (int y = 10; y < 18; y += 2) {
        c.HLine(6, 9, y, broken ? RGBA(50, 50, 50) : RGBA(90, 140, 140));
    }
    c.FillRect(4, 19, 8, 4, RGBA(52, 36, 30));
    c.FillRect(5, 20, 6, 2, RGBA(20, 24, 26));
    if (!broken) {
        GlowCircle(c, 4, 13, 5, RGBA(57, 224, 208, 110));
        GlowCircle(c, 11, 13, 5, RGBA(255, 61, 139, 80));
        c.Pixel(4, 9, RGBA(220, 255, 250, 220));
        c.Pixel(11, 16, RGBA(255, 200, 220, 180));
    } else {
        c.Line(5, 11, 10, 16, RGBA(20, 18, 18));
        c.Pixel(6, 14, RGBA(90, 60, 40, 120));
    }
    c.HLine(2, 13, 22, RGBA(20, 16, 16));
    return c;
}

static Canvas MakeNeonSign(uint32_t seed)
{
    Canvas c(80, 16);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(0, 2, 80, 12, RGBA(18, 16, 22, 230));
    c.OutlineRect(0, 2, 80, 12, RGBA(60, 40, 56));
    int w = TextWidth("AFTERGLOW", 1, 1);
    int x = (80 - w) / 2;
    GlowCircle(c, 18, 8, 12, RGBA(255, 61, 139, 70));
    GlowCircle(c, 56, 8, 12, RGBA(57, 224, 208, 60));
    DrawTextGlow(c, "AFTERGLOW", x, 5, 1,
                 RGBA(255, 170, 210), RGBA(255, 61, 139, 110), 1);
    for (int i = 0; i < 8; ++i) {
        c.Pixel(rng.Range(1, 78), rng.Range(3, 12),
                WithAlpha(RGBA(255, 61, 139), 80));
    }
    return c;
}

static Canvas MakeDoor(uint32_t seed)
{
    Canvas c(16, 32);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(1, 2, 14, 29, RGBA(30, 24, 22));
    c.FillRect(2, 3, 12, 27, RGBA(70, 48, 34));
    c.FillRect(3, 4, 10, 10, RGBA(40, 48, 52));
    c.FillRect(4, 5, 8, 8, RGBA(255, 179, 71, 190));
    c.VLine(8, 5, 12, RGBA(60, 40, 30));
    c.HLine(4, 11, 9, RGBA(60, 40, 30));
    c.FillRect(3, 16, 10, 10, RGBA(88, 62, 42));
    c.HLine(4, 11, 18, RGBA(56, 38, 28));
    c.FillRect(10, 19, 2, 2, RGBA(190, 156, 90));
    c.HLine(1, 14, 31, RGBA(16, 12, 12));
    for (int i = 0; i < 5; ++i) {
        c.Pixel(rng.Range(3, 12), rng.Range(4, 28),
                WithAlpha(RGBA(40, 28, 22), 100));
    }
    return c;
}

static Canvas MakeWindowLit(uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed);
    c.Clear(RGBA(46, 34, 30));
    c.FillRect(1, 2, 14, 12, RGBA(24, 20, 20));
    c.FillRect(2, 3, 12, 10, RGBA(255, 179, 71, 235));
    c.FillRect(2, 3, 12, 3, RGBA(255, 220, 150, 240));
    c.VLine(8, 3, 12, RGBA(54, 38, 30));
    c.HLine(2, 13, 8, RGBA(54, 38, 30));
    for (int i = 0; i < 4; ++i) {
        int x = rng.Range(3, 12);
        c.VLine(x, rng.Range(4, 6), rng.Range(9, 12),
                WithAlpha(RGBA(120, 80, 50), 140));
    }
    return c;
}

static Canvas MakePendantLamp(uint32_t seed)
{
    Canvas c(16, 16);
    c.Clear(RGBA(0, 0, 0, 0));
    c.VLine(8, 0, 4, RGBA(34, 30, 28));
    c.FillRect(5, 4, 6, 3, RGBA(64, 56, 46));
    c.FillRect(6, 6, 4, 2, RGBA(230, 200, 140));
    c.FillRect(5, 7, 6, 1, RGBA(255, 220, 160));
    GlowCircle(c, 8, 9, 7, RGBA(255, 179, 71, 70));
    return c;
}

static Canvas MakeCrateSmall(uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 8, 14, 6, 2, 90);
    c.FillRect(2, 4, 12, 11, RGBA(92, 66, 42));
    c.FillRect(3, 5, 10, 9, RGBA(122, 88, 54));
    c.HLine(3, 12, 6, RGBA(80, 56, 38));
    c.HLine(3, 12, 10, RGBA(80, 56, 38));
    c.VLine(5, 5, 13, RGBA(70, 50, 34));
    c.VLine(10, 5, 13, RGBA(70, 50, 34));
    c.Line(3, 5, 12, 13, RGBA(60, 42, 30));
    c.Line(12, 5, 3, 13, RGBA(60, 42, 30));
    c.Pixel(6, 8, RGBA(180, 140, 70, 180));
    for (int i = 0; i < 4; ++i) {
        c.Pixel(rng.Range(4, 11), rng.Range(6, 12),
                WithAlpha(RGBA(60, 42, 30), 100));
    }
    return c;
}

static Canvas MakeCrateLarge(uint32_t seed)
{
    Canvas c(32, 32);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 16, 29, 13, 3, 110);
    c.FillRect(2, 4, 28, 26, RGBA(78, 56, 38));
    c.FillRect(3, 5, 26, 24, RGBA(110, 82, 52));
    for (int x = 3; x < 30; x += 6) {
        c.VLine(x, 5, 28, RGBA(82, 58, 40));
    }
    c.HLine(3, 29, 8, RGBA(56, 40, 30));
    c.HLine(3, 29, 20, RGBA(56, 40, 30));
    c.Line(4, 6, 28, 27, RGBA(60, 44, 32));
    c.Line(28, 6, 4, 27, RGBA(60, 44, 32));
    c.FillRect(12, 14, 8, 5, RGBA(200, 140, 50));
    c.FillRect(13, 15, 6, 3, RGBA(40, 34, 30));
    c.Pixel(15, 16, RGBA(240, 220, 180));
    for (int i = 0; i < 10; ++i) {
        c.Pixel(rng.Range(4, 27), rng.Range(6, 27),
                WithAlpha(RGBA(56, 40, 30), 110));
    }
    return c;
}

static Canvas MakeCargo(uint32_t seed)
{
    Canvas c(32, 24);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 16, 22, 13, 2, 110);
    c.FillRect(2, 4, 28, 18, RGBA(70, 54, 40));
    c.FillRect(3, 5, 26, 16, RGBA(104, 82, 56));
    c.HLine(3, 28, 7, RGBA(58, 44, 34));
    c.HLine(3, 28, 17, RGBA(58, 44, 34));
    c.VLine(9, 5, 20, RGBA(150, 120, 70));
    c.VLine(22, 5, 20, RGBA(150, 120, 70));
    c.FillRect(12, 9, 8, 6, RGBA(210, 130, 50));
    c.FillRect(13, 10, 6, 4, RGBA(40, 34, 30));
    c.Pixel(15, 11, RGBA(240, 220, 180));
    c.FillRect(13, 15, 6, 1, RGBA(240, 220, 180, 160));
    c.FillRect(26, 6, 2, 2, RGBA(57, 224, 208));
    GlowCircle(c, 27, 7, 4, RGBA(57, 224, 208, 70));
    for (int i = 0; i < 8; ++i) {
        c.Pixel(rng.Range(4, 27), rng.Range(6, 19),
                WithAlpha(RGBA(50, 38, 28), 110));
    }
    return c;
}

static Canvas MakeBarrel(uint32_t seed)
{
    Canvas c(16, 20);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 8, 18, 6, 2, 90);
    c.FillRect(4, 3, 8, 16, RGBA(96, 66, 40));
    c.FillRect(5, 3, 6, 16, RGBA(126, 88, 50));
    c.EllipseFill(8, 3, 4, 2, RGBA(150, 108, 62));
    c.EllipseLine(8, 3, 4, 2, RGBA(64, 44, 30));
    c.HLine(4, 11, 7, RGBA(60, 42, 30));
    c.HLine(4, 11, 14, RGBA(60, 42, 30));
    c.FillRect(5, 8, 1, 5, RGBA(57, 224, 208, 160));
    for (int i = 0; i < 3; ++i) {
        c.Pixel(rng.Range(5, 10), rng.Range(4, 17),
                WithAlpha(RGBA(140, 70, 40), 120));
    }
    return c;
}

static Canvas MakeCar(uint32_t seed)
{
    Canvas c(48, 24);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 24, 22, 20, 2, 110);
    c.FillRect(4, 10, 40, 8, RGBA(32, 40, 44));
    c.FillRect(8, 6, 26, 7, RGBA(28, 34, 40));
    c.PolyFill({{9,12},{13,7},{31,7},{35,12}}, RGBA(46, 60, 68));
    c.FillRect(13, 8, 8, 5, RGBA(90, 130, 140, 170));
    c.FillRect(23, 8, 8, 5, RGBA(90, 130, 140, 170));
    c.HLine(4, 43, 10, RGBA(60, 72, 78));
    c.HLine(4, 43, 16, RGBA(22, 28, 32));
    c.HLine(5, 42, 11, RGBA(80, 92, 96));
    c.FillRect(4, 12, 3, 3, RGBA(255, 70, 70, 220));
    c.FillRect(41, 12, 3, 3, RGBA(255, 179, 71, 230));
    c.EllipseFill(12, 18, 4, 4, RGBA(18, 20, 24));
    c.EllipseFill(12, 18, 2, 2, RGBA(90, 96, 100));
    c.EllipseFill(36, 18, 4, 4, RGBA(18, 20, 24));
    c.EllipseFill(36, 18, 2, 2, RGBA(90, 96, 100));
    c.HLine(14, 34, 13, RGBA(60, 120, 130, 80));
    for (int i = 0; i < 6; ++i) {
        c.Pixel(rng.Range(5, 42), rng.Range(11, 16),
                WithAlpha(RGBA(70, 82, 86), 120));
    }
    return c;
}

static Canvas MakeContainer(uint32_t seed)
{
    Canvas c(64, 32);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 32, 29, 27, 3, 110);
    c.FillRect(2, 5, 60, 24, RGBA(70, 42, 36));
    c.FillRect(3, 6, 58, 22, RGBA(96, 58, 46));
    for (int x = 4; x < 60; x += 4) {
        c.VLine(x, 6, 27, RGBA(78, 46, 38));
        c.VLine(x + 1, 7, 26, RGBA(110, 68, 54));
    }
    c.HLine(3, 60, 6, RGBA(130, 84, 62));
    c.HLine(3, 60, 27, RGBA(44, 28, 24));
    c.VLine(32, 6, 27, RGBA(40, 26, 22));
    c.FillRect(36, 10, 10, 6, RGBA(190, 130, 50));
    c.FillRect(37, 11, 8, 4, RGBA(36, 30, 26));
    for (int i = 0; i < 14; ++i) {
        c.Pixel(rng.Range(4, 59), rng.Range(7, 26),
                WithAlpha(RGBA(150, 74, 44), 100));
    }
    return c;
}

static Canvas MakeForklift(uint32_t seed)
{
    Canvas c(24, 20);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 12, 18, 9, 2, 100);
    c.FillRect(3, 8, 10, 7, RGBA(160, 120, 40));
    c.FillRect(4, 9, 8, 5, RGBA(190, 150, 56));
    c.FillRect(4, 4, 6, 5, RGBA(40, 44, 46));
    c.VLine(5, 8, 14, RGBA(30, 32, 34));
    c.VLine(13, 2, 15, RGBA(80, 84, 88));
    c.VLine(14, 8, 16, RGBA(80, 84, 88));
    c.FillRect(14, 2, 7, 1, RGBA(90, 94, 98));
    c.FillRect(14, 16, 7, 1, RGBA(90, 94, 98));
    c.EllipseFill(6, 16, 3, 3, RGBA(20, 22, 24));
    c.EllipseFill(14, 16, 3, 3, RGBA(20, 22, 24));
    c.Pixel(7, 10, RGBA(230, 200, 120));
    for (int i = 0; i < 4; ++i) {
        c.Pixel(rng.Range(4, 13), rng.Range(9, 14),
                WithAlpha(RGBA(120, 70, 40), 120));
    }
    return c;
}

static Canvas MakeAlarmLight(bool on, uint32_t seed)
{
    Canvas c(16, 16);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(5, 8, 6, 7, RGBA(52, 52, 56));
    c.EllipseFill(8, 7, 4, 3, on ? RGBA(255, 61, 90) : RGBA(90, 40, 50));
    c.EllipseLine(8, 7, 4, 3, RGBA(30, 30, 34));
    if (on) {
        GlowCircle(c, 8, 7, 8, RGBA(255, 61, 90, 90));
        c.Pixel(7, 6, RGBA(255, 200, 200));
    }
    return c;
}

static Canvas MakePart(uint32_t seed)
{
    Canvas c(12, 12);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    GlowCircle(c, 6, 6, 6, RGBA(57, 224, 208, 50));
    c.FillRect(2, 3, 8, 6, RGBA(90, 94, 98));
    c.FillRect(3, 4, 6, 4, RGBA(140, 146, 150));
    c.HLine(3, 8, 5, RGBA(60, 64, 68));
    c.VLine(4, 3, 8, RGBA(200, 180, 80));
    c.Pixel(8, 4, RGBA(57, 224, 208));
    c.Pixel(3, 8, RGBA(180, 70, 50));
    for (int i = 0; i < 3; ++i) {
        c.Pixel(rng.Range(3, 8), rng.Range(4, 7),
                WithAlpha(RGBA(40, 44, 48), 120));
    }
    return c;
}

static Canvas MakePuddle(uint32_t seed)
{
    Canvas c(32, 8);
    Rng rng(seed);
    c.Clear(RGBA(0, 0, 0, 0));
    c.EllipseFill(16, 4, 14, 3, RGBA(20, 40, 48, 170));
    c.EllipseFill(14, 4, 8, 2, RGBA(30, 64, 74, 150));
    c.HLine(8, 18, 4, RGBA(57, 224, 208, 70));
    c.HLine(12, 16, 3, RGBA(255, 61, 139, 50));
    c.Pixel(10, 5, RGBA(180, 230, 230, 100));
    for (int i = 0; i < 3; ++i) {
        c.Pixel(rng.Range(4, 27), rng.Range(3, 5),
                WithAlpha(RGBA(120, 180, 190), 60));
    }
    return c;
}

// ===========================================================================
// 角色
// ===========================================================================

enum class Facing { SOUTH = 0, NORTH = 1, EAST = 2 };

struct CharStyle {
    Color outline = RGBA(11, 14, 23);
    Color skin = RGBA(201, 142, 107);
    Color skinShade = RGBA(160, 104, 78);
    Color hair = RGBA(26, 26, 31);
    Color hairHi = RGBA(60, 58, 62);
    Color coat = RGBA(46, 59, 47);
    Color coatHi = RGBA(78, 94, 72);
    Color coatShade = RGBA(30, 38, 32);
    Color pants = RGBA(38, 44, 52);
    Color boots = RGBA(24, 26, 30);
    Color accent = RGBA(47, 168, 160);
    Color accentHi = RGBA(127, 216, 207);
    Color metal = RGBA(110, 120, 126);
    Color eye = RGBA(225, 220, 205);
    bool scarf = false;
    bool longCoat = false;
    bool apron = false;
    bool hood = false;
    bool visor = false;
    bool goggles = false;
    bool bulky = false;
    bool bun = false;
    bool vest = false;
    bool implant = false;
};

static void DrawCharacterDirect(Canvas& c, const CharStyle& s, Facing f, int frame)
{
    const int ox = 0;
    const int oy = 0;
    int swing = (frame == 0) ? 1 : (frame == 2) ? -1 : 0;
    int bob = (frame == 1 || frame == 3) ? 1 : 0;
    int bodyTop = 8 - bob;
    int headTop = 2 - bob;

    Shadow(c, 8, 22, 6, 2, 90);

    // 轮廓块（内部会被实际色块覆盖，留下 1px 描边）
    c.FillRect(ox + 4, oy + 16, 8, 7, s.outline);
    c.FillRect(ox + 3, oy + bodyTop - 1, 10, s.longCoat ? 14 : 11, s.outline);
    c.FillRect(ox + 4, oy + headTop - 1, 8, 9, s.outline);
    c.FillRect(ox + 2, oy + bodyTop, 12, 8, s.outline);

    // 腿与靴
    int legShift = (f == Facing::EAST) ? 1 : 0;
    c.FillRect(ox + 5 + legShift, oy + 17, 2, 5, s.pants);
    c.FillRect(ox + 9 - legShift, oy + 17, 2, 5, s.pants);
    c.FillRect(ox + 4 - (swing > 0 ? 0 : 1), oy + 21, 3, 2, s.boots);
    c.FillRect(ox + 9 + (swing > 0 ? 1 : 0), oy + 21, 3, 2, s.boots);
    if (f == Facing::EAST) {
        c.FillRect(ox + 4, oy + 21, 4, 2, s.boots);
        c.FillRect(ox + 8, oy + 21, 4, 2, s.boots);
    }

    // 躯干
    int torsoX = s.bulky ? 3 : 4;
    int torsoW = s.bulky ? 10 : 8;
    c.FillRect(ox + torsoX, oy + bodyTop, torsoW, 9, s.coat);
    c.FillRect(ox + torsoX, oy + bodyTop, torsoW, 2, s.coatHi);
    c.HLine(ox + torsoX, ox + torsoX + torsoW - 1, oy + bodyTop + 6,
            s.coatShade);

    if (s.longCoat) {
        c.FillRect(ox + 3, oy + bodyTop + 8, 10, 5, s.coat);
        c.FillRect(ox + 3, oy + bodyTop + 8, 1, 5, s.coatShade);
        c.FillRect(ox + 12, oy + bodyTop + 8, 1, 5, s.coatShade);
        c.VLine(ox + 8, oy + bodyTop + 11, oy + bodyTop + 13, s.outline);
    }

    if (s.apron) {
        c.FillRect(ox + 6, oy + bodyTop + 3, 5, 8, RGBA(74, 59, 46));
        c.FillRect(ox + 6, oy + bodyTop + 3, 5, 1, RGBA(120, 98, 72));
        c.VLine(ox + 6, oy + bodyTop + 3, oy + bodyTop + 4, RGBA(120, 98, 72));
        c.Pixel(ox + 9, oy + bodyTop + 8, s.metal);
    }

    if (s.vest) {
        c.FillRect(ox + 5, oy + bodyTop + 2, 6, 6, RGBA(43, 58, 63));
        c.VLine(ox + 5, oy + bodyTop + 2, oy + bodyTop + 7, s.outline);
        c.Pixel(ox + 7, oy + bodyTop + 3, RGBA(180, 160, 90));
        c.Pixel(ox + 7, oy + bodyTop + 5, RGBA(180, 160, 90));
    }

    // 手臂
    int armY = bodyTop + 1 - (swing > 0 ? 1 : 0);
    c.FillRect(ox + torsoX - 1, oy + armY, 2, 6, s.coatShade);
    c.FillRect(ox + torsoX + torsoW - 1, oy + armY, 2, 6, s.coat);
    c.Pixel(ox + torsoX - 1, oy + armY + 6, s.skin);
    c.Pixel(ox + torsoX + torsoW, oy + armY + 6, s.skin);

    // 头部
    int headX = (f == Facing::EAST) ? 6 : 5;
    c.FillRect(ox + headX, oy + headTop, 6, 7, s.skin);
    c.FillRect(ox + headX, oy + headTop + 4, 1, 3, s.skinShade);
    c.FillRect(ox + headX + 5, oy + headTop + 3, 1, 3, s.skinShade);
    c.FillRect(ox + headX + 2, oy + headTop + 6, 2, 1, s.skinShade);

    // 头发
    if (s.hood) {
        c.FillRect(ox + headX - 1, oy + headTop - 1, 8, 6, s.coatShade);
        c.FillRect(ox + headX, oy + headTop + 1, 6, 5, s.skin);
        c.FillRect(ox + headX + 1, oy + headTop + 4, 4, 2, s.skinShade);
        c.FillRect(ox + headX - 1, oy + headTop - 1, 8, 2, s.coat);
        c.FillRect(ox + headX - 1, oy + headTop + 2, 1, 4, s.coat);
        c.FillRect(ox + headX + 6, oy + headTop + 2, 1, 4, s.coat);
    } else {
        c.FillRect(ox + headX, oy + headTop, 6, 2, s.hair);
        c.FillRect(ox + headX - 1, oy + headTop + 1, 1, 4, s.hair);
        c.FillRect(ox + headX + 6, oy + headTop + 1, 1, 4, s.hair);
        c.Pixel(ox + headX + 1, oy + headTop, s.hairHi);
        if (f == Facing::NORTH) {
            c.FillRect(ox + headX, oy + headTop + 2, 6, 5, s.hair);
            c.FillRect(ox + headX + 1, oy + headTop + 3, 4, 3, s.hair);
        }
        if (s.bun) {
            c.EllipseFill(ox + headX + 7, oy + headTop + 1, 2, 2, s.hair);
            c.Pixel(ox + headX + 7, oy + headTop, s.hairHi);
            c.FillRect(ox + headX - 1, oy + headTop + 5, 1, 5, s.hair);
            c.FillRect(ox + headX + 6, oy + headTop + 5, 1, 5, s.hair);
        }
    }

    // 面部
    if (f == Facing::SOUTH) {
        c.Pixel(ox + headX + 1, oy + headTop + 4, s.outline);
        c.Pixel(ox + headX + 4, oy + headTop + 4, s.outline);
        c.Pixel(ox + headX + 2, oy + headTop + 6, s.skinShade);
    } else if (f == Facing::EAST) {
        c.Pixel(ox + headX + 4, oy + headTop + 4, s.outline);
        c.Pixel(ox + headX + 6, oy + headTop + 5, s.skin);
        c.Pixel(ox + headX + 5, oy + headTop + 6, s.skinShade);
        c.Pixel(ox + headX + 2, oy + headTop + 6, s.skinShade);
    }

    if (s.visor) {
        c.FillRect(ox + headX, oy + headTop + 3, 6, 1, s.accentHi);
        c.Add(ox + headX - 1, oy + headTop + 3, s.accent);
        c.Add(ox + headX + 6, oy + headTop + 3, s.accent);
        c.Pixel(ox + headX + 1, oy + headTop + 3, RGBA(255, 255, 255));
    }
    if (s.goggles) {
        c.FillRect(ox + headX, oy + headTop + 1, 6, 2, s.metal);
        c.FillRect(ox + headX + 1, oy + headTop + 1, 2, 1, s.accent);
        c.FillRect(ox + headX + 4, oy + headTop + 1, 1, 1, s.accent);
    }
    if (s.implant) {
        c.Pixel(ox + headX + 6, oy + headTop + 4, s.accentHi);
        c.Add(ox + headX + 6, oy + headTop + 4, s.accent);
    }

    // 围巾
    if (s.scarf) {
        c.FillRect(ox + torsoX, oy + bodyTop - 1, torsoW, 2, s.accent);
        c.FillRect(ox + torsoX, oy + bodyTop - 1, torsoW, 1, s.accentHi);
        if (f == Facing::EAST) {
            c.FillRect(ox + 3, oy + bodyTop + 1, 1, 4, s.accent);
            c.Pixel(ox + 2, oy + bodyTop + 4, s.accentHi);
        } else {
            c.FillRect(ox + 12, oy + bodyTop + 1, 1, 4, s.accent);
            c.Pixel(ox + 13, oy + bodyTop + 4, s.accentHi);
        }
    }

    // 边缘光
    c.VLine(ox + 12, oy + bodyTop, oy + bodyTop + 7, WithAlpha(s.coatHi, 160));
    c.VLine(ox + headX + 5, oy + headTop + 1, oy + headTop + 5,
            WithAlpha(s.coatHi, 120));
}

static void DrawCharacter(Canvas& dst, const CharStyle& s, Facing f, int frame,
                          bool mirror)
{
    Canvas temp(16, 24);
    DrawCharacterDirect(temp, s, f, frame);
    if (mirror) {
        dst.BlitFlipX(temp, 0, 0);
    } else {
        dst.Blit(temp, 0, 0, 1);
    }
}

static void DrawSit(Canvas& c, const CharStyle& s, bool merchant)
{
    c.Clear(RGBA(0, 0, 0, 0));
    Shadow(c, 12, 22, 8, 2, 100);
    // 轮廓
    c.FillRect(4, 12, 16, 11, s.outline);
    c.FillRect(7, 3, 10, 8, s.outline);
    // 腿
    c.FillRect(6, 20, 6, 3, s.pants);
    c.FillRect(12, 20, 6, 3, s.pants);
    c.FillRect(5, 22, 7, 2, s.boots);
    c.FillRect(12, 22, 7, 2, s.boots);
    // 身体
    c.FillRect(5, 13, 14, 8, s.coat);
    c.FillRect(5, 13, 14, 2, s.coatHi);
    c.FillRect(7, 15, 10, 6, s.coatShade);
    if (s.longCoat) {
        c.FillRect(4, 18, 5, 5, s.coat);
        c.FillRect(15, 18, 5, 5, s.coat);
    }
    // 手臂
    c.FillRect(4, 15, 2, 5, s.coatShade);
    c.FillRect(18, 15, 2, 5, s.coat);
    // 头
    c.FillRect(8, 4, 6, 7, s.skin);
    c.FillRect(8, 8, 1, 3, s.skinShade);
    c.FillRect(13, 8, 1, 3, s.skinShade);
    c.FillRect(8, 2, 6, 2, s.hair);
    c.FillRect(7, 3, 1, 4, s.hair);
    c.FillRect(14, 3, 1, 4, s.hair);
    if (s.bun) {
        c.EllipseFill(15, 3, 2, 2, s.hair);
    }
    if (s.longCoat) {
        c.FillRect(6, 9, 1, 6, s.hair);
        c.FillRect(16, 9, 1, 6, s.hair);
    }
    // 面部
    c.Pixel(10, 7, s.outline);
    c.Pixel(13, 7, s.outline);
    c.Pixel(11, 9, s.skinShade);
    if (s.implant) {
        c.Pixel(14, 7, s.accentHi);
        c.Add(14, 7, s.accent);
    }
    // 围巾/领口
    if (s.scarf) {
        c.FillRect(8, 10, 6, 2, s.accent);
        c.FillRect(8, 10, 6, 1, s.accentHi);
    }
    // 手中的物品
    if (merchant) {
        c.FillRect(7, 17, 10, 4, RGBA(30, 38, 42));
        c.FillRect(8, 18, 8, 2, RGBA(57, 224, 208, 200));
        GlowCircle(c, 12, 18, 5, RGBA(57, 224, 208, 70));
    } else {
        c.FillRect(9, 17, 6, 3, RGBA(120, 80, 44));
        c.FillRect(10, 16, 4, 1, RGBA(190, 150, 90));
    }
    // 边缘光
    c.VLine(18, 14, 19, WithAlpha(s.coatHi, 140));
}

static CharStyle StylePlayer()
{
    CharStyle s;
    s.coat = RGBA(46, 59, 47);
    s.coatHi = RGBA(78, 94, 72);
    s.coatShade = RGBA(30, 38, 32);
    s.pants = RGBA(38, 44, 52);
    s.accent = RGBA(47, 168, 160);
    s.accentHi = RGBA(127, 216, 207);
    s.scarf = true;
    s.implant = true;
    return s;
}

static CharStyle StyleBigSister()
{
    CharStyle s;
    s.coat = RGBA(140, 47, 63);
    s.coatHi = RGBA(180, 74, 84);
    s.coatShade = RGBA(92, 30, 42);
    s.pants = RGBA(24, 23, 28);
    s.hair = RGBA(59, 42, 40);
    s.hairHi = RGBA(100, 76, 66);
    s.accent = RGBA(255, 179, 71);
    s.accentHi = RGBA(255, 220, 150);
    s.longCoat = true;
    s.bun = true;
    s.implant = true;
    return s;
}

static CharStyle StyleMerchant()
{
    CharStyle s;
    s.coat = RGBA(90, 74, 50);
    s.coatHi = RGBA(126, 104, 68);
    s.coatShade = RGBA(62, 50, 36);
    s.pants = RGBA(48, 44, 38);
    s.hair = RGBA(46, 36, 30);
    s.hairHi = RGBA(80, 62, 46);
    s.accent = RGBA(201, 162, 39);
    s.accentHi = RGBA(255, 220, 120);
    s.bulky = true;
    s.goggles = true;
    s.implant = true;
    return s;
}

static CharStyle StyleBartender()
{
    CharStyle s;
    s.coat = RGBA(216, 210, 196);
    s.coatHi = RGBA(245, 240, 225);
    s.coatShade = RGBA(170, 164, 150);
    s.pants = RGBA(46, 52, 56);
    s.hair = RGBA(80, 52, 38);
    s.hairHi = RGBA(120, 86, 58);
    s.accent = RGBA(74, 59, 46);
    s.accentHi = RGBA(150, 120, 80);
    s.apron = true;
    s.vest = true;
    return s;
}

static CharStyle StyleScavenger()
{
    CharStyle s;
    s.coat = RGBA(70, 68, 56);
    s.coatHi = RGBA(104, 100, 82);
    s.coatShade = RGBA(46, 44, 38);
    s.pants = RGBA(52, 50, 44);
    s.hair = RGBA(40, 38, 34);
    s.accent = RGBA(255, 138, 61);
    s.accentHi = RGBA(255, 190, 120);
    s.hood = true;
    s.bulky = true;
    s.goggles = true;
    return s;
}

static CharStyle StyleAgent()
{
    CharStyle s;
    s.coat = RGBA(20, 22, 28);
    s.coatHi = RGBA(52, 60, 72);
    s.coatShade = RGBA(14, 16, 20);
    s.pants = RGBA(18, 20, 26);
    s.hair = RGBA(14, 16, 20);
    s.skin = RGBA(60, 66, 74);
    s.skinShade = RGBA(36, 40, 46);
    s.accent = RGBA(57, 224, 208);
    s.accentHi = RGBA(150, 255, 245);
    s.visor = true;
    s.bulky = true;
    return s;
}

// ===========================================================================
// 头像
// ===========================================================================

struct PortraitSpec {
    Color bg1;
    Color bg2;
    Color glow;
    Color skin;
    Color skinShade;
    Color skinHi;
    Color hair;
    Color hairShade;
    Color hairHi;
    Color coat;
    Color coatHi;
    Color coatShade;
    Color accent;
    bool tired = false;
    bool smile = false;
    bool smirk = false;
    bool goggles = false;
    bool apron = false;
    bool scarf = false;
    bool implant = false;
    bool bun = false;
    bool silverStreak = false;
    bool stripes = false;
};

static void DrawPortrait(Canvas& c, const PortraitSpec& s)
{
    c.Clear(s.bg1);
    for (int y = 0; y < 48; ++y) {
        float t = y / 47.0f;
        Color row = LerpColor(s.bg1, s.bg2, t);
        c.HLine(0, 47, y, row);
    }
    GlowCircle(c, 24, 22, 28, s.glow);

    // 背景光斑/扫描线
    Rng rng(0x9E3779B9u + static_cast<uint32_t>(s.bg1.r) * 131u +
            static_cast<uint32_t>(s.coat.g) * 977u);
    for (int i = 0; i < 18; ++i) {
        int x = rng.Range(0, 47);
        int y = rng.Range(0, 47);
        c.Pixel(x, y, WithAlpha(s.glow, rng.Range(10, 40)));
    }
    if (s.stripes) {
        for (int y = 2; y < 46; y += 6) {
            c.HLine(0, 47, y, WithAlpha(RGBA(0, 0, 0), 40));
        }
    }

    // 肩膀/外套
    c.FillRect(3, 37, 42, 11, s.coat);
    c.EllipseFill(24, 43, 21, 10, s.coat);
    c.HLine(4, 43, 37, s.coatHi);
    c.FillRect(4, 38, 2, 10, s.coatShade);
    c.FillRect(42, 38, 2, 10, s.coatShade);

    // 脖子
    c.FillRect(20, 30, 8, 8, s.skinShade);
    c.FillRect(21, 31, 6, 6, s.skin);

    // 头部
    c.FillRect(15, 9, 18, 21, s.skin);
    c.FillRect(16, 7, 16, 2, s.skin);
    c.FillRect(14, 12, 1, 10, s.skinShade);
    c.FillRect(33, 12, 1, 11, s.skinShade);
    c.FillRect(16, 28, 16, 3, s.skinShade);
    c.FillRect(17, 30, 14, 1, s.skinShade);
    c.FillRect(17, 12, 2, 14, s.skinHi);
    c.FillRect(18, 25, 3, 2, s.skinHi);

    // 耳朵
    c.FillRect(13, 20, 2, 5, s.skin);
    c.FillRect(33, 20, 2, 5, s.skin);
    c.Pixel(13, 22, s.skinShade);
    c.Pixel(34, 22, s.skinShade);

    // 头发
    c.FillRect(13, 6, 22, 5, s.hair);
    c.FillRect(12, 10, 3, 12, s.hair);
    c.FillRect(33, 10, 3, 12, s.hair);
    c.FillRect(15, 5, 18, 2, s.hairHi);
    c.Pixel(14, 8, s.hairHi);
    c.Pixel(32, 7, s.hairShade);
    if (s.bun) {
        c.EllipseFill(36, 6, 4, 4, s.hair);
        c.EllipseFill(36, 5, 2, 2, s.hairHi);
        c.FillRect(33, 13, 3, 12, s.hair);
    } else {
        c.FillRect(34, 13, 2, 12, s.hair);
        c.FillRect(12, 13, 2, 8, s.hair);
    }
    if (s.silverStreak) {
        c.VLine(15, 7, 15, RGBA(211, 206, 196));
        c.VLine(16, 7, 14, RGBA(180, 174, 164));
    }
    if (s.tired) {
        c.FillRect(16, 15, 6, 2, s.hair);
        c.FillRect(26, 15, 6, 2, s.hair);
    } else if (s.smirk) {
        c.HLine(17, 21, 15, s.hair);
        c.HLine(26, 30, 15, s.hair);
    } else {
        c.HLine(17, 21, 16, s.hair);
        c.HLine(26, 30, 16, s.hair);
    }

    // 眼睛
    int eyeY = s.tired ? 21 : 20;
    c.FillRect(18, eyeY, 5, 3, RGBA(232, 227, 214));
    c.FillRect(26, eyeY, 5, 3, RGBA(232, 227, 214));
    c.FillRect(19, eyeY, 2, 2, s.hairShade);
    c.FillRect(27, eyeY, 2, 2, s.hairShade);
    c.Pixel(19, eyeY, s.hair);
    c.Pixel(27, eyeY, s.hair);
    c.Pixel(20, eyeY + 1, s.accent);
    c.Pixel(28, eyeY + 1, s.accent);
    if (s.tired) {
        c.FillRect(18, eyeY + 3, 5, 1, WithAlpha(s.skinShade, 180));
        c.FillRect(26, eyeY + 3, 5, 1, WithAlpha(s.skinShade, 180));
    }

    // 鼻子与嘴
    c.FillRect(23, 22, 2, 5, s.skinShade);
    c.Pixel(24, 26, Shade(s.skinShade, 0.75f));
    c.Pixel(22, 25, s.skinHi);
    if (s.smile) {
        c.HLine(21, 27, 29, s.skinShade);
        c.Pixel(20, 28, s.skinShade);
        c.Pixel(28, 28, s.skinShade);
    } else if (s.smirk) {
        c.HLine(22, 27, 29, s.skinShade);
        c.Pixel(28, 28, s.skinShade);
    } else {
        c.HLine(22, 27, 29, s.skinShade);
        c.Pixel(24, 29, Shade(s.skinShade, 0.7f));
    }

    // 服装细节
    c.FillRect(18, 36, 12, 4, s.coatShade);
    c.HLine(19, 28, 36, s.coatHi);
    if (s.scarf) {
        c.FillRect(17, 34, 14, 4, s.accent);
        c.FillRect(17, 34, 14, 1, RGBA(140, 235, 225));
        c.FillRect(29, 36, 3, 8, s.accent);
        c.FillRect(30, 40, 2, 5, Shade(s.accent, 0.85f));
    }
    if (s.apron) {
        c.FillRect(17, 38, 14, 10, RGBA(74, 59, 46));
        c.FillRect(20, 36, 1, 12, RGBA(120, 98, 72));
        c.FillRect(27, 36, 1, 12, RGBA(120, 98, 72));
    }
    if (s.goggles) {
        c.FillRect(14, 11, 20, 4, RGBA(40, 36, 30));
        c.FillRect(16, 12, 6, 3, RGBA(201, 162, 39));
        c.FillRect(26, 12, 6, 3, RGBA(201, 162, 39));
        c.FillRect(16, 12, 6, 1, RGBA(255, 230, 150));
        c.FillRect(26, 12, 6, 1, RGBA(255, 230, 150));
        c.FillRect(22, 12, 4, 2, RGBA(70, 60, 40));
    }
    if (s.implant) {
        c.FillRect(35, 21, 2, 2, s.accent);
        c.Add(35, 21, RGBA(120, 255, 245, 160));
        c.Add(36, 22, RGBA(120, 255, 245, 120));
    }

    // 边缘光与暗角
    c.VLine(45, 30, 47, WithAlpha(s.glow, 90));
    c.FillRect(0, 0, 48, 1, WithAlpha(RGBA(0, 0, 0), 120));
    c.FillRect(0, 47, 48, 1, WithAlpha(RGBA(0, 0, 0), 160));
    c.FillRect(0, 0, 1, 48, WithAlpha(RGBA(0, 0, 0), 120));
    c.FillRect(47, 0, 1, 48, WithAlpha(RGBA(0, 0, 0), 150));
}

// ===========================================================================
// 图标与特效
// ===========================================================================

static Canvas MakeIconHealth()
{
    Canvas c(12, 12);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(2, 3, 2, 2, RGBA(255, 61, 90));
    c.FillRect(4, 2, 4, 2, RGBA(255, 61, 90));
    c.FillRect(8, 3, 2, 2, RGBA(255, 61, 90));
    c.FillRect(2, 5, 8, 2, RGBA(220, 50, 80));
    c.FillRect(3, 7, 6, 2, RGBA(200, 44, 72));
    c.FillRect(5, 9, 2, 1, RGBA(180, 40, 66));
    c.Pixel(4, 4, RGBA(255, 190, 200));
    return c;
}

static Canvas MakeIconAmmo()
{
    Canvas c(12, 12);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(3, 2, 6, 5, RGBA(190, 150, 72));
    c.FillRect(3, 7, 6, 3, RGBA(120, 90, 50));
    c.FillRect(4, 2, 4, 2, RGBA(230, 200, 120));
    c.Pixel(5, 3, RGBA(255, 240, 200));
    c.FillRect(4, 8, 4, 1, RGBA(160, 120, 70));
    c.Pixel(3, 9, RGBA(90, 70, 40));
    c.Pixel(8, 9, RGBA(90, 70, 40));
    return c;
}

static Canvas MakeIconCredit()
{
    Canvas c(12, 12);
    c.Clear(RGBA(0, 0, 0, 0));
    c.EllipseFill(6, 6, 4, 4, RGBA(190, 150, 54));
    c.EllipseFill(6, 6, 3, 3, RGBA(230, 190, 80));
    c.EllipseFill(6, 6, 2, 2, RGBA(190, 150, 54));
    c.Pixel(5, 4, RGBA(255, 240, 180));
    c.Pixel(7, 8, RGBA(120, 90, 30));
    return c;
}

static Canvas MakeIconMedkit()
{
    Canvas c(12, 12);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(2, 3, 8, 8, RGBA(210, 214, 200));
    c.FillRect(3, 4, 6, 6, RGBA(238, 240, 228));
    c.FillRect(5, 5, 2, 4, RGBA(200, 50, 60));
    c.FillRect(4, 6, 4, 2, RGBA(200, 50, 60));
    c.FillRect(4, 2, 4, 1, RGBA(140, 146, 136));
    return c;
}

static Canvas MakeIconJack()
{
    Canvas c(12, 12);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(2, 4, 8, 5, RGBA(40, 54, 60));
    c.FillRect(3, 5, 6, 3, RGBA(57, 224, 208));
    c.FillRect(5, 2, 2, 2, RGBA(120, 130, 136));
    c.FillRect(5, 9, 2, 2, RGBA(120, 130, 136));
    c.Pixel(4, 6, RGBA(190, 255, 250));
    c.Pixel(7, 7, RGBA(20, 100, 100));
    return c;
}

static Canvas MakeIconObjective()
{
    Canvas c(12, 12);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(3, 1, 6, 2, RGBA(255, 179, 71));
    c.FillRect(2, 3, 8, 2, RGBA(230, 150, 50));
    c.FillRect(3, 5, 6, 2, RGBA(200, 120, 40));
    c.FillRect(5, 7, 2, 4, RGBA(180, 100, 30));
    c.Pixel(5, 2, RGBA(255, 240, 200));
    return c;
}

static Canvas MakeIconPart()
{
    Canvas c(12, 12);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(3, 3, 6, 6, RGBA(120, 126, 130));
    c.FillRect(4, 4, 4, 4, RGBA(180, 186, 190));
    c.FillRect(5, 2, 2, 2, RGBA(190, 150, 60));
    c.FillRect(5, 9, 2, 2, RGBA(190, 150, 60));
    c.Pixel(4, 5, RGBA(57, 224, 208));
    c.Pixel(7, 7, RGBA(40, 44, 48));
    return c;
}

static Canvas MakeGlow()
{
    Canvas c(64, 64);
    c.Clear(RGBA(0, 0, 0, 0));
    for (int y = 0; y < 64; ++y) {
        for (int x = 0; x < 64; ++x) {
            float dx = (x - 31.5f) / 31.5f;
            float dy = (y - 31.5f) / 31.5f;
            float d = std::sqrt(dx * dx + dy * dy);
            if (d >= 1.0f) {
                continue;
            }
            float t = 1.0f - d;
            int a = static_cast<int>(255.0f * t * t * t);
            if (a > 0) {
                c.Pixel(x, y, RGBA(255, 255, 255, a));
            }
        }
    }
    return c;
}

static Canvas MakeMuzzle(int frame)
{
    Canvas c(16, 16);
    c.Clear(RGBA(0, 0, 0, 0));
    Color core = RGBA(255, 250, 220);
    Color mid = RGBA(255, 190, 80);
    Color edge = RGBA(255, 120, 40, 180);
    if (frame == 0) {
        c.FillRect(3, 8, 10, 1, edge);
        c.FillRect(5, 7, 6, 3, mid);
        c.FillRect(6, 8, 4, 1, core);
        c.Pixel(8, 7, core);
        c.Pixel(8, 9, core);
        c.Pixel(7, 6, mid);
        c.Pixel(9, 10, mid);
    } else {
        c.FillRect(1, 8, 14, 1, WithAlpha(mid, 160));
        c.FillRect(4, 7, 8, 3, mid);
        c.FillRect(5, 8, 6, 1, core);
        c.Pixel(12, 8, core);
        c.Pixel(3, 8, mid);
        c.Pixel(8, 4, WithAlpha(mid, 120));
        c.Pixel(8, 12, WithAlpha(mid, 120));
    }
    return c;
}

static Canvas MakeBullet()
{
    Canvas c(6, 2);
    c.Clear(RGBA(0, 0, 0, 0));
    c.FillRect(0, 0, 6, 2, RGBA(255, 210, 120, 190));
    c.FillRect(2, 0, 4, 1, RGBA(255, 252, 230));
    c.Pixel(5, 0, RGBA(255, 255, 255));
    return c;
}

static Canvas MakeSpark()
{
    Canvas c(4, 4);
    c.Clear(RGBA(0, 0, 0, 0));
    c.Pixel(1, 0, RGBA(255, 220, 120));
    c.Pixel(0, 1, RGBA(255, 180, 60));
    c.Pixel(1, 1, RGBA(255, 240, 200));
    c.Pixel(2, 1, RGBA(255, 180, 60));
    c.Pixel(1, 2, RGBA(255, 220, 120));
    c.Pixel(3, 3, RGBA(255, 120, 40, 120));
    return c;
}

static Canvas MakeBlood()
{
    Canvas c(4, 4);
    c.Clear(RGBA(0, 0, 0, 0));
    c.Pixel(1, 1, RGBA(190, 40, 54));
    c.Pixel(2, 1, RGBA(140, 26, 40));
    c.Pixel(1, 2, RGBA(140, 26, 40));
    c.Pixel(2, 2, RGBA(190, 40, 54));
    c.Pixel(0, 2, RGBA(120, 20, 32));
    c.Pixel(3, 0, RGBA(120, 20, 32));
    return c;
}

static Canvas MakeShell()
{
    Canvas c(2, 2);
    c.Clear(RGBA(0, 0, 0, 0));
    c.Pixel(0, 0, RGBA(200, 160, 80));
    c.Pixel(1, 1, RGBA(130, 100, 50));
    return c;
}

static Canvas MakeRain()
{
    Canvas c(2, 8);
    c.Clear(RGBA(0, 0, 0, 0));
    for (int y = 0; y < 8; ++y) {
        int a = 30 + y * 18;
        c.Pixel(0, y, RGBA(160, 200, 210, a));
        if (y > 2) {
            c.Pixel(1, y, RGBA(120, 170, 180, a / 2));
        }
    }
    return c;
}

static Canvas MakeSmoke()
{
    Canvas c(8, 8);
    c.Clear(RGBA(0, 0, 0, 0));
    c.EllipseFill(4, 4, 3, 3, RGBA(120, 120, 120, 90));
    c.EllipseFill(3, 3, 2, 2, RGBA(160, 160, 160, 70));
    c.Pixel(4, 2, RGBA(190, 190, 190, 50));
    return c;
}

static Canvas MakeAlarmFx()
{
    Canvas c(32, 32);
    c.Clear(RGBA(0, 0, 0, 0));
    for (int y = 0; y < 32; ++y) {
        for (int x = 0; x < 32; ++x) {
            float dx = (x - 15.5f) / 15.5f;
            float dy = (y - 15.5f) / 15.5f;
            float d = std::sqrt(dx * dx + dy * dy);
            if (d < 1.0f) {
                int a = static_cast<int>((1.0f - d) * 140);
                c.Pixel(x, y, RGBA(255, 40, 60, a));
            }
        }
    }
    return c;
}

static Canvas MakePickup()
{
    Canvas c(16, 16);
    c.Clear(RGBA(0, 0, 0, 0));
    c.EllipseLine(8, 8, 6, 6, RGBA(57, 224, 208, 180));
    c.EllipseLine(8, 8, 4, 4, RGBA(150, 255, 245, 120));
    c.Pixel(8, 1, RGBA(255, 255, 255, 220));
    c.Pixel(8, 14, RGBA(255, 255, 255, 160));
    c.Pixel(1, 8, RGBA(255, 255, 255, 160));
    c.Pixel(14, 8, RGBA(255, 255, 255, 160));
    return c;
}

// ===========================================================================
// UI 与背景
// ===========================================================================

static Canvas MakePanelCorner()
{
    Canvas c(8, 8);
    c.Clear(RGBA(0, 0, 0, 0));
    c.HLine(0, 7, 0, RGBA(57, 224, 208, 200));
    c.VLine(0, 0, 7, RGBA(57, 224, 208, 200));
    c.Pixel(0, 0, RGBA(200, 255, 250));
    c.HLine(4, 7, 7, RGBA(57, 224, 208, 80));
    c.VLine(7, 4, 7, RGBA(57, 224, 208, 80));
    return c;
}

static Canvas MakeScanline()
{
    Canvas c(4, 4);
    c.Clear(RGBA(0, 0, 0, 0));
    c.HLine(0, 3, 0, RGBA(0, 0, 0, 28));
    c.HLine(0, 3, 2, RGBA(0, 0, 0, 14));
    return c;
}

static Canvas MakeNoise()
{
    Canvas c(64, 64);
    c.Clear(RGBA(0, 0, 0, 0));
    Rng rng(0xC0FFEEu);
    for (int i = 0; i < 400; ++i) {
        int x = rng.Range(0, 63);
        int y = rng.Range(0, 63);
        if (rng.Range(0, 1)) {
            c.Pixel(x, y, RGBA(255, 255, 255, rng.Range(6, 18)));
        } else {
            c.Pixel(x, y, RGBA(0, 0, 0, rng.Range(10, 26)));
        }
    }
    return c;
}

static Canvas MakeVignette()
{
    Canvas c(480, 270);
    c.Clear(RGBA(0, 0, 0, 0));
    for (int y = 0; y < 270; ++y) {
        for (int x = 0; x < 480; ++x) {
            float dx = (x - 239.5f) / 239.5f;
            float dy = (y - 134.5f) / 134.5f;
            float d = std::sqrt(dx * dx * 0.85f + dy * dy);
            float t = (d - 0.55f) / 0.45f;
            if (t <= 0) {
                continue;
            }
            int a = static_cast<int>(std::min(1.0f, t) * 150);
            c.Pixel(x, y, RGBA(4, 6, 10, a));
        }
    }
    return c;
}

static Canvas MakeTitleLogo()
{
    Canvas c(240, 64);
    c.Clear(RGBA(0, 0, 0, 0));
    GlowCircle(c, 120, 22, 55, RGBA(255, 61, 139, 34));
    GlowCircle(c, 120, 44, 55, RGBA(57, 224, 208, 26));
    int w1 = TextWidth("EMBER", 4, 2);
    DrawTextGlow(c, "EMBER", (240 - w1) / 2, 5, 4,
                 RGBA(255, 235, 225), RGBA(255, 61, 139, 100), 2);
    c.HLine(28, 96, 36, RGBA(255, 61, 139, 120));
    c.HLine(144, 212, 36, RGBA(57, 224, 208, 100));
    c.Pixel(120, 36, RGBA(255, 255, 255, 180));
    int w2 = TextWidth("OF FREE CITY", 2, 1);
    DrawTextGlow(c, "OF FREE CITY", (240 - w2) / 2, 42, 2,
                 RGBA(220, 235, 230), RGBA(57, 224, 208, 90), 1);
    for (int i = 0; i < 3; ++i) {
        c.HLine(40 + i * 4, 60 + i * 4, 60 + i, WithAlpha(RGBA(57, 224, 208), 90 - i * 20));
        c.HLine(180 - i * 4, 200 - i * 4, 60 + i, WithAlpha(RGBA(255, 61, 139), 90 - i * 20));
    }
    return c;
}

static Canvas MakeTitleBackground()
{
    Canvas c(480, 270);
    Rng rng(0xBADC0DEu);
    for (int y = 0; y < 270; ++y) {
        float t = y / 269.0f;
        Color col = LerpColor(RGBA(8, 10, 18), RGBA(24, 42, 52), t * t);
        c.HLine(0, 479, y, col);
    }
    // 远景雾
    for (int y = 120; y < 210; ++y) {
        float t = (y - 120) / 90.0f;
        c.HLine(0, 479, y, WithAlpha(RGBA(48, 90, 100), static_cast<int>(t * 34)));
    }
    // 天际线
    int x = 0;
    while (x < 480) {
        int w = rng.Range(14, 38);
        int h = rng.Range(30, 100);
        int top = 178 - h;
        Color body = RGBA(14 + rng.Range(0, 8), 20 + rng.Range(0, 8),
                          28 + rng.Range(0, 10));
        c.FillRect(x, top, w, h + 40, body);
        for (int wy = top + 4; wy < top + h - 4; wy += 5) {
            for (int wx = x + 3; wx < x + w - 3; wx += 4) {
                if (rng.Range(0, 100) < 26) {
                    Color win = (rng.Range(0, 5) == 0)
                                    ? RGBA(255, 61, 139, 140)
                                    : RGBA(255, 179, 71, 130);
                    c.Pixel(wx, wy, win);
                }
            }
        }
        if (rng.Range(0, 3) == 0) {
            c.VLine(x + w / 2, top - rng.Range(4, 16), top, RGBA(30, 40, 48));
            c.Pixel(x + w / 2, top - 4, RGBA(255, 61, 90, 180));
        }
        x += w + rng.Range(2, 10);
    }
    // 近景酒吧轮廓
    c.FillRect(0, 214, 480, 56, RGBA(10, 12, 18));
    c.FillRect(30, 150, 190, 64, RGBA(16, 20, 26));
    c.HLine(30, 219, 150, RGBA(40, 48, 54));
    c.FillRect(52, 170, 30, 22, RGBA(255, 179, 71, 180));
    c.FillRect(52, 170, 30, 4, RGBA(255, 210, 140, 200));
    c.FillRect(96, 168, 92, 12, RGBA(18, 16, 22));
    DrawTextGlow(c, "AFTERGLOW", 100, 171, 1, RGBA(255, 170, 210),
                 RGBA(255, 61, 139, 110));
    c.FillRect(206, 174, 20, 46, RGBA(26, 20, 20));
    c.FillRect(210, 180, 12, 30, RGBA(255, 179, 71, 160));
    // 霓虹光
    GlowCircle(c, 120, 180, 50, RGBA(255, 61, 139, 44));
    GlowCircle(c, 300, 200, 60, RGBA(57, 224, 208, 28));
    // 雨
    for (int i = 0; i < 170; ++i) {
        int rx = rng.Range(0, 479);
        int ry = rng.Range(0, 269);
        int len = rng.Range(4, 12);
        int a = rng.Range(20, 70);
        c.VLine(rx, ry, std::min(269, ry + len), RGBA(150, 200, 210, a));
    }
    // 水面反光
    for (int i = 0; i < 60; ++i) {
        int rx = rng.Range(0, 479);
        int ry = rng.Range(230, 269);
        c.HLine(rx, rx + rng.Range(1, 6), ry,
                WithAlpha(rng.Range(0, 1) ? RGBA(57, 224, 208)
                                          : RGBA(255, 179, 71), 40));
    }
    return c;
}

static Canvas MakeEndingBackground()
{
    Canvas c(480, 270);
    Rng rng(0x51EADu);
    for (int y = 0; y < 270; ++y) {
        float t = y / 269.0f;
        c.HLine(0, 479, y, LerpColor(RGBA(14, 9, 9), RGBA(42, 22, 18), t));
    }
    GlowCircle(c, 120, 80, 110, RGBA(255, 149, 71, 40));
    GlowCircle(c, 360, 200, 130, RGBA(255, 61, 90, 30));
    for (int i = 0; i < 26; ++i) {
        int bx = rng.Range(20, 460);
        int by = rng.Range(30, 230);
        int r = rng.Range(2, 8);
        c.EllipseFill(bx, by, r, r, WithAlpha(RGBA(255, 179, 71),
                                             rng.Range(12, 40)));
    }
    // 吧台剪影
    c.FillRect(0, 206, 480, 64, RGBA(10, 7, 7, 220));
    c.FillRect(50, 196, 380, 10, RGBA(48, 28, 22));
    c.HLine(50, 429, 196, RGBA(90, 52, 36));
    // 酒杯
    c.FillRect(200, 176, 8, 16, RGBA(160, 120, 60, 150));
    c.FillRect(202, 178, 4, 10, RGBA(255, 179, 71, 120));
    c.FillRect(300, 182, 6, 10, RGBA(100, 80, 50, 120));
    // 窗上雨痕
    for (int i = 0; i < 70; ++i) {
        int x = rng.Range(0, 479);
        int y = rng.Range(0, 180);
        c.VLine(x, y, y + rng.Range(3, 14), RGBA(160, 190, 190, 26));
    }
    c.FillRect(0, 0, 480, 1, RGBA(0, 0, 0, 160));
    c.FillRect(0, 269, 480, 1, RGBA(0, 0, 0, 200));
    return c;
}

// ===========================================================================
// 生成流程
// ===========================================================================

static void AddCharacterSet(const std::string& prefix, const CharStyle& style,
                           bool includeSit, bool merchantSit)
{
    const char* dirName[4] = {"S", "N", "E", "W"};
    for (int d = 0; d < 4; ++d) {
        Facing facing = (d == 0) ? Facing::SOUTH
                       : (d == 1) ? Facing::NORTH
                                  : Facing::EAST;
        bool mirror = (d == 3);
        for (int frame = 0; frame < 4; ++frame) {
            Canvas c(16, 24);
            c.Clear(RGBA(0, 0, 0, 0));
            DrawCharacter(c, style, facing, frame, mirror);
            AddAsset(prefix + "_" + dirName[d] + "_" + std::to_string(frame),
                     std::move(c));
        }
        Canvas idle(16, 24);
        idle.Clear(RGBA(0, 0, 0, 0));
        DrawCharacter(idle, style, facing, 0, mirror);
        AddAsset(prefix + "_" + dirName[d] + "_IDLE", std::move(idle));
    }
    if (includeSit) {
        Canvas sit(24, 24);
        DrawSit(sit, style, merchantSit);
        AddAsset(prefix + "_SIT", std::move(sit));
    }
}

static void GenerateTiles()
{
    for (int v = 0; v < 3; ++v) {
        AddAsset("TILE_BAR_FLOOR_" + std::string(1, static_cast<char>('A' + v)),
                 MakeBarFloor(v, 0x1000));
    }
    for (int v = 0; v < 2; ++v) {
        AddAsset("TILE_BAR_CARPET_" + std::string(1, static_cast<char>('A' + v)),
                 MakeBarCarpet(v, 0x2000));
    }
    AddAsset("TILE_BAR_WALL_A", MakeBarWall(0, 0x3000));
    AddAsset("TILE_BAR_WALL_B", MakeBarWall(1, 0x3100));
    AddAsset("TILE_BAR_WALL_SHELF", MakeBarShelf(0x3200));
    AddAsset("TILE_BAR_WALL_WINDOW", MakeBarWindow(0x3300));
    AddAsset("TILE_STREET_FLOOR_A", MakeStreetFloor(0, 0x4000));
    AddAsset("TILE_STREET_FLOOR_B", MakeStreetFloor(1, 0x4100));
    AddAsset("TILE_STREET_WALL_A", MakeStreetWall(0, 0x4200));
    AddAsset("TILE_STREET_WALL_B", MakeStreetWall(1, 0x4300));
    AddAsset("TILE_STREET_CURB", MakeStreetCurb(0x4400));
    AddAsset("TILE_HARBOR_FLOOR_A", MakeHarborFloor(0, 0x5000));
    AddAsset("TILE_HARBOR_FLOOR_B", MakeHarborFloor(1, 0x5100));
    AddAsset("TILE_HARBOR_FLOOR_C", MakeHarborFloor(2, 0x5200));
    AddAsset("TILE_HARBOR_WALL_A", MakeHarborWall(0, 0x5300));
    AddAsset("TILE_HARBOR_WALL_B", MakeHarborWall(1, 0x5400));
    AddAsset("TILE_HARBOR_DOOR", MakeHarborDoor(0x5500));
    AddAsset("TILE_VOID", MakeVoid(0x5600));
}

static void GenerateProps()
{
    AddAsset("PROP_BAR_COUNTER", MakeBarCounter(0x6000));
    AddAsset("PROP_BAR_SHELF", MakeBarShelfProp(0x6100));
    AddAsset("PROP_BOOTH", MakeBooth(0x6200));
    AddAsset("PROP_BOOTH_CURTAIN", MakeBoothCurtain(0x6300));
    AddAsset("PROP_TABLE_ROUND", MakeRoundTable(0x6400));
    AddAsset("PROP_CHAIR", MakeChair(0x6500));
    AddAsset("PROP_JUKEBOX", MakeJukebox(false, 0x6600));
    AddAsset("PROP_JUKEBOX_BROKEN", MakeJukebox(true, 0x6700));
    AddAsset("PROP_NEON_AFTERGLOW", MakeNeonSign(0x6800));
    AddAsset("PROP_DOOR", MakeDoor(0x6900));
    AddAsset("PROP_WINDOW_LIT", MakeWindowLit(0x6A00));
    AddAsset("PROP_LAMP_PENDANT", MakePendantLamp(0x6B00));
    AddAsset("PROP_CRATE_S", MakeCrateSmall(0x6C00));
    AddAsset("PROP_CRATE_L", MakeCrateLarge(0x6D00));
    AddAsset("PROP_CARGO", MakeCargo(0x6E00));
    AddAsset("PROP_BARREL", MakeBarrel(0x6F00));
    AddAsset("PROP_CAR", MakeCar(0x7000));
    AddAsset("PROP_CONTAINER", MakeContainer(0x7100));
    AddAsset("PROP_FORKLIFT", MakeForklift(0x7200));
    AddAsset("PROP_ALARM_OFF", MakeAlarmLight(false, 0x7300));
    AddAsset("PROP_ALARM_ON", MakeAlarmLight(true, 0x7400));
    AddAsset("PROP_PART", MakePart(0x7500));
    AddAsset("PROP_PUDDLE", MakePuddle(0x7600));
}

static void GenerateCharacters()
{
    AddCharacterSet("CHAR_PLAYER", StylePlayer(), false, false);
    AddCharacterSet("CHAR_BIGSISTER", StyleBigSister(), true, false);
    AddCharacterSet("CHAR_MERCHANT", StyleMerchant(), true, true);
    AddCharacterSet("CHAR_BARTENDER", StyleBartender(), false, false);
    AddCharacterSet("CHAR_SCAVENGER", StyleScavenger(), false, false);
    AddCharacterSet("CHAR_AGENT", StyleAgent(), false, false);
}

static void GeneratePortraits()
{
    {
        Canvas c(48, 48);
        PortraitSpec s;
        s.bg1 = RGBA(12, 18, 22);
        s.bg2 = RGBA(22, 40, 44);
        s.glow = RGBA(57, 224, 208, 34);
        s.skin = RGBA(201, 142, 107);
        s.skinShade = RGBA(156, 102, 76);
        s.skinHi = RGBA(226, 170, 132);
        s.hair = RGBA(26, 26, 31);
        s.hairShade = RGBA(16, 16, 20);
        s.hairHi = RGBA(64, 60, 66);
        s.coat = RGBA(46, 59, 47);
        s.coatHi = RGBA(84, 102, 78);
        s.coatShade = RGBA(30, 38, 32);
        s.accent = RGBA(47, 168, 160);
        s.tired = true;
        s.scarf = true;
        s.implant = true;
        DrawPortrait(c, s);
        AddAsset("PORTRAIT_PLAYER", std::move(c));
    }
    {
        Canvas c(48, 48);
        PortraitSpec s;
        s.bg1 = RGBA(24, 12, 14);
        s.bg2 = RGBA(58, 24, 26);
        s.glow = RGBA(255, 179, 71, 42);
        s.skin = RGBA(201, 142, 107);
        s.skinShade = RGBA(156, 102, 76);
        s.skinHi = RGBA(230, 174, 134);
        s.hair = RGBA(59, 42, 40);
        s.hairShade = RGBA(38, 26, 26);
        s.hairHi = RGBA(100, 76, 66);
        s.coat = RGBA(140, 47, 63);
        s.coatHi = RGBA(188, 80, 90);
        s.coatShade = RGBA(92, 30, 42);
        s.accent = RGBA(255, 179, 71);
        s.smile = true;
        s.implant = true;
        s.bun = true;
        s.silverStreak = true;
        DrawPortrait(c, s);
        AddAsset("PORTRAIT_BIGSISTER", std::move(c));
    }
    {
        Canvas c(48, 48);
        PortraitSpec s;
        s.bg1 = RGBA(14, 18, 16);
        s.bg2 = RGBA(30, 42, 40);
        s.glow = RGBA(57, 224, 208, 40);
        s.skin = RGBA(201, 142, 107);
        s.skinShade = RGBA(156, 102, 76);
        s.skinHi = RGBA(226, 170, 132);
        s.hair = RGBA(46, 36, 30);
        s.hairShade = RGBA(28, 22, 18);
        s.hairHi = RGBA(82, 64, 48);
        s.coat = RGBA(90, 74, 50);
        s.coatHi = RGBA(130, 108, 72);
        s.coatShade = RGBA(62, 50, 36);
        s.accent = RGBA(57, 224, 208);
        s.smirk = true;
        s.goggles = true;
        s.implant = true;
        s.stripes = true;
        DrawPortrait(c, s);
        AddAsset("PORTRAIT_MERCHANT", std::move(c));
    }
    {
        Canvas c(48, 48);
        PortraitSpec s;
        s.bg1 = RGBA(20, 14, 12);
        s.bg2 = RGBA(52, 34, 24);
        s.glow = RGBA(255, 179, 71, 46);
        s.skin = RGBA(201, 142, 107);
        s.skinShade = RGBA(156, 102, 76);
        s.skinHi = RGBA(230, 174, 134);
        s.hair = RGBA(80, 52, 38);
        s.hairShade = RGBA(52, 34, 26);
        s.hairHi = RGBA(122, 86, 58);
        s.coat = RGBA(216, 210, 196);
        s.coatHi = RGBA(245, 240, 225);
        s.coatShade = RGBA(170, 164, 150);
        s.accent = RGBA(255, 179, 71);
        s.smile = true;
        s.apron = true;
        DrawPortrait(c, s);
        AddAsset("PORTRAIT_BARTENDER", std::move(c));
    }
}

static void GenerateIconsAndFx()
{
    AddAsset("UI_ICON_HEALTH", MakeIconHealth());
    AddAsset("UI_ICON_AMMO", MakeIconAmmo());
    AddAsset("UI_ICON_CREDIT", MakeIconCredit());
    AddAsset("UI_ICON_MEDKIT", MakeIconMedkit());
    AddAsset("UI_ICON_JACK", MakeIconJack());
    AddAsset("UI_ICON_OBJECTIVE", MakeIconObjective());
    AddAsset("UI_ICON_PART", MakeIconPart());
    AddAsset("UI_PANEL_CORNER", MakePanelCorner());
    AddAsset("UI_SCANLINE", MakeScanline());
    AddAsset("UI_NOISE", MakeNoise());
    AddAsset("UI_VIGNETTE", MakeVignette());
    AddAsset("UI_TITLE_LOGO", MakeTitleLogo());
    AddAsset("UI_TITLE_BG", MakeTitleBackground());
    AddAsset("UI_ENDING_BG", MakeEndingBackground());
    AddAsset("FX_GLOW", MakeGlow());
    AddAsset("FX_MUZZLE_0", MakeMuzzle(0));
    AddAsset("FX_MUZZLE_1", MakeMuzzle(1));
    AddAsset("FX_BULLET", MakeBullet());
    AddAsset("FX_SPARK", MakeSpark());
    AddAsset("FX_BLOOD", MakeBlood());
    AddAsset("FX_SHELL", MakeShell());
    AddAsset("FX_RAIN", MakeRain());
    AddAsset("FX_SMOKE", MakeSmoke());
    AddAsset("FX_ALARM", MakeAlarmFx());
    AddAsset("FX_PICKUP", MakePickup());
}

static void GenerateContactSheet(const fs::path& outDir)
{
    const int CELL_W = 116;
    const int CELL_H = 84;
    const int COLS = 10;
    std::vector<const Asset*> items;
    for (const auto& a : g_assets) {
        if (!a.name.empty() && a.name[0] != '_' &&
            a.name.find("BG") == std::string::npos &&
            a.name.find("VIGNETTE") == std::string::npos &&
            a.name.find("TITLE_LOGO") == std::string::npos &&
            a.name.find("SCANLINE") == std::string::npos &&
            a.name.find("NOISE") == std::string::npos) {
            items.push_back(&a);
        }
    }
    int rows = static_cast<int>((items.size() + COLS - 1) / COLS);
    Canvas sheet(COLS * CELL_W + 16, rows * CELL_H + 40);
    sheet.Clear(RGBA(12, 16, 22));
    DrawText(sheet, "EMBER OF FREE CITY - ART CONTACT SHEET", 10, 8, 1,
             RGBA(232, 227, 214));
    DrawText(sheet, "ASSETS " + std::to_string(items.size()) + " - GENERATED BY ARTGEN", 10, 20, 1,
             RGBA(80, 120, 130));
    for (size_t i = 0; i < items.size(); ++i) {
        int col = static_cast<int>(i % COLS);
        int row = static_cast<int>(i / COLS);
        int x = 8 + col * CELL_W;
        int y = 34 + row * CELL_H;
        sheet.OutlineRect(x, y, CELL_W - 6, CELL_H - 6, RGBA(28, 38, 46));
        const Asset& a = *items[i];
        int scale = (a.canvas.w <= 64 && a.canvas.h <= 48) ? 2 : 1;
        int dw = a.canvas.w * scale;
        int dh = a.canvas.h * scale;
        if (dw > CELL_W - 12) {
            scale = 1;
            dw = a.canvas.w;
            dh = a.canvas.h;
        }
        int dx = x + (CELL_W - 6 - dw) / 2;
        int dy = y + 4 + (CELL_H - 16 - dh) / 2;
        // 棋盘底，便于查看透明像素
        for (int yy = 0; yy < dh; yy += 4) {
            for (int xx = 0; xx < dw; xx += 4) {
                bool alt = ((xx / 4 + yy / 4) & 1) != 0;
                sheet.FillRect(dx + xx, dy + yy, std::min(4, dw - xx),
                               std::min(4, dh - yy),
                               alt ? RGBA(26, 30, 38) : RGBA(20, 24, 30));
            }
        }
        sheet.Blit(a.canvas, dx, dy, scale);
        std::string label = a.name;
        if (label.size() > 17) {
            label = label.substr(0, 17);
        }
        DrawText(sheet, label, x + 3, y + CELL_H - 12, 1, RGBA(120, 150, 150));
    }
    WritePNG(outDir / "_ContactSheet.png", sheet);
    AddAsset("_CONTACT_SHEET", std::move(sheet), false);
}

static void GenerateCharacterPreview(const fs::path& outDir)
{
    std::vector<std::pair<std::string, CharStyle>> chars;
    chars.push_back({"PLAYER", StylePlayer()});
    chars.push_back({"BIG SISTER", StyleBigSister()});
    chars.push_back({"MERCHANT", StyleMerchant()});
    chars.push_back({"BARTENDER", StyleBartender()});
    chars.push_back({"SCAVENGER", StyleScavenger()});
    chars.push_back({"AGENT", StyleAgent()});

    const int SCALE = 6;
    const int SPRITE_W = 16 * SCALE;
    const int SPRITE_H = 24 * SCALE;
    const int CELL_W = 330;
    const int CELL_H = 190;
    const int COLS = 2;
    const int ROWS = 3;
    Canvas sheet(COLS * CELL_W + 16, ROWS * CELL_H + 40);
    sheet.Clear(RGBA(12, 16, 22));
    DrawText(sheet, "CHARACTER PREVIEW - SOUTH / EAST / NORTH", 12, 8, 1,
             RGBA(232, 227, 214));
    for (size_t i = 0; i < chars.size(); ++i) {
        int col = static_cast<int>(i % COLS);
        int row = static_cast<int>(i / COLS);
        int x = 10 + col * CELL_W;
        int y = 34 + row * CELL_H;
        sheet.FillRect(x, y, CELL_W - 8, CELL_H - 8, RGBA(17, 23, 29));
        sheet.OutlineRect(x, y, CELL_W - 8, CELL_H - 8, RGBA(28, 38, 46));
        DrawText(sheet, chars[i].first, x + 8, y + 6, 1, RGBA(120, 200, 195));
        for (int d = 0; d < 3; ++d) {
            Facing f = (d == 0) ? Facing::SOUTH
                       : (d == 1) ? Facing::EAST
                                  : Facing::NORTH;
            Canvas c(16, 24);
            c.Clear(RGBA(0, 0, 0, 0));
            DrawCharacter(c, chars[i].second, f, 1, false);
            int sx = x + 10 + d * (SPRITE_W + 8);
            sheet.FillRect(sx - 2, y + 22, SPRITE_W + 4, SPRITE_H + 8,
                           RGBA(22, 28, 34));
            sheet.Blit(c, sx, y + 24, SCALE);
        }
    }
    WritePNG(outDir / "_CharacterPreview.png", sheet);
}

static void GeneratePortraitPreview(const fs::path& outDir)
{
    const int SCALE = 5;
    const int CELL = 48 * SCALE + 24;
    Canvas sheet(CELL * 4 + 16, 48 * SCALE + 56);
    sheet.Clear(RGBA(12, 16, 22));
    DrawText(sheet, "PORTRAIT PREVIEW", 12, 8, 1, RGBA(232, 227, 214));
    const char* names[4] = {"PORTRAIT_PLAYER", "PORTRAIT_BIGSISTER",
                            "PORTRAIT_MERCHANT", "PORTRAIT_BARTENDER"};
    for (int i = 0; i < 4; ++i) {
        int x = 12 + i * CELL;
        int y = 30;
        for (const auto& a : g_assets) {
            if (a.name == names[i]) {
                sheet.Blit(a.canvas, x, y, SCALE);
                break;
            }
        }
        DrawText(sheet, names[i], x, y + 48 * SCALE + 8, 1,
                 RGBA(120, 200, 195));
    }
    WritePNG(outDir / "_PortraitPreview.png", sheet);
}

static void GenerateTitlePreview(const fs::path& outDir)
{
    Canvas c(480, 270);
    c.Clear(RGBA(0, 0, 0, 255));
    for (const auto& a : g_assets) {
        if (a.name == "UI_TITLE_BG") {
            c.Blit(a.canvas, 0, 0);
        }
    }
    for (const auto& a : g_assets) {
        if (a.name == "UI_TITLE_LOGO") {
            c.Blit(a.canvas, 120, 78);
        }
    }
    DrawText(c, "A FREE CITY STORY", 186, 158, 1, RGBA(190, 210, 205));
    DrawText(c, "PRESS ENTER", 200, 220, 1, RGBA(255, 179, 71));
    c.FillRect(0, 0, 480, 1, RGBA(0, 0, 0, 160));
    WritePNG(outDir / "_TitlePreview.png", c);
}

// ===========================================================================
// 入口
// ===========================================================================

int main(int argc, char** argv)
{
    fs::path base = "Resources";
    if (argc > 1) {
        base = argv[1];
    }
    fs::path artDir = base / "Art";
    std::error_code ec;
    fs::create_directories(artDir, ec);

    GenerateTiles();
    GenerateProps();
    GenerateCharacters();
    GeneratePortraits();
    GenerateIconsAndFx();

    int pngCount = 0;
    for (const auto& a : g_assets) {
        if (!a.name.empty() && a.name[0] == '_') {
            continue;
        }
        if (WritePNG(artDir / (a.name + ".png"), a.canvas)) {
            ++pngCount;
        } else {
            std::fprintf(stderr, "Failed to write PNG: %s\n", a.name.c_str());
        }
    }

    fs::path packPath = base / "ArtPack.bin";
    if (!WritePack(packPath)) {
        std::fprintf(stderr, "Failed to write art pack: %s\n", packPath.string().c_str());
        return 1;
    }

    GenerateContactSheet(artDir);
    GenerateCharacterPreview(artDir);
    GeneratePortraitPreview(artDir);
    GenerateTitlePreview(artDir);

    std::printf("Generated %d PNG assets.\n", pngCount);
    std::printf("Art pack: %s\n", packPath.string().c_str());
    std::printf("Contact sheet: %s\n", (artDir / "_ContactSheet.png").string().c_str());
    return 0;
}
