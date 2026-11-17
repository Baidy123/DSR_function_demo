#include "Game_Dialogue.hpp"
#include "Game_Inventory.hpp"
#include "Game_Quest.hpp"
#include "Game_Story.hpp"
#include "Shared_Math.hpp"
#include "UnitTests_Config.hpp"

#include <cmath>
#include <cstdio>
#include <string>
#include <utility>
#include <vector>

using namespace fc;

namespace {

int g_passed = 0;
int g_failed = 0;

void Check(bool condition, const char* name)
{
    if (condition) {
        ++g_passed;
        std::printf("[PASS] %s\n", name);
    } else {
        ++g_failed;
        std::printf("[FAIL] %s\n", name);
    }
}

void CheckFloat(float actual, float expected, const char* name)
{
    const bool ok = std::fabs(actual - expected) <= unittests::EPSILON;
    if (ok) {
        ++g_passed;
        std::printf("[PASS] %s\n", name);
    } else {
        ++g_failed;
        std::printf("[FAIL] %s (expected %.4f, got %.4f)\n", name, expected,
                    actual);
    }
}

DialogueNode TestNode(const char* text, int next,
                      DialogueEvent event = DialogueEvent::NONE)
{
    DialogueNode node;
    node.speaker = "测试";
    node.portrait = "PORTRAIT_PLAYER";
    node.text = text;
    node.next = next;
    node.event = event;
    return node;
}

void TestMath()
{
    CheckFloat(Length(Vec2(3.0f, 4.0f)), 5.0f, "Math: vector length");
    const Vec2 zero = Normalize(Vec2(0.0f, 0.0f));
    Check(zero.x == 0.0f && zero.y == 0.0f, "Math: normalize zero");
    CheckFloat(Clamp(15.0f, 0.0f, 10.0f), 10.0f, "Math: clamp high");
    CheckFloat(Lerp(0.0f, 10.0f, 0.25f), 2.5f, "Math: lerp");

    CheckFloat(Length(Vec3(0.0f, 3.0f, 4.0f)), 5.0f, "Math: vec3 length");
    const Vec3 unit = Normalize(Vec3(0.0f, 0.0f, 8.0f));
    CheckFloat(unit.z, 1.0f, "Math: vec3 normalize");
    CheckFloat(Dot(Vec3(1.0f, 0.0f, 0.0f), Vec3(0.0f, 1.0f, 0.0f)), 0.0f,
               "Math: dot orthogonal");
    const Vec3 crossZ = Cross(Vec3(1.0f, 0.0f, 0.0f), Vec3(0.0f, 1.0f, 0.0f));
    CheckFloat(crossZ.z, 1.0f, "Math: cross z axis");
    CheckFloat(DistanceXZ(Vec3(1.0f, 9.0f, 1.0f), Vec3(1.0f, 0.0f, 3.0f)),
               2.0f, "Math: distance xz ignores height");

    const Vec3 yawDir = DirectionFromYaw(0.0f);
    CheckFloat(yawDir.z, 1.0f, "Math: yaw 0 faces +Z");
    CheckFloat(YawFromDirection(Vec3(0.0f, 0.0f, -1.0f)), PI, "Math: yaw of -Z");

    // 平移矩阵应当只影响点，不影响方向。
    const Mat4 move = Mat4::Translation(Vec3(2.0f, 3.0f, 4.0f));
    const Vec3 movedPoint = move.TransformPoint(Vec3(1.0f, 0.0f, 0.0f));
    CheckFloat(movedPoint.x, 3.0f, "Math: translation point x");
    CheckFloat(movedPoint.y, 3.0f, "Math: translation point y");
    const Vec3 movedDir = move.TransformVector(Vec3(1.0f, 0.0f, 0.0f));
    CheckFloat(movedDir.x, 1.0f, "Math: translation ignores direction");

    // 绕 Y 轴 90°：+X 应当转到 -Z。
    const Vec3 rotated =
        Mat4::RotationY(PI * 0.5f).TransformPoint(Vec3(1.0f, 0.0f, 0.0f));
    CheckFloat(rotated.x, 0.0f, "Math: rotation y x");
    CheckFloat(rotated.z, -1.0f, "Math: rotation y z");

    // 透视矩阵：右手系，近平面映射为 0，远平面映射为 1。
    const Mat4 projection = Mat4::Perspective(PI * 0.5f, 16.0f / 9.0f, 0.1f,
                                              100.0f);
    CheckFloat(projection.m[11], -1.0f, "Math: perspective w row");
    CheckFloat(projection.m[10], 100.0f / (0.1f - 100.0f),
               "Math: perspective z scale");
    CheckFloat(projection.m[14], 0.1f * 100.0f / (0.1f - 100.0f),
               "Math: perspective z offset");

    // 视空间深度：更远的点应得到更大的 NDC 深度。
    const Mat4 view = Mat4::LookAt(Vec3(0.0f, 0.0f, 0.0f),
                                   Vec3(0.0f, 0.0f, 1.0f),
                                   Vec3(0.0f, 1.0f, 0.0f));
    const Mat4 viewProj = view * projection;
    const Vec3 nearPoint = viewProj.TransformPoint(Vec3(0.0f, 0.0f, 1.0f));
    const Vec3 farPoint = viewProj.TransformPoint(Vec3(0.0f, 0.0f, 40.0f));
    Check(nearPoint.z < farPoint.z, "Math: depth grows with distance");

    // 碰撞辅助函数。
    const AABB solid = MakeAABB(Vec3(0.0f, 1.0f, 0.0f), Vec3(1.0f, 1.0f, 1.0f));
    Check(CircleIntersectsBox(Vec3(1.2f, 1.0f, 0.0f), 0.4f, solid),
          "Math: circle-box intersection");
    Check(!CircleIntersectsBox(Vec3(3.0f, 1.0f, 0.0f), 0.4f, solid),
          "Math: circle-box separation");

    Vec3 pushed(1.1f, 1.0f, 0.0f);
    Check(ResolveCircleBox(pushed, 0.4f, solid), "Math: circle-box push out");
    Check(pushed.x >= 1.4f - 0.001f, "Math: pushed outside of box");

    float hitT = 0.0f;
    Check(SegmentAABB(Vec3(-4.0f, 1.0f, 0.0f), Vec3(4.0f, 1.0f, 0.0f), solid,
                      hitT),
          "Math: segment hits box");
    Check(hitT > 0.0f && hitT < 0.5f, "Math: segment hit t in range");
    Check(!SegmentAABB(Vec3(-4.0f, 5.0f, 0.0f), Vec3(4.0f, 5.0f, 0.0f), solid,
                       hitT),
          "Math: segment misses box");

    float rayDistance = 0.0f;
    Check(RayCircleXZ(Vec3(0.0f, 1.0f, -4.0f), Vec3(0.0f, 0.0f, 1.0f),
                      Vec3(0.0f, 1.0f, 0.0f), 0.5f, rayDistance),
          "Math: ray hits circle");
    CheckFloat(rayDistance, 3.5f, "Math: ray distance");

    Vec3 ground;
    Check(RayPlaneY(Vec3(0.0f, 3.0f, 0.0f), Vec3(0.0f, -1.0f, 0.0f), 0.0f,
                    ground),
          "Math: ray hits ground plane");
    CheckFloat(ground.y, 0.0f, "Math: ground hit height");
}

void TestInventory()
{
    Inventory inventory;
    Check(inventory.money == 40, "Inventory: initial money");
    Check(inventory.BuyAmmo(18, 12), "Inventory: buy ammo");
    Check(inventory.money == 22 && inventory.ammoReserve == 12,
          "Inventory: ammo purchase applied");
    Check(!inventory.BuyAmmo(30, 12), "Inventory: insufficient funds");
    Check(inventory.money == 22 && inventory.ammoReserve == 12,
          "Inventory: failed purchase leaves state");

    inventory.ammoReserve = 95;
    Check(inventory.AddAmmo(12) == 4, "Inventory: ammo cap");
    Check(inventory.ammoReserve == 99, "Inventory: reserve capped");

    inventory.money = 100;
    Check(inventory.BuyMedkit(35), "Inventory: buy medkit");
    Check(inventory.medkits == 1, "Inventory: medkit added");
    inventory.medkits = 3;
    Check(!inventory.BuyMedkit(35), "Inventory: medkit cap");

    inventory.medkits = 1;
    int hp = 80;
    Check(inventory.UseMedkit(hp, 100, 40), "Inventory: use medkit");
    Check(hp == 100 && inventory.medkits == 0, "Inventory: medkit effect");
    Check(!inventory.UseMedkit(hp, 100, 40), "Inventory: medkit at full hp");

    inventory.ammoMag = 0;
    inventory.ammoReserve = 10;
    Check(inventory.Reload(), "Inventory: reload");
    Check(inventory.ammoMag == 10 && inventory.ammoReserve == 0,
          "Inventory: reload transfer");

    Inventory kit;
    kit.GiveStarterKit();
    Check(kit.hasGear && kit.ammoMag == 12 && kit.ammoReserve == 24 &&
              kit.medkits == 1,
          "Inventory: starter kit");
}

void TestQuest()
{
    QuestState quest;
    Check(MainObjective(quest) == "进入余烬酒吧", "Quest: initial objective");
    quest.main = MainStage::GO_WAREHOUSE;
    Check(!MainObjective(quest).empty(), "Quest: warehouse objective");
    quest.main = MainStage::COMPLETE;
    Check(IsMainQuestComplete(quest), "Quest: complete");
    Check(!IsSideQuestVisible(quest), "Quest: side hidden");
    quest.side = SideStage::ACCEPTED;
    Check(IsSideQuestVisible(quest), "Quest: side visible");
    Check(SideObjective(quest).find("点唱机") != std::string::npos,
          "Quest: side objective text");
}

void TestDialogue()
{
    Dialogue linear;
    linear.nodes.push_back(TestNode("第一句", 1));
    linear.nodes.push_back(TestNode("第二句", -1));

    DialogueController controller;
    controller.Start(linear);
    Check(!controller.IsFinished(), "Dialogue: started");
    controller.Update(10.0f);
    Check(controller.IsTextComplete(), "Dialogue: typewriter finished");
    controller.Advance();
    Check(controller.Current() != nullptr &&
              controller.Current()->text == "第二句",
          "Dialogue: advanced to next");
    controller.Update(10.0f);
    controller.Advance();
    Check(controller.IsFinished(), "Dialogue: finished");

    Dialogue choice;
    DialogueNode first = TestNode("选择", -1);
    first.options.push_back(DialogueOption{"选项 A", 1});
    first.options.push_back(DialogueOption{"选项 B", 2});
    choice.nodes.push_back(first);
    choice.nodes.push_back(TestNode("结果 A", -1));
    choice.nodes.push_back(TestNode("结果 B", -1));
    DialogueController choiceController;
    choiceController.Start(choice);
    choiceController.Update(10.0f);
    Check(choiceController.IsWaitingForChoice(), "Dialogue: waiting choice");
    choiceController.MoveSelection(1);
    choiceController.Confirm();
    Check(choiceController.Current() != nullptr &&
              choiceController.Current()->text == "结果 B",
          "Dialogue: option jump");

    Dialogue eventDialogue;
    eventDialogue.nodes.push_back(TestNode("事件", -1, DialogueEvent::SIDE_ACCEPT));
    DialogueController eventController;
    eventController.Start(eventDialogue);
    Check(eventController.ConsumeEvent() == DialogueEvent::SIDE_ACCEPT,
          "Dialogue: node event");
}

bool ValidPortrait(const std::string& portrait)
{
    if (portrait.empty()) {
        return true;
    }
    return portrait == "PORTRAIT_PLAYER" ||
           portrait == "PORTRAIT_BIGSISTER" ||
           portrait == "PORTRAIT_MERCHANT" ||
           portrait == "PORTRAIT_BARTENDER";
}

void ValidateDialogue(const std::string& name, const Dialogue& dialogue)
{
    bool valid = !dialogue.nodes.empty();
    int optionCount = 0;
    for (size_t i = 0; i < dialogue.nodes.size(); ++i) {
        const DialogueNode& node = dialogue.nodes[i];
        if (node.text.empty()) {
            valid = false;
        }
        if (node.next < -1 ||
            node.next >= static_cast<int>(dialogue.nodes.size())) {
            valid = false;
        }
        if (!ValidPortrait(node.portrait)) {
            valid = false;
        }
        for (const DialogueOption& option : node.options) {
            ++optionCount;
            if (option.text.empty() || option.target < -1 ||
                option.target >= static_cast<int>(dialogue.nodes.size())) {
                valid = false;
            }
        }
    }
    Check(valid, ("Story: valid nodes / " + name).c_str());

    DialogueController controller;
    controller.Start(dialogue);
    controller.Update(20.0f);
    Check(true, ("Story: startable / " + name).c_str());
    (void)optionCount;
}

void TestStory()
{
    Story story;
    QuestState quest;
    std::vector<std::pair<std::string, Dialogue>> dialogues;
    dialogues.emplace_back("intro", story.BuildIntro());
    dialogues.emplace_back("bartender_first", story.BuildBartenderFirst());
    dialogues.emplace_back("bartender_side_offer", story.BuildBartenderSideOffer());
    dialogues.emplace_back("bartender_side_complete", story.BuildBartenderSideComplete());
    dialogues.emplace_back("bartender_idle", story.BuildBartenderIdle(quest));
    dialogues.emplace_back("bigsister_first", story.BuildBigSisterFirst());
    dialogues.emplace_back("bigsister_return", story.BuildBigSisterReturn());
    dialogues.emplace_back("bigsister_idle", story.BuildBigSisterIdle(quest));
    dialogues.emplace_back("merchant_first", story.BuildMerchantFirst());
    dialogues.emplace_back("merchant_shop", story.BuildMerchantShop(0));
    dialogues.emplace_back("car_locked", story.BuildCarLocked());
    dialogues.emplace_back("bar_exit_locked", story.BuildBarExitLocked());
    dialogues.emplace_back("jukebox", story.BuildJukebox(false));
    dialogues.emplace_back("terminal", story.BuildTerminal());
    dialogues.emplace_back("ambush_warning", story.BuildAmbushWarning());
    dialogues.emplace_back("street_sign", story.BuildStreetSign());

    for (const auto& entry : dialogues) {
        ValidateDialogue(entry.first, entry.second);
    }

    const Dialogue ending = story.BuildBigSisterReturn();
    bool hasAccept = false;
    bool hasWait = false;
    for (const DialogueNode& node : ending.nodes) {
        if (node.event == DialogueEvent::EPILOGUE_ACCEPT) {
            hasAccept = true;
        }
        if (node.event == DialogueEvent::EPILOGUE_WAIT) {
            hasWait = true;
        }
    }
    Check(hasAccept && hasWait, "Story: ending choices present");
}

} // namespace

int main()
{
    std::printf("=== Ember of Free City UnitTests ===\n");
    TestMath();
    TestInventory();
    TestQuest();
    TestDialogue();
    TestStory();

    std::printf("------------------------------------\n");
    std::printf("PASSED: %d  FAILED: %d\n", g_passed, g_failed);
    return g_failed == 0 ? unittests::RESULT_OK : unittests::RESULT_FAILED;
}
