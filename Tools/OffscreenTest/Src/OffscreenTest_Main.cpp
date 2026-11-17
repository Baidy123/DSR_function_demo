#include "Game_App.hpp"
#include "OffscreenTest_Config.hpp"
#include "Platform_Resource.hpp"
#include "Platform_Window.hpp"
#include "Shared_Log.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

using namespace fc;

namespace {

/**
 * @brief 拼接目录下所有文本网格（.fcm）为一份网格库文本。
 * @param [IN] directory 网格目录（相对项目根目录）。
 * @param [OUT] text 网格库文本。
 * @return 至少成功读取一个文件时返回 true。
 */
bool LoadMeshText(const std::string& directory, std::string& text)
{
    text.clear();
    std::error_code error;
    std::vector<std::filesystem::path> files;
    for (const auto& entry :
         std::filesystem::directory_iterator(directory, error)) {
        if (error) {
            return false;
        }
        if (entry.is_regular_file() && entry.path().extension() == ".fcm") {
            files.push_back(entry.path());
        }
    }
    if (files.empty()) {
        return false;
    }
    std::sort(files.begin(), files.end());
    for (const std::filesystem::path& path : files) {
        std::vector<uint8_t> bytes;
        if (!LoadFileBytes(path.string(), bytes)) {
            std::printf("[WARN] Cannot read mesh file: %s\n",
                        path.string().c_str());
            continue;
        }
        text.append(reinterpret_cast<const char*>(bytes.data()), bytes.size());
        text.push_back('\n');
    }
    return !text.empty();
}

struct Options {
    std::string scene = "title";
    std::string ui = "none";
    std::string output;
    std::string meshes = offscreen::DEFAULT_MESH_DIR;
    int frames = offscreen::DEFAULT_FRAMES;
    bool endingWait = false;
    bool flow = false;
};

bool ParseInt(const char* text, int& value)
{
    if (text == nullptr) {
        return false;
    }
    char* end = nullptr;
    const long parsed = std::strtol(text, &end, 10);
    if (end == text || parsed <= 0) {
        return false;
    }
    value = static_cast<int>(parsed);
    return true;
}

Options ParseOptions(int argc, char** argv)
{
    Options options;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--scene" && i + 1 < argc) {
            options.scene = argv[++i];
        } else if (arg == "--ui" && i + 1 < argc) {
            options.ui = argv[++i];
        } else if (arg == "--out" && i + 1 < argc) {
            options.output = argv[++i];
        } else if (arg == "--meshes" && i + 1 < argc) {
            options.meshes = argv[++i];
        } else if (arg == "--frames" && i + 1 < argc) {
            ParseInt(argv[++i], options.frames);
        } else if (arg == "--choice" && i + 1 < argc) {
            options.endingWait = std::string(argv[++i]) == "wait";
        } else if (arg == "--flow") {
            options.flow = true;
        }
    }
    if (options.output.empty()) {
        options.output = std::string(offscreen::DEFAULT_OUTPUT_DIR) + "/" +
                         options.scene + "_" + options.ui + ".bmp";
    }
    return options;
}

