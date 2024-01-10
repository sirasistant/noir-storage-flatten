mod types;
mod utils;

use utils::{is_empty, array_length, validate_array};
use types::{StorageOp, StorageLeaf, SortedStorageOp};

global LEN = 100;

fn main(
    sorted_transcript: [StorageOp; LEN],
    sorted_transcript_with_rewinds: [SortedStorageOp; 2*LEN],
    initial_leaves: [StorageLeaf; LEN]
) {
    // Ensure that the sorted_transcript is sorted by slot and counter
    validate_array(sorted_transcript);
    let sorted_transcript_length = array_length(sorted_transcript);
    for i in 1..LEN {
        if (i as u32) < (sorted_transcript_length as u32) {
            let prev = sorted_transcript[i - 1];
            let curr = sorted_transcript[i];
            if prev.slot == curr.slot {
                assert(prev.counter < curr.counter);
            } else {
                assert(dep::std::eddsa::lt_bytes32(prev.slot, curr.slot));
            }
        }
    }

    // Ensure that the initial leaves are sorted by slot.
    // This ensures that there are no duplicated leaves for a given slot.
    validate_array(initial_leaves);
    let initial_leaves_length = array_length(initial_leaves);
    for i in 1..LEN {
        if (i as u32) < (initial_leaves_length as u32) {
            assert(dep::std::eddsa::lt_bytes32(initial_leaves[i - 1].slot, initial_leaves[i].slot));
        }
    }

    let mut last_slot = 0;
    let mut next_leaf = 0;
    let mut next_op = 0;

    for i in 0..sorted_transcript_with_rewinds.len() {
        let item_being_validated = sorted_transcript_with_rewinds[i];
        if !is_empty(item_being_validated) {
            if item_being_validated.op.slot != last_slot {
                // We are in a new slot, so we cannot be rewinding
                assert(item_being_validated.is_rewind.is_none());

                let original_op = sorted_transcript[next_op];
                assert(original_op.eq(item_being_validated.op));
                next_op += 1;

                // We are in a new slot, so we know that we are pointing against a leaf
                let leaf = initial_leaves[next_leaf];
                assert(leaf.slot == item_being_validated.op.slot);
                next_leaf += 1;
                if !item_being_validated.op.is_write {
                    assert_eq(leaf.value, item_being_validated.op.value);
                }
            } else {
                // Same slot, new counter
                let idx = if i == 0 { 0 } else { i - 1 };
                let prev_item = sorted_transcript_with_rewinds[idx];
                if item_being_validated.is_rewind.is_none() {
                    // Base case, we are not rewinding
                    let original_op = sorted_transcript[next_op];
                    assert(original_op.eq(item_being_validated.op));
                    next_op += 1;

                    if !item_being_validated.op.is_write {
                        // The previous op must live long enough
                        assert(prev_item.op.lifetime_end > item_being_validated.op.counter);
                        assert_eq(prev_item.op.value, item_being_validated.op.value);
                    }
                } else {
                    // Rewind!!!
                    // We only rewind if the previous op is reverted
                    assert(prev_item.op.lifetime_end < item_being_validated.op.counter);
                    // The previous op must revert in a more nested segment than ours
                    assert(prev_item.op.lifetime_end < item_being_validated.op.lifetime_end);
                    let last_reverted_op = prev_item.op;

                    // Lets validate the hint
                    let hinted_first_reverted_op_index = item_being_validated.is_rewind.unwrap();
                    assert(hinted_first_reverted_op_index < (i as u32));
                    let hinted_first_reverted_op = sorted_transcript_with_rewinds[hinted_first_reverted_op_index].op;
                    assert(hinted_first_reverted_op.slot == item_being_validated.op.slot);

                    // The first reverted op must be in the same reverted segment
                    assert(hinted_first_reverted_op.lifetime_end == last_reverted_op.lifetime_end);
                    // The first reverted op must happen before the last reverted op
                    assert(hinted_first_reverted_op.counter <= last_reverted_op.counter);

                    let last_not_reverted_op = sorted_transcript_with_rewinds[hinted_first_reverted_op_index - 1].op;
                    assert(last_not_reverted_op.slot == item_being_validated.op.slot);
                    // The previous op before the first reverted op must be out of the reverted segment
                    assert(last_not_reverted_op.lifetime_end > hinted_first_reverted_op.lifetime_end);

                    // Let's validate the rewind then
                    assert(item_being_validated.op.counter == last_reverted_op.lifetime_end);
                    assert(item_being_validated.op.lifetime_end == last_not_reverted_op.lifetime_end);
                    assert(item_being_validated.op.is_write);
                    assert_eq(item_being_validated.op.value, last_not_reverted_op.value);
                }
            }

            last_slot = item_being_validated.op.slot;
        }
    }
    assert_eq(next_op, sorted_transcript_length, "All original ops must be consumed");
}
