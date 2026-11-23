# Freeing Queue Directory Nodes Once All Child Directories are Processed

The finder() function opens a dequeued directory and enqueues its child directories. 

These child directories will be processed by future instances of finder().

Each instance of the finder increments its parent's child_dirs_remaining when enqueueing descendants.

When a directory has no child directories to enqueue, the finder decrements its parent's child_dirs_remaining. If the parent's child_dirs remaining reaches zero, it indicates that all of its child directories have been processed, and the parent directory can be safely freed. The finder ascends the directory tree, decrementing child_dirs_remaining and freeing each directory for which child_dirs_remaining is zero
until it reaches a parent with remaining children or the root directory.

This ensures that directories are only freed when all of their children have been fully processed, preventing premature deallocation and potential access violations.

Easy peasy, right? We'll see how this works in practice in the next section, where we will implement the finder() function and demonstrate its behavior with a sample directory structure.

Nothing is as easy as it seems in the beginning, nor as difficult as seems just before
the conclusion. In retrospect, its just another adventure in the world of
programming. We learn as we go, progressing as we manage our resources effectively and ensure the integrity of our systems.

Above all, thank you Lord, for giving me these opportunities to learn and grow in the field of programming. May I continue to develop my skills and contribute positively to the world of technology.

Hell must be a World without problems, for that would truly be unbearable.
