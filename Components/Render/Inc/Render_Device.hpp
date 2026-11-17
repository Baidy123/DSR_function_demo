#ifndef __RENDER_DEVICE_HPP__
#define __RENDER_DEVICE_HPP__

#include "Render_Mesh.hpp"
#include "Render_SpriteBatch.hpp"
#include "Render_Texture.hpp"
#include "Shared_Types.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <d3d11.h>

#include <memory>
#include <string>
#include <vector>

namespace fc {

/** @brief 单帧最多支持的点光源数量。 */
constexpr int MAX_POINT_LIGHTS = 8;

/**
 * @brief 点光源参数。
 */
struct PointLight {
    Vec3 position;
    float range = 6.0f;
    Color color{1.0f, 0.8f, 0.5f, 1.0f};
    float intensity = 1.0f;
};

/**
 * @brief 每帧 3D 渲染常量。
 */
struct SceneFrame {
    Mat4 viewProjection;
    Vec3 cameraPosition;
    Color ambient{0.10f, 0.12f, 0.16f, 1.0f};
    Color fogColor{0.03f, 0.04f, 0.06f, 1.0f};
    float fogNear = 6.0f;
    float fogFar = 40.0f;
    float fogDensity = 0.85f;
    float time = 0.0f;
    PointLight lights[MAX_POINT_LIGHTS];
    int lightCount = 0;
};

/**
 * @brief 离屏渲染目标（颜色 + 可选深度 + SRV）。
 */
struct RenderTarget {
    int width = 0;
    int height = 0;
    ComPtr<ID3D11Texture2D> colorTexture;
    ComPtr<ID3D11RenderTargetView> rtv;
    ComPtr<ID3D11ShaderResourceView> srv;
    ComPtr<ID3D11Texture2D> depthTexture;
    ComPtr<ID3D11DepthStencilView> dsv;
    Texture colorView;
};

/**
 * @brief Direct3D 11 渲染设备。
 *
 * 渲染分为三步：
 * 1. `BeginFrame` 绑定 480×270 的内部颜色/深度目标并清屏；
 * 2. 玩法层通过 `SceneRenderer` 绘制低多面体场景，再用 SpriteBatch 叠加 UI；
 * 3. `Present` 执行低清后处理（抖动、扫描线、暗角、色差）并整数倍放大到窗口。
 */
class RenderDevice {
public:
    RenderDevice() = default;
    ~RenderDevice();

    /**
     * @brief 初始化设备、交换链与内部渲染目标。
     * @param [IN] hwnd 窗口句柄。
     * @param [IN] width 客户区宽度。
     * @param [IN] height 客户区高度。
     * @return 成功返回 true。
     */
    bool Initialize(HWND hwnd, int width, int height);

    /**
     * @brief 释放全部资源。
     */
    void Shutdown();

    /**
     * @brief 调整交换链尺寸。
     * @param [IN] width 客户区宽度。
     * @param [IN] height 客户区高度。
     * @return 成功返回 true。
     */
    bool Resize(int width, int height);

    /**
     * @brief 开始一帧：绑定内部目标并清屏。
     * @param [IN] fogColor 清屏色（通常与雾色一致）。
     */
    void BeginFrame(const Color& fogColor);

    /**
     * @brief 结束 3D 场景绘制（恢复 2D 状态）。
     */
    void EndScene3D();

    /**
     * @brief 开始 3D 场景：设置管线、常量与视口。
     * @param [IN] frame 帧常量。
     */
    void BeginScene3D(const SceneFrame& frame);

    /**
     * @brief 绘制一个网格。
     * @param [IN] mesh 网格。
     * @param [IN] world 世界矩阵。
     * @param [IN] tint 颜色乘数（alpha 参与透明度）。
     * @param [IN] emission 自发光颜色。
     * @param [IN] alphaBlend 是否使用透明混合。
     */
    void DrawMesh(const Mesh& mesh, const Mat4& world, const Color& tint,
                  const Color& emission = Color(0.0f, 0.0f, 0.0f, 0.0f),
                  bool alphaBlend = false);

    /**
     * @brief 绘制网格的单个部件（用于角色动画）。
     * @param [IN] part 部件。
     * @param [IN] world 世界矩阵（已包含枢轴旋转）。
     * @param [IN] tint 颜色乘数。
     * @param [IN] emission 自发光。
     */
    void DrawMeshPart(const MeshPart& part, const Mat4& world,
                      const Color& tint,
                      const Color& emission = Color(0.0f, 0.0f, 0.0f, 0.0f));

    /**
     * @brief 呈现到窗口。
     * @param [IN] vsync 是否垂直同步。
     */
    void Present(bool vsync);

    /**
     * @brief 渲染后处理到离屏目标并保存 BMP（无头验证）。
     * @param [IN] path 输出路径。
     * @return 成功返回 true。
     */
    bool CaptureOffscreen(const std::string& path);

    /**
     * @brief 创建纹理。
     * @param [IN] bgra 像素数据。
     * @param [IN] width 宽。
     * @param [IN] height 高。
     * @param [IN] debugName 调试名。
     * @param [OUT] texture 输出纹理。
     * @return 成功返回 true。
     */
    bool CreateTexture(const uint8_t* bgra, int width, int height,
                       const char* debugName, Texture& texture);

