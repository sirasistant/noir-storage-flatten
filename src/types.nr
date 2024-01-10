use dep::std::default::Default;
use dep::std::cmp::Eq;

struct StorageOp {
    counter: u32,
    lifetime_end: u32,
    is_write: bool,
    slot: Field,
    value: Field,
}

impl StorageOp {
    pub fn new(slot: Field, value: Field, is_write: bool, counter: u32, lifetime_end: u32) -> Self {
        Self {
            counter: counter,
            lifetime_end: lifetime_end,
            is_write: is_write,
            slot: slot,
            value: value,
        }
    }

    pub fn read(slot: Field, value: Field, counter: u32, lifetime_end: u32) -> Self {
        StorageOp::new(slot, value, false, counter, lifetime_end)
    }

    pub fn write(slot: Field, value: Field, counter: u32, lifetime_end: u32) -> Self {
        StorageOp::new(slot, value, true, counter, lifetime_end)
    }
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

impl StorageLeaf {
    pub fn new(slot: Field, value: Field) -> Self {
        Self {
            slot: slot,
            value: value,
        }
    }
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
    rewind_target: Option<u32>
}

impl SortedStorageOp {
    pub fn new(op: StorageOp) -> Self {
        Self {
            op: op,
            rewind_target: Option::none(),
        }
    }

    pub fn rewind(slot: Field, value: Field, counter: u32, lifetime_end: u32, rewind_to: u32) -> Self {
        Self {
            op: StorageOp::write(slot, value, counter, lifetime_end),
            rewind_target: Option::some(rewind_to),
        }
    }
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
            rewind_target: Option::none(),
        }
    }
}

impl Eq for SortedStorageOp {
    fn eq(self, other: Self) -> bool {
        (self.op == other.op) & is_option_eq(self.rewind_target, other.rewind_target) 
    }
}
