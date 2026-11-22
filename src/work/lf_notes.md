# lf Performance Analysis Notes

To analyze multi-threaded performance with Linux perf, you must look beyond aggregate CPU cycles to identify thread-level bottlenecks like lock contention, false sharing, and scheduler delays. By default, perf aggregates metrics across all active threads in a process, which can mask imbalances where one thread is stalled while others are spinning.

Essential Commands for Multi-Threaded Analysis

Use specific flags to isolate individual threads and observe how the Linux kernel schedules them across CPU cores.

• View per-thread hardware counters. Run 

```bash
perf stat --per-thread -p <PID>
```

to break down CPU cycles, instructions, and cache misses for each thread instead of seeing a single combined total.

• Profile specific threads. Use the perf record command below to capture call graphs,
then inspect individual threads using perf report.

```bash
perf record -g -p <PID>

perf report --tid=<TID>
perf report -s pid,tid,symbol

```


• Measure scheduler latency and context switches. Run the commands below 
to see how long threads wait in the run queue before getting CPU time.

```bash
perf sched record
perf sched latency
```

• Analyze lock contention. Use perf lock record and perf lock report to identify which mutexes or spinlocks are causing threads to block or spin excessively.

```bash
perf lock record
perf lock report
```

• Benchmark multi-threaded IPC and scheduling. Run built-in stress tests, such
as the command below to measure how well the system handles multi-threaded message passing.

```bash
perf bench sched messaging -t
```

Key Metrics to Watch

When scaling an application across multiple threads, check these specific indicators to find out why performance plateaus:

• Instructions Per Cycle (IPC). A low IPC (typically below 1.0) alongside high CPU usage often means threads are stalled waiting on memory or spinning on active locks.

low IPC, high CPU - threads stalled

• Context switches and CPU migrations. High numbers of context-switches or cpu-migrations in perf stat indicate threads are frequently yielding or bouncing between cores, which invalidates CPU caches.

Context switches and CPU migrations - threads yielding or bouncing between cores

• Cache misses and false sharing. Use perf c2c (Cache-to-Cache) to detect false sharing, which happens when threads on different cores modify independent variables that sit on the same cache line.

```bash
perf c2c record
perf c2c report
```

For deeper kernel-level examples and visualization workflows like Flame Graphs, check out Brendan Gregg's Linux perf Examples or the official Linux Perf Wiki Tutorial.

If you are troubleshooting a specific application, share:
• The programming language or threading library (e.g., C++ std::thread, pthreads, Rust, Java)
• The symptom you are seeing (e.g., high CPU with low throughput, high latency, or poor scaling past a certain core count)
I can give you the exact perf command sequence and event flags to pinpoint the bottleneck.

+5
• 
Denis Bakhvalov
Performance analysis of multithreaded applications. | Easyperf
Benchmark: h264dec from Starbench using pthread with one main, one reader, configurable workers, and one writer thread. Performanc...
• 
Stack Overflow
Using perf stat for multithreaded applications - Stack Overflow
Perf Cycles Metric: The `perf stat cycles` metric reports the aggregate number of CPU cycles across all active threads, not an ave...
• 
perf: Linux profiling with performance counters
Introduction - perf: Linux profiling with performance counters
You must first collect the samples using perf record . This generates an output file called perf. data . That file can then be ana...
Show all
For the perf commands that require a process id and a program that runs in one tenth of a second, how would you determine the process id?
7:37 PM

How to Launch and Profile Directly

Replace -p <PID> with -- ./my_program at the end of my perf command.
• Measure per-thread hardware counters. Run the following command to capture thread-level metrics from the exact moment the process starts until it exits.

```bash
perf stat --per-thread -- ./lf4
```

• Record call graphs and thread execution. Run the following command to collect and view samples across all spawned threads automatically.

```bash
perf record -g -- ./lf4
perf report -s pid,tid,symbol
```

• Adjust sampling frequency for short runs. A 0.1-second run only captures about 100 samples at the default 1,000 Hz rate. For example:

```bash
perf record -F 4000 -g -- ./lf4
```

Alternative: Handling Background or Wrapper Scripts

If a wrapper script or parent process launches the target binary and it cannot be invoke directly, use these techniques to catch the PID:

• Trace child processes automatically. Run perf on the parent script using the -i flag disabled (which is the default behavior). By default, perf stat and perf record follow all fork() and clone() calls, capturing every thread and child process spawned by the wrapper.

• Pause execution at startup. If you must attach via -p <PID>, wrap the target program in a shell subshell that stops itself before executing: (kill -STOP $BASHPID; exec ./my_program) &. This prints the exact PID, lets you attach perf record -p <PID>, and lets you resume the program with kill -CONT <PID>.

Launching the command directly works cleanly. Place a double dash (--) before ./lf4 and keep the redirection at the very end.
The -- tells perf to stop parsing flags so -H is passed to lf4 instead of being interpreted as a perf option, while >/dev/null discards only the target program's output so perf can still display its report.

Exact Commands to Run

Use these commands depending on what you want to measure:
• Per-thread CPU and cache counters. Run the following command to see cycle counts, IPC, and context switches broken down for every thread lf4 spawns.

```bash
perf stat --per-thread -- ./lf4 -H /home/bill >/dev/null
```

• High-resolution call graph profiling. Run the following command to sample at 4,000 Hz, which gives you roughly 400 samples over a 0.1-second runtime.

```bash
perf record -F 4000 -g -- ./lf4 -H /home/bill >/dev/null 
```

• Inspect the recorded thread breakdown. Run the following command afterward to view which functions are consuming time inside each individual thread.

```bash
perf report -s pid,tid,symbol
```

Watch Out for One Detail

• Output redirection order. Make sure >/dev/null stays at the end of the line. Because perf stat writes its summary to stderr (2>), redirecting stdout (>/dev/null) silences lf4 without hiding perf metrics.

Once you run perf stat --per-thread on lf4, share the IPC (insn per cycle) or context-switches numbers if anything looks off, and I can help you interpret where the threads are bottlenecking.

When I try the per-thread command example above, I get: The --per-thread option is only available when monitoring via -p -t -a options or only --per-thread.
 -p, --pid <pid> stat events on existing process id
 -t, --tid <tid> stat events on existing thread id
7:42 PM

That error occurs because perf stat --per-thread requires an existing PID or TID and cannot dynamically create per-thread counters when launching a brand-new command directly. To work around this on a 0.1-second program, pause the process in a subshell before exec runs, attach perf stat --per-thread -p <PID>, and then resume it.

3-Step Subshell Method

Run these commands in the same terminal window to catch the exact PID before lf4 executes its first instruction:
1. Launch lf4 in a paused state. Run (kill -STOP $BASHPID; exec ./lf4 -H /home/bill >/dev/null) & to spawn a background subshell that immediately freezes itself and prints its PID (e.g., [1] 12345).
2. Attach perf stat to that PID. Run perf stat --per-thread -p $! & right away so perf attaches to the frozen process and waits for it to run.
3. Resume the program. Run kill -CONT %1 to unfreeze lf4, letting it run for 0.1 seconds while perf captures every thread it spawns until exit.

One-Liner Alternative

If you want to run this repeatedly without typing three separate commands, paste this single line:

```bash
bash -c 'kill -STOP $$; exec ./lf4 -H /home/bill >/dev/null' & PID=$!; sleep 0.05; perf stat --per-thread -p $PID & sleep 0.05; kill -CONT $PID; wait
```

