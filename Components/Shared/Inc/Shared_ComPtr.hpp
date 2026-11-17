#ifndef __SHARED_COMPTR_HPP__
#define __SHARED_COMPTR_HPP__

#include <cstddef>
#include <utility>

namespace fc {

/**
 * @brief 轻量 COM 智能指针，避免依赖 WRL，仅覆盖项目所需的接口。
 * @tparam T COM 接口类型，必须提供 AddRef/Release。
 */
template <typename T>
class ComPtr {
public:
    ComPtr() = default;
    ~ComPtr() { Reset(); }

    ComPtr(const ComPtr&) = delete;
    ComPtr& operator=(const ComPtr&) = delete;

    ComPtr(ComPtr&& other) noexcept : m_ptr(other.m_ptr) { other.m_ptr = nullptr; }

    ComPtr& operator=(ComPtr&& other) noexcept
    {
        if (this != &other) {
            Reset();
            m_ptr = other.m_ptr;
            other.m_ptr = nullptr;
        }
        return *this;
    }

    /**
     * @brief 释放当前接口并置空。
     */
    void Reset()
    {
        if (m_ptr != nullptr) {
            m_ptr->Release();
            m_ptr = nullptr;
        }
    }

    /**
     * @brief 获取接口指针。
     * @return 裸指针，可能为空。
     */
    T* Get() const { return m_ptr; }

    /**
     * @brief 获取用于接收新接口的地址。
     * @return 指向内部指针的地址；调用前必须为空。
     */
    T** GetAddressOf()
    {
        Reset();
        return &m_ptr;
    }

    /**
     * @brief 获取用于接收新接口的地址（供 out 参数使用）。
     * @return 指向内部指针的地址。
     */
    T** ReleaseAndGetAddressOf()
    {
        Reset();
        return &m_ptr;
    }

    T* operator->() const { return m_ptr; }
    explicit operator bool() const { return m_ptr != nullptr; }

    bool operator==(std::nullptr_t) const { return m_ptr == nullptr; }
    bool operator!=(std::nullptr_t) const { return m_ptr != nullptr; }

    /**
     * @brief 接管一个已增加引用计数的指针。
     * @param [IN] ptr 裸指针。
     */
    void Attach(T* ptr)
    {
        Reset();
        m_ptr = ptr;
    }

    /**
     * @brief 放弃所有权。
     * @return 裸指针，调用者负责释放。
     */
    T* Detach()
    {
        T* result = m_ptr;
        m_ptr = nullptr;
        return result;
    }

private:
    T* m_ptr = nullptr;
};

} // namespace fc

#endif // __SHARED_COMPTR_HPP__
