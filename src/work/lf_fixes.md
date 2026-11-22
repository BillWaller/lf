# lf4 Performance Analytics & Race Condition Debugging 

------------------------------------------------
find /home/bill

0.43user 0.48system 0:00.91elapsed 99%CPU (0avgtext+0avgdata 35488maxresident)k
0inputs+0outputs (0major+11824minor)pagefaults 0swaps
found 541151 files

------------------------------------------------
fd . -H -I /home/bill

0.89user 0.73system 0:00.21elapsed 753%CPU (0avgtext+0avgdata 67276maxresident)k
0inputs+0outputs (0major+15064minor)pagefaults 0swaps
expected 541150 files, found 541150 files

------------------------------------------------
./lf -H /home/bill

0.29user 0.69system 0:00.09elapsed 1036%CPU (0avgtext+0avgdata 20808maxresident)k
0inputs+0outputs (0major+514minor)pagefaults 0swaps
expected 541150 files, found 541150 files

------------------------------------------------
./lf2 -H /home/bill

0.28user 0.67system 0:00.09elapsed 1026%CPU (0avgtext+0avgdata 20936maxresident)k
0inputs+0outputs (0major+515minor)pagefaults 0swaps
expected 541150 files, found 541150 files

------------------------------------------------
./lf3 -H /home/bill

0.30user 0.76system 0:00.12elapsed 882%CPU (0avgtext+0avgdata 149672maxresident)k
0inputs+0outputs (0major+805minor)pagefaults 0swaps
expected 541150 files, found 541150 files

------------------------------------------------
./lf4 -H /home/bill

0.22user 0.70system 0:00.08elapsed 1043%CPU (0avgtext+0avgdata 17964maxresident)k
0inputs+0outputs (0major+695minor)pagefaults 0swaps
expected 541150 files, found 541150 files

---

Notice that the benchmarks above all found the expected number of files, but in the next benchmark which was run by the same test harness, lf4 found 541144 files instead of the expected 541151. Running the same benchmark repeatedly produced erratic results.

---

./lf4 -H /home/bill

0.21user 0.72system 0:00.09elapsed 1041%CPU (0avgtext+0avgdata 18036maxresident)k
0inputs+0outputs (0major+695minor)pagefaults 0swaps
expected 541151 files, found 541144 files
         ------              ------

------------------------------------------------

I believe I have narrowed the problem down to a loop in mpmc_bulk_enqueue().
The first part of mpmc_bulk_enqueue reserves the number of slots needed to
commit nodes staged in the finder.

I inserted an fprintf statement in an attempt to debug the issue, but that
somehow stabilized the offending code, and the number of files found is
rock-solid as long as the DEBUGZ flag remains true. Remove the "#define DEBUGZ 1"
and the number of files found becomes erratic.

This is a classic "Heisenbug" caused by either a memory-ordering / compiler-barrier issue in your lock-free MPMC queue or an early termination condition, which fprintf masks by introducing a lock, a syscall, and a full compiler/memory fence.

Why Helgrind Missed It & Why fprintf Stabilizes It