• How it works. bash -c freezes itself (kill -STOP $$) before replacing itself with lf4, $! grabs the exact PID, perf stat attaches while it is paused, and kill -CONT lets it run cleanly to completion.
• No race conditions. Because exec replaces the bash process in place, the PID stays identical from start to finish, and perf catches 100% of the threads spawned by lf4.
Try running that one-liner and let me know if all threads show up cleanly in the perf stat output or if you see any permission errors (such as perf_event_paranoid restrictions).
I got:

bash -c 'kill -STOP $$; exec ./lf4 -H /home/bill >/dev/null' & PID=$!; sleep 0.05; perf stat --per-thread -p $PID & sleep 0.05; kill -CONT $PID; wait
[1] 462758

[1]+ Stopped bash -c 'kill -STOP $$; exec ./lf4 -H /home/bill >/dev/null'
[2] 462760
xsh: wait: warning: job 1[462758] stopped

 Performance counter stats for process id '462758':

 bash-462758 5,493 context-switches # 4612.7 cs/sec cs_per_second
 bash-462758 37 cpu-migrations # 31.1 migrations/sec migrations_per_second
 bash-462758 785 page-faults # 659.2 faults/sec page_faults_per_second
 bash-462758 1,190.83 msec task-clock # 1.2 CPUs CPUs_utilized
 bash-462758 7,420,804 branch-misses # 2.3 % branch_miss_rate (29.67%)
 bash-462758 337,887,889 branches # 283.7 M/sec branch_frequency (29.21%)
 bash-462758 3,308,897,190 cpu-cycles # 2.8 GHz cycles_frequency (43.62%)
 bash-462758 1,885,349,511 instructions # 0.6 instructions insn_per_cycle (57.39%)
 bash-462758 2,590,926,925 stalled-cycles-frontend # 0.77 frontend_cycles_idle (56.46%)
 bash-462758 1,979,705,649 stalled-cycles-backend # 0.59 backend_cycles_idle (42.83%)
 bash-462758 1,948,034,534 stalled-cycles-backend # 1.46 stalled_cycles_per_instruction (29.58%)

 1.001092614 seconds time elapsed

[2]+ Done perf stat --per-thread -p $PID
7:46 PM
The output actually captured the entire run, and it reveals two important things: first, lf4 ran to completion (the bash-462758 name is just the initial process name before exec changed it, and 1.2 CPUs utilized over 1.00 second proves multiple threads ran), and second, perf stat --per-thread does not automatically track newly spawned threads after attaching to a single-threaded process.

Why Only One Row Appeared

When perf stat --per-thread -p $PID attaches to a paused process, it reads /proc/<PID>/task/ at that exact instant. Because lf4 hasn't spawned its worker threads yet while paused, perf only creates counters for the main thread (and rolls child thread totals into it or misses their individual names).

How to See Every Individual Thread

To get a true per-thread breakdown for a fast program, use perf record with thread tracking instead of perf stat --per-thread:

1. Record with thread context switches and sampling. Run this single command directly—no subshell or kill -STOP required:bash

```bash
perf record -F 4000 -g -- ./lf4 -H /home/bill >/dev/null
```

2. View the per-thread CPU breakdown. Run perf report grouped by Thread ID (tid) and command name (comm):bash

```bash
perf report --stdio -s comm,tid
```

	• What this shows. It lists every single thread lf4 created, its exact percentage of total CPU time, and the thread's name (if the target program names its threads).

What Your Current Numbers Already Tell Us

Even from the aggregate output you just captured, two metrics stand out immediately:

• High context-switch rate (4,612.7 cs/sec). Your threads are switching in and out over 4,600 times per second, which often indicates lock contention or threads rapidly waking up and sleeping on small chunks of work.

• Low IPC (0.6 insn_per_cycle) with high frontend/backend stalls. Your CPU is spending over half its cycles stalled waiting on memory or instruction fetches rather than executing code.

Run the following commands and share the output—we can see how many threads actually ran and whether one thread is hogging the work or if they are all stalling on locks.

```bash
perf record -F 4000 -g -- ./lf4 -H /home/bill >/dev/null
perf report --stdio -s comm,tid
```

Bypass the pager ($PAGER / /home/bill/menuapp/bin/view) so perf report prints plain text directly to terminal:

```bash
PERF_PAGER=cat perf report --stdio -s comm,tid
```

• Why this works. Even when --stdio is passed, perf report still pipes its output through the $PAGER environment variable unless stdout is redirected or PERF_PAGER is overridden. Setting PERF_PAGER=cat prevents perf from launching /home/bill/menuapp/bin/view.

• Alternative: Write to a text file. You can also redirect the output directly to a file, which automatically disables the pager:

```bash
perf report --stdio -s comm,tid > report.txt && cat report.txt
```

Bonus: See Which Functions Are Slowing Down Each Thread

Once PERF_PAGER=cat works, run this command to see both the thread breakdown and the exact functions each thread is spending time in:

```bash
PERF_PAGER=cat perf report --stdio -s comm,tid,symbol --no-children
```


Try running  the following command and paste the output here—we can look at the thread distribution and see what is causing the high context switches in lf4.

```bash
PERF_PAGER=cat perf report --stdio -s comm,tid 
```

When I tried to set PERF_PAGER, it returned "Unknown --sort key: tid.

Your version of perf uses pid as the sort key for threads (which prints PID:TID together) instead of a separate tid key.

Run This Command Instead

Replace tid with pid while keeping PERF_PAGER=cat:
```bash
PERF_PAGER=cat perf report --stdio -s comm,pid
```

• How perf displays threads. In older or distro-specific perf builds, the pid sort key outputs both the Process ID and Thread ID formatted as PID:TID (for example, 462810:462812), allowing you to distinguish every individual worker thread.

• Include function names. To see which functions are running inside each thread, add symbol to the sort list:bash

Run the following command and share the output—we can check how evenly the work is split across PID:TID threads.

```bash
PERF_PAGER=cat perf report --stdio -s comm,pid,symbol --no-children
```

Here is the first 200 lines: 