int RunFlow(GameApp& app)
{
    int passed = 0;
    int failed = 0;
    auto expect = [&](bool condition, const char* name) {
        if (condition) {
            ++passed;
            std::printf("[PASS] %s\n", name);
        } else {
            ++failed;
            std::printf("[FAIL] %s\n", name);
        }
    };
    auto step = [&](int frames) {
        for (int i = 0; i < frames; ++i) {
            app.Update(1.0f / 60.0f);
        }
    };

    app.DebugStartNewGame();
    expect(app.DebugMode() == GameMode::DIALOGUE, "Flow: intro dialogue");
    app.DebugAdvanceDialogue(200);
    step(1);
    expect(app.DebugMode() == GameMode::PLAYING, "Flow: intro finished");

    app.DebugInteract("bar_entrance");
    step(60);
    expect(app.DebugScene() == SceneId::BAR_INTERIOR, "Flow: enter bar");
    expect(app.DebugMainStage() == MainStage::TALK_BARTENDER,
           "Flow: bartender objective");

    app.DebugInteract("bartender");
    app.DebugAdvanceDialogue(200);
    step(1);
    expect(app.DebugMainStage() == MainStage::TALK_BIGSISTER,
           "Flow: bartender briefed");

    app.DebugInteract("bigsister");
    app.DebugAdvanceDialogue(300);
    step(1);
    expect(app.DebugMainStage() == MainStage::GET_GEAR,
           "Flow: main quest accepted");

    app.DebugInteract("bartender");
    app.DebugAdvanceDialogue(300);
    app.DebugChooseDialogue(0);
    app.DebugFinishDialogue();
    step(1);
    expect(app.DebugSideStage() == SideStage::ACCEPTED,
           "Flow: side quest accepted");

    app.DebugInteract("merchant");
    app.DebugAdvanceDialogue(200);
    step(1);
    expect(app.DebugMode() == GameMode::SHOP, "Flow: shop opened");
    app.DebugCloseShop();
    expect(app.DebugHasGear(), "Flow: starter kit granted");
    expect(app.DebugMainStage() == MainStage::GO_WAREHOUSE,
           "Flow: warehouse objective");

    app.DebugInteract("bar_exit");
    step(60);
    expect(app.DebugScene() == SceneId::BAR_EXTERIOR, "Flow: leave bar");

    app.DebugInteract("car");
    step(60);
    expect(app.DebugScene() == SceneId::IRON_HARBOR, "Flow: arrive harbor");
    expect(app.DebugMainStage() == MainStage::FIND_CARGO,
           "Flow: cargo objective");
    expect(app.DebugAliveEnemies() > 0, "Flow: scavengers present");

    app.DebugInteract("part");
    expect(app.DebugSideStage() == SideStage::HAVE_PART,
           "Flow: jukebox part collected");

    app.DebugInteract("cargo");
    app.DebugAdvanceDialogue(50);
    step(1);
    expect(app.DebugMainStage() == MainStage::DEFEAT_AGENTS,
           "Flow: ambush triggered");
    expect(app.DebugAliveEnemies() >= 3, "Flow: agents present");

    app.DebugKillEnemies();
    step(1);
    expect(app.DebugMainStage() == MainStage::RETURN_BAR,
           "Flow: agents cleared");

    app.DebugInteract("warehouse_exit");
    step(60);
    expect(app.DebugScene() == SceneId::BAR_EXTERIOR, "Flow: return outside");

    app.DebugInteract("bar_entrance");
    step(60);
    expect(app.DebugScene() == SceneId::BAR_INTERIOR, "Flow: return bar");

    app.DebugInteract("bartender");
    app.DebugAdvanceDialogue(200);
    step(1);
    expect(app.DebugSideStage() == SideStage::COMPLETED,
           "Flow: side quest completed");

    app.DebugInteract("bigsister");
    app.DebugAdvanceDialogue(300);
    app.DebugChooseDialogue(0);
    app.DebugFinishDialogue();
    step(1);
    expect(app.DebugMode() == GameMode::EPILOGUE, "Flow: epilogue reached");
    expect(app.DebugEndingChoice() == EndingChoice::ACCEPT,
           "Flow: ending choice accepted");
    expect(app.DebugMainStage() == MainStage::COMPLETE,
           "Flow: main quest complete");
    expect(app.DebugMoney() >= 280, "Flow: rewards granted");

    std::printf("Flow summary: PASSED=%d FAILED=%d\n", passed, failed);
    return failed == 0 ? 0 : 1;
}

void ApplyView(GameApp& app, const Options& options)
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
        app.DebugShowEnding(!options.endingWait);
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

int main(int argc, char** argv)
{
    SetProcessDPIAware();
    LogInitialize();

    const Options options = ParseOptions(argc, argv);
    std::printf("OffscreenTest: scene=%s ui=%s frames=%d\n",
                options.scene.c_str(), options.ui.c_str(), options.frames);

    Window window;
    if (!window.Create(WINDOW_WIDTH, WINDOW_HEIGHT, L"OffscreenTest", false)) {
        std::printf("[FAIL] Cannot create hidden window\n");
        LogShutdown();
        return 1;
    }

    std::string meshText;
    if (!LoadMeshText(options.meshes, meshText)) {
        std::printf("[FAIL] Cannot load mesh assets: %s\n", options.meshes.c_str());
        LogShutdown();
        return 1;
    }

    GameApp app;
    if (!app.Initialize(window.Handle(), window.ClientWidth(),
                        window.ClientHeight(), meshText, true)) {
        std::printf("[FAIL] Cannot initialize game\n");
        LogShutdown();
        return 1;
    }

    if (options.flow) {
        const int result = RunFlow(app);
        app.Shutdown();
        LogShutdown();
        return result;
    }

    ApplyView(app, options);
    for (int frame = 0; frame < options.frames; ++frame) {
        app.Update(1.0f / 60.0f);
        app.Render();
    }
    app.Present(false);

    try {
        const std::filesystem::path outputPath(options.output);
        if (outputPath.has_parent_path()) {
            std::filesystem::create_directories(outputPath.parent_path());
        }
    } catch (...) {
        // 目录创建失败时由 Capture 报错。
    }

    const bool saved = app.Capture(options.output);
    app.Shutdown();
    LogShutdown();

    if (!saved) {
        std::printf("[FAIL] Screenshot capture failed: %s\n",
                    options.output.c_str());
        return 1;
    }
    std::printf("[PASS] Screenshot saved: %s\n", options.output.c_str());
    return 0;
}
