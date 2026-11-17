#include "Audio_System.hpp"

#include "Shared_Log.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace fc {

namespace {

constexpr float PI = 3.14159265358979323846f;

float ClampF(float value, float lo, float hi)
{
    return value < lo ? lo : (value > hi ? hi : value);
}

float Sine(float frequency, float time)
{
    return std::sin(2.0f * PI * frequency * time);
}

float Square(float frequency, float time)
{
    return Sine(frequency, time) >= 0.0f ? 1.0f : -1.0f;
}

float Triangle(float frequency, float time)
{
    const float phase = frequency * time;
    const float f = phase - std::floor(phase);
    return 4.0f * std::fabs(f - 0.5f) - 1.0f;
}

float HashNoise(float time)
{
    const float x = std::sin(time * 12345.678f) * 43758.5453f;
    return (x - std::floor(x)) * 2.0f - 1.0f;
}

float VoiceDuration(SfxId id)
{
    switch (id) {
    case SfxId::SHOOT: return 0.20f;
    case SfxId::HIT: return 0.12f;
    case SfxId::PICKUP: return 0.28f;
    case SfxId::RELOAD: return 0.70f;
    case SfxId::BUY: return 0.30f;
    case SfxId::DENY: return 0.24f;
    case SfxId::DOOR: return 0.45f;
    case SfxId::ALARM: return 0.70f;
    case SfxId::UI: return 0.08f;
    case SfxId::MEDKIT: return 0.35f;
    case SfxId::DEATH: return 1.20f;
    default: return 0.20f;
    }
}

} // namespace

AudioSystem::~AudioSystem()
{
    Shutdown();
}

bool AudioSystem::Initialize()
{
    if (m_waveOut != nullptr) {
        return true;
    }

    m_format.wFormatTag = WAVE_FORMAT_PCM;
    m_format.nChannels = CHANNELS;
    m_format.nSamplesPerSec = SAMPLE_RATE;
    m_format.wBitsPerSample = 16;
    m_format.nBlockAlign = static_cast<WORD>(CHANNELS * 2);
    m_format.nAvgBytesPerSec = SAMPLE_RATE * m_format.nBlockAlign;
    m_format.cbSize = 0;

    m_event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (m_event == nullptr) {
        LogWarn("Audio: CreateEvent failed, running silent");
        return false;
    }

    const MMRESULT openResult = waveOutOpen(
        &m_waveOut, WAVE_MAPPER, &m_format,
        reinterpret_cast<DWORD_PTR>(m_event), 0, CALLBACK_EVENT);
    if (openResult != MMSYSERR_NOERROR) {
        LogWarn("Audio: waveOutOpen failed (%u), running silent",
                static_cast<unsigned int>(openResult));
        CloseHandle(m_event);
        m_event = nullptr;
        m_waveOut = nullptr;
        return false;
    }

    m_buffers.resize(BUFFER_COUNT);
    for (int i = 0; i < BUFFER_COUNT; ++i) {
        Buffer& buffer = m_buffers[static_cast<size_t>(i)];
        buffer.samples.assign(FRAMES_PER_BUFFER * CHANNELS, 0);
        buffer.header.lpData = reinterpret_cast<LPSTR>(buffer.samples.data());
        buffer.header.dwBufferLength =
            static_cast<DWORD>(buffer.samples.size() * sizeof(std::int16_t));
        buffer.header.dwFlags = 0;
        if (waveOutPrepareHeader(m_waveOut, &buffer.header,
                                 sizeof(WAVEHDR)) != MMSYSERR_NOERROR) {
            LogWarn("Audio: waveOutPrepareHeader failed");
            Shutdown();
            return false;
        }
        RenderBuffer(i);
        if (waveOutWrite(m_waveOut, &buffer.header, sizeof(WAVEHDR)) !=
            MMSYSERR_NOERROR) {
            LogWarn("Audio: waveOutWrite failed");
            Shutdown();
            return false;
        }
    }

    ResetVoices();
    m_running = true;
    m_thread = std::thread(&AudioSystem::MixerThread, this);
    LogInfo("Audio system initialized");
    return true;
}

