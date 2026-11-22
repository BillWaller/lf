
# lf - A Lightning Fast File Finder

## lf Quality Assurance

NOTE: lf has also been tested with -fsanitize=thread and -fsanitize=address, and no errors were found.

### Helgrind output

```
==792531== Helgrind, a thread error detector
==792531== Copyright (C) 2007-2026, and GNU GPL'd, by OpenWorks LLP et al.
==792531== Using Valgrind-3.29.0.GIT and LibVEX; rerun with -h for copyright info
==792531== Command: ./lf -H
==792531== Parent PID: 792529
==792531== 
==792531== 
==792531== Use --history-level=approx or =none to gain increased speed, at
==792531== the cost of reduced accuracy of conflicting-access information
==792531== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 135 from 10)
--792531-- 
--792531-- used_suppression:    135 helgrind-glibc2X-005 /usr/libexec/valgrind/default.supp:1022
==792531== 
==792531== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 135 from 10)
```

---

### Valgrind output

```
==797634== Memcheck, a memory error detector
==797634== Copyright (C) 2002-2026, and GNU GPL'd, by Julian Seward et al.
==797634== Using Valgrind-3.29.0.GIT- and LibVEX; rerun with -h for copyright info
==797634== Command: ./lf -H
==797634== Parent PID: 797632
==797634== ==797634== HEAP SUMMARY:
==797634==     in use at exit: 0 bytes in 0 blocks
==797634==   total heap usage: 60 allocs, 60 frees, 8,415,217 bytes allocated
==797634== 
==797634== All heap blocks were freed -- no leaks are possible
==797634== 
==797634== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)
```
---

## File Finder Comparative Benchmark

### Baseline find (GNU findutils) version 4.11.0

```
find /home/bill
find: ‘/home/bill/.config/google-chrome/BrowserMetrics’: Permission denied
0.36user 0.48system 0:00.85elapsed 99%CPU (0avgtext+0avgdata 35500maxresident)k
0inputs+0outputs (0major+11893minor)pagefaults 0swaps
found 511296 files
```
---

### Baseline fd version 10.5.0

```
fd . -H -I /home/bill
0.91user 0.69system 0:00.24elapsed 654%CPU (0avgtext+0avgdata 51740maxresident)k
0inputs+0outputs (0major+13314minor)pagefaults 0swaps
expected 511295 files, found 511295 files
```
---

### lf 6 threads

```
./lf -H /home/bill -T6
OPEN_FAIL,/home/bill/.config/google-chrome/BrowserMetrics,13:Permission denied
0.11user 0.37system 0:00.09elapsed 529%CPU (0avgtext+0avgdata 17316maxresident)k
0inputs+0outputs (0major+432minor)pagefaults 0swaps
expected 511295, found 511295 files
```
---

### lf 13 threads

---
```
./lf -H /home/bill -T13
OPEN_FAIL,/home/bill/.config/google-chrome/BrowserMetrics,13:Permission denied
0.18user 0.56system 0:00.07elapsed 957%CPU (0avgtext+0avgdata 18312maxresident)k
0inputs+0outputs (0major+782minor)pagefaults 0swaps
expected 511295, found 511295 files
```
---

### lf 15 threads

```
./lf -H /home/bill -T15
OPEN_FAIL,/home/bill/.config/google-chrome/BrowserMetrics,13:Permission denied
0.19user 0.62system 0:00.07elapsed 1026%CPU (0avgtext+0avgdata 18824maxresident)k
0inputs+0outputs (0major+865minor)pagefaults 0swaps
expected 511295, found 511295 files
```
------------------------------------------------

### lf 16 threads

```
./lf -H /home/bill -T16
OPEN_FAIL,/home/bill/.config/google-chrome/BrowserMetrics,13:Permission denied
0.16user 0.67system 0:00.08elapsed 1030%CPU (0avgtext+0avgdata 18780maxresident)k
0inputs+0outputs (0major+902minor)pagefaults 0swaps
expected 511295, found 511295 files
```
---
