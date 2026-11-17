#include "Game_Story.hpp"

#include <initializer_list>

namespace fc {

namespace {

DialogueNode Node(const char* speaker, const char* portrait, const char* text,
                  int next = -1, DialogueEvent event = DialogueEvent::NONE)
{
    DialogueNode node;
    node.speaker = speaker != nullptr ? speaker : "";
    node.portrait = portrait != nullptr ? portrait : "";
    node.text = text != nullptr ? text : "";
    node.next = next;
    node.event = event;
    return node;
}

DialogueOption Option(const char* text, int target)
{
    DialogueOption option;
    option.text = text != nullptr ? text : "";
    option.target = target;
    return option;
}

Dialogue MakeDialogue(std::initializer_list<DialogueNode> nodes,
                      DialogueEvent completeEvent = DialogueEvent::NONE,
                      bool cinematic = true)
{
    Dialogue dialogue;
    dialogue.nodes.assign(nodes.begin(), nodes.end());
    dialogue.completeEvent = completeEvent;
    dialogue.cinematic = cinematic;
    for (size_t i = 0; i < dialogue.nodes.size(); ++i) {
        DialogueNode& node = dialogue.nodes[i];
        if (node.options.empty() && node.next == -1 &&
            i + 1 < dialogue.nodes.size()) {
            node.next = static_cast<int>(i + 1);
        }
    }
    return dialogue;
}

} // namespace

Dialogue Story::BuildIntro() const
{
    return MakeDialogue({
        Node("", "", "雨敲在车顶。酒吧的霓虹在积水里碎成一片。"),
        Node("小明", "PORTRAIT_PLAYER", "就差一点……我也会和他们一起完蛋。"),
        Node("小明", "PORTRAIT_PLAYER", "……人可能都已经没了，现在找她还有用吗？"),
        Node("小明", "PORTRAIT_PLAYER", "……算了，来都来了。至少得把这件事告诉她。")
    });
}

Dialogue Story::BuildBartenderFirst() const
{
    return MakeDialogue({
        Node("小帅", "PORTRAIT_BARTENDER", "晚上好，喝点什么？"),
        Node("小明", "PORTRAIT_PLAYER", "我来找人。"),
        Node("小帅", "PORTRAIT_BARTENDER", "找谁？"),
        Node("小明", "PORTRAIT_PLAYER", "大美。"),
        Node("小帅", "PORTRAIT_BARTENDER", "头一次来我们这儿？"),
        Node("小明", "PORTRAIT_PLAYER", "嗯。"),
        Node("小帅", "PORTRAIT_BARTENDER", "难怪，以前没见过你。"),
        Node("小帅", "PORTRAIT_BARTENDER", "吧台后面那排卡座。不过她这会儿应该有客人，你可能得等一会儿。"),
        Node("小明", "PORTRAIT_PLAYER", "谢了。"),
        Node("小帅", "PORTRAIT_BARTENDER", "不客气。要喝点什么随时叫我。")
    });
}

Dialogue Story::BuildBartenderSideOffer() const
{
    Dialogue dialogue = MakeDialogue({
        Node("小帅", "PORTRAIT_BARTENDER", "还没修好呢？……你好呀，昨晚睡得还不错吧？"),
        Node("小明", "PORTRAIT_PLAYER", "挺好的。这东西坏得很严重吗？"),
        Node("小帅", "PORTRAIT_BARTENDER", "昨天我还以为只是接触不良，拆开才发现里面好几个零件都有问题。"),
        Node("小帅", "PORTRAIT_BARTENDER", "我前几天订了一批酒，本来今天中午就该送到，到现在连个影子都没见着。"),
        Node("小帅", "PORTRAIT_BARTENDER", "那边说东西到了铁港转运仓就没消息了。你能替我去看看吗？"),
        Node("小明", "PORTRAIT_PLAYER", "要是货丢了呢？"),
        Node("小帅", "PORTRAIT_BARTENDER", "那也没办法。你告诉我一声，我再找供货商想办法。"),
        Node("小帅", "PORTRAIT_BARTENDER", "反正就是跑个腿，不会让你白忙活。怎么样，愿意帮这个忙吗？")
    });
    dialogue.nodes.back().options.push_back(Option("行吧，我过去看看。", 8));
    dialogue.nodes.back().options.push_back(Option("我还有别的事情要忙。", 9));

    dialogue.nodes.push_back(Node(
        "小帅", "PORTRAIT_BARTENDER",
        "那可真是太感谢你了。地址发给你了。仓库那边最近不太平，你自己小心点。",
        -1, DialogueEvent::SIDE_ACCEPT));
    dialogue.nodes.push_back(Node(
        "小帅", "PORTRAIT_BARTENDER",
        "唉，行吧。本来还想着今天能把这破东西修好呢。看来只能自己跑一趟了。",
        -1, DialogueEvent::SIDE_DECLINE));
    return dialogue;
}

Dialogue Story::BuildBartenderSideComplete() const
{
    return MakeDialogue({
        Node("小帅", "PORTRAIT_BARTENDER", "你回来了！东西呢？"),
        Node("小明", "PORTRAIT_PLAYER", "在口袋里。"),
        Node("小帅", "PORTRAIT_BARTENDER", "就是这个……你从哪儿找到的？算了，先别管这个。给我五分钟。"),
        Node("", "", "点唱机重新亮了起来，沙哑的旋律在大厅里散开。"),
        Node("小帅", "PORTRAIT_BARTENDER", "成了！你听听，这才叫点唱机。说好的报酬，拿着。")
    }, DialogueEvent::SIDE_COMPLETE);
}

Dialogue Story::BuildBartenderIdle(const QuestState& quest) const
{
    if (quest.main < MainStage::TALK_BIGSISTER) {
        return MakeDialogue({
            Node("小帅", "PORTRAIT_BARTENDER", "大美就在吧台后面那排卡座。不过她这会儿可能有客人。")
        }, DialogueEvent::NONE, false);
    }
    if (quest.side == SideStage::ACCEPTED) {
        return MakeDialogue({
            Node("小帅", "PORTRAIT_BARTENDER", "铁港那边要是有个旧零件，顺手帮我带回来？点唱机就差它了。")
        }, DialogueEvent::NONE, false);
    }
    if (quest.side == SideStage::HAVE_PART) {
        return MakeDialogue({
            Node("小帅", "PORTRAIT_BARTENDER", "你手里那个……是不是我要找的零件？快给我看看。")
        }, DialogueEvent::NONE, false);
    }
    if (quest.side == SideStage::COMPLETED) {
        return MakeDialogue({
            Node("小帅", "PORTRAIT_BARTENDER", "想听什么歌？今天点唱机心情不错。")
        }, DialogueEvent::NONE, false);
    }
    return MakeDialogue({
        Node("小帅", "PORTRAIT_BARTENDER", "要喝点什么随时叫我。别客气。")
    }, DialogueEvent::NONE, false);
}

Dialogue Story::BuildBigSisterFirst() const
{
    return MakeDialogue({
        Node("大美", "PORTRAIT_BIGSISTER", "刚来自由城没多久？"),
        Node("小明", "PORTRAIT_PLAYER", "……嗯。"),
        Node("大美", "PORTRAIT_BIGSISTER", "我说怎么没见过你。坐吧。"),
        Node("小明", "PORTRAIT_PLAYER", "他让我来找你。"),
        Node("大美", "PORTRAIT_BIGSISTER", "哦，他怎么了？"),
        Node("小明", "PORTRAIT_PLAYER", "他遇到了点麻烦，想请你帮忙。不过……现在可能已经来不及了。"),
        Node("大美", "PORTRAIT_BIGSISTER", "Fortshine 终于去收拾他了？"),
        Node("小明", "PORTRAIT_PLAYER", "我刚离开据点，公司的人就到了。他们封锁了街道，直接冲了进去。"),
        Node("大美", "PORTRAIT_BIGSISTER", "那他人呢？"),
        Node("小明", "PORTRAIT_PLAYER", "不知道。我没敢回去。"),
        Node("大美", "PORTRAIT_BIGSISTER", "这个蠢货。我早就跟他说过，别去参和公司的破事。"),
        Node("大美", "PORTRAIT_BIGSISTER", "你是为了思维接入，才去跟着他的吧？"),
        Node("小明", "PORTRAIT_PLAYER", "……你怎么知道？"),
        Node("大美", "PORTRAIT_BIGSISTER", "见得多了。多少人花光积蓄来到自由城，结果发现想找份正经工作还得再交一大笔钱。"),
        Node("大美", "PORTRAIT_BIGSISTER", "这时候有人愿意给条门路，自然就有人肯替他卖命。你也是这样吧？"),
        Node("小明", "PORTRAIT_PLAYER", "……嗯。"),
        Node("大美", "PORTRAIT_BIGSISTER", "不过你也别太灰心。城里又不是只有他一个人有门路。"),
        Node("小明", "PORTRAIT_PLAYER", "你也能弄到？"),
        Node("大美", "PORTRAIT_BIGSISTER", "我不做这个生意。不过我认识个专门倒腾这些东西的家伙。"),
        Node("大美", "PORTRAIT_BIGSISTER", "对了，你老板在铁港还有个仓库，对吧？"),
        Node("小明", "PORTRAIT_PLAYER", "嗯，替他送过几次货。"),
        Node("大美", "PORTRAIT_BIGSISTER", "我之前托他转交过一批东西。现在他出了这么大的事，那批货恐怕也没人管了。"),
        Node("大美", "PORTRAIT_BIGSISTER", "你熟悉那边，帮我跑一趟怎么样？最好今晚就把东西取回来。"),
        Node("大美", "PORTRAIT_BIGSISTER", "要是碰上公司的人，直接回来就行。那点货还不值得拿命去换。"),
        Node("小明", "PORTRAIT_PLAYER", "报酬怎么算？"),
        Node("大美", "PORTRAIT_BIGSISTER", "货带回来，给你一百八。怎么样？"),
        Node("小明", "PORTRAIT_PLAYER", "成交。"),
        Node("大美", "PORTRAIT_BIGSISTER", "不过……你这次带装备了吗？"),
        Node("小明", "PORTRAIT_PLAYER", "走得急，什么都没有拿。"),
        Node("大美", "PORTRAIT_BIGSISTER", "那正好。东子除了接入装置，还倒腾些武器、弹药。第一套算我请你的。"),
        Node("大美", "PORTRAIT_BIGSISTER", "转角那个卡座，一直低头摆弄老古董的就是他。")
    });
}

Dialogue Story::BuildBigSisterReturn() const
{
    Dialogue dialogue = MakeDialogue({
        Node("大美", "PORTRAIT_BIGSISTER", "哟，回来啦？"),
        Node("小明", "PORTRAIT_PLAYER", "嗯，东西拿回来了。"),
        Node("大美", "PORTRAIT_BIGSISTER", "怎么样，在铁港没遇上什么麻烦吧？"),
        Node("小明", "PORTRAIT_PLAYER", "几个想趁火打劫的拾荒者，打发走了。后来公司的人也来了。"),
        Node("大美", "PORTRAIT_BIGSISTER", "手脚挺利索。"),
        Node("", "", "她打开箱子，动作忽然停住。里面是一排用防静电袋包好的神经桥。"),
        Node("大美", "PORTRAIT_BIGSISTER", "你打开看过吗？"),
        Node("小明", "PORTRAIT_PLAYER", "没有。"),
        Node("大美", "PORTRAIT_BIGSISTER", "最好没有。"),
        Node("小明", "PORTRAIT_PLAYER", "这是……"),
        Node("大美", "PORTRAIT_BIGSISTER", "接入装置。没登记的，查不到来源，也不会上传你的名字。"),
        Node("大美", "PORTRAIT_BIGSISTER", "我本来打算把它们拆开，分批送给几个和你差不多的人。现在公司盯上了这批货，得换个地方。"),
        Node("大美", "PORTRAIT_BIGSISTER", "你为了这东西，跟了那个蠢货那么久。现在它就在你面前。"),
        Node("小明", "PORTRAIT_PLAYER", "……用了它，我就能找到正经工作了？"),
        Node("大美", "PORTRAIT_BIGSISTER", "能。然后你就会变成系统里的一个名字，一条记录，一个随时可以被找到的人。"),
        Node("大美", "PORTRAIT_BIGSISTER", "想清楚。自由城不会因为你接入了就变好，只是你终于有资格排队了。"),
        Node("大美", "PORTRAIT_BIGSISTER", "想要的话，拿一个走。就当今晚的报酬。")
    });
    dialogue.nodes.back().options.push_back(Option("我接。", 17));
    dialogue.nodes.back().options.push_back(Option("再等等。", 18));
    dialogue.nodes.push_back(Node("小明", "PORTRAIT_PLAYER",
                                  "我把那枚东西攥在手里，很轻，像一枚硬币。",
                                  -1, DialogueEvent::EPILOGUE_ACCEPT));
    dialogue.nodes.push_back(Node("小明", "PORTRAIT_PLAYER",
                                  "我把手收了回来。不是不想要。只是还没想好，要用什么来换。",
                                  -1, DialogueEvent::EPILOGUE_WAIT));
    return dialogue;
}

Dialogue Story::BuildBigSisterIdle(const QuestState& quest) const
{
    if (quest.main < MainStage::GET_GEAR) {
        return MakeDialogue({
            Node("大美", "PORTRAIT_BIGSISTER", "先去找东子把装备领了。空着手去铁港，可不是什么好主意。")
        }, DialogueEvent::NONE, false);
    }
    if (quest.main == MainStage::GO_WAREHOUSE) {
        return MakeDialogue({
            Node("大美", "PORTRAIT_BIGSISTER", "铁港那边不太平。碰上公司的人，直接回来。别硬来。")
        }, DialogueEvent::NONE, false);
    }
    if (quest.main == MainStage::DEFEAT_AGENTS) {
        return MakeDialogue({
            Node("大美", "PORTRAIT_BIGSISTER", "还愣着干什么？把货带回来。")
        }, DialogueEvent::NONE, false);
    }
    return MakeDialogue({
        Node("大美", "PORTRAIT_BIGSISTER", "坐吧。今晚辛苦了。")
    }, DialogueEvent::NONE, false);
}

Dialogue Story::BuildMerchantFirst() const
{
    return MakeDialogue({
        Node("东子", "PORTRAIT_MERCHANT", "欢迎光临，你要买什么？"),
        Node("小明", "PORTRAIT_PLAYER", "大美让我来找你。"),
        Node("东子", "PORTRAIT_MERCHANT", "哦，你就是她刚才说的那个倒霉蛋啊。东西已经在给你准备了。"),
        Node("小明", "PORTRAIT_PLAYER", "听说你能弄到思维接入装置？"),
        Node("东子", "PORTRAIT_MERCHANT", "能倒是能，不过这价钱可不便宜。你自己看看吧。"),
        Node("东子", "PORTRAIT_MERCHANT", "其他东西也可以随便看看，有什么感兴趣的尽管问。")
    }, DialogueEvent::OPEN_SHOP);
}

Dialogue Story::BuildMerchantShop(int purchaseCount) const
{
    if (purchaseCount <= 0) {
        return MakeDialogue({
            Node("东子", "PORTRAIT_MERCHANT", "欢迎光临，今天想买点什么？正好刚到了些新货。")
        }, DialogueEvent::OPEN_SHOP, false);
    }
    if (purchaseCount < 3) {
        return MakeDialogue({
            Node("东子", "PORTRAIT_MERCHANT", "又来了？补给这东西，永远不嫌多。")
        }, DialogueEvent::OPEN_SHOP, false);
    }
    return MakeDialogue({
        Node("东子", "PORTRAIT_MERCHANT", "你倒是照顾我生意。放心，下次给你留点好货。")
    }, DialogueEvent::OPEN_SHOP, false);
}

Dialogue Story::BuildCarLocked() const
{
    return MakeDialogue({
        Node("小明", "PORTRAIT_PLAYER", "现在还不是去铁港的时候。先弄清楚该怎么走。")
    }, DialogueEvent::NONE, false);
}

Dialogue Story::BuildBarExitLocked() const
{
    return MakeDialogue({
        Node("小明", "PORTRAIT_PLAYER", "还没弄清楚该做什么。先和酒吧里的人聊聊。")
    }, DialogueEvent::NONE, false);
}

Dialogue Story::BuildJukebox(bool repaired) const
{
    if (repaired) {
        return MakeDialogue({
            Node("", "", "点唱机放着沙哑的老歌。小帅把它修好了。")
        }, DialogueEvent::NONE, false);
    }
    return MakeDialogue({
        Node("", "", "外壳上几道旧划痕，歌单停留在二十年前。它没有反应。")
    }, DialogueEvent::NONE, false);
}

Dialogue Story::BuildTerminal() const
{
    return MakeDialogue({
        Node("", "", "旧式账本终端。屏幕上的字被灰尘磨得发白。"),
        Node("", "", "账户余额：40　　身份验证：待补全　　激活资格：未确认"),
        Node("", "", "思维接入装置：500　　账户托管方：已注销"),
        Node("", "", "屏幕闪了两下，跳出一行红字：ACCESS DENIED。"),
        Node("小明", "PORTRAIT_PLAYER", "……又是这个词。")
    }, DialogueEvent::NONE, false);
}

Dialogue Story::BuildStreetSign() const
{
    return MakeDialogue({
        Node("", "", "AFTERGLOW。招牌只亮着一半，另一半像被人掐住了喉咙。")
    }, DialogueEvent::NONE, false);
}

Dialogue Story::BuildAmbushWarning() const
{
    return MakeDialogue({
        Node("", "", "东侧的卷帘门亮起刺眼的红光。"),
        Node("特工", "", "目标确认。交出资产。"),
        Node("特工", "", "封锁已生效。")
    });
}

} // namespace fc
