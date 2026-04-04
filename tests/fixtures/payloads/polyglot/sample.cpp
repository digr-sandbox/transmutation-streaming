#include <iostream>
#include <vector>
#include <memory>

namespace core {
    class NativeEngine {
    public:
        NativeEngine(int threads) : m_threads(threads) {}
        virtual ~NativeEngine() = default;
        
        void execute(const std::vector<char>& buffer) {
            if (buffer.empty()) return;
            std::cout << "Executing C++ Native" << std::endl;
        }
    private:
        int m_threads;
    };
}