mod types;
mod utils;

use utils::{is_empty, array_length, validate_array};
use types::{StorageOp, StorageLeaf, StorageLinkedItem};

fn create_linked_linked_items<N>(
    storage_ops: [StorageOp; N],
    initial_leaves: [StorageLeaf; N],
    linked_hints: [(u32, bool); N]
) -> [StorageLinkedItem; N] {
    // Populate the proving items with the hints
    let mut linked_items = [StorageLinkedItem::default(); N];
    for i in 0..N {
        linked_items[i] = StorageLinkedItem {
            op: storage_ops[i],
            prev_index: linked_hints[i].0,
            has_prev_leaf: linked_hints[i].1,
        };
    }

    // Ensure that the initial leaves are sorted by slot.
    // This ensures that there are no duplicated leaves for a given slot.
    validate_array(initial_leaves);
    let initial_leaves_length = array_length(initial_leaves);
    for i in 1..N {
        if (i as u32) < (initial_leaves_length as u32) {
            assert(dep::std::eddsa::lt_bytes32(initial_leaves[i - 1].slot, initial_leaves[i].slot));
        }
    }

    // Ensure that all operations are linked to a valid previous operation or initial leaf.
    let mut leaves_targeted = [false; N];
    let mut ops_targeted = [false; N];

    for i in 0..N {
        let linked_item = linked_items[i];
        if is_empty(linked_item.op) {
            // If the op is empty, we assert an empty proving item
            assert(is_empty(linked_item));
        } else if linked_item.has_prev_leaf {
            // If the proving item points to a previous leaf, we check that it wasn't targeted before and the slot matches
            assert(!leaves_targeted[linked_item.prev_index]);
            leaves_targeted[linked_item.prev_index] = true;

            let leaf = initial_leaves[linked_item.prev_index];
            assert(leaf.slot == linked_item.op.slot);
        } else {
            // If the proving item points to a previous op, we check that it wasn't targeted before and the slot matches and the counter increases
            assert(!ops_targeted[linked_item.prev_index]);
            ops_targeted[linked_item.prev_index] = true;

            let prev_op = storage_ops[linked_item.prev_index];
            assert(prev_op.slot == linked_item.op.slot);
            assert(prev_op.counter <= linked_item.op.counter);
        }
    }

    linked_items
}

fn add_rewind_to_linked_linked_items<N, K>(
    mut linked_items: [StorageLinkedItem; N],
    rewind_hints: [Option<u32>; N],
    _double_len_hint: [(); K]
) -> [StorageLinkedItem; K] {
    assert_eq(N * 2, K);

    let mut rewinds = [StorageLinkedItem::default(); N];

    for i in 0..N {
        let hint_opt = rewind_hints[i - N];
        if hint_opt.is_some() {
            let hint = hint_opt.unwrap();
            assert(hint < (N as u32));

            let needs_rewind_item = linked_items[i];
            assert(!needs_rewind_item.has_prev_leaf);
            let hinted_first_discarded_op = linked_items[hint];

            assert(!is_empty(needs_rewind_item));
            assert(!is_empty(hinted_first_discarded_op));

            let last_discarded_op = linked_items[needs_rewind_item.prev_index];
            let last_not_discarded_op = linked_items[hinted_first_discarded_op.prev_index];
            assert(!is_empty(last_discarded_op));
            assert(!is_empty(last_not_discarded_op));

            // We are talking about the same slot
            assert_eq(needs_rewind_item.op.slot, hinted_first_discarded_op.op.slot);

            // The hinted first discarded does happen before the last discarded op
            assert(hinted_first_discarded_op.op.counter < last_discarded_op.op.counter);
            // They are both in the same reverted segment
            assert(hinted_first_discarded_op.op.lifetime_end == last_discarded_op.op.lifetime_end);

            // The hinted first discarded is the left boundary of the reverted segment
            assert(last_not_discarded_op.op.counter > hinted_first_discarded_op.op.lifetime_end);
            // The needs rewind item is the right boundary of the reverted segment
            assert(needs_rewind_item.op.counter > last_discarded_op.op.lifetime_end);
            // Now that we have both boundaries, we can safely add the rewind item
            rewinds[i] = StorageLinkedItem {
                op: StorageOp {
                    counter: last_discarded_op.op.lifetime_end,
                    lifetime_end: last_not_discarded_op.op.lifetime_end,
                    is_write: true,
                    slot: needs_rewind_item.op.slot,
                    value: last_not_discarded_op.op.value,
                },
                prev_index: needs_rewind_item.prev_index,
                has_prev_leaf: false,
            };
            // Now the needs rewind item points to the rewind item 
            linked_items[i].prev_index = i + N;
        }
    }

    let mut all_linked_items = [StorageLinkedItem::default(); K];
    for i in 0..N {
        all_linked_items[i] = linked_items[i];
        all_linked_items[i + N] = rewinds[i];
    }

    all_linked_items
}

fn validate_storage_ops<N, K>(storage_ops: [StorageLinkedItem; K], initial_leaves: [StorageLeaf; N]) {
    for i in 0..K {
        let storage_op = storage_ops[i];
        if !is_empty(storage_op) {
            if storage_op.has_prev_leaf {
                let leaf = initial_leaves[storage_op.prev_index];
                assert(leaf.slot == storage_op.op.slot);
                if !storage_op.op.is_write {
                    assert_eq(leaf.value, storage_op.op.value);
                }
            } else {
                let prev_op = storage_ops[storage_op.prev_index];
                assert(prev_op.op.slot == storage_op.op.slot);
                assert(prev_op.op.counter < storage_op.op.counter);
                assert(prev_op.op.lifetime_end > storage_op.op.counter);
                if !storage_op.op.is_write {
                    assert_eq(prev_op.op.value, storage_op.op.value);
                }
            }
        }
    }
}

global LEN = 20;

fn main(
    storage_ops: [StorageOp; LEN],
    initial_leaves: [StorageLeaf; LEN],
    linked_hints: [(u32, bool); LEN],
    rewind_hints: [Option<u32>; LEN]
) {
    let linked_items = create_linked_linked_items(storage_ops, initial_leaves, linked_hints);
    let with_rewinds = add_rewind_to_linked_linked_items(linked_items, rewind_hints, [(); LEN * 2]);
    validate_storage_ops(with_rewinds, initial_leaves);
}
