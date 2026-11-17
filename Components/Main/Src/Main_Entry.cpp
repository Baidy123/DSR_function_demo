#include "Game_App.hpp"
#include "Platform_Input.hpp"
#include "Platform_Resource.hpp"
#include "Platform_Time.hpp"
#include "Platform_Window.hpp"
#include "Shared_Log.hpp"
#include "Shared_String.hpp"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

using namespace fc;

namespace {

struct LaunchOptions {
    bool screenshot = false;
    std::string screenshotPath = "Temp/shot.bmp";
    std::string scene = "title";
    std::string ui = "none";
    int frames = 150;
};

std::string ArgumentValue(const std::string& commandLine, const char* key)
{
    const std::string text = " " + commandLine + " ";
    const std::string needle = std::string(" ") + key + " ";
    size_t pos = text.find(needle);
    if (pos == std::string::npos) {
        return std::string();
    }
    pos += needle.size();
    size_t end = text.find(' ', pos);
    if (end == std::string::npos) {
        end = text.size();
    }
    return text.substr(pos, end - pos);
}

bool HasFlag(const std::string& commandLine, const char* key)
{
    return commandLine.find(key) != std::string::npos;
}

LaunchOptions ParseOptions()
{
    LaunchOptions options;
    const char* raw = GetCommandLineA();
    const std::string commandLine = raw != nullptr ? raw : "";
    options.screenshot = HasFlag(commandLine, "--shot");
    const std::string path = ArgumentValue(commandLine, "--shot");
    if (!path.empty()) {
        options.screenshotPath = path;
    }
    const std::string scene = ArgumentValue(commandLine, "--scene");
    if (!scene.empty()) {
        options.scene = scene;
    }
    const std::string ui = ArgumentValue(commandLine, "--ui");
    if (!ui.empty()) {
        options.ui = ui;
    }
    const std::string frames = ArgumentValue(commandLine, "--frames");
    if (!frames.empty()) {
        options.frames = std::atoi(frames.c_str());
        if (options.frames <= 0) {
            options.frames = 150;
        }
    }
    return options;
}

void ApplyDebugView(GameApp& app, const LaunchOptions& options)
{
    if (options.scene == "street") {
        app.DebugLoadScene(SceneId::BAR_EXTERIOR);
    } else if (options.scene == "bar") {
        app.DebugLoadScene(SceneId::BAR_INTERIOR);
    } else if (options.scene == "harbor") {
        app.DebugLoadScene(SceneId::IRON_HARBOR);
    }

    if (options.ui == "dialogue") {
        app.DebugShowDialogue();
    } else if (options.ui == "shop") {
        app.DebugShowShop();
    } else if (options.ui == "journal") {
        app.DebugShowJournal();
    } else if (options.ui == "ending") {
        app.DebugShowEnding(true);
    } else if (options.ui == "death") {
        if (options.scene == "title") {
            app.DebugLoadScene(SceneId::IRON_HARBOR);
        }
        app.DebugSetMode(GameMode::DEAD);
    } else if (options.ui == "pause") {
        if (options.scene == "title") {
            app.DebugLoadScene(SceneId::BAR_INTERIOR);
        }
        app.DebugSetMode(GameMode::PAUSED);
    }
}

} // namespace

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int)
{
    SetProcessDPIAware();
    LogInitialize();

    const LaunchOptions options = ParseOptions();
    LogInfo("Ember of Free City starting (screenshot=%d, scene=%s, ui=%s)",
            options.screenshot ? 1 : 0, options.scene.c_str(),
            options.ui.c_str());

    const int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    const int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    const int windowWidth = std::min(WINDOW_WIDTH, std::max(960, screenWidth - 80));
    const int windowHeight = std::min(WINDOW_HEIGHT, std::max(540, screenHeight - 120));

    Window window;
    if (!window.Create(windowWidth, windowHeight, L"Ember of Free City",
                       !options.screenshot)) {
        LogError("Failed to create window");
        LogShutdown();
        return 1;
    }

    std::vector<uint8_t> pack;
    if (!LoadEmbeddedResource(L"ART_PACK", pack)) {
        LogError("Failed to load embedded art pack");
        LogShutdown();
        return 1;
    }

    GameApp app;
    if (!app.Initialize(window.Handle(), window.ClientWidth(),
                        window.ClientHeight(), pack, options.screenshot)) {
        LogError("Failed to initialize game");
        LogShutdown();
        return 1;
    }

    if (options.screenshot) {
        ApplyDebugView(app, options);
        for (int frame = 0; frame < options.frames; ++frame) {
            app.Update(1.0f / 60.0f);
            app.Render();
        }
        app.Present(false);
        if (!app.Capture(options.screenshotPath)) {
            LogError("Failed to capture screenshot: %s",
                     options.screenshotPath.c_str());
        } else {
            LogInfo("Screenshot saved: %s", options.screenshotPath.c_str());
        }
    } else {
        Clock clock;
        bool running = true;
        while (running) {
            running = window.PumpMessages();
            if (!running || app.ShouldQuit()) {
                break;
            }
            if (window.ClientWidth() != 0 && window.ClientHeight() != 0) {
                app.Resize(window.ClientWidth(), window.ClientHeight());
            }
            const float dt = clock.Tick();
            app.Update(dt);
            app.Render();
            app.Present(true);
            Input::Get().EndFrame();
        }
    }

    app.Shutdown();
    LogInfo("Ember of Free City stopped");
    LogShutdown();
    return 0;
}
