#include "Game_Dialogue.hpp"

#include "Shared_String.hpp"

#include <algorithm>

namespace fc {

namespace {
constexpr float REVEAL_UNITS_PER_SECOND = 32.0f;
}

void DialogueController::Start(const Dialogue& dialogue)
{
    m_dialogue = dialogue;
    m_index = -1;
    m_finished = m_dialogue.nodes.empty();
    m_pendingEvent = DialogueEvent::NONE;
    m_selectedOption = 0;
    m_visibleUnits = 0;
    m_totalUnits = 0;
    m_revealAccumulator = 0.0f;
    if (!m_finished) {
        EnterNode(0);
    } else {
        m_pendingEvent = m_dialogue.completeEvent;
    }
}

void DialogueController::Update(float dt)
{
    if (m_finished || dt <= 0.0f) {
        return;
    }
    if (m_visibleUnits >= m_totalUnits) {
        return;
    }
    m_revealAccumulator += dt * REVEAL_UNITS_PER_SECOND;
    const int add = static_cast<int>(m_revealAccumulator);
    if (add > 0) {
        m_revealAccumulator -= static_cast<float>(add);
        m_visibleUnits = std::min(m_totalUnits, m_visibleUnits + add);
    }
}

void DialogueController::Advance()
{
    if (m_finished) {
        return;
    }
    const DialogueNode* node = Current();
    if (node == nullptr) {
        Finish(m_dialogue.completeEvent);
        return;
    }
    if (!IsTextComplete()) {
        m_visibleUnits = m_totalUnits;
        m_revealAccumulator = 0.0f;
        return;
    }
    if (!node->options.empty()) {
        return;
    }
    if (node->next >= 0 &&
        node->next < static_cast<int>(m_dialogue.nodes.size())) {
        EnterNode(node->next);
    } else {
        Finish(m_dialogue.completeEvent);
    }
}

void DialogueController::MoveSelection(int delta)
{
    if (!IsWaitingForChoice()) {
        return;
    }
    const DialogueNode* node = Current();
    if (node == nullptr) {
        return;
    }
    const int count = static_cast<int>(node->options.size());
    if (count <= 0) {
        return;
    }
    m_selectedOption = (m_selectedOption + delta + count) % count;
}

void DialogueController::SelectOption(int index)
{
    const DialogueNode* node = Current();
    if (node == nullptr || node->options.empty()) {
        return;
    }
    const int count = static_cast<int>(node->options.size());
    if (index < 0) {
        index = 0;
    }
    if (index >= count) {
        index = count - 1;
    }
    m_selectedOption = index;
}

void DialogueController::Confirm()
{
    if (m_finished) {
        return;
    }
    const DialogueNode* node = Current();
    if (node == nullptr) {
        Finish(m_dialogue.completeEvent);
        return;
    }
    if (!IsTextComplete()) {
        m_visibleUnits = m_totalUnits;
        m_revealAccumulator = 0.0f;
        return;
    }
    if (node->options.empty()) {
        Advance();
        return;
    }
    if (m_selectedOption < 0 ||
        m_selectedOption >= static_cast<int>(node->options.size())) {
        m_selectedOption = 0;
    }
    const DialogueOption& option = node->options[static_cast<size_t>(m_selectedOption)];
    if (option.target >= 0 &&
        option.target < static_cast<int>(m_dialogue.nodes.size())) {
        EnterNode(option.target);
    } else {
        Finish(m_dialogue.completeEvent);
    }
}

const DialogueNode* DialogueController::Current() const
{
    if (m_index < 0 || m_index >= static_cast<int>(m_dialogue.nodes.size())) {
        return nullptr;
    }
    return &m_dialogue.nodes[static_cast<size_t>(m_index)];
}

bool DialogueController::IsWaitingForChoice() const
{
    if (m_finished || !IsTextComplete()) {
        return false;
    }
    const DialogueNode* node = Current();
    return node != nullptr && !node->options.empty();
}

DialogueEvent DialogueController::ConsumeEvent()
{
    const DialogueEvent event = m_pendingEvent;
    m_pendingEvent = DialogueEvent::NONE;
    return event;
}

void DialogueController::ForceFinish()
{
    Finish(m_dialogue.completeEvent);
}

void DialogueController::EnterNode(int index)
{
    if (index < 0 || index >= static_cast<int>(m_dialogue.nodes.size())) {
        Finish(m_dialogue.completeEvent);
        return;
    }
    m_index = index;
    m_visibleUnits = 0;
    m_revealAccumulator = 0.0f;
    m_selectedOption = 0;
    const DialogueNode& node = m_dialogue.nodes[static_cast<size_t>(index)];
    m_totalUnits = static_cast<int>(Utf8ToWide(node.text).size());
    if (node.event != DialogueEvent::NONE) {
        m_pendingEvent = node.event;
    }
}

void DialogueController::Finish(DialogueEvent event)
{
    m_finished = true;
    m_index = -1;
    m_visibleUnits = 0;
    m_totalUnits = 0;
    if (event != DialogueEvent::NONE) {
        m_pendingEvent = event;
    }
}

} // namespace fc
