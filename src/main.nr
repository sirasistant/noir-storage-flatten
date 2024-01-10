mod types;
mod utils;

use utils::{is_empty, array_length, validate_array};
use types::{StorageOp, StorageLeaf, SortedStorageOp};

pub fn validate_sorted_transcript<N, K>(
    sorted_transcript: [StorageOp; N],
    sorted_transcript_with_rewinds: [SortedStorageOp; K],
    leaves: [StorageLeaf; N]
) {
    assert(
        (K as u32) >= (N as u32), "We need at least the same space for rewinds than the original transcript"
    );
    // Ensure that the sorted_transcript is sorted by slot and counter
    validate_array(sorted_transcript);
    let sorted_transcript_length = array_length(sorted_transcript);
    for i in 1..sorted_transcript.len() {
        if (i as u32) < (sorted_transcript_length as u32) {
            let prev = sorted_transcript[i - 1];
            let curr = sorted_transcript[i];
            if prev.slot == curr.slot {
                assert(prev.counter < curr.counter, "Same slot, counter must be increasing");
            } else {
                assert(dep::std::eddsa::lt_bytes32(prev.slot, curr.slot), "Slot must be increasing");
            }
        }
    }

    // Ensure that the initial leaves are sorted by slot.
    // This ensures that there are no duplicated leaves for a given slot.
    validate_array(leaves);
    let leaves_length = array_length(leaves);
    for i in 1..leaves.len() {
        if (i as u32) < (leaves_length as u32) {
            assert(
                dep::std::eddsa::lt_bytes32(leaves[i - 1].slot, leaves[i].slot), "Slot must be increasing"
            );
        }
    }

    let mut last_slot = 0;
    let mut next_leaf = 0;
    let mut next_op = 0;

    for i in 0..sorted_transcript_with_rewinds.len() {
        let item_being_validated = sorted_transcript_with_rewinds[i];
        if !is_empty(item_being_validated) {
            if item_being_validated.op.slot != last_slot {
                assert(item_being_validated.rewind_target.is_none(), "New slot, so we cannot rewinding");

                let original_op = sorted_transcript[next_op];
                assert(original_op.eq(item_being_validated.op), "Original op must match");
                next_op += 1;

                // We are in a new slot, so we know that we are pointing against a leaf
                let leaf = leaves[next_leaf];
                assert(leaf.slot == item_being_validated.op.slot, "Leaf slot must match");
                next_leaf += 1;
                if !item_being_validated.op.is_write {
                    assert_eq(leaf.value, item_being_validated.op.value, "Leaf value must match");
                }
            } else {
                // Same slot, new counter
                // Noir complains about the index being out of bounds even after an assert that it won't, so wrap it in a conditional
                let idx = if i != 0 {
                    i - 1
                } else {
                    assert(false, "First item must change slot");
                    0
                };
                let prev_item = sorted_transcript_with_rewinds[idx];
                if item_being_validated.rewind_target.is_none() {
                    // Base case, we are not rewinding
                    let original_op = sorted_transcript[next_op];
                    assert(original_op.eq(item_being_validated.op), "Original op must match");
                    next_op += 1;

                    if !item_being_validated.op.is_write {
                        // The previous op must live long enough
                        assert(
                            prev_item.op.lifetime_end > item_being_validated.op.counter, "Previous op must live long enough"
                        );
                        assert_eq(
                            prev_item.op.value, item_being_validated.op.value, "Previous op value must match"
                        );
                    }
                } else {
                    // Rewind!!!
                    assert(
                        prev_item.op.lifetime_end < item_being_validated.op.lifetime_end, "The previous op must revert in a more nested segment than ours"
                    );
                    let last_reverted_op = prev_item.op;

                    // Lets validate the hint
                    let hinted_first_reverted_op_index = item_being_validated.rewind_target.unwrap();
                    assert(hinted_first_reverted_op_index < (i as u32), "Hinted index must be valid");
                    let hinted_first_reverted_op = sorted_transcript_with_rewinds[hinted_first_reverted_op_index].op;
                    assert(
                        hinted_first_reverted_op.slot == item_being_validated.op.slot, "Hinted op must be in the same slot"
                    );

                    assert(
                        hinted_first_reverted_op.lifetime_end == last_reverted_op.lifetime_end, "The first reverted op must be in the same reverted segment"
                    );
                    assert(
                        hinted_first_reverted_op.counter <= last_reverted_op.counter, "The first reverted op must happen before the last reverted op"
                    );

                    let last_not_reverted_op = sorted_transcript_with_rewinds[hinted_first_reverted_op_index - 1].op;
                    assert(
                        last_not_reverted_op.slot == item_being_validated.op.slot, "Last not reverted op must be in the same slot"
                    );
                    assert(
                        last_not_reverted_op.lifetime_end > hinted_first_reverted_op.lifetime_end, "The previous op before the first reverted op must be out of the reverted segment"
                    );

                    // Let's validate the rewind then
                    assert(
                        item_being_validated.op.counter == last_reverted_op.lifetime_end, "Rewind must just after the reverted segment"
                    );
                    assert(
                        item_being_validated.op.lifetime_end == last_not_reverted_op.lifetime_end, "Rewind must live the same as the last not reverted op"
                    );
                    assert(item_being_validated.op.is_write, "Rewind must be a write");
                    assert_eq(
                        item_being_validated.op.value, last_not_reverted_op.value, "Rewind value must match"
                    );
                }
            }

            last_slot = item_being_validated.op.slot;
        }
    }
    assert_eq(next_op, sorted_transcript_length, "All original ops must be consumed");
    assert_eq(next_leaf, leaves_length, "All initial leaves must be consumed");
}

