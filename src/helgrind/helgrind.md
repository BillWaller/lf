```
Helgrind, a thread error detector
Copyright (C) 2007-2026, and GNU GPL'd, by OpenWorks LLP et al.
Using Valgrind-3.29.0.GIT and LibVEX; rerun with -h for copyright info
Command: ./lf -H
2026-11-27T21:00:14Z Condensed Format by Bill Waller

cntxt errors action size  at_addr by_addr fn                          thread  line
----- ------ ------ ---- -------- ------- ------------------------------ --- -----
    1      1 read      4  4AB2100  4076A3 mpmc_dequeue                    12  1126
    1        write                 407F7A worker                           7  1273
    2      1 write     4  4AB2100  407F7A worker                           7  1273
    2        read                  4076A3 mpmc_dequeue                    11  1126
    3      1 write     1  56BD364  407411 mpmc_bulk_enqueue                7  1086
    3        write                 407411 mpmc_bulk_enqueue                2  1086
    4      2 write     1  56BD1E6  407411 mpmc_bulk_enqueue                5  1086
    4        read                  407DED worker                           4  1245
    5      2 read      2  56BD4E4  407ED8 worker                           7  1258
    5        write                 407411 mpmc_bulk_enqueue                2  1086
    6      2 read      1  56BD1E2  407ED8 worker                           7  1258
    6        write                 407411 mpmc_bulk_enqueue                5  1086
    7      2 write     4  56BD1C0  40744F mpmc_bulk_enqueue                5  1087
    7        read                  408006 release_directory_chain          4  1285
    8      2 write     2  56BD2E0  40738B mpmc_bulk_enqueue                5  1085
    8        read                  407C6B worker                           4  1226
    9      2 write     8  56BD1D8  407341 mpmc_bulk_enqueue                5  1084
    9        write                 407341 mpmc_bulk_enqueue                2  1084
   10      2 write     8  56BD1D0  4072FA mpmc_bulk_enqueue                5  1083
   10        write                 4072FA mpmc_bulk_enqueue                2  1083
   11      2 write     4  56BD1C8  4072B4 mpmc_bulk_enqueue                5  1082
   11        write                 4072B4 mpmc_bulk_enqueue                2  1082
   12      2 write     4  56BD1C4  40726F mpmc_bulk_enqueue                5  1081
   12        read                  407CCB worker                           4  1231
   13      2 read      4  56BD180  406DBE node_alloc                       5   999
   13        write                 406E93 node_free                        4  1015
   14      2 read      4  56BD4C0  408D2F flush_stage_buffer               5  1525
   14        write                 40744F mpmc_bulk_enqueue                2  1087
   15      2 read      4  56BD4C8  408747 finder                           5  1420
   15        write                 4072B4 mpmc_bulk_enqueue                2  1082
   16      3 read      2  56BD1E4  407DED worker                           4  1245
   16        write                 407411 mpmc_bulk_enqueue                2  1086
   17      4 read      1  56BD7E2  407DED worker                           6  1245
   17        write                 407411 mpmc_bulk_enqueue                2  1086
   18      4 read      1  56BD1E0  407ED8 worker                           7  1258
   18        write                 407411 mpmc_bulk_enqueue                5  1086
   19      4 read      4  56BD344  407D24 worker                           6  1234
   19        write                 40726F mpmc_bulk_enqueue                2  1081
   20      4 read      2  56BD460  407CF1 worker                           6  1233
   20        write                 40738B mpmc_bulk_enqueue                2  1085
   21      4 write     4  4AB22C0  4075B1 mpmc_bulk_enqueue                2  1102
   21        read                  407780 mpmc_dequeue                     3  1132
   22      4 read      4  4AB22C4  407824 mpmc_dequeue                     4  1143
   22        write                 40758D mpmc_bulk_enqueue                2  1101
   23      5 read      4  4AB22C0  407780 mpmc_dequeue                     4  1132
   23        write                 4075B1 mpmc_bulk_enqueue                2  1102
   24      5 read      4  56BD1C4  407CCB worker                           4  1231
   24        write                 40726F mpmc_bulk_enqueue                2  1081
   25      5 read      2  56BD2E0  407C6B worker                           4  1226
   25        write                 40738B mpmc_bulk_enqueue                2  1085
   26      5 write     4  4AB22C0  407876 mpmc_dequeue                     4  1144
   26        write                 4075B1 mpmc_bulk_enqueue                2  1102
   27      6 write     2  56BD1E0  407411 mpmc_bulk_enqueue                5  1086
   27        read                  407DED worker                           4  1245
   28      6 write     4  56BD180  406E93 node_free                        4  1015
   28        read                  406DBE node_alloc                       2   999
   29      6 read      4  56BD1C4  408031 release_directory_chain          4  1292
   29        write                 40726F mpmc_bulk_enqueue                2  1081
   30      7 read      2  56BD360  407ED8 worker                           6  1258
   30        write                 407411 mpmc_bulk_enqueue                2  1086
   31      8 read      2  56BD1E0  407DED worker                           4  1245
   31        write                 407411 mpmc_bulk_enqueue                2  1086
   32      8 read      4  56BD1C0  408006 release_directory_chain          4  1285
   32        write                 40744F mpmc_bulk_enqueue                2  1087
   33     14 read      1  56BD7E0  407DED worker                           6  1245
   33        write                 407411 mpmc_bulk_enqueue                2  1086
      ------
         129 total errors
```

