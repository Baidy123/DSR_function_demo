#include "Game_Renderer.hpp"

#include "Shared_Log.hpp"
#include "Shared_Math.hpp"
#include "World_Collision.hpp"

#include <algorithm>
#include <cmath>

namespace fc {

namespace {

const Color WHITE = Color(1.0f, 1.0f, 1.0f, 1.0f);

Color FlickerColor(const LightDef& light, float time)
{
    float intensity = light.intensity;
    if (light.flicker > 0.0f) {
        const float n = std::sin(time * 11.0f + light.position.x * 3.1f) *
                        std::sin(time * 4.3f + light.position.z * 1.7f);
        intensity *= 1.0f - light.flicker * 0.5f * (0.5f + 0.5f * n);
    }
    return Color(light.color.r * intensity, light.color.g * intensity,
                 light.color.b * intensity, 1.0f);
}

Mat4 TransformFor(const Vec3& position, float yaw, float scale)
{
    return Mat4::Scale(Vec3(scale, scale, scale)) *
           Mat4::RotationY(yaw) * Mat4::Translation(position);
}

} // namespace

void UpdateCameraMatrices(CameraRuntime& camera, float aspect)
{
    camera.view = Mat4::LookAt(camera.current.eye, camera.current.target,
                               camera.current.up);
    camera.projection = Mat4::Perspective(
        camera.current.fovDegrees * PI / 180.0f, aspect, 0.08f, 90.0f);
    camera.viewProjection = camera.view * camera.projection;
}

bool GameRenderer::Initialize(RenderDevice* device, MeshLibrary* meshes,
                              CharacterLibrary* characters)
{
    m_device = device;
    m_meshes = meshes;
    m_characters = characters;
    if (m_device == nullptr || m_meshes == nullptr || m_characters == nullptr) {
        return false;
    }

    MeshBuilder cubeBuilder;
    cubeBuilder.BeginPart("default", Vec3());
    cubeBuilder.SetColor(WHITE);
    cubeBuilder.SetPattern(8);
    cubeBuilder.AddBox(Vec3(0.0f, 0.0f, 0.0f), Vec3(0.5f, 0.5f, 0.5f));
    m_cube = m_meshes->AddMesh(cubeBuilder.Finish("FX_CUBE"), "FX_CUBE");

    MeshBuilder shadowBuilder;
    shadowBuilder.BeginPart("default", Vec3());
    shadowBuilder.SetColor(Color(0.02f, 0.02f, 0.03f, 1.0f));
    shadowBuilder.SetPattern(0);
    const int segments = 16;
    for (int i = 0; i < segments; ++i) {
        const float a0 = static_cast<float>(i) / segments * 2.0f * PI;
        const float a1 = static_cast<float>(i + 1) / segments * 2.0f * PI;
        shadowBuilder.AddTriangle(Vec3(0.0f, 0.0f, 0.0f),
                                  Vec3(std::sin(a0), 0.0f, std::cos(a0)),
                                  Vec3(std::sin(a1), 0.0f, std::cos(a1)));
    }
    m_shadowMesh = m_meshes->AddMesh(shadowBuilder.Finish("FX_SHADOW"),
                                     "FX_SHADOW");

    MeshBuilder sphereBuilder;
    sphereBuilder.BeginPart("default", Vec3());
    sphereBuilder.SetColor(WHITE);
    sphereBuilder.SetPattern(8);
    sphereBuilder.AddSphere(Vec3(0.0f, 0.0f, 0.0f), 0.5f, 8, 5);
    m_sphere = m_meshes->AddMesh(sphereBuilder.Finish("FX_SPHERE"), "FX_SPHERE");
    return true;
}

bool GameRenderer::LoadScene(const SceneDef& scene, CollisionWorld& collision)
{
    m_props.clear();
    collision.Clear();

    MeshBuilder builder;
    builder.BeginPart("room", Vec3());
    for (const RoomBlock& block : scene.blocks) {
        builder.SetColor(block.color);
        builder.SetPattern(block.pattern);
        builder.AddBox(block.center, block.half);
        if (block.solid) {
            collision.AddBox(
                MakeAABB(block.center, block.half));
        }
    }
    const MeshData data = builder.Finish("SCENE_ROOM");
    const std::string roomName =
        std::string("SCENE_ROOM_") + std::to_string(static_cast<int>(scene.id));
    m_roomMesh = m_meshes->AddMesh(MeshData(data), roomName);

    for (const PropDef& def : scene.props) {
        const Mesh* mesh = m_meshes->Get(def.mesh);
        if (mesh == nullptr || !mesh->IsValid()) {
            LogWarn("Scene %s: missing prop mesh %s",
                    scene.displayName.c_str(), def.mesh.c_str());
            continue;
        }
        PropInstance prop;
        prop.mesh = mesh;
        prop.position = def.position;
        prop.yaw = def.yawDegrees * PI / 180.0f;
        prop.scale = def.scale;
        prop.tint = def.tint;

        const Vec3 halfExtent((mesh->boundsMax.x - mesh->boundsMin.x) * 0.5f,
                              (mesh->boundsMax.y - mesh->boundsMin.y) * 0.5f,
                              (mesh->boundsMax.z - mesh->boundsMin.z) * 0.5f);
        Vec3 colliderHalf = def.colliderHalf;
        if (colliderHalf.x <= 0.0f || colliderHalf.y <= 0.0f ||
            colliderHalf.z <= 0.0f) {
            colliderHalf = halfExtent;
        }
        if (std::fabs(prop.yaw) > 0.001f) {
            // 旋转道具用包围盒的 XZ 最大半径近似，避免旋转后穿模。
            const float radiusXZ = std::sqrt(colliderHalf.x * colliderHalf.x +
                                             colliderHalf.z * colliderHalf.z);
            colliderHalf.x = radiusXZ;
            colliderHalf.z = radiusXZ;
        }
        colliderHalf *= prop.scale;
        const Vec3 center = def.position + def.colliderOffset +
                            Vec3(0.0f, colliderHalf.y, 0.0f);
        prop.bounds = MakeAABB(center, colliderHalf);
        prop.solid = def.solid;
        if (def.solid) {
            collision.AddBox(prop.bounds);
        }
        m_props.push_back(prop);
    }
    LogInfo("Scene '%s' loaded: %zu props, %zu colliders",
            scene.displayName.c_str(), m_props.size(),
            static_cast<size_t>(collision.Count()));
    return true;
}

void GameRenderer::DrawShadow(const Vec3& position, float radius, float alpha)
{
    if (m_shadowMesh == nullptr) {
        return;
    }
    const Mat4 world = Mat4::Scale(Vec3(radius, 1.0f, radius)) *
                       Mat4::Translation(Vec3(position.x, 0.021f, position.z));
    m_device->DrawMesh(*m_shadowMesh, world,
                       Color(1.0f, 1.0f, 1.0f, alpha), Color(), true);
}

void GameRenderer::DrawScene(const SceneDef& scene, const Player& player,
                             const std::vector<NpcInstance>& npcs,
                             const std::vector<Enemy>& enemies,
                             const std::vector<Bullet>& bullets,
                             const std::vector<Particle>& particles,
                             const std::vector<Pickup>& pickups,
                             const CameraRuntime& camera,
                             const std::vector<LightDef>& lights, float time)
{
    if (m_device == nullptr || m_roomMesh == nullptr) {
        return;
    }

    SceneFrame frame;
    frame.viewProjection = camera.viewProjection;
    frame.cameraPosition = camera.current.eye;
    frame.ambient = scene.ambient;
    frame.fogColor = scene.fogColor;
    frame.fogNear = scene.fogNear;
    frame.fogFar = scene.fogFar;
    frame.fogDensity = scene.fogDensity;
    frame.time = time;
    frame.lightCount = 0;
    for (const LightDef& light : lights) {
        if (frame.lightCount >= MAX_POINT_LIGHTS) {
            break;
        }
        const Color color = FlickerColor(light, time);
        if (color.r + color.g + color.b <= 0.001f) {
            continue;
        }
        PointLight& target = frame.lights[frame.lightCount++];
        target.position = light.position;
        target.range = light.range;
        target.color = light.color;
        target.intensity = light.intensity;
        if (light.flicker > 0.0f) {
            target.intensity *= 1.0f - light.flicker * 0.5f *
                                            (0.5f + 0.5f * std::sin(time * 11.0f +
                                                                    light.position.x));
        }
    }

    m_device->BeginScene3D(frame);

    m_device->DrawMesh(*m_roomMesh, Mat4::Identity(), WHITE);

    DrawShadow(player.position, 0.42f, 0.55f);
    for (const NpcInstance& npc : npcs) {
        if (npc.visible) {
            DrawShadow(npc.position, 0.4f, 0.5f);
        }
    }
    for (const Enemy& enemy : enemies) {
        if (!enemy.dead) {
            DrawShadow(enemy.position, 0.38f, 0.45f);
        }
    }

    for (const PropInstance& prop : m_props) {
        if (prop.mesh == nullptr || prop.hidden) {
            continue;
        }
        const Mat4 world = Mat4::Scale(Vec3(prop.scale, prop.scale, prop.scale)) *
                           Mat4::RotationY(prop.yaw) *
                           Mat4::Translation(prop.position);
        m_device->DrawMesh(*prop.mesh, world, prop.tint);
    }

    // NPC
    for (const NpcInstance& npc : npcs) {
        if (!npc.visible) {
            continue;
        }
        const Mesh* mesh = m_characters->Get(npc.id);
        if (mesh == nullptr) {
            continue;
        }
        CharacterAnim anim;
        anim.time = time;
        anim.walking = false;
        anim.aiming = false;
        const Mat4 base = Mat4::RotationY(npc.yaw) *
                          Mat4::Translation(npc.position);
        m_characters->Draw(*m_device, *mesh, base, anim, WHITE);
    }

    // 敌人
    for (const Enemy& enemy : enemies) {
        const Mesh* mesh = m_characters->Get(enemy.character);
        if (mesh == nullptr) {
            continue;
        }
        CharacterAnim anim;
        anim.time = enemy.time;
        anim.walkPhase = enemy.walkPhase;
        anim.walking = enemy.moving;
        anim.aiming = enemy.aiming && !enemy.dead;
        anim.aimPitch = enemy.aimPitch;
        anim.hitFlash = enemy.hitFlash;
        if (enemy.dead) {
            anim.alpha = Clamp(enemy.deathTimer / 0.6f, 0.0f, 1.0f);
        }
        const Mat4 base = Mat4::RotationY(enemy.yaw) *
                          Mat4::Translation(enemy.position);
        const Color tint = enemy.dead ? Color(0.6f, 0.55f, 0.55f, 1.0f) : WHITE;
        m_characters->Draw(*m_device, *mesh, base, anim, tint);
    }

    // 玩家
    {
        const Mesh* mesh = m_characters->Get(CharacterId::PLAYER);
        if (mesh != nullptr) {
            CharacterAnim anim;
            anim.time = player.time;
            anim.walkPhase = player.walkPhase;
            anim.walking = player.moving;
            anim.aiming = player.aiming;
            anim.aimPitch = player.aimPitch;
            anim.recoil = player.recoil;
            anim.hitFlash = player.hitFlash;
            const Mat4 base = Mat4::RotationY(player.yaw) *
                              Mat4::Translation(player.position);
            m_characters->Draw(*m_device, *mesh, base, anim, WHITE);
        }
        if (player.recoil > 0.02f) {
            const Vec3 muzzle = MuzzlePosition(player);
            m_device->DrawMesh(*m_sphere,
                               Mat4::Scale(Vec3(0.16f, 0.16f, 0.16f)) *
                                   Mat4::Translation(muzzle),
                               Color(1.0f, 0.85f, 0.5f, 1.0f),
                               Color(0.9f, 0.6f, 0.2f, 1.0f));
        }
    }

    for (const Bullet& bullet : bullets) {
        if (bullet.active) {
            DrawBullet(bullet);
        }
    }
    for (const Pickup& pickup : pickups) {
        if (pickup.active) {
            DrawPickup(pickup);
        }
    }
    for (const Particle& particle : particles) {
        if (particle.life > 0.0f) {
            DrawParticle(particle);
        }
    }

    m_device->EndScene3D();
}

Vec3 GameRenderer::MuzzlePosition(const Player& player) const
{
    const Vec3 forward(std::sin(player.aimYaw), 0.0f, std::cos(player.aimYaw));
    return player.position + Vec3(0.0f, 1.32f, 0.0f) + forward * 0.62f;
}

void GameRenderer::DrawBullet(const Bullet& bullet) const
{
    const float yaw = YawFromDirection(bullet.direction);
    const Mat4 world = Mat4::Scale(Vec3(0.05f, 0.05f, 0.32f)) *
                       Mat4::RotationY(yaw) * Mat4::Translation(bullet.position);
    const Color color = bullet.hostile ? Color(1.0f, 0.28f, 0.34f, 0.95f)
                                       : Color(1.0f, 0.82f, 0.45f, 0.95f);
    m_device->DrawMesh(*m_cube, world, color,
                       Color(color.r, color.g, color.b, 1.0f), false);
}

void GameRenderer::DrawPickup(const Pickup& pickup) const
{
    const float y = pickup.position.y + 0.28f + std::sin(pickup.bob) * 0.05f;
    Color color(0.85f, 0.85f, 0.8f, 1.0f);
    float size = 0.14f;
    switch (pickup.type) {
    case PickupType::AMMO: color = Color(0.95f, 0.75f, 0.35f, 1.0f); break;
    case PickupType::MEDKIT: color = Color(0.9f, 0.92f, 0.85f, 1.0f); break;
    case PickupType::MONEY: color = Color(0.95f, 0.8f, 0.3f, 1.0f); break;
    case PickupType::PART: color = Color(0.45f, 0.9f, 0.85f, 1.0f); break;
    }
    const Mat4 world = Mat4::Scale(Vec3(size, size, size)) *
                       Mat4::RotationY(pickup.bob) *
                       Mat4::Translation(Vec3(pickup.position.x, y,
                                              pickup.position.z));
    m_device->DrawMesh(*m_cube, world, color, color, false);
}

void GameRenderer::DrawParticle(const Particle& particle) const
{
    const float t = Clamp(particle.life / std::max(0.001f, particle.maxLife),
                          0.0f, 1.0f);
    Color color = particle.color;
    color.a *= t;
    const Mat4 world =
        Mat4::Scale(Vec3(particle.size, particle.size, particle.size)) *
        Mat4::Translation(particle.position);
    m_device->DrawMesh(*m_cube, world, color, color, false);
}

bool GameRenderer::WorldToScreen(const CameraRuntime& camera, const Vec3& world,
                                 Vec2& screen) const
{
    const Mat4& m = camera.viewProjection;
    const float x = world.x * m.m[0] + world.y * m.m[4] + world.z * m.m[8] + m.m[12];
    const float y = world.x * m.m[1] + world.y * m.m[5] + world.z * m.m[9] + m.m[13];
    const float w = world.x * m.m[3] + world.y * m.m[7] + world.z * m.m[11] + m.m[15];
    if (w <= 0.0001f) {
        return false;
    }
    const float ndcX = x / w;
    const float ndcY = y / w;
    screen.x = (ndcX * 0.5f + 0.5f) * static_cast<float>(INTERNAL_WIDTH);
    screen.y = (1.0f - (ndcY * 0.5f + 0.5f)) * static_cast<float>(INTERNAL_HEIGHT);
    return true;
}

void GameRenderer::DrawLightGlows(const CameraRuntime& camera,
                                  const std::vector<LightDef>& lights, float time,
                                  const Player& player, bool alarm)
{
    if (m_device == nullptr) {
        return;
    }
    SpriteBatch& batch = m_device->Batch();
    const Texture& glow = m_device->Glow();

    for (const LightDef& light : lights) {
        Vec2 screen;
        if (!WorldToScreen(camera, light.position, screen)) {
            continue;
        }
        const float distance = Length(light.position - camera.current.eye);
        float strength = light.intensity;
        if (light.flicker > 0.0f) {
            strength *= 1.0f - light.flicker * 0.4f *
                                    (0.5f + 0.5f * std::sin(time * 13.0f +
                                                            light.position.z));
        }
        if (strength <= 0.01f) {
            continue;
        }
        const float size = Clamp(light.range * 26.0f / std::max(distance, 0.6f),
                                 8.0f, 120.0f);
        Color color(light.color.r, light.color.g, light.color.b,
                    Clamp(strength * 0.22f, 0.0f, 0.6f));
        batch.DrawTexture(glow, screen.x - size * 0.5f, screen.y - size * 0.5f,
                          size, size, color, true, false);
    }

    if (player.recoil > 0.02f) {
        Vec2 screen;
        if (WorldToScreen(camera, MuzzlePosition(player), screen)) {
            batch.DrawTexture(glow, screen.x - 14.0f, screen.y - 14.0f, 28.0f,
                              28.0f, Color(1.0f, 0.8f, 0.45f, 0.55f), true,
                              false);
        }
    }

    if (alarm) {
        Vec2 screen;
        if (WorldToScreen(camera, Vec3(11.0f, 2.8f, 0.0f), screen)) {
            const float pulse = 0.35f + 0.35f * std::sin(time * 7.0f);
            batch.DrawTexture(glow, screen.x - 60.0f, screen.y - 60.0f, 120.0f,
                              120.0f, Color(1.0f, 0.15f, 0.2f, pulse * 0.4f),
                              true, false);
        }
    }
}

bool GameRenderer::BuildPortraits()
{
    if (m_portraitsReady || m_device == nullptr) {
        return m_portraitsReady;
    }

    CameraRuntime camera;
    camera.current.eye = Vec3(0.42f, 1.62f, 0.82f);
    camera.current.target = Vec3(0.0f, 1.5f, 0.0f);
    camera.current.fovDegrees = 38.0f;
    UpdateCameraMatrices(camera, 1.0f);

    for (int i = 0; i < 6; ++i) {
        if (!m_device->CreateRenderTarget(80, 80, true, m_portraits[i])) {
            return false;
        }
        m_device->BeginRenderTarget(m_portraits[i],
                                    Color(0.05f, 0.045f, 0.05f, 1.0f));

        SceneFrame frame;
        frame.viewProjection = camera.viewProjection;
        frame.cameraPosition = camera.current.eye;
        frame.ambient = Color(0.20f, 0.22f, 0.26f, 1.0f);
        frame.fogColor = Color(0.05f, 0.045f, 0.05f, 1.0f);
        frame.fogNear = 20.0f;
        frame.fogFar = 40.0f;
        frame.fogDensity = 0.0f;
        frame.lightCount = 2;
        frame.lights[0].position = Vec3(0.7f, 1.9f, 1.1f);
        frame.lights[0].range = 4.0f;
        frame.lights[0].color = Color(1.0f, 0.72f, 0.45f, 1.0f);
        frame.lights[0].intensity = 2.6f;
        frame.lights[1].position = Vec3(-0.9f, 1.6f, -0.4f);
        frame.lights[1].range = 3.5f;
        frame.lights[1].color = Color(0.35f, 0.6f, 0.95f, 1.0f);
        frame.lights[1].intensity = 1.1f;
        m_device->BeginScene3D(frame);

        const CharacterId id = static_cast<CharacterId>(i);
        const Mesh* mesh = m_characters->Get(id);
        if (mesh != nullptr) {
            CharacterAnim anim;
            anim.time = 0.0f;
            anim.aiming = false;
            const Mat4 base = Mat4::RotationY(-0.42f) *
                              Mat4::Translation(Vec3(0.0f, 0.0f, 0.0f));
            m_characters->Draw(*m_device, *mesh, base, anim, WHITE);
        }
        m_device->EndScene3D();
    }
    m_device->BeginInternalTarget();
    m_portraitsReady = true;
    return true;
}

const Texture* GameRenderer::Portrait(CharacterId id) const
{
    const int index = static_cast<int>(id);
    if (!m_portraitsReady || index < 0 || index >= 6) {
        return nullptr;
    }
    return &m_portraits[index].colorView;
}

void GameRenderer::HidePropsByMesh(const std::string& meshName)
{
    for (PropInstance& prop : m_props) {
        if (prop.mesh != nullptr && prop.mesh->name == meshName) {
            prop.hidden = true;
        }
    }
}

} // namespace fc