global LENGTH = 100;

fn main(
    sorted_transcript: [StorageOp; LENGTH],
    sorted_transcript_with_rewinds: [SortedStorageOp; 2*LENGTH],
    leaves: [StorageLeaf; LENGTH]
) {
    validate_sorted_transcript(sorted_transcript, sorted_transcript_with_rewinds, leaves);
}

mod tests {
    use crate::validate_sorted_transcript;
    use crate::utils::{is_empty, array_length, validate_array};
    use crate::types::{StorageOp, StorageLeaf, SortedStorageOp};

    global INF = 4294967295;

    #[test]
    fn basic_validation() {
        let slot = 27;
        let sorted_transcript = [StorageOp::read(slot, 100, 0, INF)];
        let with_rewinds = sorted_transcript.map(|op: StorageOp| SortedStorageOp::new(op));
        let leaves = [StorageLeaf::new(slot, 100)];

        validate_sorted_transcript(sorted_transcript, with_rewinds, leaves);
    }

    #[test]
    fn write_then_read_validation() {
        let slot = 27;
        let sorted_transcript = [StorageOp::write(slot, 120, 0, INF), StorageOp::read(slot, 120, 1, INF)];
        let with_rewinds = sorted_transcript.map(|op: StorageOp| SortedStorageOp::new(op));
        let leaves = [StorageLeaf::new(slot, 10), StorageLeaf::default()];

        validate_sorted_transcript(sorted_transcript, with_rewinds, leaves);
    }

    // This has the following call graph:
    // | 1-INF/w
    // |
    // ----------
    //          | 10-15/w
    //          |
    // ----------
    // | 
    // ----------
    //          | 20-25/w
    //          |
    // ----------
    // | 30-INF/r
    //
    #[test]
    fn simple_rewind_test() {
        let slot = 27;
        let sorted_transcript = [
            StorageOp::write(slot, 100, 1, INF),
            StorageOp::write(slot, 101, 10, 15),
            StorageOp::write(slot, 102, 20, 25),
            StorageOp::read(slot, 100, 30, INF)
        ];

        let with_rewinds = [
            SortedStorageOp::new(sorted_transcript[0]),
            SortedStorageOp::new(sorted_transcript[1]),
            SortedStorageOp::rewind(slot, 100, 15, INF, 1),
            SortedStorageOp::new(sorted_transcript[2]),
            SortedStorageOp::rewind(slot, 100, 25, INF, 3),
            SortedStorageOp::new(sorted_transcript[3])
        ];

        let mut leaves = sorted_transcript.map(|_op| StorageLeaf::default());
        leaves[0] = StorageLeaf::new(slot, 10);

        validate_sorted_transcript(sorted_transcript, with_rewinds, leaves);
    }

    // This has the following call graph:
    // | 1-INF/w
    // |
    // ----------
    //          | 10-25/w
    //          |
    //          ----------
    //                   | 15-20/w
    //                   |
    // ┌------------------
    // | 30-INF/r
    //
    #[test]
    fn rewind_nested_writes() {
        let slot = 27;
        let sorted_transcript = [
            StorageOp::write(slot, 100, 0, INF),
            StorageOp::write(slot, 101, 10, 25),
            StorageOp::write(slot, 102, 15, 20),
            StorageOp::read(slot, 100, 30, INF)
        ];

        let with_rewinds = [
            SortedStorageOp::new(sorted_transcript[0]),
            SortedStorageOp::new(sorted_transcript[1]),
            SortedStorageOp::new(sorted_transcript[2]),
            SortedStorageOp::rewind(slot, 101, 20, 25, 2),
            SortedStorageOp::rewind(slot, 100, 25, INF, 1),
            SortedStorageOp::new(sorted_transcript[3])
        ];

        let mut leaves = sorted_transcript.map(|_op| StorageLeaf::default());
        leaves[0] = StorageLeaf::new(slot, 10);

        validate_sorted_transcript(sorted_transcript, with_rewinds, leaves);
    }
}