```
line_no errors Conflicts
------- ------ -------------------------------------------------
   999r      8  1015w
  1015w      8   999r
  1081w     17  1231r 1234r 1292r
  1082w      6  1082w 1420r
  1083w      4  1083w
  1084w      4  1084w
  1085w     11  1226r 1233r
  1086w     54  1086w 1245r 1258r
  1087w     12  1285r 1525r
  1101w      4  1143r
  1102w     14  1132r 1144w
  1126r      2  1273w
  1132r      9  1102w
  1143r      4  1101w
  1144w      5  1102w
  1226r      7  1085w
  1231r      7  1081w
  1233r      4  1085w
  1234r      4  1081w
  1245r     37  1086w
  1258r     15  1086w
  1273w      2  1126r
  1285r     10  1087w
  1292r      6  1081w
  1420r      2  1082w
  1525r      2  1087w
        ------ 
total      258 (2 x 129) 
```

```c
   >>> __G->queue[idx].next_free

   999r         uint32_t next = atomic_load_explicit(&__G->queue[idx].next_free, memory_order_relaxed);
  1015w         atomic_store_explicit(&__G->queue[idx].next_free, (uint32_t)head, memory_order_release);
```

```c
   >>> __G->queue[idx].parent_idx

  1081w        __G->queue[idx].parent_idx = __tl->stage[i].parent_idx;
  1231r        uint32_t parent_idx = __G->queue[q_pos].parent_idx;
  1233r            cum_path_len += __G->queue[parent_idx].name_len + 1;
  1234r            parent_idx = __G->queue[parent_idx].parent_idx;
  1292r            uint32_t parent = __G->queue[curr].parent_idx;
```

```c
   >>> __G->queue[idx].depth

  1082w        __G->queue[idx].depth = __tl->stage[i].depth;
  1420r                __tl->depth = __G->queue[__tl->queue_idx].depth + 1;
```


```c
   >>> __G->queue[idx].dev
  1083w        __G->queue[idx].dev = __tl->stage[i].dev;
```

```c
   >>> __G->queue[idx].ino
  1084w        __G->queue[idx].ino = __tl->stage[i].ino;
```

```c
   >>> __G->queue[idx].name_len

  1085w        __G->queue[idx].name_len = __tl->stage[i].name_len;
  1226r        uint32_t q_path_len = __G->queue[q_pos].name_len;
  1084w        __G->queue[idx].ino = __tl->stage[i].ino;
  1233r            cum_path_len += __G->queue[parent_idx].name_len + 1;
```

```c
   >>> __G->queue[idx].name

  1086w        memcpy(__G->queue[idx].name, __tl->stage[i].name, __tl->stage[i].name_len + 1);
  1245r        memcpy(&__tl.path[write_cursor],
  1246r               &__G->queue[q_pos].name, __G->queue[q_pos].name_len);
  1258r            memcpy(&__tl.path[write_cursor],
  1259r                   &__G->queue[parent_idx].name,
  1260r                   __G->queue[parent_idx].name_len);
```

```c
   >>> __G->queue[idx].child_dirs_remaining

  1087w        atomic_store_explicit(&__G->queue[idx].child_dirs_remaining, 1, memory_order_relaxed);
  1285r        uint32_t prev = atomic_fetch_sub_explicit(
  1286r            &__G->queue[curr].child_dirs_remaining,
  1287r            1,
  1288r            memory_order_acq_rel);
  1525r    atomic_fetch_add_explicit(&__G->queue[__tl->queue_idx].child_dirs_remaining, __tl->stage_idx, memory_order_relaxed);
```

```c
   >>> slot->node_idx

  1101w                    slot->node_idx = allocated_indices[i];
  1143r                *out_node_idx = __G->ring[pos & QUEUE_MASK].node_idx;
  1144w                atomic_store_explicit(&__G->ring[pos & QUEUE_MASK].sequence, pos + QUEUE_NODES, memory_order_release);
```

```c
   >>> slot->sequence
  1102w                    atomic_store_explicit(&slot->sequence, pos + 1, memory_order_release);
  1132r        uint32_t seq = atomic_load_explicit(&slot->sequence, memory_order_acquire);
  1144w                atomic_store_explicit(&__G->ring[pos & QUEUE_MASK].sequence, pos + QUEUE_NODES, memory_order_release);
```
