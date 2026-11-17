#ifndef __RENDER_TEXT_HPP__
#define __RENDER_TEXT_HPP__

#include "Render_SpriteBatch.hpp"
#include "Render_Texture.hpp"
#include "Shared_Types.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace fc {

class RenderDevice;

/**
 * @brief 文本中的一行及其像素度量。
 */
struct TextLine {
    int startUnit = 0;                 ///< 在 UTF-16 全文中的起始索引。
    int lengthUnits = 0;               ///< 该行字符数。
    int y = 0;                         ///< 在纹理中的 y 偏移。
    int height = 0;                    ///< 行高。
    int width = 0;                     ///< 该行像素宽度。
    std::vector<int> charX;            ///< 每个字符前缀的像素宽度，大小 length+1。
};

/**
 * @brief 一段已排版并渲染为纹理的文本。
 */
struct TextBlock {
    Texture texture;
    std::vector<TextLine> lines;
    int width = 0;
    int height = 0;
    int unitCount = 0;
    int lineHeight = 0;
};

/**
 * @brief 基于 GDI 的中文文本渲染器：排版、光栅化、上传纹理、缓存。
 */
class TextRenderer {
public:
    TextRenderer() = default;
    ~TextRenderer();

    /**
     * @brief 初始化 GDI 资源。
     * @param [IN] device 渲染设备。
     * @return 成功返回 true。
     */
    bool Initialize(RenderDevice* device);

    /**
     * @brief 释放缓存、字体与 GDI 资源。必须在渲染设备关闭前调用。
     */
    void Shutdown();

    /**
     * @brief 获取排版后的文本块；不存在时创建。
     * @param [IN] text UTF-8 文本。
     * @param [IN] px 字体像素高度。
     * @param [IN] maxWidth 最大行宽（像素）。
     * @return 文本块指针；失败返回 nullptr。
     */
    const TextBlock* Get(const std::string& text, int px, int maxWidth);

    /**
     * @brief 绘制文本块。
     * @param [IN] batch 精灵批处理。
     * @param [IN] block 文本块。
     * @param [IN] x 左上角 x。
     * @param [IN] y 左上角 y。
     * @param [IN] tint 颜色。
     * @param [IN] visibleUnits 可见的 UTF-16 字符数；默认全部。
     * @param [IN] shadow 是否绘制 1px 阴影。
     */
    void Draw(SpriteBatch& batch, const TextBlock& block, float x, float y,
              Color tint, int visibleUnits = 0x7FFFFFFF, bool shadow = true);

    /**
     * @brief 测量文本高度。
     * @param [IN] text UTF-8 文本。
     * @param [IN] px 字体像素高度。
     * @param [IN] maxWidth 最大行宽。
     * @return 像素高度。
     */
    int MeasureHeight(const std::string& text, int px, int maxWidth);

    /**
     * @brief 计算可见字符数对应的像素宽度（用于打字机光标）。
     * @param [IN] block 文本块。
     * @param [IN] visibleUnits 可见字符数。
     * @param [OUT] outLine 当前行索引。
     * @param [OUT] outX 当前行内的像素 x。
     * @return 是否有可见内容。
     */
    bool GetCaretPosition(const TextBlock& block, int visibleUnits,
                          int& outLine, int& outX) const;

private:
    struct FontRecord {
        HFONT font = nullptr;
        int px = 0;
        int lineHeight = 0;
    };

    FontRecord* GetFont(int px);
    std::unique_ptr<TextBlock> Build(const std::string& text, int px, int maxWidth);
    void ClearCache();

    RenderDevice* m_device = nullptr;
    HDC m_memoryDC = nullptr;
    std::unordered_map<int, FontRecord> m_fonts;
    std::unordered_map<std::string, std::unique_ptr<TextBlock>> m_cache;
};

} // namespace fc

#endif // __RENDER_TEXT_HPP__