    /**
     * @brief 创建离屏渲染目标。
     * @param [IN] width 宽。
     * @param [IN] height 高。
     * @param [IN] withDepth 是否附带深度缓冲。
     * @param [OUT] target 目标。
     * @return 成功返回 true。
     */
    bool CreateRenderTarget(int width, int height, bool withDepth,
                            RenderTarget& target);

    /**
     * @brief 绑定渲染目标并清屏。
     * @param [IN] target 目标。
     * @param [IN] clearColor 清屏色。
     */
    void BeginRenderTarget(RenderTarget& target, const Color& clearColor);

    /**
     * @brief 恢复内部目标。
     */
    void BeginInternalTarget();

    /**
     * @brief 设置后处理参数。
     * @param [IN] time 时间。
     * @param [IN] damage 受伤强度（0–1）。
     * @param [IN] fade 淡入淡出（0–1）。
     * @param [IN] glitch 故障强度（0–1）。
     */
    void SetPostParams(float time, float damage, float fade, float glitch);

    /**
     * @brief 获取精灵批处理。
     * @return 批处理引用。
     */
    SpriteBatch& Batch() { return m_batch; }

    /**
     * @brief 获取 1×1 白色纹理。
     * @return 纹理引用。
     */
    const Texture& White() const { return m_whiteTexture; }

    /**
     * @brief 获取辉光纹理（径向渐变）。
     * @return 纹理引用。
     */
    const Texture& Glow() const { return m_glowTexture; }

    /**
     * @brief 获取 D3D11 设备。
     * @return 设备指针。
     */
    ID3D11Device* Device() const { return m_device.Get(); }

    /**
     * @brief 客户区坐标转内部坐标。
     * @param [IN] screen 客户区坐标。
     * @return 内部坐标。
     */
    Vec2 ScreenToInternal(Vec2 screen) const;

    /**
     * @brief 内部坐标转客户区坐标。
     * @param [IN] internal 内部坐标。
     * @return 客户区坐标。
     */
    Vec2 InternalToScreen(Vec2 internal) const;

    int Scale() const { return m_scale; }
    int WindowWidth() const { return m_windowWidth; }
    int WindowHeight() const { return m_windowHeight; }
    const RectF& Letterbox() const { return m_letterbox; }
    bool IsReady() const { return m_device != nullptr; }

private:
    bool CreateShaders();
    bool CreateStates();
    bool CreateInternalTargets();
    bool CreateBackBufferViews();
    void UpdateLetterbox();
    bool RunPostPass(ID3D11RenderTargetView* target, int vpX, int vpY, int vpW,
                     int vpH);
    bool WriteBmp(const std::string& path, const uint8_t* bgra, int width,
                  int height, int pitch);
    void EnsureCaptureTarget();

    HWND m_hwnd = nullptr;
    int m_windowWidth = 0;
    int m_windowHeight = 0;
    int m_scale = 1;
    RectF m_letterbox;

    ComPtr<ID3D11Device> m_device;
    ComPtr<ID3D11DeviceContext> m_context;
    ComPtr<IDXGISwapChain> m_swapChain;
    ComPtr<ID3D11Texture2D> m_backBuffer;
    ComPtr<ID3D11RenderTargetView> m_backBufferRTV;

    RenderTarget m_internal;
    RenderTarget m_capture;
    RenderTarget* m_currentTarget = nullptr;

    ComPtr<ID3D11VertexShader> m_sceneVS;
    ComPtr<ID3D11PixelShader> m_scenePS;
    ComPtr<ID3D11InputLayout> m_sceneLayout;
    ComPtr<ID3D11Buffer> m_frameCB;
    ComPtr<ID3D11Buffer> m_objectCB;

    ComPtr<ID3D11VertexShader> m_postVS;
    ComPtr<ID3D11PixelShader> m_postPS;
    ComPtr<ID3D11Buffer> m_postCB;
    ComPtr<ID3D11SamplerState> m_pointSampler;
    ComPtr<ID3D11SamplerState> m_linearSampler;
    ComPtr<ID3D11BlendState> m_alphaBlend;
    ComPtr<ID3D11BlendState> m_additiveBlend;
    ComPtr<ID3D11DepthStencilState> m_depthState;
    ComPtr<ID3D11DepthStencilState> m_depthDisabled;
    ComPtr<ID3D11RasterizerState> m_rasterizer;
    ComPtr<ID3D11RasterizerState> m_rasterizerNoCull;

    SpritePipeline m_spritePipeline;
    SpriteBatch m_batch;
    ComPtr<ID3D11VertexShader> m_spriteVertexShader;
    ComPtr<ID3D11PixelShader> m_spritePixelShader;
    ComPtr<ID3D11InputLayout> m_spriteLayout;
    ComPtr<ID3D11Buffer> m_spriteConstantBuffer;

    Texture m_whiteTexture;
    Texture m_glowTexture;

    bool m_depthEnabled = false;
    float m_postTime = 0.0f;
    float m_postDamage = 0.0f;
    float m_postFade = 0.0f;
    float m_postGlitch = 0.0f;
    SceneFrame m_frame;
};

} // namespace fc

#endif // __RENDER_DEVICE_HPP__
