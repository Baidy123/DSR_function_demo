#include "Render_Mesh.hpp"

#include "Shared_Log.hpp"
#include "Shared_Math.hpp"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <sstream>

namespace fc {

namespace {

std::string Trim(const std::string& text)
{
    size_t begin = 0;
    while (begin < text.size() &&
           std::isspace(static_cast<unsigned char>(text[begin])) != 0) {
        ++begin;
    }
    size_t end = text.size();
    while (end > begin &&
           std::isspace(static_cast<unsigned char>(text[end - 1])) != 0) {
        --end;
    }
    return text.substr(begin, end - begin);
}

std::string Lower(std::string text)
{
    for (char& c : text) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return text;
}

} // namespace

void MeshBuilder::BeginPart(const std::string& name, const Vec3& pivot)
{
    m_data.parts.push_back(MeshPartData());
    m_part = &m_data.parts.back();
    m_part->name = name;
    m_part->pivot = pivot;
}

bool MeshBuilder::HasPart() const
{
    return m_part != nullptr;
}

MeshPartData* MeshBuilder::CurrentPart()
{
    if (m_part == nullptr) {
        BeginPart("default", Vec3());
    }
    return m_part;
}

void MeshBuilder::SetColor(const Color& color)
{
    m_color = color;
}

void MeshBuilder::SetPattern(int pattern)
{
    m_pattern = static_cast<float>(pattern);
}

void MeshBuilder::SetMaterial(int material)
{
    m_material = static_cast<float>(material);
}

void MeshBuilder::ExpandBounds(const Vec3& p)
{
    if (m_data.vertexCount == 0) {
        m_data.boundsMin = p;
        m_data.boundsMax = p;
        return;
    }
    m_data.boundsMin.x = std::min(m_data.boundsMin.x, p.x);
    m_data.boundsMin.y = std::min(m_data.boundsMin.y, p.y);
    m_data.boundsMin.z = std::min(m_data.boundsMin.z, p.z);
    m_data.boundsMax.x = std::max(m_data.boundsMax.x, p.x);
    m_data.boundsMax.y = std::max(m_data.boundsMax.y, p.y);
    m_data.boundsMax.z = std::max(m_data.boundsMax.z, p.z);
}

void MeshBuilder::AppendVertex(const Vec3& position, const Vec3& normal)
{
    MeshPartData* part = CurrentPart();
    MeshVertex vertex;
    vertex.position = position;
    vertex.normal = normal;
    vertex.color = m_color;
    vertex.pattern = m_pattern;
    vertex.material = m_material;
    part->vertices.push_back(vertex);
    ++m_data.vertexCount;
    ExpandBounds(position);
}

void MeshBuilder::AddTriangle(const Vec3& a, const Vec3& b, const Vec3& c,
                              bool twoSided)
{
    MeshPartData* part = CurrentPart();
    const Vec3 normal = Normalize(Cross(b - a, c - a));
    const std::uint32_t base = static_cast<std::uint32_t>(part->vertices.size());

    AppendVertex(a, normal);
    AppendVertex(b, normal);
    AppendVertex(c, normal);
    part->indices.push_back(base);
    part->indices.push_back(base + 1);
    part->indices.push_back(base + 2);
    ++m_data.triangleCount;

    if (twoSided) {
        const Vec3 flipped = -normal;
        const std::uint32_t base2 =
            static_cast<std::uint32_t>(part->vertices.size());
        AppendVertex(a, flipped);
        AppendVertex(c, flipped);
        AppendVertex(b, flipped);
        part->indices.push_back(base2);
        part->indices.push_back(base2 + 1);
        part->indices.push_back(base2 + 2);
        ++m_data.triangleCount;
    }
}

void MeshBuilder::AddQuad(const Vec3& a, const Vec3& b, const Vec3& c,
                          const Vec3& d, bool twoSided)
{
    AddTriangle(a, b, c, twoSided);
    AddTriangle(a, c, d, twoSided);
}

void MeshBuilder::AddBox(const Vec3& center, const Vec3& half, float yaw)
{
    const Mat4 rotation = Mat4::RotationY(yaw);
    auto point = [&](float sx, float sy, float sz) {
        return center + rotation.TransformVector(Vec3(sx * half.x, sy * half.y,
                                                     sz * half.z));
    };

    const Vec3 p000 = point(-1, -1, -1);
    const Vec3 p100 = point(1, -1, -1);
    const Vec3 p110 = point(1, 1, -1);
    const Vec3 p010 = point(-1, 1, -1);
    const Vec3 p001 = point(-1, -1, 1);
    const Vec3 p101 = point(1, -1, 1);
    const Vec3 p111 = point(1, 1, 1);
    const Vec3 p011 = point(-1, 1, 1);

    AddQuad(p001, p101, p111, p011);  // +Z
    AddQuad(p100, p000, p010, p110);  // -Z
    AddQuad(p101, p100, p110, p111);  // +X
    AddQuad(p000, p001, p011, p010);  // -X
    AddQuad(p011, p111, p110, p010);  // +Y
    AddQuad(p000, p100, p101, p001);  // -Y
}

void MeshBuilder::AddBeveledBox(const Vec3& center, const Vec3& half,
                                float bevel, float yaw)
{
    bevel = Clamp(bevel, 0.0f, 0.9f);
    const float topScale = 1.0f - bevel;
    const Mat4 rotation = Mat4::RotationY(yaw);
    auto point = [&](float sx, float sy, float sz) {
        return center + rotation.TransformVector(Vec3(sx * half.x, sy * half.y,
                                                     sz * half.z));
    };

    const Vec3 b00 = point(-1, -1, -1);
    const Vec3 b10 = point(1, -1, -1);
    const Vec3 b11 = point(1, -1, 1);
    const Vec3 b01 = point(-1, -1, 1);
    const Vec3 t00 = point(-topScale, 1, -topScale);
    const Vec3 t10 = point(topScale, 1, -topScale);
    const Vec3 t11 = point(topScale, 1, topScale);
    const Vec3 t01 = point(-topScale, 1, topScale);

    AddQuad(t01, t11, t10, t00);  // 顶
    AddQuad(b00, b10, b11, b01);  // 底
    AddQuad(b01, b11, t11, t01);  // +Z
    AddQuad(b10, b00, t00, t10);  // -Z
    AddQuad(b11, b10, t10, t11);  // +X
    AddQuad(b00, b01, t01, t00);  // -X
}

void MeshBuilder::AddCylinder(const Vec3& baseCenter, float radiusBottom,
                              float radiusTop, float height, int segments,
                              float yaw, bool caps)
{
    segments = ClampInt(segments, 3, 48);
    const float step = 2.0f * PI / static_cast<float>(segments);
    for (int i = 0; i < segments; ++i) {
        const float a0 = static_cast<float>(i) * step + yaw;
        const float a1 = static_cast<float>(i + 1) * step + yaw;
        const Vec3 b0 = baseCenter + Vec3(std::sin(a0) * radiusBottom, 0.0f,
                                          std::cos(a0) * radiusBottom);
        const Vec3 b1 = baseCenter + Vec3(std::sin(a1) * radiusBottom, 0.0f,
                                          std::cos(a1) * radiusBottom);
        const Vec3 t0 = baseCenter + Vec3(std::sin(a0) * radiusTop, height,
                                          std::cos(a0) * radiusTop);
        const Vec3 t1 = baseCenter + Vec3(std::sin(a1) * radiusTop, height,
                                          std::cos(a1) * radiusTop);
        AddQuad(b0, b1, t1, t0, true);
        if (caps) {
            if (radiusTop > 0.0001f) {
                AddTriangle(Vec3(baseCenter.x, baseCenter.y + height,
                                 baseCenter.z), t0, t1);
            }
            if (radiusBottom > 0.0001f) {
                AddTriangle(baseCenter, b1, b0);
            }
        }
    }
}

void MeshBuilder::AddCone(const Vec3& baseCenter, float radius, float height,
                          int segments, float yaw)
{
    AddCylinder(baseCenter, radius, 0.0f, height, segments, yaw, true);
}

void MeshBuilder::AddSphere(const Vec3& center, float radius, int segments,
                            int rings)
{
    segments = ClampInt(segments, 3, 32);
    rings = ClampInt(rings, 2, 16);
    const float latStep = PI / static_cast<float>(rings);
    const float lonStep = 2.0f * PI / static_cast<float>(segments);

    for (int r = 0; r < rings; ++r) {
        const float lat0 = -PI * 0.5f + static_cast<float>(r) * latStep;
        const float lat1 = lat0 + latStep;
        for (int s = 0; s < segments; ++s) {
            const float lon0 = static_cast<float>(s) * lonStep;
            const float lon1 = lon0 + lonStep;
            auto point = [&](float lat, float lon) {
                return center + Vec3(std::cos(lat) * std::sin(lon) * radius,
                                     std::sin(lat) * radius,
                                     std::cos(lat) * std::cos(lon) * radius);
            };
            const Vec3 p00 = point(lat0, lon0);
            const Vec3 p10 = point(lat0, lon1);
            const Vec3 p11 = point(lat1, lon1);
            const Vec3 p01 = point(lat1, lon0);
            AddQuad(p00, p10, p11, p01, true);
        }
    }
}

void MeshBuilder::AddPlane(const Vec3& center, float halfX, float halfZ,
                           bool up)
{
    if (up) {
        AddQuad(Vec3(center.x - halfX, center.y, center.z + halfZ),
                Vec3(center.x + halfX, center.y, center.z + halfZ),
                Vec3(center.x + halfX, center.y, center.z - halfZ),
                Vec3(center.x - halfX, center.y, center.z - halfZ));
    } else {
        AddQuad(Vec3(center.x - halfX, center.y, center.z - halfZ),
                Vec3(center.x + halfX, center.y, center.z - halfZ),
                Vec3(center.x + halfX, center.y, center.z + halfZ),
                Vec3(center.x - halfX, center.y, center.z + halfZ));
    }
}

void MeshBuilder::AddWall(const Vec3& center, float halfWidth, float halfHeight,
                          float yaw)
{
    const Vec3 right(std::cos(yaw) * halfWidth, 0.0f,
                     -std::sin(yaw) * halfWidth);
    const Vec3 up(0.0f, halfHeight, 0.0f);
    const Vec3 p0 = center - right - up;
    const Vec3 p1 = center + right - up;
    const Vec3 p2 = center + right + up;
    const Vec3 p3 = center - right + up;
    AddQuad(p0, p1, p2, p3, true);
}

MeshData MeshBuilder::Finish(const std::string& name)
{
    m_data.name = name;
    for (auto& part : m_data.parts) {
        if (part.name.empty()) {
            part.name = "default";
        }
    }
    m_data.parts.erase(
        std::remove_if(m_data.parts.begin(), m_data.parts.end(),
                       [](const MeshPartData& part) {
                           return part.indices.empty();
                       }),
        m_data.parts.end());
    m_part = nullptr;
    return std::move(m_data);
}

namespace {

bool ParseColorToken(const std::string& token, Color& out)
{
    if (token.size() > 2 && token[0] == '0' &&
        (token[1] == 'x' || token[1] == 'X')) {
        const unsigned long value = std::strtoul(token.c_str(), nullptr, 16);
        out = ColorFromHex(static_cast<unsigned int>(value));
        return true;
    }
    if (!token.empty() && token[0] == '#') {
        const unsigned long value = std::strtoul(token.c_str() + 1, nullptr, 16);
        out = ColorFromHex(static_cast<unsigned int>(value));
        return true;
    }
    return false;
}

/**
 * @brief 把材质名称解析为 `SurfaceMaterial` 编号。
 * @param [IN] key 已转为小写的名称。
 * @param [OUT] material 材质编号。
 * @return 识别成功返回 true。
 */
bool ParseSurfaceName(const std::string& key, int& material)
{
    using M = SurfaceMaterial;
    if (key == "plaster" || key == "concrete") {
        material = static_cast<int>(M::PLASTER);
    } else if (key == "wood") {
        material = static_cast<int>(M::WOOD);
    } else if (key == "metal" || key == "steel") {
        material = static_cast<int>(M::METAL_MATTE);
    } else if (key == "chrome" || key == "brass") {
        material = static_cast<int>(M::METAL_POLISHED);
    } else if (key == "glass") {
        material = static_cast<int>(M::GLASS);
    } else if (key == "plastic") {
        material = static_cast<int>(M::PLASTIC);
    } else if (key == "cardboard" || key == "paper") {
        material = static_cast<int>(M::CARDBOARD);
    } else if (key == "cloth" || key == "fabric") {
        material = static_cast<int>(M::FABRIC);
    } else if (key == "ceramic" || key == "enamel") {
        material = static_cast<int>(M::CERAMIC);
    } else if (key == "rubber" || key == "asphalt") {
        material = static_cast<int>(M::RUBBER);
    } else if (key == "liquid" || key == "water") {
        material = static_cast<int>(M::LIQUID);
    } else if (key == "emissive" || key == "lamp") {
        material = static_cast<int>(M::EMISSIVE);
    } else {
        return false;
    }
    return true;
}

} // namespace

int ParseMeshText(const std::string& text, std::vector<MeshData>& out)
{
    std::istringstream stream(text);
    std::string rawLine;
    MeshBuilder builder;
    bool inMesh = false;
    int meshCount = 0;
    std::string meshName;

    auto ensurePart = [&]() {
        if (!builder.HasPart()) {
            builder.BeginPart("default", Vec3());
        }
    };

    while (std::getline(stream, rawLine)) {
        std::string line = Trim(rawLine);
        if (line.empty() || line[0] == '#') {
            continue;
        }
        if (line.size() >= 2 && line[0] == '/' && line[1] == '/') {
            continue;
        }

        std::istringstream tokens(line);
        std::string command;
        tokens >> command;
        command = Lower(command);

        if (command == "mesh") {
            std::string name;
            tokens >> name;
            builder = MeshBuilder();
            meshName = name;
            inMesh = true;
            builder.BeginPart("default", Vec3());
            continue;
        }
        if (!inMesh) {
            continue;
        }
        if (command == "endmesh") {
            out.push_back(builder.Finish(meshName));
            ++meshCount;
            inMesh = false;
            continue;
        }
        if (command == "part") {
            std::string name;
            float px = 0.0f;
            float py = 0.0f;
            float pz = 0.0f;
            tokens >> name >> px >> py >> pz;
            builder.BeginPart(name, Vec3(px, py, pz));
            continue;
        }
        if (command == "endpart") {
            ensurePart();
            continue;
        }
        if (command == "mat" || command == "color") {
            std::string token;
            tokens >> token;
            Color color;
            if (ParseColorToken(token, color)) {
                builder.SetColor(color);
            } else {
                float r = 0.7f;
                float g = 0.7f;
                float b = 0.7f;
                r = static_cast<float>(std::atof(token.c_str()));
                tokens >> g >> b;
                builder.SetColor(Color(r, g, b, 1.0f));
            }
            continue;
        }
        if (command == "pattern") {
            int pattern = 0;
            tokens >> pattern;
            builder.SetPattern(pattern);
            continue;
        }
        if (command == "surface" || command == "material") {
            // 支持数字与名称两种写法：`surface 3` / `surface glass`。
            std::string token;
            tokens >> token;
            const std::string key = Lower(token);
            int material = 0;
            if (!ParseSurfaceName(key, material)) {
                material = std::atoi(token.c_str());
            }
            builder.SetMaterial(material);
            continue;
        }
        if (command == "box") {
            float cx = 0.0f;
            float cy = 0.0f;
            float cz = 0.0f;
            float sx = 1.0f;
            float sy = 1.0f;
            float sz = 1.0f;
            float yaw = 0.0f;
            tokens >> cx >> cy >> cz >> sx >> sy >> sz;
            if (!(tokens >> yaw)) {
                yaw = 0.0f;
            }
            ensurePart();
            builder.AddBox(Vec3(cx, cy, cz), Vec3(sx * 0.5f, sy * 0.5f, sz * 0.5f),
                           yaw * PI / 180.0f);
            continue;
        }
        if (command == "bevel") {
            float cx = 0.0f;
            float cy = 0.0f;
            float cz = 0.0f;
            float sx = 1.0f;
            float sy = 1.0f;
            float sz = 1.0f;
            float bevel = 0.25f;
            float yaw = 0.0f;
            tokens >> cx >> cy >> cz >> sx >> sy >> sz >> bevel >> yaw;
            ensurePart();
            builder.AddBeveledBox(Vec3(cx, cy, cz),
                                  Vec3(sx * 0.5f, sy * 0.5f, sz * 0.5f),
                                  bevel, yaw * PI / 180.0f);
            continue;
        }
        if (command == "cyl") {
            float cx = 0.0f;
            float cy = 0.0f;
            float cz = 0.0f;
            float radius = 0.5f;
            float radiusTop = 0.5f;
            float height = 1.0f;
            int segments = 8;
            float yaw = 0.0f;
            tokens >> cx >> cy >> cz >> radius >> radiusTop >> height >>
                segments >> yaw;
            ensurePart();
            builder.AddCylinder(Vec3(cx, cy, cz), radius, radiusTop, height,
                                segments, yaw * PI / 180.0f);
            continue;
        }
        if (command == "cone") {
            float cx = 0.0f;
            float cy = 0.0f;
            float cz = 0.0f;
            float radius = 0.5f;
            float height = 1.0f;
            int segments = 8;
            float yaw = 0.0f;
            tokens >> cx >> cy >> cz >> radius >> height >> segments >> yaw;
            ensurePart();
            builder.AddCone(Vec3(cx, cy, cz), radius, height, segments,
                            yaw * PI / 180.0f);
            continue;
        }
        if (command == "sphere") {
            float cx = 0.0f;
            float cy = 0.0f;
            float cz = 0.0f;
            float radius = 0.5f;
            int segments = 8;
            int rings = 5;
            tokens >> cx >> cy >> cz >> radius >> segments >> rings;
            ensurePart();
            builder.AddSphere(Vec3(cx, cy, cz), radius, segments, rings);
            continue;
        }
        if (command == "plane") {
            float cx = 0.0f;
            float cy = 0.0f;
            float cz = 0.0f;
            float halfX = 1.0f;
            float halfZ = 1.0f;
            tokens >> cx >> cy >> cz >> halfX >> halfZ;
            ensurePart();
            builder.AddPlane(Vec3(cx, cy, cz), halfX, halfZ);
            continue;
        }
        if (command == "wall") {
            float cx = 0.0f;
            float cy = 0.0f;
            float cz = 0.0f;
            float halfWidth = 1.0f;
            float halfHeight = 1.0f;
            float yaw = 0.0f;
            tokens >> cx >> cy >> cz >> halfWidth >> halfHeight >> yaw;
            ensurePart();
            builder.AddWall(Vec3(cx, cy, cz), halfWidth, halfHeight,
                            yaw * PI / 180.0f);
            continue;
        }
        if (command == "quad" || command == "tri") {
            const int count = command == "quad" ? 4 : 3;
            Vec3 p[4];
            bool ok = true;
            for (int i = 0; i < count; ++i) {
                if (!(tokens >> p[i].x >> p[i].y >> p[i].z)) {
                    ok = false;
                }
            }
            if (!ok) {
                continue;
            }
            ensurePart();
            if (count == 3) {
                builder.AddTriangle(p[0], p[1], p[2], true);
            } else {
                builder.AddQuad(p[0], p[1], p[2], p[3], true);
            }
            continue;
        }
    }

    if (inMesh) {
        out.push_back(builder.Finish(meshName));
        ++meshCount;
    }
    return meshCount;
}

void MeshLibrary::Initialize(ID3D11Device* device)
{
    m_device = device;
}

int MeshLibrary::AddText(const std::string& text)
{
    std::vector<MeshData> parsed;
    const int count = ParseMeshText(text, parsed);
    for (MeshData& data : parsed) {
        m_cpu[data.name] = std::move(data);
    }
    return count;
}

bool MeshLibrary::Upload(const MeshData& data, Mesh& out)
{
    if (m_device == nullptr) {
        return false;
    }
    out.name = data.name;
    out.boundsMin = data.boundsMin;
    out.boundsMax = data.boundsMax;
    out.triangleCount = data.triangleCount;
    out.parts.clear();
    out.parts.reserve(data.parts.size());

    for (const MeshPartData& source : data.parts) {
        if (source.indices.empty() || source.vertices.empty()) {
            continue;
        }
        MeshPart part;
        part.name = source.name;
        part.pivot = source.pivot;
        part.indexCount = static_cast<UINT>(source.indices.size());

        D3D11_BUFFER_DESC vbDesc = {};
        vbDesc.Usage = D3D11_USAGE_IMMUTABLE;
        vbDesc.ByteWidth = static_cast<UINT>(source.vertices.size() *
                                             sizeof(MeshVertex));
        vbDesc.BindFlags = D3D11_BIND_VERTEX_BUFFER;
        D3D11_SUBRESOURCE_DATA vbData = {};
        vbData.pSysMem = source.vertices.data();
        if (FAILED(m_device->CreateBuffer(&vbDesc, &vbData,
                                          part.vertexBuffer.GetAddressOf()))) {
            LogError("MeshLibrary: VB creation failed for %s/%s",
                     data.name.c_str(), source.name.c_str());
            return false;
        }

        D3D11_BUFFER_DESC ibDesc = {};
        ibDesc.Usage = D3D11_USAGE_IMMUTABLE;
        ibDesc.ByteWidth = static_cast<UINT>(source.indices.size() *
                                             sizeof(std::uint32_t));
        ibDesc.BindFlags = D3D11_BIND_INDEX_BUFFER;
        D3D11_SUBRESOURCE_DATA ibData = {};
        ibData.pSysMem = source.indices.data();
        if (FAILED(m_device->CreateBuffer(&ibDesc, &ibData,
                                          part.indexBuffer.GetAddressOf()))) {
            LogError("MeshLibrary: IB creation failed for %s/%s",
                     data.name.c_str(), source.name.c_str());
            return false;
        }

        out.parts.push_back(std::move(part));
    }
    return !out.parts.empty();
}

const Mesh* MeshLibrary::Get(const std::string& name)
{
    const auto gpuIt = m_gpu.find(name);
    if (gpuIt != m_gpu.end()) {
        return gpuIt->second.get();
    }
    const auto cpuIt = m_cpu.find(name);
    if (cpuIt == m_cpu.end()) {
        LogWarn("MeshLibrary: missing mesh '%s'", name.c_str());
        return Placeholder();
    }
    std::unique_ptr<Mesh> mesh(new Mesh());
    if (!Upload(cpuIt->second, *mesh)) {
        return Placeholder();
    }
    const Mesh* result = mesh.get();
    m_gpu[name] = std::move(mesh);
    return result;
}

const MeshData* MeshLibrary::GetData(const std::string& name) const
{
    const auto it = m_cpu.find(name);
    return it == m_cpu.end() ? nullptr : &it->second;
}

const Mesh* MeshLibrary::AddMesh(MeshData&& data, const std::string& name)
{
    if (name.empty()) {
        return Placeholder();
    }
    data.name = name;
    const auto existing = m_gpu.find(name);
    if (existing != m_gpu.end()) {
        return existing->second.get();
    }
    std::unique_ptr<Mesh> mesh(new Mesh());
    MeshData copy = data;
    if (!Upload(copy, *mesh)) {
        return Placeholder();
    }
    const Mesh* result = mesh.get();
    m_gpu[name] = std::move(mesh);
    return result;
}

std::vector<std::string> MeshLibrary::Names() const
{
    std::vector<std::string> names;
    names.reserve(m_cpu.size());
    for (const auto& entry : m_cpu) {
        names.push_back(entry.first);
    }
    std::sort(names.begin(), names.end());
    return names;
}

const Mesh* MeshLibrary::Placeholder()
{
    if (m_placeholder) {
        return m_placeholder.get();
    }
    MeshData data;
    MeshBuilder builder;
    builder.BeginPart("default", Vec3());
    builder.SetColor(Color(1.0f, 0.0f, 1.0f, 1.0f));
    builder.AddBox(Vec3(0.0f, 0.5f, 0.0f), Vec3(0.25f, 0.25f, 0.25f));
    data = builder.Finish("_MISSING");
    m_placeholder.reset(new Mesh());
    if (!Upload(data, *m_placeholder)) {
        m_placeholder.reset(new Mesh());
    }
    return m_placeholder.get();
}

} // namespace fc
