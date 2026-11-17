#ifndef __RENDER_MESH_HPP__
#define __RENDER_MESH_HPP__

#include "Shared_ComPtr.hpp"
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
 * @brief 网格顶点：位置、法线、颜色与程序化材质编号。
 *
 * 材质编号在像素着色器中用于生成砖缝、木纹、锈迹等程序化图案，
 * 因此不需要任何贴图文件。
 */
struct MeshVertex {
    Vec3 position;
    Vec3 normal;
    Color color;
    float pattern = 0.0f;
};

/**
 * @brief CPU 侧网格部件；部件可围绕枢轴旋转，用于角色动画。
 */
struct MeshPartData {
    std::string name;
    Vec3 pivot;
    std::vector<MeshVertex> vertices;
    std::vector<std::uint32_t> indices;
};

/**
 * @brief CPU 侧网格数据。
 */
struct MeshData {
    std::string name;
    std::vector<MeshPartData> parts;
    Vec3 boundsMin;
    Vec3 boundsMax;
    int triangleCount = 0;
    int vertexCount = 0;
};

/**
 * @brief 程序化网格构建器：所有 3D 资产都由基本体组合而成。
 */
class MeshBuilder {
public:
    /**
     * @brief 开始一个新的部件。
     * @param [IN] name 部件名（torso/head/armL 等）。
     * @param [IN] pivot 旋转枢轴。
     */
    void BeginPart(const std::string& name, const Vec3& pivot);

    /**
     * @brief 设置后续面片颜色。
     * @param [IN] color 颜色。
     */
    void SetColor(const Color& color);

    /**
     * @brief 设置后续面片的程序化材质编号。
     * @param [IN] pattern 编号（0 平涂，1 砖，2 木纹，3 金属肋，4 锈，5 布纹，6 混凝土）。
     */
    void SetPattern(int pattern);

    /**
     * @brief 添加三角形（自动平面法线）。
     * @param [IN] a 顶点 A。
     * @param [IN] b 顶点 B。
     * @param [IN] c 顶点 C。
     * @param [IN] twoSided 是否正反面都绘制。
     */
    void AddTriangle(const Vec3& a, const Vec3& b, const Vec3& c,
                     bool twoSided = false);

    /**
     * @brief 添加四边形（拆为两个三角形）。
     * @param [IN] a 顶点 A。
     * @param [IN] b 顶点 B。
     * @param [IN] c 顶点 C。
     * @param [IN] d 顶点 D。
     * @param [IN] twoSided 是否正反面都绘制。
     */
    void AddQuad(const Vec3& a, const Vec3& b, const Vec3& c, const Vec3& d,
                 bool twoSided = false);

    /**
     * @brief 添加盒子。
     * @param [IN] center 中心。
     * @param [IN] half 半长。
     * @param [IN] yaw 绕 Y 轴旋转（弧度）。
     */
    void AddBox(const Vec3& center, const Vec3& half, float yaw = 0.0f);

    /**
     * @brief 添加圆柱/圆台。
     * @param [IN] baseCenter 底面中心。
     * @param [IN] radiusBottom 底面半径。
     * @param [IN] radiusTop 顶面半径。
     * @param [IN] height 高度（向上）。
     * @param [IN] segments 侧面分段。
     * @param [IN] yaw 绕 Y 轴旋转（弧度）。
     * @param [IN] caps 是否封顶底。
     */
    void AddCylinder(const Vec3& baseCenter, float radiusBottom,
                     float radiusTop, float height, int segments, float yaw = 0.0f,
                     bool caps = true);

    /**
     * @brief 添加圆锥。
     * @param [IN] baseCenter 底面中心。
     * @param [IN] radius 底面半径。
     * @param [IN] height 高度。
     * @param [IN] segments 分段。
     * @param [IN] yaw 绕 Y 轴旋转。
     */
    void AddCone(const Vec3& baseCenter, float radius, float height,
                 int segments, float yaw = 0.0f);

    /**
     * @brief 添加球体（低分段）。
     * @param [IN] center 中心。
     * @param [IN] radius 半径。
     * @param [IN] segments 经度分段。
     * @param [IN] rings 纬度分段。
     */
    void AddSphere(const Vec3& center, float radius, int segments, int rings);

    /**
     * @brief 添加水平面片。
     * @param [IN] center 中心。
     * @param [IN] halfX X 半长。
     * @param [IN] halfZ Z 半长。
     * @param [IN] up 法线是否朝上。
     */
    void AddPlane(const Vec3& center, float halfX, float halfZ, bool up = true);

