# Child Dirs

    dequeue (1)
        enqueue (1-1), (1-2), (1-3)
        (1)->dirs_remaining += 3

    dequeue (1-1)
        enqueue (1-1-1), (1-1-2)
        (1-1)->dirs_remaining += 2

    dequeue (1-2)
        enqueue (1-2-1), (1-2-2), (1-2-3), (1-2-4)
        (1-2)->dirs_remaining += 4

    dequeue (1-3)
        enqueue (1-3-1), (1-3-2)
        (1-3)->dirs_remaining += 2

    dequeue (1-1-1)
        enqueue (1-1-1-1), (1-1-1-2), (1-1-1-3)
        (1-1-1)->dirs_remaining += 3

    dequeue (1-1-1-1)
        enqueue (1-1-1-1-1), (1-1-1-1-2), (1-1-1-1-3), (1-1-1-1-4)
        (1-1-1-1)->dirs_remaining += 4

    dequeue (1-1-1-1-1)
        if (__tl->dirs_remaining != 0)
            enqueue(current_dir)
        else {
            while (true) {
                if queue[q_idx]->dirs_remaining == 0
                    remove(queue[q_idx])
                queue[q_idx]->dirs_remaining -= 1
                if (queue[q_idx]->parent_idx == NO_PARENT)
                    break
                q_idx = queue[q_idx]->parent_idx
            }
        }

    // --------------------------------------------
    //  if (1-1-1-1-1)->dirs_remaining == 0
    //      remove(1-1-1-1-1)
    //      (1-1-1-1)->dirs_remaining -= 1
    //      if (1-1-1-1)->dirs_remaining == 0
    //          remove(1-1-1-1)
    //          (1-1-1)->dirs_remaining -= 1
    //          if (1-1-1)->dirs_remaining == 0
    //              remove(1-1-1)
    //              (1-1)->dirs_remaining -= 1
    //              if (1-1)->dirs_remaining == 0
    //                  remove(1-1)
    //                  (1)->dirs_remaining -= 1 
    //                  if (1)->dirs_remaining == 0
    //                      remove(1)


if (1-1-1-1)->dirs_remaining == 0
        remove(1-1-1-1) from queue


q_idx = q_idx->parent_idx (1-1-1)
if (q_idx)->dirs_remaining == 0

            if (queue(q_idx)->dirs_remaining == 0) {
                
            q_idx = queue(q_idx)->q_parent_idx
        }

if (1-1-1-1-1)->dirs_remaining == 0;
            (1-1-1-1)->dirs_remaining -= 1
        if ()
            if (1-1-1-1)->dirs_remaining == 0;
                (1-1-1)->dirs_remaining -= 1
                if (1-1-1)->dirs_remaining == 0;
                    (1-1)->dirs_remaining -= 1
                    if (1-1)->dirs_remaining == 0;
                        (1)->dirs_remaining -= 1
                        if (1)->dirs_remaining == 0;
                            enqueue (done)
