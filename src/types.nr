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

struct SortedStorageOp {
    op: StorageOp,
    is_rewind: Option<u32>
}

fn is_option_eq<T>(a: Option<T>, b: Option<T>) -> bool where T: Eq {
    if a.is_some() & b.is_some() {
        a.unwrap().eq(b.unwrap())
    } else if a.is_none() & b.is_none() {
        true
    } else {
        false
    }
}

impl Default for SortedStorageOp {
    fn default() -> Self {
        Self {
            op: StorageOp::default(),
            is_rewind: Option::none(),
        }
    }
}

impl Eq for SortedStorageOp {
    fn eq(self, other: Self) -> bool {
        (self.op == other.op) & is_option_eq(self.is_rewind, other.is_rewind) 
    }
}
