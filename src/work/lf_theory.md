# Queueing Systems for Directory Traversal

## Ring Buffer Queue

A ring buffer queue is a data structure that uses a fixed-size array to implement a queue. It is called a "ring buffer" because the end of the array wraps around to the beginning, creating a circular structure. This allows for efficient use of memory and constant time complexity for enqueue and dequeue operations.


## File System Directory Trees

Given a base directory, a file system directory tree can be represented as a
hierarchical structure where each directory may contain files and subdirectories.
Normally, the files will be sent to output as encountered, while the subdirectories will be saved as queue nodes for further processing. In addition to the queue, a character buffer serving as pool of directory name strings may be accessed by offset and length fields in the queue nodes. The nodes also contain the index numbers of
parent directories, which allows for reverse traversal of each ancestor in the tree.

## Queue Node Structure

Each queue node represents a directory, thus it may be referred to as a Queue Node
and a Directory Node. It contains the following information:

Parent node index in the queue
Directory name offset and length in the character buffer
Device and inode pair for cycle Detection
Child directory count for pruning unneeded nodes
Depth in the directory tree

## Cycle Detection

The parent node links (indexes) are used to match device and inode numbers, which
can be used to detect file system links pointing to a parent directory (cycles or
cyclic links). Obviously this is only possible if the parent directory is still
in the queue. Therefore, parent nodes must be retained in the queue until all child directories have been processed.

## Identifying and Pruning Unneeded Nodes

Because lf employs a virtual queue, it is possible to retain parent nodes in the
queue even after all of their child directories have been processed. This allows for cycle detection and reverse traversal of the directory tree. However, retaining parent nodes in the queue can lead to increased memory usage and decreased performance, albeit unlikely.

The question is how to determine when a parent node can be pruned from the queue. The answer is that a parent node can be pruned when all of its child directories have been processed.

This can be determined by keeping track of the number of child directories for each parent node and decrementing this count as each child directory is processed.
When a child directory is fully processed, the count for its parent node is decremented. When a node's remaining subdirectory count reaches zero, it can be safely removed from the queue, and the remaining subdirectory count of its parent can then
decremented. 

## Workers

In a multi-threaded system, each thread starts a worker process that is both a
consumer and producer of the queue. The worker will dequeue a directory node, process it, and enqueue any child directories found within it. This allows for concurrent processing of multiple directories, improving the overall efficiency of the traversal.

The worker examines a global pointer to determine which directory node to
process next. 

## Queue Management

The queue is managed using a ring buffer structure, which allows for efficient enqueue and dequeue operations. The queue maintains a head and tail pointer to keep track of the current position in the buffer. When a directory node is enqueued, it is added to the position indicated by the tail pointer, and the tail pointer is incremented. When a directory node is dequeued, it is removed from the position indicated by the head pointer, and the head pointer is incremented.

## Contention for Queue Access

In a multi-threaded environment, multiple workers may attempt to access the queue simultaneously, leading to contention. To manage this contention, synchronization mechanisms such as mutexes or semaphores can be used to ensure that only one worker can access the queue at a time. In this particular implementation, lock-free atomic operations, such as Compare and Swap (CAS) are used to atomically update the head and tail pointers, preventing race conditions and ensuring the integrity of the queue data structure.

## Token Based Queue Access

Instead of using locks, a token-based approach can be employed to manage access to the queue. Each worker thread can be assigned a unique token that grants it permission to access the queue. When a worker wants to enqueue or dequeue a directory node, it must first acquire its token. Once the operation is complete, the worker releases the token, allowing other workers to access the queue. This approach reduces contention and improves performance in multi-threaded environments.

This strategy may be convenient for bulk processing of directories. A worker can
request a number of tokens, for reserved queue nodes not subject to contention on an open queue. 

