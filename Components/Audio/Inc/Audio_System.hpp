#ifndef __AUDIO_SYSTEM_HPP__
#define __AUDIO_SYSTEM_HPP__

#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mmsystem.h>

namespace fc {

/**
 * @brief 程序化音效 ID。
 */
enum class SfxId : std::uint8_t {
    SHOOT = 0,
    HIT,
    PICKUP,
    RELOAD,
    BUY,
    DENY,
    DOOR,
    ALARM,
    UI,
    MEDKIT,
    DEATH
};

/**
 * @brief 基于 waveOut 的程序化音乐、环境音与音效混音器。
 *
 * 无音频设备时 Initialize 返回 false，游戏继续静音运行。
 */
class AudioSystem {
public:
    AudioSystem() = default;
    ~AudioSystem();

    /**
     * @brief 打开音频设备并启动混音线程。
     * @return 成功返回 true。
     */
    bool Initialize();

    /**
     * @brief 停止线程并关闭设备。
     */
    void Shutdown();

    /**
     * @brief 设置静音。
     * @param [IN] muted 是否静音。
     */
    void SetMuted(bool muted);

    /**
     * @brief 查询静音状态。
     * @return 静音返回 true。
     */
    bool IsMuted() const { return m_muted.load(); }

    /**
     * @brief 播放一次性音效。
     * @param [IN] id 音效 ID。
     */
    void PlaySfx(SfxId id);

    /**
     * @brief 设置场景氛围。
     * @param [IN] scene 0=酒吧，1=街道，2=铁港。
     * @param [IN] rain 是否下雨。
     */
    void SetScene(int scene, bool rain);

    /**
     * @brief 设置战斗强度。
     * @param [IN] combat 是否处于战斗。
     */
    void SetCombat(bool combat);

private:
    static constexpr int SAMPLE_RATE = 44100;
    static constexpr int CHANNELS = 2;
    static constexpr int FRAMES_PER_BUFFER = 512;
    static constexpr int BUFFER_COUNT = 4;
    static constexpr int MAX_VOICES = 16;

    struct Buffer {
        WAVEHDR header = {};
        std::vector<std::int16_t> samples;
    };

    struct Voice {
        bool active = false;
        SfxId id = SfxId::UI;
        float time = 0.0f;
        float duration = 0.0f;
        float phase = 0.0f;
    };

    void MixerThread();
    void RenderBuffer(int index);
    float RenderVoice(const Voice& voice) const;
    void ResetVoices();

    HWAVEOUT m_waveOut = nullptr;
    HANDLE m_event = nullptr;
    WAVEFORMATEX m_format = {};
    std::vector<Buffer> m_buffers;
    std::thread m_thread;
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_muted{false};
    std::atomic<int> m_scene{1};
    std::atomic<bool> m_rain{true};
    std::atomic<bool> m_combat{false};
    std::mutex m_voiceMutex;
    Voice m_voices[MAX_VOICES];
    double m_sampleTime = 0.0;
    float m_noiseFilter = 0.0f;
    float m_noiseFilter2 = 0.0f;
    std::uint32_t m_rngState = 0x12345678u;
};

} // namespace fc

#endif // __AUDIO_SYSTEM_HPP__
