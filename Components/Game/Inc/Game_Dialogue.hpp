#ifndef __GAME_DIALOGUE_HPP__
#define __GAME_DIALOGUE_HPP__

#include <string>
#include <vector>

namespace fc {

/**
 * @brief 对话节点或对话结束时触发的事件。
 */
enum class DialogueEvent : unsigned char {
    NONE = 0,
    OPEN_SHOP,
    GIVE_STARTER_KIT,
    START_MAIN_QUEST,
    SIDE_ACCEPT,
    SIDE_DECLINE,
    SIDE_COMPLETE,
    RETURN_COMPLETE,
    EPILOGUE_ACCEPT,
    EPILOGUE_WAIT,
    REPAIR_JUKEBOX
};

/**
 * @brief 对话选项。
 */
struct DialogueOption {
    std::string text;
    int target = -1;  ///< 目标节点索引；-1 表示结束。
};

/**
 * @brief 单个对话节点。
 */
struct DialogueNode {
    std::string speaker;   ///< 说话人；空串表示旁白。
    std::string portrait;  ///< 头像资产名；空串表示无头像。
    std::string text;      ///< UTF-8 正文。
    std::vector<DialogueOption> options;
    int next = -1;         ///< 无选项时的下一节点；-1 表示结束。
    DialogueEvent event = DialogueEvent::NONE;
};

/**
 * @brief 一段完整对话。
 */
struct Dialogue {
    std::vector<DialogueNode> nodes;
    DialogueEvent completeEvent = DialogueEvent::NONE;
    bool cinematic = true;
};

/**
 * @brief 对话推进器：打字机、选项、节点跳转与事件。
 */
class DialogueController {
public:
    DialogueController() = default;

    /**
     * @brief 开始一段对话。
     * @param [IN] dialogue 对话数据（会被复制）。
     */
    void Start(const Dialogue& dialogue);

    /**
     * @brief 推进打字机。
     * @param [IN] dt 帧间隔（秒）。
     */
    void Update(float dt);

    /**
     * @brief 补全文本或进入下一节点；选项节点不自动推进。
     */
    void Advance();

    /**
     * @brief 移动选项光标。
     * @param [IN] delta -1 或 +1。
     */
    void MoveSelection(int delta);

    /**
     * @brief 直接设置选项光标（调试/测试用）。
     * @param [IN] index 选项索引，会被限制在合法范围内。
     */
    void SelectOption(int index);

    /**
     * @brief 确认当前选项。
     */
    void Confirm();

    /**
     * @brief 当前节点。
     * @return 节点指针；无效时为空。
     */
    const DialogueNode* Current() const;

    /**
     * @brief 当前可见字符数（UTF-16 单位）。
     * @return 可见字符数。
     */
    int VisibleUnits() const { return m_visibleUnits; }

    /**
     * @brief 当前节点总字符数。
     * @return 字符数。
     */
    int TotalUnits() const { return m_totalUnits; }

    /**
     * @brief 文本是否已完全显示。
     * @return 完成返回 true。
     */
    bool IsTextComplete() const { return m_visibleUnits >= m_totalUnits; }

    /**
     * @brief 是否正在等待选项。
     * @return 等待返回 true。
     */
    bool IsWaitingForChoice() const;

    /**
     * @brief 当前选项光标。
     * @return 索引。
     */
    int SelectedOption() const { return m_selectedOption; }

    /**
     * @brief 对话是否已结束。
     * @return 结束返回 true。
     */
    bool IsFinished() const { return m_finished; }

    /**
     * @brief 取出并清除待处理事件。
     * @return 事件。
     */
    DialogueEvent ConsumeEvent();

    /**
     * @brief 立即结束对话并触发完成事件。
     */
    void ForceFinish();

private:
    void EnterNode(int index);
    void Finish(DialogueEvent event);

    Dialogue m_dialogue;
    int m_index = -1;
    int m_visibleUnits = 0;
    int m_totalUnits = 0;
    float m_revealAccumulator = 0.0f;
    int m_selectedOption = 0;
    bool m_finished = true;
    DialogueEvent m_pendingEvent = DialogueEvent::NONE;
};

} // namespace fc

#endif // __GAME_DIALOGUE_HPP__