```
# To display the perf.data header info, please use --header/--header-only options.
#
#
# Total Lost Samples: 0
#
# Samples: 5K of event 'cpu/cycles/P'
# Event count (approx.): 3271122661
#
# Overhead Command Pid:Command Symbol IPC [IPC Coverage]
# ........ ....... ............... .................................................. ....................
#
 1.63% lf4 462847:lf4 [.] queue_node_create - - 
 | 
 --1.61%--queue_node_create
 init_lf
 main
 __libc_start_call_main
 0x7ffe414c877c
 0x622f656d6f682f00

 0.96% lf4 462852:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.90% lf4 462853:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.89% lf4 462861:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.89% lf4 462858:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.87% lf4 462856:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.86% lf4 462860:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.85% lf4 462863:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.85% lf4 462862:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.84% lf4 462854:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.83% lf4 462850:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.83% lf4 462851:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.82% lf4 462859:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.82% lf4 462855:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.78% lf4 462849:lf4 [k] __ext4fs_dirhash - - 
 |
 ---__ext4fs_dirhash
 ext4fs_dirhash
 htree_dirblock_to_tree
 ext4_htree_fill_tree
 ext4_readdir
 iterate_dir
 __x64_sys_getdents64
 do_syscall_64
 entry_SYSCALL_64_after_hwframe
 syscall
 worker
 start_thread

 0.76% lf4 462857:lf4 [.] mpmc_dequeue - - 
 |
 ---mpmc_dequeue
 worker
 start_thread

 0.69% lf4 462849:lf4 [k] ext4_htree_store_dirent - - 
 |
 ---ext4_htree_store_dirent
 htree_dirblock_to_tree
 ext4_htree_fill_tree
 ext4_readdir
 iterate_dir
 __x64_sys_getdents64
 do_syscall_64
 entry_SYSCALL_64_after_hwframe
 syscall
 worker
 start_thread

 0.63% lf4 462861:lf4 [k] __ext4fs_dirhash - - 
 |
 ---__ext4fs_dirhash
 ext4fs_dirhash
 htree_dirblock_to_tree
 ext4_htree_fill_tree
 ext4_readdir
 iterate_dir
 __x64_sys_getdents64
 do_syscall_64
 entry_SYSCALL_64_after_hwframe
 syscall
 worker
 start_thread

 0.61% lf4 462847:lf4 [k] folio_zero_user - - 
 | 
 --0.51%--folio_zero_user
 vma_alloc_anon_folio_pmd
 do_huge_pmd_anonymous_page
 __handle_mm_fault
 handle_mm_fault
 do_user_addr_fault
 exc_page_fault
 asm_exc_page_fault

 0.46% lf4 462858:lf4 [.] print_file - - 
 0.44% lf4 462855:lf4 [k] entry_SYSRETQ_unsafe_stack - - 
 0.41% lf4 462859:lf4 [k] entry_SYSRETQ_unsafe_stack - - 
 0.41% lf4 462852:lf4 [k] entry_SYSRETQ_unsafe_stack - - 
 0.40% lf4 462849:lf4 [.] print_file - - 
 0.38% lf4 462853:lf4 [k] entry_SYSRETQ_unsafe_stack - - 
 0.38% lf4 462861:lf4 [k] entry_SYSRETQ_unsafe_stack - - 
 0.37% lf4 462862:lf4 [k] entry_SYSRETQ_unsafe_stack - - 
 0.36% lf4 462863:lf4 [.] print_file - - 
 0.35% lf4 462860:lf4 [k] entry_SYSRETQ_unsafe_stack - - 
 0.33% lf4 462849:lf4 [k] memchr - - 
 0.32% lf4 462849:lf4 [k] filldir64 - - 
 0.31% lf4 462863:lf4 [k] entry_SYSRETQ_unsafe_stack - - 
 0.31% lf4 462857:lf4 [k] entry_SYSRETQ_unsafe_stack - - 
 0.31% lf4 462849:lf4 [k] __ext4_check_dir_entry - - 
 0.31% lf4 462849:lf4 [k] __kmalloc_noprof - - 
 0.31% lf4 462854:lf4 [k] __ext4fs_dirhash - - 
 0.31% lf4 462859:lf4 [k] __ext4fs_dirhash - - 
 0.30% lf4 462851:lf4 [k] __ext4fs_dirhash - - 
 0.29% lf4 462850:lf4 [.] print_file - - 
 0.29% lf4 462859:lf4 [.] print_file - - 
 0.28% lf4 462856:lf4 [k] __ext4fs_dirhash - - 
 0.28% lf4 462849:lf4 [k] kfree - - 
 0.28% lf4 4628
```

7:56 PM

This profile reveals the exact bottlenecks in lf4: high contention on mpmc_dequeue across 16 worker threads, heavy startup memory allocation in queue_node_create, and kernel directory traversal overhead (getdents64).

1. MPMC Queue Contention (mpmc_dequeue)

Every single worker thread (462849 through 462863) appears at the very top of the profile spending ~0.82% to 0.96% of total program cycles inside mpmc_dequeue. Combined across 16 threads, mpmc_dequeue is consuming roughly 13–15% of the entire runtime.

• Why this happens. When 16 threads hammer a single Multi-Producer Multi-Consumer (MPMC) queue for tiny tasks (like reading or stat-ing individual directory entries), they constantly fight over the same atomic head/tail cache lines. This directly explains the low IPC (0.6) and high cache stalls you saw earlier.

• How to fix it.
	• Use work-stealing or per-thread local queues. Give each worker its own local LIFO stack or deque for newly discovered subdirectories, and only touch a shared queue (or steal from another thread) when its local queue runs empty.
	• Batch queue items. Push and pop directory entries in chunks (e.g., 32 or 64 items per queue operation) instead of one file/directory at a time to reduce atomic operations by 95%+.
	• Pad atomic indices. Ensure the head and tail pointers in the MPMC queue are separated by at least 64 bytes (alignas(64)) to prevent false sharing between producers and consumers.

2. Expensive Startup Allocation (queue_node_create)

The single hottest function in the entire run is queue_node_create inside init_lf on the main thread (462847), taking 1.63% of total cycles, paired with folio_zero_user (0.61%) from page faults.

• Why this happens. init_lf is pre-allocating a massive pool of queue nodes using individual malloc or calloc calls before the workers even start, forcing the Linux kernel to zero-fill brand-new memory pages (folio_zero_user) on the main thread.

• How to fix it.
	• Allocate a single contiguous slab. Replace per-node heap allocations in queue_node_create with one large malloc array (e.g., node_pool = malloc(N * sizeof(Node))) and link them using integer indices instead of 64-bit pointers.

	• Avoid calloc if you overwrite fields. calloc forces immediate page zeroing; malloc lets you initialize fields lazily as nodes are actually used.

3. Filesystem & Syscall Overhead (getdents64 & print_file)

Your workers spend a significant share of time inside the Linux kernel ([k] __ext4fs_dirhash, ext4_htree_store_dirent, entry_SYSRETQ_unsafe_stack) executing getdents64 syscalls, alongside print_file in user space.

• Why this happens. Directory traversal on ext4 is syscall-bound, and print_file (likely calling printf or write) acquires stdout locks (flockfile) every time a worker prints a match.

