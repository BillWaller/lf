# MMAP two-step allocation pattern

```c
#include <stddef.h>
#include <sys/mman.h>

// 1. Reserve 1 GB of virtual address space (no physical RAM used)
size_t reserve_size = 1024ULL * 1024 * 1024;
void *base = mmap(NULL, reserve_size, PROT_NONE,
                  MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);

// 2. Commit or map a 4 MB chunk at a page-aligned offset
size_t chunk_size = 4 * 1024 * 1024;
void *chunk = mmap(base, chunk_size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
```

Reserve address space directly using mmap with PROT_NONE and MAP_NORESERVE. [1] (https://www.reddit.com/r/C_Programming/comments/18vyr9d/contiguous_allocations_with_mmap/)

The Optimal Approach: Direct mmap Reservation

One point of consensus among developers on Reddit's r/C_Programming is that the standard, high-performance pattern on Linux (commonly used in arena allocators and game engines) is a two-step mmap process:

[Two-Step Process](https://www.reddit.com/r/C_Programming/comments/18vyr9d/contiguous_allocations_with_mmap/)

1. Reserve the virtual address range. Call mmap with PROT_NONE and MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE. This allocates virtual address space in the kernel's page tables with near-zero overhead and zero physical memory usage. 

[Contiguous Allocations with MMAP](https://www.reddit.com/r/C_Programming/comments/18vyr9d/contiguous_allocations_with_mmap/)

2. Commit sub-regions on demand. When you are ready to use a portion of that space, call mmap on a page-aligned offset within that range using MAP_FIXED (or mprotect with PROT_READ | PROT_WRITE for anonymous memory).

[Contiguous Allocations with MMAP](https://www.reddit.com/r/C_Programming/comments/18vyr9d/contiguous_allocations_with_mmap/)

```c
#include <stddef.h>
#include <sys/mman.h>

// 1. Reserve 1 GB of virtual address space (no physical RAM used)
size_t reserve_size = 1024ULL * 1024 * 1024;
void *base = mmap(NULL, reserve_size, PROT_NONE,
                  MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);

// 2. Commit or map a 4 MB chunk at a page-aligned offset
size_t chunk_size = 4 * 1024 * 1024;
void *chunk = mmap(base, chunk_size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
```

Performance Tips for mmap

• Use mprotect for Anonymous Pages. If you are backing the reserved region with regular anonymous RAM rather than mapping a file descriptor, calling mprotect(addr, len, PROT_READ | PROT_WRITE) is even faster than a second mmap(..., MAP_FIXED) because it updates permissions in-place without splitting or recreating Virtual Memory Areas (VMAs) in the kernel.
• Batch Your Commits. Each mmap or mprotect syscall incurs a user-to-kernel context switch and triggers TLB shootdowns across CPU cores when permissions change. Commit memory in larger chunks (e.g., 64 KB to several megabytes) rather than page-by-page.
• Consider Huge Pages. For multi-megabyte or gigabyte reservations, adding MAP_HUGETLB (or calling madvise with MADV_HUGEPAGE) drastically reduces page table overhead and TLB misses during memory access.
Are you mapping a file into this reserved space, or building a custom arena allocator with anonymous RAM? Sharing your target allocation size can help me tailor the exact flags and madvise hints for best throughput.