void AudioSystem::Shutdown()
{
    const bool wasRunning = m_running.exchange(false);
    if (m_event != nullptr) {
        SetEvent(m_event);
    }
    if (m_thread.joinable()) {
        m_thread.join();
    }
    if (m_waveOut != nullptr) {
        waveOutReset(m_waveOut);
        for (Buffer& buffer : m_buffers) {
            waveOutUnprepareHeader(m_waveOut, &buffer.header, sizeof(WAVEHDR));
        }
        waveOutClose(m_waveOut);
        m_waveOut = nullptr;
    }
    if (m_event != nullptr) {
        CloseHandle(m_event);
        m_event = nullptr;
    }
    m_buffers.clear();
    if (wasRunning) {
        LogInfo("Audio system stopped");
    }
}

void AudioSystem::SetMuted(bool muted)
{
    m_muted = muted;
}

void AudioSystem::SetScene(int scene, bool rain)
{
    m_scene = scene;
    m_rain = rain;
}

void AudioSystem::SetCombat(bool combat)
{
    m_combat = combat;
}

void AudioSystem::PlaySfx(SfxId id)
{
    if (m_waveOut == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(m_voiceMutex);
    for (Voice& voice : m_voices) {
        if (!voice.active) {
            voice.active = true;
            voice.id = id;
            voice.time = 0.0f;
            voice.duration = VoiceDuration(id);
            voice.phase = 0.0f;
            return;
        }
    }
}

void AudioSystem::ResetVoices()
{
    std::lock_guard<std::mutex> lock(m_voiceMutex);
    for (Voice& voice : m_voices) {
        voice = Voice();
    }
}

void AudioSystem::MixerThread()
{
    while (m_running.load()) {
        const DWORD result = WaitForSingleObject(m_event, 50);
        if (!m_running.load()) {
            break;
        }
        if (result == WAIT_TIMEOUT && m_waveOut == nullptr) {
            break;
        }
        for (int i = 0; i < static_cast<int>(m_buffers.size()); ++i) {
            Buffer& buffer = m_buffers[static_cast<size_t>(i)];
            if ((buffer.header.dwFlags & WHDR_DONE) != 0) {
                RenderBuffer(i);
                waveOutWrite(m_waveOut, &buffer.header, sizeof(WAVEHDR));
            }
        }
    }
}

float AudioSystem::RenderVoice(const Voice& voice) const
{
    const float t = voice.time;
    const float env = ClampF(1.0f - t / std::max(0.001f, voice.duration), 0.0f, 1.0f);
    switch (voice.id) {
    case SfxId::SHOOT: {
        const float noise = HashNoise(t * 3.0f) * std::exp(-t * 26.0f);
        const float body = Sine(95.0f, t) * std::exp(-t * 16.0f);
        return (noise * 0.55f + body * 0.45f) * 0.55f;
    }
    case SfxId::HIT:
        return HashNoise(t * 4.0f) * std::exp(-t * 38.0f) * 0.45f;
    case SfxId::PICKUP: {
        const float first = Sine(880.0f, t) * (t < 0.10f ? 1.0f : 0.0f);
        const float second = Sine(1320.0f, t) * (t >= 0.10f ? 1.0f : 0.0f);
        return (first + second) * env * 0.28f;
    }
    case SfxId::RELOAD: {
        float clicks = 0.0f;
        const float times[3] = {0.05f, 0.34f, 0.62f};
        for (float clickTime : times) {
            if (t >= clickTime && t < clickTime + 0.05f) {
                clicks += HashNoise((t - clickTime) * 8.0f) *
                          (1.0f - (t - clickTime) / 0.05f);
            }
        }
        return clicks * 0.35f + Sine(140.0f, t) * 0.08f * env;
    }
    case SfxId::BUY:
        return (Sine(660.0f, t) + Sine(990.0f, t)) * env * 0.18f;
    case SfxId::DENY:
        return Square(110.0f, t) * env * 0.16f;
    case SfxId::DOOR:
        return (Sine(70.0f, t) * 0.5f + HashNoise(t * 2.0f) * 0.3f) *
               std::exp(-t * 5.0f) * 0.5f;
    case SfxId::ALARM: {
        const float warble = 620.0f + 90.0f * Sine(4.0f, t);
        return Sine(warble, t) * env * 0.20f;
    }
    case SfxId::UI:
        return Sine(1200.0f, t) * env * 0.12f;
    case SfxId::MEDKIT: {
        const float frequency = 500.0f + 500.0f * (t / std::max(0.001f, voice.duration));
        return Sine(frequency, t) * env * 0.18f;
    }
    case SfxId::DEATH: {
        const float frequency = 220.0f - 150.0f * (t / std::max(0.001f, voice.duration));
        return Sine(frequency, t) * env * 0.30f;
    }
    default:
        return 0.0f;
    }
}

void AudioSystem::RenderBuffer(int index)
{
    if (index < 0 || index >= static_cast<int>(m_buffers.size())) {
        return;
    }
    Buffer& buffer = m_buffers[static_cast<size_t>(index)];
    const int scene = m_scene.load();
    const bool rain = m_rain.load();
    const bool combat = m_combat.load();
    const bool muted = m_muted.load();
    const float invRate = 1.0f / static_cast<float>(SAMPLE_RATE);

    std::lock_guard<std::mutex> lock(m_voiceMutex);
    for (int frame = 0; frame < FRAMES_PER_BUFFER; ++frame) {
        const double absolute = m_sampleTime + frame * invRate;
        const float t = static_cast<float>(absolute);

        const double barLength = 4.0;
        const int chordIndex = static_cast<int>(absolute / barLength) % 4;
        const double roots[4] = {55.0, 49.0, 65.406, 58.270};
        const double root = roots[chordIndex];
        const float beat = static_cast<float>(
            std::fmod(absolute, combat ? 0.34 : 0.5));
        const float bassEnv = std::exp(-beat * 5.5f);
        const float bass = Square(static_cast<float>(root), t) * 0.055f * bassEnv;

        const double arpStepLength = combat ? 0.125 : 0.25;
        const int arpStep = static_cast<int>(absolute / arpStepLength) % 4;
        const double ratios[4] = {4.0, 5.0, 6.0, 8.0};
        const float arpPhase = static_cast<float>(
            std::fmod(absolute, arpStepLength) / arpStepLength);
        const float arp = Triangle(static_cast<float>(root * ratios[arpStep]), t) *
                          0.042f * std::exp(-arpPhase * 4.0f);

        const float pad = (Sine(static_cast<float>(root * 2.0), t) +
                           Sine(static_cast<float>(root * 3.0), t)) *
                          (scene == 0 ? 0.026f : 0.016f);
        float music = bass + arp + pad;

        if (combat) {
            const float kickPhase = static_cast<float>(std::fmod(absolute, 0.5));
            music += Sine(55.0f, kickPhase) * std::exp(-kickPhase * 16.0f) * 0.14f;
        }

        const float white = HashNoise(t * 1.7f);
        m_noiseFilter = m_noiseFilter * 0.985f + white * 0.015f;
        m_noiseFilter2 = m_noiseFilter2 * 0.995f + white * 0.005f;
        if (rain && scene != 0) {
            music += m_noiseFilter * 0.07f;
        } else if (scene == 0) {
            music += m_noiseFilter2 * 0.025f;
        }
        if (scene == 2) {
            music += Sine(50.0f, t) * 0.012f;
        }

        float fx = 0.0f;
        for (Voice& voice : m_voices) {
            if (!voice.active) {
                continue;
            }
            fx += RenderVoice(voice);
            voice.time += invRate;
            if (voice.time >= voice.duration) {
                voice.active = false;
            }
        }

        float left = music + fx;
        float right = music + fx;
        left *= 0.95f + 0.05f * Sine(0.31f, t);
        right *= 0.95f - 0.05f * Sine(0.31f, t);
        if (muted) {
            left = 0.0f;
            right = 0.0f;
        }
        left = ClampF(left, -0.95f, 0.95f);
        right = ClampF(right, -0.95f, 0.95f);
        buffer.samples[static_cast<size_t>(frame) * 2 + 0] =
            static_cast<std::int16_t>(left * 32767.0f);
        buffer.samples[static_cast<size_t>(frame) * 2 + 1] =
            static_cast<std::int16_t>(right * 32767.0f);
    }
    m_sampleTime += static_cast<double>(FRAMES_PER_BUFFER) * invRate;
}

} // namespace fc