    /**
     * @brief 添加竖直面片（面向 ±X 或 ±Z）。
     * @param [IN] center 中心。
     * @param [IN] halfWidth 半宽（水平）。
     * @param [IN] halfHeight 半高。
     * @param [IN] yaw 朝向（0 面向 +Z）。
     */
    void AddWall(const Vec3& center, float halfWidth, float halfHeight,
                 float yaw);

    /**
     * @brief 添加倒角盒（顶面略小），用于低多面体机身。
     * @param [IN] center 中心。
     * @param [IN] half 半长。
     * @param [IN] bevel 顶部收窄比例（0–1）。
     * @param [IN] yaw 绕 Y 轴旋转。
     */
    void AddBeveledBox(const Vec3& center, const Vec3& half, float bevel,
                       float yaw = 0.0f);

    /**
     * @brief 结束并返回网格数据。
     * @param [IN] name 网格名。
     * @return 网格数据。
     */
    MeshData Finish(const std::string& name);

    /**
     * @brief 当前是否有打开的部件。
     * @return 打开返回 true。
     */
    bool HasPart() const;

private:
    MeshPartData* CurrentPart();
    void AppendVertex(const Vec3& position, const Vec3& normal);
    void ExpandBounds(const Vec3& p);

    MeshData m_data;
    MeshPartData* m_part = nullptr;
    Color m_color{0.7f, 0.7f, 0.7f, 1.0f};
    float m_pattern = 0.0f;
    MeshData m_scratch;
};

/**
 * @brief GPU 网格部件。
 */
struct MeshPart {
    std::string name;
    Vec3 pivot;
    ComPtr<ID3D11Buffer> vertexBuffer;
    ComPtr<ID3D11Buffer> indexBuffer;
    UINT indexCount = 0;
};

/**
 * @brief GPU 网格。
 */
struct Mesh {
    std::string name;
    std::vector<MeshPart> parts;
    Vec3 boundsMin;
    Vec3 boundsMax;
    int triangleCount = 0;

    /**
     * @brief 是否已上传 GPU。
     * @return 有效返回 true。
     */
    bool IsValid() const
    {
        return !parts.empty() && parts.front().vertexBuffer != nullptr;
    }
};

/**
 * @brief 文本网格库：解析 `.fcm` 文本，按需上传 GPU。
 *
 * 文本资产格式示例：
 * @code
 * mesh PROP_STOOL
 * part body pivot 0 0 0
 * mat 0x8c6f52
 * pattern 3
 * cyl 0 0 0 0.22 0.22 0.55 10
 * box 0 0.58 0 0.26 0.05 0.26
 * endpart
 * endmesh
 * @endcode
 */
class MeshLibrary {
public:
    MeshLibrary() = default;
    ~MeshLibrary() = default;

    /**
     * @brief 绑定设备。
     * @param [IN] device D3D11 设备。
     */
    void Initialize(ID3D11Device* device);

    /**
     * @brief 解析一段文本资产并加入库（仅 CPU）。
     * @param [IN] text UTF-8 文本。
     * @return 解析出的网格数量；失败返回 0。
     */
    int AddText(const std::string& text);

    /**
     * @brief 按名称获取 GPU 网格；不存在时创建占位网格。
     * @param [IN] name 网格名。
     * @return 网格指针，永不为空。
     */
    const Mesh* Get(const std::string& name);

    /**
     * @brief 按名称获取 CPU 网格数据。
     * @param [IN] name 网格名。
     * @return 数据指针；不存在返回 nullptr。
     */
    const MeshData* GetData(const std::string& name) const;

    /**
     * @brief 直接加入一个 GPU 网格（用于程序化房间/角色）。
     * @param [IN] data CPU 网格数据。
     * @param [IN] name 网格名。
     * @return 网格指针；失败返回占位。
     */
    const Mesh* AddMesh(MeshData&& data, const std::string& name);

    /**
     * @brief 获取全部网格名。
     * @return 名称列表。
     */
    std::vector<std::string> Names() const;

    /**
     * @brief 已解析的 CPU 网格数量。
     * @return 数量。
     */
    int Count() const { return static_cast<int>(m_cpu.size()); }

private:
    bool Upload(const MeshData& data, Mesh& out);
    const Mesh* Placeholder();

    ID3D11Device* m_device = nullptr;
    std::unordered_map<std::string, MeshData> m_cpu;
    std::unordered_map<std::string, std::unique_ptr<Mesh>> m_gpu;
    std::unique_ptr<Mesh> m_placeholder;
};

/**
 * @brief 解析单个 `.fcm` 文本块。
 * @param [IN] text UTF-8 文本。
 * @param [OUT] out 解析结果。
 * @return 解析出的网格数量。
 */
int ParseMeshText(const std::string& text, std::vector<MeshData>& out);

} // namespace fc

#endif // __RENDER_MESH_HPP__