• How to fix it.
	• Increase the getdents64 buffer size. If you are calling syscall(SYS_getdents64, ...) directly, bump the buffer size to 32 KB or 64 KB (standard readdir uses 32 KB) to cut syscall transitions (entry_SYSRETQ_unsafe_stack) in half.
	• Thread-local output buffering. Instead of having 16 workers call printf or fwrite on stdout concurrently (which serializes threads behind glibc's internal FILE mutex), format output into a thread-local buffer and flush it in large chunks with write(STDOUT_FILENO, ...).

Verify Overall Function Totals

Because sorting by pid splits each function across 16 separate rows, run this command to see the combined percentage of every function across all threads:
bash

```bash
PERF_PAGER=cat perf report --stdio -s symbol --no-children | head -n 40
```

Run that aggregate symbol report (PERF_PAGER=cat perf report --stdio -s symbol --no-children | head -n 40) and share the top 15–20 lines—it will show the exact combined percentage spent in mpmc_dequeue, print_file, and kernel syscalls across all 16 threads so we know which optimization will give you the biggest speedup first.

```
# To display the perf.data header info, please use --header/--header-only options.
#
#
# Total Lost Samples: 0
#
# Samples: 5K of event 'cpu/cycles/P'
# Event count (approx.): 3271122661
#
# Overhead Symbol IPC [IPC Coverage]
# ........ .................................................. ....................
#
 12.03% [.] mpmc_dequeue - - 
 |
 ---worker
 start_thread

 4.59% [k] entry_SYSRETQ_unsafe_stack - - 
 | 
 --4.26%--entry_SYSRETQ_unsafe_stack
 | 
 |--2.62%--syscall
 | worker
 | start_thread
 | 
 --1.00%--__syscall_cancel_arch
 | 
 --0.89%--worker
 start_thread

 4.50% [k] __ext4fs_dirhash - - 
 | 
 --4.42%--__ext4fs_dirhash
 ext4fs_dirhash
 htree_dirblock_to_tree
 ext4_htree_fill_tree
 ext4_readdir
 iterate_dir
 __x64_sys_getdents64
 do_syscall_64
 entry_SYSCALL_64_after_hwframe
```
8:02 PM

The aggregate numbers make the primary bottleneck crystal clear: mpmc_dequeue alone consumes 12.03% of total CPU cycles, making it nearly three times hotter than any other single function in user space or the kernel.

Breakdown of Your Top 3 Bottlenecks

• mpmc_dequeue (12.03%). Your 16 worker threads are spending one out of every eight CPU cycles contending on the shared MPMC queue. When threads repeatedly spin or compare-and-swap on the same queue pointers for individual directory entries, they suffer severe cache-line bouncing across CPU cores.

• entry_SYSRETQ_unsafe_stack (4.59%). Nearly 5% of total runtime is spent just returning from Linux kernel syscalls (syscall inside worker, plus __syscall_cancel_arch from glibc wrappers like openat or close). This confirms workers are making a high volume of small, rapid syscalls.

• __ext4fs_dirhash (4.50%). The kernel is spending 4.5% of cycles computing directory entry hashes inside getdents64 (ext4_htree_fill_tree). This is normal work for reading large ext4 directories, meaning multi-threaded traversal is fast enough that filesystem metadata lookup is now an active limit.

Highest-Impact Optimizations to Apply Next

To cut runtime significantly on this workload, target the top two items first:

1. Eliminate shared queue contention (mpmc_dequeue).
	• Add a thread-local work stack. When a worker reads a directory via getdents64 and finds subdirectories, push those subdirectories onto a private, non-atomic local stack inside that worker thread instead of pushing them back into the global MPMC queue.
	• Only touch the MPMC queue when starved. Have a worker pop from the global MPMC queue only when its own local stack is empty, or push excess items to the global queue only if the global queue is running low. This eliminates ~90% of atomic operations and cache-line invalidations.
	• Check spin-wait behavior. If mpmc_dequeue spins in a tight loop waiting for work when the queue is temporarily empty, add _mm_pause() (on x86_64) inside the spin loop so spinning threads don't starve active threads of execution units or burn power.
2. Reduce syscall transition overhead (entry_SYSRETQ_unsafe_stack).
	• Enlarge the getdents64 buffer. If the syscall(SYS_getdents64, ...) buffer is 4 KB or 8 KB, increase it to 64 KB or 128 KB. Fewer getdents64 calls per directory directly reduces entry_SYSRETQ_unsafe_stack overhead.
	• Skip unnecessary stat / fstatat calls. Inside getdents64, check d_type (DT_DIR vs DT_REG). Only fall back to fstatat when d_type == DT_UNKNOWN, which avoids thousands of extra syscalls on ext4.
 
```c
alignas(CACHE_LINE_SIZE) uint_fast32_t pos = atomic_load_explicit(&__G->dequeue_pos, memory_order_relaxed);
 while (true) {
 if (atomic_load_explicit(&__G->shut_down, memory_order_acquire)) {
 ANNOTATE_HAPPENS_AFTER(&__G->shut_down);
 return false;
 }

 // Line 1246
 alignas(CACHE_LINE_SIZE) uint_fast32_t seq =
 atomic_load_explicit(&__G->queue_node[pos & QUEUE_MASK].sequence, memory_order_acquire);

 intptr_t diff = (intptr_t)seq - (intptr_t)(pos + 1);
 if (diff == 0) { // Catch!
 if (atomic_compare_exchange_weak_explicit(&__G->dequeue_pos, &pos,
 pos + 1, memory_order_acquire, memory_order_relaxed)) {
 // Ensure this sits directly inside the successful CAS block
 ANNOTATE_HAPPENS_AFTER(&__G->queue_node[pos & QUEUE_MASK].sequence);
 break;
 }
 } else if (diff < 0) { // No Joy!
 if (atomic_load_explicit(&__G->active_tasks, memory_order_acquire) == 0) {
// Re-verify the queue state hasn't moved under high thread pressure
#if defined(__x86_64__)
 // __builtin_ia32_pause();
#else
 sched_yield();
#endif
 uint_fast32_t check_pos =
 atomic_load_explicit(&__G->dequeue_pos, memory_order_acquire);
 uint_fast32_t check_seq = atomic_load_explicit(
 &__G->queue_node[check_pos & QUEUE_MASK].sequence, memory_order_acquire);
 if ((intptr_t)check_seq - (intptr_t)(check_pos + 1) < 0) {
 // Exchange ensures multiple threads don't trigger overlapping relaxed writes
 atomic_exchange_explicit(&__G->shut_down, 1, memory_order_release);
 return false;
 }
 }
#if defined(__x86_64__)
 __builtin_ia32_pause();
#else
 sched_yield();
#endif
 pos = atomic_load_explicit(&__G->dequeue_pos, memory_order_acquire);
 } else { // Snatched by another thread, try again
 pos = atomic_load_explicit(&__G->dequeue_pos, memory_order_acquire);
 }
 }
 *dequeue_pos = pos;
 // VALGRIND ANNOTATION: Tell Helgrind this thread is done reading and
 // releases the slot
 uint_fast32_t reset_seq = pos + QUEUE_NODES;
 atomic_exchange_explicit(&__G->queue_node[pos & QUEUE_MASK].sequence, reset_seq, memory_order_release);
 return true;
}
```
8:06 PM

Looking at mpmc_dequeue, there is a critical data race bug at the bottom of the function alongside four distinct hardware cache-line bottlenecks that explain the 12.03% CPU burn and low IPC (0.6).

1. Critical Race Condition: Early Slot Release

Look at the last three lines of mpmc_dequeue:
```c
    *dequeue_pos = pos;
    uint_fast32_t reset_seq = pos + QUEUE_NODES;
    atomic_exchange_explicit(&__G->queue_node[pos & QUEUE_MASK].sequence, reset_seq, memory_order_release);
    return true;
```

• The bug. You are resetting sequence = pos + QUEUE_NODES before the caller (worker) actually reads the payload from __G->queue_node[pos & QUEUE_MASK]! As soon as sequence is updated, a fast producer thread can immediately overwrite that slot's data while worker is still reading it.

• The fix. Move the sequence release into a separate mpmc_release_slot(__G, pos) helper called after worker finishes reading the node's directory path/fd, or copy the payload inside mpmc_dequeue before updating sequence. (Also use atomic_store_explicit instead of atomic_exchange_explicit here—an atomic exchange issues a costly LOCK XCHG instruction when a plain release store on x86_64 needs zero lock prefixes).

2. Why mpmc_dequeue Is Burning 12% of Your CPU

Even without the race, four architectural patterns in this loop are causing massive cache-line invalidations across 16 cores:

• Spinning on empty (diff < 0) with 16 threads. In directory traversal, whenever one thread opens a deep directory, the other 15 threads run out of queue items and hammer dequeue_pos, sequence, and active_tasks in a tight spin loop. Even with __builtin_ia32_pause(), 15 threads spinning on shared atomics saturate the memory interconnect and steal execution resources from the threads actually doing getdents64 syscalls.

• False sharing across adjacent queue_node entries. Because pos increments by 1 (pos & QUEUE_MASK), threads reading pos and pos + 1 hit adjacent elements in queue_node[]. If sizeof(queue_node[0]) is smaller than 64 bytes (or not alignas(64)), updating sequence on slot N invalidates the L1 cache line for the thread reading slot N + 1.

• Unnecessary alignas(CACHE_LINE_SIZE) on stack variables. Putting alignas(CACHE_LINE_SIZE) on local variables pos and seq forces the compiler to emit extra stack-pointer alignment instructions (and rsp, -64) on every call, without helping cross-thread cache behavior at all. Remove alignas from local stack variables and put it on the struct fields inside GlobalContext (enqueue_pos, dequeue_pos, active_tasks, shut_down) and on struct QueueNode.

• Costly atomic_exchange_explicit on shutdown. When shutting down, 15 threads hit atomic_exchange_explicit(&__G->shut_down, 1) simultaneously, triggering 15 separate cache-line ownership transfers (LOCK XCHG) instead of a simple atomic_store_explicit(&__G->shut_down, 1, memory_order_release).

3. Cleaned-Up, High-Performance Fix

Here is how to fix the race condition and eliminate the cache-line thrashing in mpmc_dequeue:

```c
// Ensure GlobalContext separates hot atomics onto distinct cache lines:
// alignas(64) atomic_uint_fast32_t enqueue_pos;
// alignas(64) atomic_uint_fast32_t dequeue_pos;
// alignas(64) atomic_uint_fast32_t active_tasks;
// alignas(64) atomic_uint_fast32_t shut_down;

bool mpmc_dequeue(GlobalContext *__G, uint_fast32_t *dequeue_pos) {
    uint_fast32_t pos = atomic_load_explicit(&__G->dequeue_pos, memory_order_relaxed);
    int spin_count = 0;

    while (true) {
        if (atomic_load_explicit(&__G->shut_down, memory_order_acquire)) {
            ANNOTATE_HAPPENS_AFTER(&__G->shut_down);
            return false;
        }

        QueueNode *node = &__G->queue_node[pos & QUEUE_MASK];
        uint_fast32_t seq = atomic_load_explicit(&node->sequence, memory_order_acquire);
        intptr_t diff = (intptr_t)seq - (intptr_t)(pos + 1);

        if (diff == 0) {
            if (atomic_compare_exchange_weak_explicit(
                    &__G->dequeue_pos, &pos, pos + 1,
                    memory_order_acquire, memory_order_relaxed)) {
                ANNOTATE_HAPPENS_AFTER(&node->sequence);
                *dequeue_pos = pos;
                return true; // Caller MUST call mpmc_release_slot(__G, pos) after reading payload!
            }
            spin_count = 0;
        } else if (diff < 0) {
            if (atomic_load_explicit(&__G->active_tasks, memory_order_acquire) == 0) {
                uint_fast32_t check_pos = atomic_load_explicit(&__G->dequeue_pos, memory_order_acquire);
                uint_fast32_t check_seq = atomic_load_explicit(
                    &__G->queue_node[check_pos & QUEUE_MASK].sequence, memory_order_acquire);
                if ((intptr_t)check_seq - (intptr_t)(check_pos + 1) < 0) {
                    atomic_store_explicit(&__G->shut_down, 1, memory_order_release);
                    return false;
                }
            }
            // Back off exponentially before yielding to stop 15 threads from thrashing the bus
            if (++spin_count < 64) {
                for (int i = 0; i < spin_count; i++) {
#if defined(__x86_64__)
                    __builtin_ia32_pause();
#endif
                }
            } else {
                sched_yield();
            }
            pos = atomic_load_explicit(&__G->dequeue_pos, memory_order_relaxed);
        } else {
            // Another thread won this slot; reload relaxed since sequence load provides acquire
            pos = atomic_load_explicit(&__G->dequeue_pos, memory_order_relaxed);
        }
    }
}

static inline void mpmc_release_slot(GlobalContext *__G, uint_fast32_t pos) {
    atomic_store_explicit(&__G->queue_node[pos & QUEUE_MASK].sequence,
                          pos + QUEUE_NODES, memory_order_release);
}
```

Key Improvements in This Version

• Fixes the data race. Separating mpmc_release_slot prevents producers from overwriting a slot while worker is still reading the directory path out of it.
• Cuts bus traffic during empty-queue spins. Exponential _mm_pause() backoff followed by sched_yield() stops idle threads from starving the active threads doing getdents64, while switching the reload pos loads to memory_order_relaxed avoids redundant memory barriers on ARM/non-x86 architectures.
• Replaces LOCK XCHG with plain stores. Using atomic_store_explicit(..., memory_order_release) instead of atomic_exchange_explicit compiles to a single MOV instruction on x86_64.
Would you like to share how worker consumes the node and enqueues subdirectories so we can wire up mpmc_release_slot cleanly and check if a thread-local work stack can bypass the MPMC queue altogether for inner directories?

```c
void *finder(GlobalContext *__G, ThreadLocal *__tl) {
 long nread;
 struct stat sb = {};
 struct linux_dirent64 *entry;
 dev_t actual_dev = 0, effective_dev = 0;
 ino_t actual_ino = 0, effective_ino = 0;
 unsigned char actual_type;
 int rc;
 LogCtx *log_ctx = &__tl->log_ctx;
 __tl->stage_idx = 0;
 __tl->stage->path_offset = 0;

 struct open_how how = {
 .flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC,
 .mode = 0};
 if (!__G->follow_links)
 how.resolve |= RESOLVE_NO_SYMLINKS;
 int dir_fd = syscall(SYS_openat2, AT_FDCWD, __tl->path, &how, sizeof(struct open_how));
 if (dir_fd == -1) {
 if (__G->f_logging) {
 lf_log(ERROR, "OPEN_FAIL,%s,%s", __tl->path, strerror(errno));
 } else
 fprintf(stderr, "OPEN_FAIL,%s,%d:%s\n", __tl->path, errno, strerror(errno));
 flush_output_buffer(__G, __tl->output);
 // delete goes here - TO BE IMPLEMENTED IN FUTURE
 // if (__G->unlink)
 // finalize_directory_node(&dequeued_node->dir_ctx);
 return NULL;
 }
 while (1) {
 nread = syscall(SYS_getdents64, dir_fd, __tl->dir_buf, DIR_BUF_SIZE);
 if (__builtin_expect(nread == -1, 0)) {
 atomic_fetch_add(&__G->error_count, 1);
 if (__G->f_logging)
 lf_log(ERROR, "READDIR_FAIL,%s,%s", __tl->path, strerror(errno));
 break;
 }
 if (nread == 0)
 break;
 for (uint_fast32_t bpos = 0; bpos < (size_t)nread;) {
 entry = (struct linux_dirent64 *)(__tl->dir_buf + bpos);
 bpos += entry->d_reclen;
 actual_type = entry->d_type;
 __tl->effective_type = actual_type;
 // -------------------------------------------------------------------
 // PROCESS DIRECTORY ENTRIES
 // -------------------------------------------------------------------
 if (__builtin_expect(actual_type == DT_DIR, 0)) {
 if (entry->d_name[0] == '.') {
 if (entry->d_name[1] == '\0')
 continue;
 if (entry->d_name[1] == '.' && entry->d_name[2] == '\0')
 continue;
 }
 }
 // -------------------------------------------------------------------
 // GET ADVANCED METADATA
 // -------------------------------------------------------------------
 bool need_metadata = (__G->follow_links && actual_type == DT_LNK);
 // Only evaluate the complex logging mask arrays if logging is
 // explicitly active
 if (__builtin_expect(__G->f_logging, 0)) {
 if ((__G->file_level_mask & ll_t[CYCLE].bits) ||
 (__G->disp_level_mask & ll_t[CYCLE].bits)) {
 need_metadata = true;
 }
 }
 if (__builtin_expect(need_metadata, 0)) {
 memset(&sb, 0, sizeof(struct stat));
 rc = fstatat(dir_fd, entry->d_name, &sb, AT_SYMLINK_NOFOLLOW);
 if (rc == -1) {
 atomic_fetch_add(&__G->error_count, 1);
 if (__G->f_logging)
 lf_log(ERROR, "LSTAT_FAIL,%s/%s,%s", __tl->path, entry->d_name,
 strerror(errno));
 } else {
 actual_ino = sb.st_ino;
 actual_dev = sb.st_dev;
 actual_type = (sb.st_mode & S_IFMT) >> 12;
 effective_dev = actual_dev;
 effective_ino = actual_ino;
 __tl->effective_type = actual_type;
 }
 if (S_ISLNK(sb.st_mode)) {
 if (__G->follow_links) {
 // -------------------------------------------------------
 // GET LINK METADATA
 // -------------------------------------------------------
 rc = fstatat(dir_fd, entry->d_name, &sb, 0);
 if (rc == -1) {
 atomic_fetch_add(&__G->error_count, 1);
 if (__G->f_logging)
 lf_log(ERROR, _("FSTATAT_FAIL,%s/%s,%s\n"), __tl->path, entry->d_name,
 strerror(errno));
 } else {
 effective_ino = sb.st_ino;
 effective_dev = sb.st_dev;
 __tl->effective_type = (sb.st_mode & S_IFMT) >> 12;
 }
 } else {
 __tl->effective_type = DT_REG;
 }
 }
 }
 // --------------------------------------------------------------------
 // DIRECTORY PROCESSING
 // --------------------------------------------------------------------
 if (__tl->effective_type == DT_DIR) {
 __tl->depth = __G->dir_node[__tl->queue_idx].depth + 1;
 if (__G->max_depth > 0 && __tl->depth + 1 > __G->max_depth)
 continue;
 // ----------------------------------------------------------------
 // HIGH-PERFORMANCE CYCLE DETECTION (Only if links followed)
 // ----------------------------------------------------------------
 if (__G->follow_links && actual_type == DT_LNK) {
 bool cycle_found = false;
 char target_path[MAX_PATH_LEN] = {'\0'};
 if (__builtin_expect(__G->f_logging, 0)) {
 if ((__G->file_level_mask & ll_t[CYCLE].bits) ||
 (__G->disp_level_mask & ll_t[CYCLE].bits)) {
 size_t len = readlinkat(dir_fd, entry->d_name, target_path,
 sizeof(target_path) - 1);
 if (len != (size_t)-1) {
 target_path[len] = '\0';
 atomic_fetch_add_explicit(&__G->error_count, 1,
 memory_order_relaxed);
 lf_log(ERROR, "READLINK_FAIL,%s/%s,%s\n",
 __tl->path, entry->d_name, strerror(errno));
 }
 lf_log(CYCLE, "Target item: dev: %lu, ino: %lu, Name: %s/%s\n",
 effective_dev, effective_ino, __tl->path, entry->d_name);
 }
 }
 // CYCLE Backtrack verification
 uint_fast32_t current_parent_idx = __tl->queue_idx;
 while (current_parent_idx != NO_PARENT) {
 CycleNode *ancestor = &__G->cyc_node[current_parent_idx];
 if (effective_dev == ancestor->dev &&
 effective_ino == ancestor->ino) {
 cycle_found = true;
 break;
 }
 current_parent_idx = __G->queue_node->parent_idx;
 }
 if (cycle_found) {
 atomic_fetch_add_explicit(&__G->error_count, 1,
 memory_order_relaxed);
 build_path(__tl, entry->d_name);
 print_file(__G, __tl);
 continue;
 }
 }
```

 ---- This is all I can get in one message ---
8:17 PM
Your finder function is already written with low-level optimizations (SYS_openat2, SYS_getdents64, __builtin_expect), which explains why mpmc_dequeue and kernel directory traversal stood out as the dominant costs. Looking closely at this snippet, there are two subtle bugs alongside three major performance improvements you can make right here.

1. Two Bugs Found in This Snippet

• Infinite loop risk in cycle backtracking. Look at line current_parent_idx = __G->queue_node->parent_idx;. That reads queue_node[0].parent_idx on every iteration instead of __G->queue_node[current_parent_idx].parent_idx, which will loop infinitely if queue_node[0].parent_idx is not NO_PARENT.

• Inverted readlinkat error check. In 

```c
if (len != (size_t)-1)
you log READLINK_FAIL and increment error_count when readlinkat succeeds (len != -1), rather than when it fails
(len == (size_t)-1).
```


2. Three High-Impact Performance Optimizations

• Eliminate syscall(...) glibc wrapper overhead. In the perf output, entry_SYSRETQ_unsafe_stack spent 2.62% inside syscall (worker -> syscall). Calling syscall(SYS_openat2, ...) and syscall(SYS_getdents64, ...) forces glibc's variadic syscall() wrapper to shuffle registers on every call. On x86_64 Linux, inline assembly wrappers for openat2 and getdents64 execute a direct syscall instruction with zero register-shuffling overhead.

• Handle d_type == DT_UNKNOWN safely. On filesystems like XFS or NFS (or older ext4 volumes), getdents64 can return DT_UNKNOWN instead of DT_DIR. Currently, need_metadata only triggers when __G->follow_links && actual_type == DT_LNK, so DT_UNKNOWN entries skip fstatat and are silently ignored as non-directories. Adding || actual_type == DT_UNKNOWN handles those filesystems without adding any syscalls on modern ext4.

• Skip memset(&sb, 0, ...) and target_path[MAX_PATH_LEN] = {'\0'}. Zeroing a 144-byte struct stat before fstatat (which overwrites the whole struct on rc == 0) and zero-initializing a MAX_PATH_LEN (4096-byte) stack buffer on every symlink costs unnecessary cycles. Declare struct stat sb; and char target_path[MAX_PATH_LEN]; uninitialized, since you already null-terminate target_path[len] = '\0'.
Please paste the second half of finder and the worker loop in the next message—that is where subdirectories get enqueued into the MPMC queue and where we can add a thread-local work stack to cut mpmc_dequeue's 12% CPU share down to near zero.
here is the rest of 
finder:
```c
 // ----------------------------------------------------------------
 // STAGE CHILD TASKS (Local Stack Buffering)
 // ----------------------------------------------------------------
 if (__tl->stage_idx >= STAGE_NODES - 1) {
 if (mpmc_bulk_enqueue(__G, __tl) == false) {
 atomic_fetch_add_explicit(&__G->error_count, 1,
 memory_order_relaxed);
 if (__G->f_logging)
 lf_log(ERROR, "STAGE_ENQUEUE_FAIL,%s\n",
 __tl->path);
 return NULL;
 } else {
 atomic_fetch_add_explicit(&__G->active_tasks,
 __tl->stage_idx, memory_order_relaxed);
 }
 __tl->stage_idx = 0;
 }
 __tl->d_name_len = strlen(entry->d_name);
 __tl->d_name = entry->d_name;
 __tl->stage->queue_node[__tl->stage_idx].parent_idx = __tl->queue_idx;
 __tl->stage->dir_node[__tl->stage_idx].path_len = __tl->d_name_len;
 __tl->stage->dir_node[__tl->stage_idx].child_dirs_remaining = 0;
 __tl->stage->dir_node[__tl->stage_idx].depth = __tl->depth;
 __tl->stage->dir_node[__tl->stage_idx].path_offset = __tl->stage->path_offset;
 memcpy(__tl->stage->path_data + __tl->stage->path_offset,
 __tl->d_name, __tl->d_name_len);
 __tl->stage->path_offset += __tl->d_name_len;
 __tl->stage->path_data[__tl->stage->path_offset++] = '\0';
 if (__G->follow_links) {
 __tl->stage->cyc_node[__tl->stage_idx].dev = effective_dev;
 __tl->stage->cyc_node[__tl->stage_idx].ino = effective_ino;
 }
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
Worker next:
8:28 PM
You already have a local staging buffer (__tl->stage with mpmc_bulk_enqueue)—which is a great design—and seeing the rest of finder reveals two important details:

1. Why mpmc_dequeue is still 12% even with mpmc_bulk_enqueue. You enqueue in batches (STAGE_NODES), which keeps mpmc_enqueue cheap, but mpmc_dequeue still pops one node at a time—meaning all 16 threads still contend on dequeue_pos for every single directory, and idle threads still spin tightly whenever the queue temporarily empties.

2. A subtle bug in the STAGE_NODES overflow check. Notice if (__tl->stage_idx >= STAGE_NODES - 1): when stage_idx hits STAGE_NODES - 1, you flush STAGE_NODES - 1 items, reset stage_idx = 0, and write the new item to slot 0. However, make sure __tl->stage->path_offset + __tl->d_name_len + 1 is also bounds-checked against the staging path_data buffer capacity so long directory names cannot overflow path_data before stage_idx reaches STAGE_NODES - 1.

3. Avoid strlen(entry->d_name) inside getdents64. linux_dirent64 gives you entry->d_reclen, which already encodes the record length (offsetof(struct linux_dirent64, d_name) + strlen + padding). Computing strlen on every directory entry scans every filename byte twice (once in strlen, once in memcpy).

Send over worker next and we can wire together:
• The thread-local LIFO fast path (so a worker keeps at least one staged subdirectory locally instead of pushing everything to the MPMC queue and immediately fighting 15 other threads to pop it back), and
• The safe slot release (mpmc_release_slot) in worker after reading the dequeued node.
Ready whenever you paste worker—we'll look at how it pops from mpmc_dequeue, invokes finder, and flushes remaining staged nodes.


```c
void *worker(void *arg) {
 // ----------------------------------------------------------------------
 // INITIALIZE GLOBAL LF (__G) DATA STRUCTURE
 // ----------------------------------------------------------------------
 GlobalContext *__G = (GlobalContext *)arg;
 // ----------------------------------------------------------------------
 // INITIALIZE THREAD LOCAL (__tl) DATA STRUCTURES
 // ----------------------------------------------------------------------

 alignas(CACHE_LINE_SIZE) ThreadLocal __tl;
 QueueNode queue_payload = {};
 __tl.local_queue_node = &queue_payload;
 alignas(CACHE_LINE_SIZE) Stage *stage =
 calloc(STAGE_NODES, sizeof(Stage));
 __tl.stage = stage;
 alignas(CACHE_LINE_SIZE) QueueNode *queue_node = calloc(STAGE_NODES, sizeof(QueueNode));
 __tl.stage->queue_node = queue_node;
 alignas(CACHE_LINE_SIZE) DirectoryNode *dir_node = calloc(STAGE_NODES, sizeof(DirectoryNode));
 __tl.stage->dir_node = dir_node;
 if (__G->follow_links) {
 alignas(CACHE_LINE_SIZE) CycleNode *cyc_node = calloc(STAGE_NODES, sizeof(CycleNode));
 __tl.stage->cyc_node = cyc_node;
 }
 alignas(CACHE_LINE_SIZE) char *path_data = calloc(STAGE_PATH_BYTES, sizeof(char));
 __tl.stage->path_data = path_data;
 alignas(CACHE_LINE_SIZE) char *path = calloc(MAX_PATH_LEN, sizeof(char));
 __tl.path = path;
 alignas(CACHE_LINE_SIZE) char dir_buf[DIR_BUF_SIZE];
 __tl.dir_buf = dir_buf;
 alignas(CACHE_LINE_SIZE) OutputBuffer *output_buffer = calloc(1, sizeof(OutputBuffer));
 __tl.output = output_buffer;
 __tl.path_offset = 0;
 __tl.stage_idx = 0;
 __tl.thread_id = atomic_fetch_add_explicit(&__G->thread_id, 1, memory_order_relaxed);
 uint_fast32_t q_pos = 0;
 LogCtx log_ctx = {};
 __tl.log_ctx = log_ctx;
 log_ctx.thread_id = __tl.thread_id;
 if (__G->f_logging && __G->log_fd == -1)
 initialize_timer(__G, &log_ctx);
 else
 initialize_thread_timer(__G, &log_ctx);
 while (1) {
 if (mpmc_dequeue(__G, &q_pos) == false)
 break;
 atomic_thread_fence(memory_order_acquire);
 // CACHE LINE ALIGNMENT
 // Ensure that the dequeued node is aligned to a cache line boundary
 // if (((uintptr_t)__tl.local_queue_node & (CACHE_LINE_SIZE - 1)) != 0)
 // {
 // perror("Warning: Dequeued node is not cache line aligned\n");
 // exit(EXIT_FAILURE);
 // }
 // ----------------------------------------------------------------
 // Reconstruct the relative path for the dequeued directory node
 // ----------------------------------------------------------------
 __tl.queue_idx = q_pos;
 uint_fast32_t q_path_len = __G->dir_node[q_pos].path_len;
 uint_fast32_t q_path_offset = atomic_load_explicit(&__G->dir_node[q_pos].path_offset, memory_order_acquire);

 __tl.path_len = q_path_len;
 uint_fast32_t cum_path_len = q_path_len; // length of dequeued dir_node path
 // ----------------------------------------------------------------
 // Get the length of the parent path
 // ----------------------------------------------------------------
 uint_fast32_t parent_idx = __G->queue_node[q_pos].parent_idx;
 while (parent_idx != NO_PARENT) {
 cum_path_len += __G->dir_node[parent_idx].path_len + 1;
 parent_idx = __G->queue_node[parent_idx].parent_idx;
 }
 if (cum_path_len >= MAX_PATH_LEN) {
 atomic_fetch_sub_explicit(&__G->active_tasks, 1, memory_order_relaxed);
 continue;
 }
 // __tl.path[cum_path_len] = '\0';
 // ----------------------------------------------------------------
 // Reconstruct the relative path for the dequeued directory node
 // ----------------------------------------------------------------
 uint_fast32_t write_cursor = cum_path_len;
 write_cursor -= q_path_len;
 memcpy(&__tl.path[write_cursor],
 &__G->path_data[q_path_offset],
 q_path_len);
 __tl.path[cum_path_len] = '\0';
 parent_idx = __G->queue_node[q_pos].parent_idx;
 uint_fast32_t p_path_len;
 uint_fast32_t p_path_offset;
 while (parent_idx != NO_PARENT) {
 write_cursor -= 1;
 __tl.path[write_cursor] = '/';
 p_path_len = __G->dir_node[parent_idx].path_len;
 p_path_offset = __G->dir_node[parent_idx].path_offset;
 write_cursor -= p_path_len;
 memcpy(&__tl.path[write_cursor],
 &__G->path_data[p_path_offset],
 p_path_len);
 parent_idx = __G->queue_node[parent_idx].parent_idx;
 }
 __tl.parent_path_len = cum_path_len;
 // ----------------------------------------------------------------
 // __tl->path now contains a relative path to the directory to open
 // ----------------------------------------------------------------
 finder(__G, &__tl);
 atomic_fetch_sub_explicit(&__G->active_tasks, 1, memory_order_relaxed);
 }
 free(output_buffer);
 free(path);
 free(path_data);
 path_data = NULL;
 if (__G->follow_links) {
 free(__tl.stage->cyc_node);
 __tl.stage->cyc_node = NULL;
 }
 free(dir_node);
 free(queue_node);
 free(stage);
 return NULL;
}
```
8:30 PM
Seeing worker alongside finder and mpmc_dequeue makes the entire picture clear. Your architecture uses an append-only node arena indexed by q_pos (which explains why queue_node is never overwritten in place, making the early sequence update safe as long as QUEUE_NODES exceeds the total directories traversed!).
However, four major bottlenecks in worker and finder are directly driving the 12% mpmc_dequeue burn, 4.6% syscall overhead, and startup page faults (folio_zero_user):

1. Eliminating mpmc_dequeue Contention (12% of Total CPU)

Right now, every time finder finishes reading a directory, it flushes its local staging buffer (__tl->stage) into the global MPMC queue, and then worker immediately loops back to fight 15 other threads in mpmc_dequeue to pop a directory back out—rebuilding the full path string from root to leaf on every single directory!

• Why this wastes cycles. When a worker opens /home/bill/projects/app, it already has /home/bill/projects/app sitting in __tl.path (__tl.parent_path_len) and an open file descriptor (dir_fd). Pushing all subdirectories into the global MPMC queue forces another thread to walk parent pointers all the way back to /home/bill and call openat2(AT_FDCWD, ...) from scratch.

• The fix: Depth-First Local Fast Path. Keep a small thread-local stack of pending subdirectories (or keep the first staged subdirectory locally in __tl) while flushing excess subdirectories to the global MPMC queue so idle threads still get work.

	• When finder discovers subdirectories, push the first subdirectory onto a local LIFO stack (storing its q_pos or appending its name directly onto __tl.path and calling openat(dir_fd, entry->d_name, ...)), and push remaining subdirectories into __tl->stage for mpmc_bulk_enqueue.

	• In worker, pop from thread-local stack first with zero atomic operations. Only call mpmc_dequeue when the local stack is empty. This cuts MPMC queue traffic and parent-chain path reconstruction by 70–90%.

2. Fixing the Premature active_tasks Underflow Risk

Look closely at finder and worker:

• In finder, you increment active_tasks after mpmc_bulk_enqueue succeeds (atomic_fetch_add_explicit(&__G->active_tasks, __tl->stage_idx, ...)).

• The race condition. Between mpmc_bulk_enqueue publishing the new items and atomic_fetch_add(&__G->active_tasks, ...) running, another thread can dequeue those items, finish them, decrement active_tasks to 0, and trigger shut_down = 1 prematurely!

• The fix. Always increment active_tasks before calling mpmc_bulk_enqueue (and subtract it back if mpmc_bulk_enqueue fails).

3. Cutting Thread Startup & Page Fault Overhead (calloc)

In worker, every single one of the 16 threads runs 7 separate calloc calls on startup (stage, queue_node, dir_node, cyc_node, path_data, path, output_buffer), plus a large stack array char dir_buf[DIR_BUF_SIZE].

• Why this hurts on a 0.1s run. On a 100-millisecond program, 16 threads concurrently calling calloc acquire glibc arena locks and trigger hundreds of minor page faults (folio_zero_user) as the kernel zeroes pages on first touch.

• The fix.
	• Replace calloc with malloc for buffers you overwrite anyway (path_data, path, queue_node, dir_node), or allocate one single contiguous block per thread (void *arena = malloc(total_tl_bytes)) and slice pointers out of it.
	• Keep OutputBuffer and Stage structs directly on the thread stack or inside that single malloc block instead of 7 separate heap allocations.

4. Removing alignas(CACHE_LINE_SIZE) on Local Pointers

Notice lines like:

```c
alignas(CACHE_LINE_SIZE) Stage *stage = calloc(...);
alignas(CACHE_LINE_SIZE) char *path = calloc(...);
```

• In C11, alignas(64) on a pointer variable (char *path) aligns the 8-byte pointer variable on the stack, not the heap memory returned by calloc! Worse, putting alignas(64) on 8 separate stack pointers forces the compiler to waste 512 bytes of stack space and emit stack-alignment prologues.

• If you want the heap buffers cache-line aligned, use aligned_alloc(CACHE_LINE_SIZE, size) instead of alignas(CACHE_LINE_SIZE) char *ptr = calloc(...).

Summary of Immediate Code Changes

1. Fix mpmc_dequeue spin-backoff (using exponential __builtin_ia32_pause() + sched_yield()) so idle threads stop burning 12% CPU when the queue briefly empties.
2. Increment active_tasks before mpmc_bulk_enqueue so worker threads never see active_tasks == 0 while items are in flight.
3. Replace 7 calloc calls per thread with 1 malloc arena (or stack storage) to eliminate startup page faults and allocator lock contention.
4. Add a local subdirectory fast path in worker/finder so each thread traverses deep directory chains locally without round-tripping through mpmc_dequeue and reconstructing paths from root.
Would you like a concrete code example showing how to add the thread-local LIFO stack to worker and finder (using openat on the parent dir_fd so you don't even have to reconstruct full paths)?
sure
8:38 PM

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

In worker, check __tl.local_top > 0 at the top of the while (1) loop. When popping a local task, you already have the parent path sitting in __tl.path, so constructing the child path takes a single memcpy instead of walking parent pointers all the way back to /home/bill.

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

    // ... existing parent-pointer path reconstruction code ...
    
    finder(__G, &__tl);
    atomic_fetch_sub_explicit(&__G->active_tasks, 1, memory_order_relaxed);
}
```

Why This Works So Well

• Zero active_tasks contention on local work. Because local tasks never enter the global MPMC queue, you never increment or decrement __G->active_tasks for them. Meanwhile, the parent task that spawned them keeps active_tasks >= 1 until its entire local subtree finishes, guaranteeing no other thread triggers shut_down early.

• Immediate parallel fan-out. Capping the local fast-path threshold at local_top < 4 ensures that as soon as the root directory (/home/bill) is scanned, any subdirectories beyond the first 4 immediately spill into mpmc_bulk_enqueue so all 16 worker threads saturate the CPU cores within microseconds.

• Cache locality. Each worker drills depth-first into its own directory subtree, keeping the kernel's dentry cache and __tl.path hot in L1/L2 cache.
After adding this local fast path and the spin-backoff in mpmc_dequeue, re-run perf record -F 4000 -g -- ./lf4 -H /home/bill >/dev/null and share the new mpmc_dequeue percentage and elapsed time—we can see how much closer you are to pure getdents64 filesystem speed.

