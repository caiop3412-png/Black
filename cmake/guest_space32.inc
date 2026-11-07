#ifndef _WIN32
// armv7: reserve the guest space as three ranges instead of one 4 GB block. Guest address va is host address base + va
// (modulo 2^32), so the search is for a base where every range falls on free host memory. The ranges are the low block
// (user + system pool + stacks, contiguous in guest space), the contiguous window and the write combine window.
static void* ReserveGuestSpace(uint64_t) {
    struct Chunk {
        uint32_t va, size;
    };
    const Chunk chunks[] = {{kUserLow, kStackBase + kStackSize - kUserLow},
                            {kContiguousBase, kPhysicalSize},
                            {kWriteCombineBase, kPhysicalSize}};
    constexpr int kChunks = sizeof(chunks) / sizeof(chunks[0]);
    int tried = 0;
    for (uint64_t base = 0x00400000; base < 0x100000000ull; base += 0x00400000) {
        void* got[kChunks] = {};
        bool ok = true;
        for (int i = 0; i < kChunks && ok; i++) {
            uint64_t host = uint32_t(base + chunks[i].va);
            if (host < 0x10000 || host + chunks[i].size > 0x100000000ull) {
                ok = false;
                break;
            }
            void* want = reinterpret_cast<void*>(uintptr_t(host));
            void* p = mmap(want, chunks[i].size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
            if (p == MAP_FAILED) {
                ok = false;
                break;
            }
            got[i] = p;
            if (p != want) ok = false;  // the kernel put it elsewhere: the hinted range was taken
        }
        tried++;
        if (ok) {
            LOGI("memory: guest ranges mapped around host base %08X (%d tries)", uint32_t(base), tried);
            return reinterpret_cast<void*>(uintptr_t(base));
        }
        for (int i = 0; i < kChunks; i++)
            if (got[i]) munmap(got[i], chunks[i].size);
    }
    LOGE("memory: no host base has the three guest ranges free (%d tries)", tried);
    return MAP_FAILED;
}
#endif
