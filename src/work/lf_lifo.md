Here is how you can add a thread-local LIFO stack to worker and finder.
Instead of pushing every discovered subdirectory to the global MPMC queue (forcing threads to contend on mpmc_dequeue, rebuild full paths from root, and call openat2(AT_FDCWD, ...)), each worker keeps a local stack of subdirectories. It shares excess work with the global MPMC queue only when its local stack has plenty of items for other threads to steal.

1. Define a Small Thread-Local Stack

Add a fixed-size local stack inside ThreadLocal (no heap allocation needed). Each entry stores the directory's metadata alongside its offset in __tl.path, allowing worker to simply truncate __tl.path back to parent_path_len and append the child's name—eliminating the while (parent_idx != NO_PARENT) path reconstruction loop completely.
```c
#define LOCAL_STACK_MAX 64

typedef struct {
    uint_fast32_t parent_idx;      // Global index for cycle backtracking
    uint_fast32_t depth;
    uint_fast16_t parent_path_len; // Where to truncate __tl->path
    uint_fast16_t name_len;
    dev_t dev;
    ino_t ino;
    char name[NAME_MAX + 1];       // 256 bytes max on Linux
} LocalDirTask;

// Add to ThreadLocal:
// LocalDirTask local_stack[LOCAL_STACK_MAX];
// int local_top; // Initialize to 0 in worker()
```

2. Route Subdirectories in finder

When finder encounters a directory (__tl->effective_type == DT_DIR), keep it on __tl->local_stack if there is room. Only push to __tl->stage (the global MPMC queue) once the local stack already has a few items buffered (e.g., local_top >= 4) so idle threads still get fed quickly at startup.
```c
// Inside finder() when __tl->effective_type == DT_DIR:
__tl->d_name_len = strlen(entry->d_name);

// Keep up to 4 directories locally before spilling to the global MPMC queue,
// or keep locally anytime the staging buffer is full and local stack has space.
if (__tl->local_top < 4 || (__tl->stage_idx >= STAGE_NODES - 1 && __tl->local_top < LOCAL_STACK_MAX)) {
    LocalDirTask *task = &__tl->local_stack[__tl->local_top++];
    task->parent_idx = __tl->queue_idx;
    task->depth = __tl->depth;
    task->parent_path_len = __tl->parent_path_len;
    task->name_len = __tl->d_name_len;
    task->dev = effective_dev;
    task->ino = effective_ino;
    memcpy(task->name, entry->d_name, __tl->d_name_len + 1);
} else {
    // Spill excess subdirectories to global MPMC staging buffer for other threads
    if (__tl->stage_idx >= STAGE_NODES - 1) {
        atomic_fetch_add_explicit(&__G->active_tasks, __tl->stage_idx, memory_order_relaxed);
        if (mpmc_bulk_enqueue(__G, __tl) == false) {
            atomic_fetch_sub_explicit(&__G->active_tasks, __tl->stage_idx, memory_order_relaxed);
            atomic_fetch_add_explicit(&__G->error_count, 1, memory_order_relaxed);
            return NULL;
        }
        __tl->stage_idx = 0;
    }
    // ... existing code that populates __tl->stage[__tl->stage_idx++] ...
}
```
(Note: Because mpmc_bulk_enqueue assigns global indices in __G->dir_node[] / __G->cyc_node[] for cycle backtracking, if --follow-links is active you can either push all directories to the global staging buffer when follow_links == true or record a lightweight node in __G.)

3. Pop Locally First in worker

In worker, check __tl.local_top > 0 at the top of the while (1) loop. When popping a local task, you already have the parent path sitting in __tl.path, so constructing the child path takes a single memcpy instead of walking parent pointers all the way back to /home/bill/

```c
__tl.local_top = 0;

while (1) {
    // 1. FAST PATH: Pop from thread-local LIFO stack (zero atomics, zero path walk)
    if (__tl.local_top > 0) {
        LocalDirTask *task = &__tl.local_stack[--__tl.local_top];
        
        uint_fast32_t new_len = task->parent_path_len + 1 + task->name_len;
        if (new_len >= MAX_PATH_LEN) {
            continue;
        }

        // Append "/<child_name>" directly onto the existing parent path in __tl.path
        __tl.path[task->parent_path_len] = '/';
        memcpy(&__tl.path[task->parent_path_len + 1], task->name, task->name_len + 1);
        
        __tl.path_len = task->name_len;
        __tl.parent_path_len = new_len;
        __tl.depth = task->depth;
        __tl.queue_idx = task->parent_idx;

        finder(__G, &__tl);
        continue; // Do NOT decrement active_tasks; local tasks were never added to it!
    }

    // 2. SLOW PATH: Local stack is empty; pull from global MPMC queue
    if (mpmc_dequeue(__G, &q_pos) == false)
        break;

    // ... your existing parent-pointer path reconstruction code ...
    
    finder(__G, &__tl);
    atomic_fetch_sub_explicit(&__G->active_tasks, 1, memory_order_relaxed);
}
```

Why This Works So Well

• Zero active_tasks contention on local work. Because local tasks never enter the global MPMC queue, you never increment or decrement __G->active_tasks for them. Meanwhile, the parent task that spawned them keeps active_tasks >= 1 until its entire local subtree finishes, guaranteeing no other thread triggers shut_down early.
• Immediate parallel fan-out. Capping the local fast-path threshold at local_top < 4 ensures that as soon as the root directory (/home/bill) is scanned, any subdirectories beyond the first 4 immediately spill into mpmc_bulk_enqueue so all 16 worker threads saturate your CPU cores within microseconds.
• Cache locality. Each worker drills depth-first into its own directory subtree, keeping the kernel's dentry cache and __tl.path hot in L1/L2 cache.

After adding this local fast path and the spin-backoff in mpmc_dequeue, re-run perf record -F 4000 -g -- ./lf4 -H /home/bill >/dev/null and share the new mpmc_dequeue percentage and elapsed time—we can see how much closer you are to pure getdents64 filesystem speed.