1. Why Helgrind reported 0 errors: Helgrind tracks POSIX synchronization primitives (pthread_mutex_t, pthread_cond_t, etc.) and relies on happens-before edges from those calls. If your MPMC ring buffer uses C11 <stdatomic.h> or GCC __atomic_* builtins directly without pthread locks, Helgrind cannot observe the happens-before relationships between atomic loads/stores and often misses subtle memory-ordering bugs (like memory_order_relaxed where acquire/release is required). (Note: GCC's ThreadSanitizer, compiled with -fsanitize=thread, is much better at catching C11 atomic data races than Helgrind.)

2. Why #define DEBUGZ 1 with fprintf hides the bug: Calling fprintf inside mpmc_bulk_enqueue() alters execution in three critical ways:
	• Compiler & Memory Barrier: fprintf is an external function call that forces the compiler to flush registers to memory and prevents instruction reordering across the call.
	• Serialization (flockfile): fprintf acquires an internal FILE* mutex under the hood, effectively turning your lock-free concurrent enqueue into a serialized, lock-protected operation and eliminating simultaneous CAS contention.
	• Timing / Backoff: The I/O latency gives consumer threads plenty of time to drain the queue and advance sequence numbers, preventing wrap-around or premature "queue empty / all workers done" termination checks.

Likely Culprits in mpmc_bulk_enqueue()

When a bulk enqueue drops a handful of items (e.g., 7 out of 541,151) only under full concurrency, the root cause is usually one of three patterns:

• Premature Termination Detection: A worker or coordinator checks if the queue is empty and all threads are idle while another thread has reserved slots in mpmc_bulk_enqueue() (advancing the tail index) but has not yet published the data/sequence numbers into those slots. Without fprintf slowing things down, the consumer sees head == tail or an unready sequence number and exits early, abandoning the in-flight batch.

• Weak Memory Ordering on Slot Publication: If slot reservation uses atomic_compare_exchange_weak(..., memory_order_relaxed, ...) and writes the node pointers before publishing the slot's sequence number with memory_order_relaxed instead of memory_order_release, another core can observe the updated sequence number before the node data is visible—or overwrite an unconsumed slot.

• Missing Volatile / Atomic Reload in the Reservation Loop: If the CAS loop reads the tail or head into a local variable outside the retry loop or uses a non-atomic load, the compiler may cache the value in a register across iterations when DEBUGZ is disabled.


```c
// Author Bill Waller
typedef struct {
    uint_fast32_t parent_idx;           //   4
    uint_fast32_t path_offset;          //   4
    uint_fast32_t path_len;             //   4
    uint_fast32_t child_dirs_remaining; //   4
    uint_fast32_t depth;                //   4
    dev_t dev;                          //   8
    ino_t ino;                          //   8
} QueueNode;                            //  36 bytes total

alignas(CACHE_LINE_SIZE) QueueNode *queue;
    alignas(CACHE_LINE_SIZE) char *path_data;
    alignas(CACHE_LINE_SIZE) atomic_uint_fast32_t path_offset;
    alignas(CACHE_LINE_SIZE) atomic_uint_fast32_t shut_down;
    alignas(CACHE_LINE_SIZE) atomic_uint_fast32_t enqueue_pos;
    alignas(CACHE_LINE_SIZE) atomic_uint_fast32_t dequeue_pos;
    alignas(CACHE_LINE_SIZE) atomic_uint_fast32_t active_tasks;
    alignas(CACHE_LINE_SIZE) atomic_uint_fast32_t queue_idx;
    alignas(CACHE_LINE_SIZE) atomic_uint_fast32_t thread_id;
    alignas(CACHE_LINE_SIZE) atomic_uint_fast32_t sequence[QUEUE_NODES];
    ...

} GlobalContext;


bool mpmc_bulk_enqueue(GlobalContext *__G, ThreadLocal *__tl) {
    if (__tl->stage_idx == 0)
        return true;
    uint_fast32_t spin_count = 0;
    uint_fast32_t base_idx = atomic_load_explicit(&__G->enqueue_pos, memory_order_acquire);
    while (true) {
        // Check slots from [base_idx] to [base_idx + __tl->stage_idx - 1]
        bool block_available = true;
        uint_fast32_t i;
        uint_fast32_t seq;
        uint_fast32_t queue_idx;
        for (i = 0; i < __tl->stage_idx; ++i) {
            queue_idx = (base_idx + i) & QUEUE_MASK;
            seq = atomic_load_explicit(&__G->sequence[queue_idx], memory_order_acquire);
            if ((intptr_t)seq - (intptr_t)queue_idx != 0) {
                block_available = false;
                break;
            }
        }
        if (block_available) { // Success
            if (atomic_compare_exchange_weak_explicit(
                    &__G->enqueue_pos, &base_idx, base_idx + __tl->stage_idx,
                    memory_order_relaxed, memory_order_relaxed)) {
                break; // Success, slot reservation finalized
            }
        } else {
            return false; // Fail: Queue is full
        }
        if (++spin_count < 64) {
            for (i = 0; i < spin_count; i++) {
#if defined(__x86_64__)
                __builtin_ia32_pause();
#endif
            }
        } else {
            sched_yield();
        }
    }
    for (uint_fast32_t sidx = 0; sidx < __tl->stage_idx; ++sidx) {

        uint_fast32_t enqueue_pos = (base_idx + sidx) & QUEUE_MASK;
        __G->queue[enqueue_pos] = __tl->stage_node[sidx];
        uint_fast32_t len_to_add = __tl->stage_node[sidx].path_len + 1;
        uint_fast32_t offset = atomic_fetch_add_explicit(&__G->path_offset,
                                                         len_to_add, memory_order_acquire);
        if (__builtin_expect(offset + len_to_add >= PATH_BYTES, 0)) {
            fprintf(stderr, "Fatal: Path arena exhausted (%lu / %d bytes)\n", offset + len_to_add, PATH_BYTES);
            return false;
        }
        memcpy(&__G->path_data[offset],
               &__tl->path_data[__tl->stage_node[sidx].path_offset],
               __tl->stage_node[sidx].path_len);
#ifdef DEBUGZ
        char *path = &__tl->path_data[__tl->stage_node[sidx].path_offset];
        fprintf(stderr, "line: %d, %s, enqueued pos %lu, sidx %lu, path: %s\n", __LINE__, __func__, enqueue_pos, sidx, path);
#endif
        __G->queue[enqueue_pos].path_offset = offset;
        __G->path_data[offset + __tl->stage_node[sidx].path_len] = '\0';
        // ANNOTATE_HAPPENS_BEFORE(&__G->queue[enqueue_pos]);
        // forces unconditional atomic read-write that Helgrind can't
        // misinterpret
        uint_fast32_t target_seq = base_idx + sidx + 1;
        atomic_exchange_explicit(&__G->sequence[enqueue_pos],
                                 target_seq, memory_order_release);
        atomic_thread_fence(memory_order_release);
        __tl->cum_path_offset = 0;
    }
    return true;
}

```

Found two bugs in mpmc_bulk_enqueue(), including a critical wrap-around bug in the sequence check that explains why items are dropped under high concurrency and why fprintf hides it.

1. The Primary Bug: seq - queue_idx != 0 Breaks After One Queue Wrap-Around (and Races with Other Producers)

Look at your slot availability check:

```c
queue_idx = (base_idx + i) & QUEUE_MASK;
seq = atomic_load_explicit(&__G->sequence[queue_idx], memory_order_acquire);
if ((intptr_t)seq - (intptr_t)queue_idx != 0) {
    block_available = false;
    break;
}
```

And look at how you publish target_seq:

```c
uint_fast32_t target_seq = base_idx + sidx + 1;
```

In a Vyukov-style MPMC queue, base_idx is a monotonically increasing counter (not masked), whereas queue_idx = (base_idx + i) & QUEUE_MASK is masked to \[0, QUEUE_NODES - 1\].

• What happens after the queue wraps around once (base_idx >= QUEUE_NODES): When a consumer finishes consuming slot queue_idx, it resets __G->sequence\[queue_idx\] to the next expected unmasked position: (old_base_idx + QUEUE_NODES) (i.e., base_idx + i).

• Because your check compares seq against the masked queue_idx instead of the unmasked position pos = base_idx + i, as soon as base_idx >= QUEUE_NODES (or when another producer has already reserved base_idx + i and set seq to base_idx + i + 1 while base_idx is stale), (intptr_t)seq - (intptr_t)queue_idx != 0 evaluates to true!

• Why mpmc_bulk_enqueue drops the files: When that check fails, your function hits else { return false; }. If the caller doesn't fall back to single-item enqueues or doesn't flush/retry when mpmc_bulk_enqueue returns false, those __tl->stage_idx staged directories are silently dropped!

• Why fprintf hid it: fprintf slows producers down just enough that the queue never backs up / wraps around in the way that triggers the stale base_idx vs. queue_idx mismatch—or keeps mpmc_bulk_enqueue from hitting the return false branch.

2. Secondary Bug: Prematurely Returning false on a Stale base_idx

Even before wrap-around, look at what happens when Producer A and Producer B enter mpmc_bulk_enqueue() at the same time:

1. Both load base_idx = 100.

2. Producer A wins the atomic_compare_exchange_weak_explicit, advancing enqueue_pos to 105, and writes target_seq = 101..105 into sequence[100..104].

3. Producer B hasn't reached the CAS yet, so its local base_idx is still 100! It reads sequence\[100\], sees seq == 101 (not 100), sets block_available = false, and immediately executes return false;—reporting "Queue is full" when the queue isn't full at all! It simply read a stale base_idx before attempting the CAS.
In a CAS loop, you must only treat the queue as full if seq < pos (meaning the consumer hasn't freed that slot yet). If seq > pos, another producer already claimed pos—you must reload base_idx and retry the loop rather than returning false!

How to Fix mpmc_bulk_enqueue()

1. Compare seq against the unmasked pos = base_idx + i, not the masked queue_idx.

2. Distinguish between "another producer beat me" (dif > 0) and "queue is genuinely 
full"

    (dif < 0):
	• dif == 0: Slot is free for this pos.
	• dif < 0: Consumer hasn't finished the previous lap (seq < pos) → Queue is actually full; return false (or spin/yield).
	• dif > 0: Another producer already claimed pos (seq > pos) → Reload base_idx from enqueue_pos and retry!

3. Also verify how mpmc_dequeue resets sequence\[dequeue_pos\]: When mpmc_dequeue finishes reading slot pos (unmasked), it must store pos + QUEUE_NODES into sequence\[pos & QUEUE_MASK\] with memory_order_release so the next lap's producer sees seq == pos_next_lap.

Corrected Reservation Loop

```c
    uint_fast32_t spin_count = 0;
    uint_fast32_t base_idx = atomic_load_explicit(&__G->enqueue_pos, memory_order_relaxed);

    while (true) {
        bool block_available = true;
        bool queue_full = false;

        for (uint_fast32_t i = 0; i < __tl->stage_idx; ++i) {
            uint_fast32_t pos = base_idx + i;
            uint_fast32_t queue_idx = pos & QUEUE_MASK;
            uint_fast32_t seq = atomic_load_explicit(&__G->sequence[queue_idx], memory_order_acquire);
            intptr_t dif = (intptr_t)seq - (intptr_t)pos;

            if (dif < 0) {
                // Slot is still occupied from the previous lap -> genuinely full
                block_available = false;
                queue_full = true;
                break;
            } else if (dif > 0) {
                // Another producer already claimed this slot -> base_idx is stale
                block_available = false;
                break;
            }
        }

        if (queue_full) {
            return false; // Caller should fall back to local stack or single enqueue
        }

        if (block_available) {
            if (atomic_compare_exchange_weak_explicit(
                    &__G->enqueue_pos, &base_idx, base_idx + __tl->stage_idx,
                    memory_order_relaxed, memory_order_relaxed)) {
                break; // Reservation finalized; base_idx holds our starting position
            }
            // CAS failed: base_idx was automatically updated with the current enqueue_pos
        } else {
            // dif > 0: Reload fresh base_idx before backing off/retrying
            base_idx = atomic_load_explicit(&__G->enqueue_pos, memory_order_relaxed);
        }

        if (++spin_count < 64) {
            for (uint_fast32_t i = 0; i < spin_count; i++) {
#if defined(__x86_64__)
                __builtin_ia32_pause();
#endif
            }
        } else {
            sched_yield();
        }
    }
```

Two Bonus Cleanup Notes in the Second Loop

• __tl->cum_path_offset = 0;: You reset this inside the for (sidx ...) loop on every iteration instead of once after the loop finishes. Move it outside the loop (along with resetting __tl->stage_idx = 0; if the caller expects mpmc_bulk_enqueue to clear the staging buffer).

• Redundant fence: atomic_exchange_explicit(&__G->sequence\[enqueue_pos\], target_seq, memory_order_release) already provides release semantics (and atomic_store_explicit(..., memory_order_release) is slightly cheaper than an exchange XCHG on x86-64 since you don't use the return value). The trailing atomic_thread_fence(memory_order_release) is unnecessary.
Would you like to share mpmc_dequeue() and the call site of mpmc_bulk_enqueue() so we can verify that:
\
• mpmc_dequeue() resets sequence to pos + QUEUE_NODES properly on wrap-around

• The caller handles a false (queue full) return without dropping staged directories

I have run it 10 times and get the correct number of files each time. However, I would like for you to look at mpmc_dequeue to see if I have errors there, and possibly also my staging code. Here's mpmc_dequeuebool mpmc_dequeue

```c
// Author Bill Waller
(LfCtx *lf, QueuePayload *dequeued_node) {
    // Use memory_order_relaxed for the initial position load;
    // CAS handles synchronization
    size_t pos = atomic_load_explicit(&lf->q->dequeue_pos, memory_order_relaxed);
    while (true) {
        if (atomic_load_explicit(&lf->q->shut_down, memory_order_relaxed))
            return false;
        size_t seq = atomic_load_explicit(&lf->q->sequence[pos & QUEUE_MASK],
                                          memory_order_acquire);
        intptr_t diff = (intptr_t)seq - (intptr_t)(pos + 1);
        if (diff == 0) { // Success
            if (atomic_compare_exchange_weak_explicit(&lf->q->dequeue_pos, &pos,
                                                      pos + 1, memory_order_acquire,
                                                      memory_order_relaxed)) {
                break;
            }
        } else if (diff < 0) { // Queue empty
            // Queue is temporarily empty. Check global task counter safely.
            // If active_tasks is 0, we can safely initiate a shutdown check.
            if (atomic_load_explicit(&lf->q->active_tasks, memory_order_relaxed) ==
                0) {
                // Re-verify the queue state hasn't moved under high thread pressure
                size_t check_pos =
                    atomic_load_explicit(&lf->q->dequeue_pos, memory_order_relaxed);
                size_t check_seq = atomic_load_explicit(
                    &lf->q->sequence[check_pos & QUEUE_MASK], memory_order_acquire);
                if ((intptr_t)check_seq - (intptr_t)(check_pos + 1) < 0) {
                    atomic_store_explicit(&lf->q->shut_down, 1, memory_order_release);
                    return false;
                }
            }
#if defined(__x86_64__)
            __builtin_ia32_pause();
#else
            sched_yield();
#endif
            pos = atomic_load_explicit(&lf->q->dequeue_pos, memory_order_relaxed);
        } else { // Already consumed by another thread, try again
            pos = atomic_load_explicit(&lf->q->dequeue_pos, memory_order_relaxed);
        }
    }
    // Extract the element safely from our uniquely owned slot index
    if (dequeued_node)
        // *dequeued_node = lf->queue_arena->nodes[pos & QUEUE_MASK];
        *dequeued_node = lf->q->nodes[pos & QUEUE_MASK];
    // CRITICAL FIX: Advance sequence by the macro ring capacity wrapper
    // (QUEUE_CAPACITY). This flips the sequence flag to match the next possible
    // enqueue phase loop iteration.
    atomic_store_explicit(&lf->q->sequence[pos & QUEUE_MASK], pos + QUEUE_NODES,
                          memory_order_release);
    return true;
}
```

Your core Vyukov dequeue logic (the diff == 0 CAS and advancing sequence to pos + QUEUE_NODES) is solid, but there are three subtle race conditions in the shutdown check, active_tasks ordering, and integer width.

1. Subtle Shutdown Race Condition (diff < 0 + active_tasks == 0)

Look closely at your empty-queue shutdown check:

```c
if (atomic_load_explicit(&lf->q->active_tasks, memory_order_relaxed) == 0) {
    size_t check_pos = atomic_load_explicit(&lf->q->dequeue_pos, memory_order_relaxed);
    size_t check_seq = atomic_load_explicit(&lf->q->sequence[check_pos & QUEUE_MASK], memory_order_acquire);
    if ((intptr_t)check_seq - (intptr_t)(check_pos + 1) < 0) {
        atomic_store_explicit(&lf->q->shut_down, 1, memory_order_release);
        return false;
    }
}
```

Here is how a race can still occur right as the very last directory finishes:

1. Worker A is the only active worker (active_tasks == 1). It finishes scanning a directory, stages 3 subdirectories, and calls mpmc_bulk_enqueue().

2. Worker A wins the enqueue_pos CAS (advancing enqueue_pos from 10 to 13), but hasn't written sequence[10..12] yet (or hasn't incremented active_tasks yet, depending on where you increment active_tasks).

3. Meanwhile, Worker B is spinning in mpmc_dequeue() at pos = 10:
	• If you decrement active_tasks before mpmc_bulk_enqueue finishes publishing sequence—or if active_tasks is incremented after mpmc_bulk_enqueue—there is a brief window where active_tasks == 0 and sequence\[10\] is still 10 (not 11)!
	• Worker B sees active_tasks == 0 and check_seq - (check_pos + 1) < 0, sets shut_down = 1, and kills all workers while Worker A's 3 subdirectories are still in flight!

How to Prevent Premature Shutdown Completely

• Rule 1 (Accounting Order): Always increment active_tasks before calling mpmc_bulk_enqueue() (when staging a directory, or right before reserving slots), and only decrement active_tasks after a worker has completely finished processing a dequeued directory and finished enqueueing all of its children.

• Rule 2 (Check enqueue_pos == dequeue_pos): Inside the active_tasks == 0 check, also verify that enqueue_pos == check_pos (using memory_order_acquire on active_tasks). If a producer has already reserved slots (enqueue_pos > check_pos) and is currently copying nodes into the ring buffer, enqueue_pos != check_pos will catch it even before sequence is updated:

```c
if (atomic_load_explicit(&lf->q->active_tasks, memory_order_acquire) == 0) {
    size_t check_pos = atomic_load_explicit(&lf->q->dequeue_pos, memory_order_acquire);
    size_t enq_pos = atomic_load_explicit(&lf->q->enqueue_pos, memory_order_acquire);
    if (enq_pos == check_pos) {
        size_t check_seq = atomic_load_explicit(
            &lf->q->sequence[check_pos & QUEUE_MASK], memory_order_acquire);
        if ((intptr_t)check_seq - (intptr_t)(check_pos + 1) < 0) {
            atomic_store_explicit(&lf->q->shut_down, 1, memory_order_release);
            return false;
        }
    }
}
```

2. Integer Width Mismatch (uint_fast32_t vs size_t)

In your previous snippet, GlobalContext declared:

```c
atomic_uint_fast32_t enqueue_pos;
atomic_uint_fast32_t dequeue_pos;
atomic_uint_fast32_t sequence[QUEUE_NODES];
```
                                                                                                        ```
In mpmc_dequeue(), you use size_t pos, size_t seq, and (intptr_t)seq - (intptr_t)(pos + 1).

• On 64-bit Linux (x86_64), uint_fast32_t is 64 bits (unsigned long), so it happens to match size_t.

• However, on 32-bit targets or other ABIs where uint_fast32_t is 32 bits while intptr_t is 64 bits, (intptr_t)seq - (intptr_t)(pos + 1) will fail to handle 32-bit unsigned wrap-around (turning negative differences into huge positive numbers).

• Fix: Explicitly use atomic_size_t (or atomic_uint64_t) for enqueue_pos, dequeue_pos, and sequence[], and cast the difference to ptrdiff_t (or int64_t) so signed wrap-around arithmetic works identically on every architecture.

3. Minor: shut_down Load Ordering & CAS Failure Reload

• shut_down load: Use memory_order_acquire (or relaxed is fine if shut_down is strictly monotonic 0 -> 1 and you don't read any shared summary state immediately after mpmc_dequeue returns false, though memory_order_acquire is free on x86-64 and safer).

• Redundant reload after CAS failure: When atomic_compare_exchange_weak_explicit(&lf->q->dequeue_pos, &pos, ...) fails, pos is automatically updated with the latest value of dequeue_pos, which works cleanly on the next loop iteration.
Please go ahead and share your staging code and the loop where active_tasks is incremented/decremented—checking how active_tasks pairs with staging and mpmc_bulk_enqueue will confirm there are no remaining edge cases under heavy contention.

AI can make mistakes, so double-check responses 

```c
// Author Bill Waller
// ----------------------------------------------------------------
                // STAGE BUFFERING
                // ----------------------------------------------------------------
                if (__tl->stage_idx >= STAGE_NODES - 1) {
                    atomic_fetch_add_explicit(&__G->active_tasks, __tl->stage_idx, memory_order_relaxed);
                    if (mpmc_bulk_enqueue(__G, __tl) == false) {
                        atomic_fetch_sub_explicit(&__G->active_tasks, __tl->stage_idx, memory_order_relaxed);
                        atomic_fetch_add_explicit(&__G->error_count, 1, memory_order_relaxed);
                        if (__G->f_logging)
                            lf_log(ERROR, "STAGE_ENQUEUE_FAIL,%s\n",
                                   __tl->path);
                        return NULL;
                    }
                    __tl->stage_idx = 0;
                }
                __tl->d_name = entry->d_name;
#ifdef DEBUGT
                // 6
                fprintf(stderr, "line: %d, %s, T%lu, path %s, d_name %s, tl->stage_idx %lu\n", __LINE__, __func__, __tl->thread_id, __tl->path, entry->d_name, __tl->stage_idx);
#endif
                __tl->stage_node[__tl->stage_idx].parent_idx = __tl->queue_idx;
                __tl->stage_node[__tl->stage_idx].path_offset = __tl->cum_path_offset;
                __tl->stage_node[__tl->stage_idx].path_len = __tl->d_name_len;
                __tl->stage_node[__tl->stage_idx].child_dirs_remaining = 0;
                __tl->stage_node[__tl->stage_idx].depth = __tl->depth;
                __tl->stage_node[__tl->stage_idx].dev = effective_dev;
                __tl->stage_node[__tl->stage_idx].ino = effective_ino;
                memcpy(__tl->path_data + __tl->stage_node[__tl->stage_idx].path_offset,
                       __tl->d_name,
                       __tl->d_name_len);
                __tl->cum_path_offset += __tl->d_name_len;
                __tl->path_data[__tl->cum_path_offset++] = '\0';
                __tl->stage_idx++;
                // --------------------------------------------------------
                // CONDITIONALLY PRINT AS DIRECTORY
                // --------------------------------------------------------
                if (entry->d_name[0] == '.') {
                    if (!__G->include_hidden && !__G->hidden_only)
                        continue;
                } else {
                    if (__G->hidden_only)
                        continue;
                }
                if (!__G->only_errors) {
                    build_path(__tl, entry->d_name);
                    print_file(__G, __tl);
                }
            } else {
                // --------------------------------------------------------
                // FILE PROCESSING FAST-PATH
                // --------------------------------------------------------
                if (entry->d_name[0] == '.') {
                    if (!__G->include_hidden && !__G->hidden_only)
                        continue;
                } else {
                    if (__G->hidden_only)
                        continue;
                }
                if (__tl->path[0] != '\0' && !__G->only_errors) {
                    build_path(__tl, entry->d_name);
                    print_file(__G, __tl);
                }
            }
        }
    }
