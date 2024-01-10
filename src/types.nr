use dep::std::default::Default;
use dep::std::cmp::Eq;

struct StorageOp {
    counter: u32,
    lifetime_end: u32,
    is_write: bool,
    slot: Field,
    value: Field,
}

impl Default for StorageOp {
    fn default() -> Self {
        Self {
            counter: 0,
            lifetime_end: 0,
            is_write: false,
            slot: 0,
            value: 0,
        }
    }
}

impl Eq for StorageOp {
    fn eq(self, other: Self) -> bool {
        (self.is_write == other.is_write) & (self.slot == other.slot) & (self.value == other.value) & (self.counter == other.counter) & (self.lifetime_end == other.lifetime_end)
    }
}

struct StorageLeaf {
    slot: Field,
    value: Field,
}

impl Default for StorageLeaf {
    fn default() -> Self {
        Self {
            slot: 0,
            value: 0,
        }
    }
}

impl Eq for StorageLeaf {
    fn eq(self, other: Self) -> bool {
        (self.slot == other.slot) & (self.value == other.value)
    }
}

struct StorageLinkedItem {
    op: StorageOp,
    prev_index: u32,
    has_prev_leaf: bool,
}

impl Default for StorageLinkedItem {
    fn default() -> Self {
        Self {
            op: StorageOp::default(),
            prev_index: 0,
            has_prev_leaf: false,
        }
    }
}

impl Eq for StorageLinkedItem {
    fn eq(self, other: Self) -> bool {
        (self.op == other.op) & (self.prev_index == other.prev_index) & (self.has_prev_leaf == other.has_prev_leaf)
    }
}