```

Your active_tasks increment-before-enqueue pattern is good, but there are three high-impact issues here: one explains why lf4 suddenly exits and drops whole subtrees under heavy bursts (return NULL; on mpmc_bulk_enqueue == false), and two affect correctness and memory safety during staging.

1. Fatal Early Exit on Queue Full (return NULL;)

Look at what happens when the global ring buffer (QUEUE_NODES) momentarily fills up:

```c
if (mpmc_bulk_enqueue(__G, __tl) == false) {
    atomic_fetch_sub_explicit(&__G->active_tasks, __tl->stage_idx, memory_order_relaxed);
    atomic_fetch_add_explicit(&__G->error_count, 1, memory_order_relaxed);
    if (__G->f_logging)
        lf_log(ERROR, "STAGE_ENQUEUE_FAIL,%s\n", __tl->path);
    return NULL;
}
```

• Why this drops files (and caused your earlier bug): Because mpmc_bulk_enqueue() returns false whenever the global ring buffer has fewer than __tl->stage_idx free slots, returning NULL kills the worker thread immediately—abandoning:

    1. All __tl->stage_idx subdirectories sitting in __tl->stage_node[]

    2. All remaining unread getdents64 / readdir entries in the directory currently being scanned

    3. The current task's own active_tasks decrement (unless you have a pthread_cleanup handler)

• How to fix it: When the global queue is full, do not fail or exit the worker. Instead, either:

    • Process locally (DFS fallback): Pop one staged directory from __tl->stage_node[--__tl->stage_idx] (and decrement active_tasks by 1) and traverse it directly on the current thread (via a small thread-local work stack), or

    • Drain one item from the global queue: Call mpmc_dequeue() on the current thread to process a queued directory and free up slots in __G->queue, then retry mpmc_bulk_enqueue(). (Note: Do not simply spin-wait on mpmc_bulk_enqueue() if all worker threads could simultaneously hit a full queue, as that would deadlock—draining locally guarantees forward progress even with 1 thread.)

2. Potential Buffer Overflow in __tl->path_data During Staging

Look at how __tl->cum_path_offset is checked and incremented:

```c
if (__tl->stage_idx >= STAGE_NODES - 1) {
    ...
    __tl->stage_idx = 0;
}
...
memcpy(__tl->path_data + __tl->stage_node[__tl->stage_idx].path_offset,
       __tl->d_name,
       __tl->d_name_len);
__tl->cum_path_offset += __tl->d_name_len;
__tl->path_data[__tl->cum_path_offset++] = '\0';
__tl->stage_idx++;
```

    • Risk 1 (Path buffer overflow): You flush the staging buffer when __tl->stage_idx >= STAGE_NODES - 1, but you never check whether __tl->cum_path_offset + __tl->d_name_len + 1 exceeds the capacity of __tl->path_data! If a directory contains STAGE_NODES - 2 subdirectories with long names (e.g., 200+ bytes each), __tl->path_data will overflow before stage_idx hits STAGE_NODES - 1.
	• Fix: Flush before staging if either __tl->stage_idx >= STAGE_NODES - 1 or __tl->cum_path_offset + __tl->d_name_len + 1 >= TL_PATH_BYTES.

    • Risk 2 (__tl->cum_path_offset reset location): Right after mpmc_bulk_enqueue() succeeds, you reset __tl->stage_idx = 0;, but you did not reset __tl->cum_path_offset = 0; right there (you were resetting it inside mpmc_bulk_enqueue()). Resetting both __tl->stage_idx = 0 and __tl->cum_path_offset = 0 together at the flush site makes the invariant obvious and prevents stale offsets if mpmc_bulk_enqueue is ever bypassed when stage_idx == 0.

3. Memory Ordering on active_tasks & End-of-Directory Flush

• Use memory_order_release when incrementing active_tasks:

```c
atomic_fetch_add_explicit(&__G->active_tasks, __tl->stage_idx, memory_order_release);
```

Pairing memory_order_release on active_tasks increments/decrements with memory_order_acquire in mpmc_dequeue()'s shutdown check guarantees that all prior writes to staged nodes and queue slots are visible before active_tasks can ever be observed as 0.

• Verify your end-of-directory flush: The snippet shown handles flushing mid-directory when stage_idx >= STAGE_NODES - 1. Make sure that after the readdir / getdents64 loop finishes for a directory, you flush any remaining staged nodes (if (__tl->stage_idx > 0)) before decrementing active_tasks for the parent directory you just finished scanning.

If you'd like to share the end of the worker loop (where a directory scan finishes, remaining staged nodes are flushed, and active_tasks is decremented), I can verify the exact handoff so active_tasks can never hit zero prematurely.

```c
// Author Bill Waller
void *worker(void *arg) {
    GlobalContext *__G = (GlobalContext *)arg;
    ThreadLocal __tl;
    __tl.stage_queue_size = sizeof(QueueNode) * STAGE_NODES;
    __tl.stage_path_size = 32 * STAGE_NODES;
    __tl.stage_arena_size = (__tl.stage_queue_size + __tl.stage_path_size);
    void *stage_arena = mmap(NULL, __tl.stage_arena_size, PROT_NONE,
                             MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    mprotect(stage_arena, __tl.stage_arena_size, PROT_READ | PROT_WRITE);
    __tl.stage_arena = stage_arena;
    __tl.stage_node = (QueueNode *)__tl.stage_arena;
    __tl.path_data = (char *)__tl.stage_arena + __tl.stage_queue_size;
    __tl.cum_path_offset = 0;
    __tl.stage_idx = 0;
    __tl.thread_id = atomic_fetch_add_explicit(&__G->thread_id, 1, memory_order_relaxed);
    char dir_buf[DIR_BUF_SIZE];
    __tl.dir_buf = dir_buf;
    OutputBuffer output_buffer;
    __tl.output = &output_buffer;
    uint_fast32_t q_pos = 0;
    LogCtx log_ctx = {};
    __tl.log_ctx = log_ctx;
    log_ctx.thread_id = __tl.thread_id;
    if (__G->f_logging && __G->log_fd == -1)
        initialize_timer(__G, &log_ctx);
    else
        initialize_thread_timer(__G, &log_ctx);
    while (1) {
        if (mpmc_dequeue(__G, &q_pos) == false) {
            break;
        }
        atomic_thread_fence(memory_order_acquire);
        // ----------------------------------------------------------------
        // Reconstruct the relative path for the dequeued directory node
        // ----------------------------------------------------------------
        __tl.queue_idx = q_pos;
        uint_fast32_t q_path_len = __G->queue[q_pos].path_len;
        uint_fast32_t q_path_offset = __G->queue[q_pos].path_offset;
        // ----------------------------------------------------------------
        // Get the length of the parent path
        // ----------------------------------------------------------------
        uint_fast32_t cum_path_len = q_path_len; // length of dequeued dir_node path
        uint_fast32_t parent_idx = __G->queue[q_pos].parent_idx;
        while (parent_idx != NO_PARENT) {
            cum_path_len += __G->queue[parent_idx].path_len + 1;
            parent_idx = __G->queue[parent_idx].parent_idx;
        }
        if (cum_path_len >= MAX_PATH_LEN) {
            atomic_fetch_sub_explicit(&__G->active_tasks, 1, memory_order_relaxed);
            continue;
        }
        // ----------------------------------------------------------------
        // Reconstruct the relative path for the dequeued directory node
        // ----------------------------------------------------------------
        uint_fast32_t write_cursor = cum_path_len;
        write_cursor -= q_path_len;
        memcpy(&__tl.path[write_cursor],
               &__G->path_data[q_path_offset],
               q_path_len);
        __tl.path[cum_path_len] = '\0';
#ifdef DEBUGX
        // 2
        fprintf(stderr, "line: %d, %s, T%lu, dequeued path %s\n", __LINE__, __func__, __tl.thread_id, __tl.path);
#endif
        parent_idx = __G->queue[q_pos].parent_idx;
        uint_fast32_t p_path_len;
        uint_fast32_t p_path_offset;
        while (parent_idx != NO_PARENT) {
            write_cursor -= 1;
            __tl.path[write_cursor] = '/';
            p_path_len = __G->queue[parent_idx].path_len;
            p_path_offset = __G->queue[parent_idx].path_offset;
            write_cursor -= p_path_len;
            memcpy(&__tl.path[write_cursor],
                   &__G->path_data[p_path_offset],
                   p_path_len);
            parent_idx = __G->queue[parent_idx].parent_idx;
        }
#ifdef DEBUGY
        // 1
        fprintf(stderr, "line: %d, %s, T%lu constructed path %s\n", __LINE__, __func__, __tl.thread_id, __tl.path);
#endif
        __tl.parent_path_len = cum_path_len;
        // ----------------------------------------------------------------
        // __tl->path_data now contains a relative path to the directory to open
        // ----------------------------------------------------------------
        finder(__G, &__tl);
        atomic_fetch_sub_explicit(&__G->active_tasks, 1, memory_order_relaxed);
    }
    munmap(stage_arena, __tl.stage_arena_size);
    return NULL;
}
```

---

Resume


Wait—you just revealed a massive architectural hazard in worker() that will corrupt paths and randomly drop directories whenever the ring buffer wraps around!
Look closely at how parent_idx works in worker():

```c
__tl.queue_idx = q_pos;
...
while (parent_idx != NO_PARENT) {
    ...
    p_path_len = __G->queue[parent_idx].path_len;
    p_path_offset = __G->queue[parent_idx].path_offset;
    ...
    parent_idx = __G->queue[parent_idx].parent_idx;
}
```

And look at what mpmc_dequeue() does the instant it dequeues a slot:

```c
atomic_store_explicit(&lf->q->sequence[pos & QUEUE_MASK], pos + QUEUE_NODES,
                      memory_order_release);
```

1. Critical Architectural Bug: Ring Buffer Slot Overwrite While Child Tasks Still Reference parent_idx

You are storing parent pointers (parent_idx) directly as indices into the circular ring buffer __G->queue[q_pos], and mpmc_dequeue frees slot q_pos for reuse before the parent directory's children—or even the parent directory itself—have finished running!
Trace what happens when the queue wraps around (QUEUE_NODES items enqueued):

1. Parent directory /a/b is dequeued from slot q_pos = 42.

2. mpmc_dequeue() immediately sets sequence[42] = 42 + QUEUE_NODES, marking slot 42 free for any producer to overwrite!

3. Worker 1 scans /a/b, stages subdirectory c with parent_idx = 42, and enqueues c into the queue.

4. Before Worker 2 dequeues c and walks parent_idx -> 42 to reconstruct /a/b/c, the ring buffer wraps around and Producer 3 overwrites __G->queue[42] with a completely unrelated directory /x/y!

5. Worker 2 dequeues c, reads __G->queue[42], and reconstructs /x/y/c instead of /a/b/c (which fails openat() with ENOENT and silently drops the entire subtree under /a/b/c)!

6. Even worse: while Worker 1 is still scanning /a/b and staging children with parent_idx = 42, slot 42 is already unprotected and can be overwritten mid-scan!

How to Fix This Cleanly

You have two clean ways to eliminate the parent_idx ring-buffer lifetime bug:

• Option A (Append-Only DirectoryNode Arena — Recommended):
Keep __G->queue[] purely as a ring buffer of uint_fast32_t indices (or QueueNode copies) pointing into a separate, append-only dir_nodes[] array allocated via mmap(..., MAP_NORESERVE) (just like your path_data arena, reserved via atomic_fetch_add(&__G->dir_node_offset, 1)). Because entries in dir_nodes[] are never overwritten during the run, parent_idx remains valid forever—even after the ring buffer wraps around dozens of times!

• Option B (Store Full Relative Path in path_data):
Instead of walking parent_idx chains at dequeue time, format the full relative path (parent/child) into __tl->path_data when staging, and copy the full path string into __G->path_data at enqueue time. Then QueueNode needs no parent_idx at all, and slots in __G->queue are completely self-contained.

2. Three Additional Issues in worker()

1. Staging Path Arena Size (32 * STAGE_NODES) vs. Overflow:
In worker(), you allocate:

```c
__tl.stage_path_size = 32 * STAGE_NODES;
```

That assumes an average directory name length of < 32 bytes. If a directory contains STAGE_NODES subdirectories whose names average 40+ bytes (common in node_modules, .cache, Rust target/, or browser profiles), __tl.path_data will overflow into unmapped memory (SIGSEGV) or corrupt adjacent memory.

    • Fix: Either size stage_path_size to NAME_MAX * STAGE_NODES (256 * STAGE_NODES—still tiny, e.g., 64 KB for 256 nodes) or check __tl->cum_path_offset + __tl->d_name_len + 1 >= __tl->stage_path_size before staging so it flushes early when the path buffer fills up.

2. Double-Check mpmc_dequeue Signature Mismatch:

In worker(), you call mpmc_dequeue(__G, &q_pos) expecting q_pos to be set to the slot index, whereas your earlier mpmc_dequeue snippet took (LfCtx *lf, QueuePayload *dequeued_node) and copied the node out before advancing sequence. Make sure mpmc_dequeue is not returning a raw slot index q_pos after setting sequence[q_pos] = pos + QUEUE_NODES, because the moment sequence is updated, another thread can overwrite __G->queue[q_pos] before worker() even reads __G->queue[q_pos].path_len on the next line!

3. active_tasks Decrement Ordering:

Change:

```c
atomic_fetch_sub_explicit(&__G->active_tasks, 1, memory_order_relaxed);
```

to memory_order_release (or memory_order_acq_rel) so all work done by this task—including flushing remaining staged nodes at the end of finder()—is guaranteed to be visible to any thread observing active_tasks == 0 with memory_order_acquire.
Which fix fits your design better—moving QueueNodes into an append-only mmap arena so parent_idx never gets overwritten on ring wrap-around, or storing full relative paths so nodes don't need parent_idx? I can help write the exact lock-free snippet for whichever approach you prefer.

I would strongly recommend avoiding in-place defragmentation of __G->path_data—it is nearly impossible to make lock-free without pausing all worker threads and rewriting every live offset pointer simultaneously.
Instead, you can reclaim memory cleanly and lock-free using Epoch/Chunked Arenas or a Hybrid Path Approach, depending on whether you want bounded memory or maximum speed.
Here is why defragmentation is so painful in a lock-free design, followed by the three cleanest alternatives.

Why In-Place Defragmentation Doesn't Mix with Lock-Free Queues

To compact holes out of __G->path_data while 10+ worker threads are running:

1. You have to stop all workers at a global safepoint (a stop-the-world barrier) because threads actively hold raw path_offset integers in local registers, staging buffers, and queue nodes.

2. You have to walk every live QueueNode across the global queue and every thread's private stage_node[] array to update its path_offset to the new compacted address.

3. That stop-the-world pause and pointer-fixup pass costs far more CPU time than the entire 0.08-second traversal of 541,000 files.

Three Much Better Ways to Handle path_data & Node Lifetimes


Approach	Memory Usage	Lock-Free Complexity	Best When

1. Hybrid: Fixed char path[MAX_PATH_LEN] in Queue + mmap Arena	Bounded (~few MB)	Very Low	You want rock-solid simplicity and zero lifetime tracking

2. Chunked Slab Arenas with Refcounts	Bounded & Reusable	Medium	You traverse massive trees (tens of millions of dirs)

3. Virtual mmap Arena (MAP_NORESERVE)	Proportional to dir names only	Lowest	Standard filesystem runs (500K–5M files)


Option 1: Store Full Paths in a Fixed-Size Ring Buffer (Simplest & Zero Holes)

If you store full paths instead of parent chains, you don't need a separate variable-length path_data heap or child_dirs_remaining refcounting at all:

• Each slot in the ring buffer (e.g., QUEUE_NODES = 16384) holds a fixed char path\[PATH_MAX\] (or char path\[1024\] with a fallback for deeper paths).

• 16,384 slots × 1,024 bytes = 16 MB total—a tiny, fixed footprint.

• Because each slot is self-contained, the moment mpmc_dequeue() copies the path into __tl.path, both the node and its path memory are instantly reclaimed when the ring buffer wraps around. Zero holes, zero refcounting, zero fragmentation.

• Trade-off: Copying a 60-byte path string on enqueue/dequeue instead of a 12-byte basename costs a few nanoseconds per directory, which is completely invisible compared to the openat() + getdents64() syscalls.

Option 2: Chunked Slab Arenas (If Keeping parent_idx + child_dirs_remaining)

If you want to keep your parent_idx + child_dirs_remaining design and reclaim memory on huge filesystems without moving bytes:

• Instead of one monolithic __G->path_data, allocate paths in fixed-size 64 KB or 256 KB slabs (using a simple atomic bump pointer within the active slab).

• Give each slab an atomic_uint_fast32_t live_bytes (or live_entries) counter.

• When a directory is allocated in a slab, add its path_len to that slab's live_bytes.

• When child_dirs_remaining hits 0 (using your bottom-up completion logic), subtract that node's path_len from its slab's live_bytes.

• When a closed slab's live_bytes drops to 0, push that slab onto a lock-free free-list (or call madvise(slab, SLAB_SIZE, MADV_DONTNEED) to immediately hand its physical RAM pages back to the Linux kernel!).

• Why this wins: Memory is reclaimed in O(1) atomic operations without ever moving a byte or updating a single offset.

Option 3: Over-Provisioned MAP_NORESERVE Arena (What fd / ripgrep Often Rely On)

Notice that __G->path_data only stores directory basenames (not files!), and only 1 in ~10 filesystem entries is a directory:

• For 541,000 files (~50,000 directories) with an average basename of 16 bytes, the entire run uses less than 1 MB of path_data! Even a massive 50-million-file filesystem (~5 million directories) uses only ~80 MB.

• If you map a 512 MB virtual arena with mmap(..., PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0), Linux allocates zero physical RAM until pages are actually touched (maxresident stays tiny, as your 18036k benchmark already shows), and the kernel automatically reclaims everything in microseconds when the process exits.

My Recommendation for Your Learning & Codebase

If your goal is to keep the parent_idx + child_dirs_remaining architecture you have already designed—because understanding bottom-up atomic reference counting is a great systems programming exercise—go with Option 3 (MAP_NORESERVE arena) first to get your concurrency 100% deterministic, and if you ever want bounded memory reuse later, add Option 2 (MADV_DONTNEED on 256 KB slabs) rather than defragmenting.

Take your time digesting the memory-ordering and slot-lifetime pieces—those are the exact fundamentals that separate fragile lock-free code from rock-solid systems code.

When you're ready to dive back in, let me know if you'd like to explore:
The lock-free slab + MADV_DONTNEED pattern for reclaiming path_data without moving pointersHow child_dirs_remaining atomic decrement interacts with active_tasks

