pub fn is_empty<T>(item: T) -> bool where T: Default + Eq {
    item.eq(T::default())
}

// Routine which validates that all zero values of an array form a contiguous region at the end, i.e.,
// of the form: [*,*,*...,0,0,0,0] where any * is non-zero. Note that a full array of non-zero values is
// valid.
pub fn validate_array<T, N>(array: [T; N]) where T: Default + Eq {
    for i in 1..array.len() {
        let prev_is_empty = is_empty(array[i - 1]);
        let curr_is_empty = is_empty(array[i]);
        assert(!(prev_is_empty & !curr_is_empty), "invalid array");
    }
}

// Helper method to determine the number of non-zero/empty elements in a validated array (ie, validate_array(array) 
// should be true).
pub fn array_length<T, N>(array: [T; N]) -> Field where T: Default + Eq {
    array.fold(0, |acc, elem| acc + if is_empty(elem) { 0 } else { 1 })
}

global PLO: Field = 53438638232309528389504892708671455233;
global PHI: Field = 64323764613183177041862057485226039389;
global TWO_POW_128: Field = 0x100000000000000000000000000000000;

#[test]
fn check_plo_phi() {
    assert_eq(PLO + PHI * TWO_POW_128, 0);
}

unconstrained fn decompose_unsafe(x: Field) -> (Field, Field) {
    let x_bytes = x.to_le_bytes(32);

    let mut low: Field = 0;
    let mut high: Field = 0;

    let mut offset = 1;
    for i in 0..16 {
        low += (x_bytes[i] as Field) * offset;
        high += (x_bytes[i + 16] as Field) * offset;
        offset *= 256;
    }

    (low, high)
}

#[test]
fn test_decompose_unsafe() {
    assert_eq(decompose_unsafe(TWO_POW_128), (0, 1));
    assert_eq(decompose_unsafe(TWO_POW_128 + 0x1234567890), (0x1234567890, 1));
    assert_eq(decompose_unsafe(0x1234567890), (0x1234567890, 0));
}

unconstrained fn lt_bytes16_unsafe(x: Field, y: Field) -> bool {
    let x_bytes = x.to_le_bytes(16);
    let y_bytes = y.to_le_bytes(16);
    let mut x_is_lt = false;
    let mut done = false;
    for i in 0..16 {
        if (!done) {
            let x_byte = x_bytes[15 - i];
            let y_byte = y_bytes[15 - i];
            let bytes_match = x_byte == y_byte;
            if !bytes_match {
                x_is_lt = x_byte < y_byte;
                done = true;
            }
        }
    }
    x_is_lt
}

#[test]
fn test_lt_bytes16_unsafe() {
    assert(lt_bytes16_unsafe(0, 1));
    assert(lt_bytes16_unsafe(0, 0x100));
    assert(lt_bytes16_unsafe(0x100, TWO_POW_128 - 1));
    assert(!lt_bytes16_unsafe(0, TWO_POW_128));
}

unconstrained fn lte_bytes16_unsafe(x: Field, y: Field) -> bool {
    lt_bytes16_unsafe(x, y) | (x == y)
}

#[test]
fn test_lte_bytes16_unsafe() {
    assert(lte_bytes16_unsafe(0, 1));
    assert(lte_bytes16_unsafe(0, 0x100));
    assert(lte_bytes16_unsafe(0x100, TWO_POW_128 - 1));
    assert(!lte_bytes16_unsafe(0, TWO_POW_128));

    assert(lte_bytes16_unsafe(0, 0));
    assert(lte_bytes16_unsafe(0x100, 0x100));
    assert(lte_bytes16_unsafe(TWO_POW_128 - 1, TWO_POW_128 - 1));
    assert(lte_bytes16_unsafe(TWO_POW_128, TWO_POW_128));
}

pub fn decompose(x: Field) -> (Field, Field) {
    let (xlo, xhi) = decompose_unsafe(x);
    let borrow = lt_bytes16_unsafe(PLO, xlo);

    xlo.assert_max_bit_size(128);
    xhi.assert_max_bit_size(128);

    assert_eq(x, xlo + TWO_POW_128 * xhi);
    let rlo = PLO - xlo + (borrow as Field) * TWO_POW_128;
    let rhi = PHI - xhi - (borrow as Field);

    rlo.assert_max_bit_size(128);
    rhi.assert_max_bit_size(128);

    (xlo, xhi)
}

pub fn assert_gt(a: Field, b: Field) {
    let (alo, ahi) = decompose(a);
    let (blo, bhi) = decompose(b);

    let borrow = lte_bytes16_unsafe(alo, blo);

    let rlo = alo - blo - 1 + (borrow as Field) * TWO_POW_128;
    let rhi = ahi - bhi - (borrow as Field);

    rlo.assert_max_bit_size(128);
    rhi.assert_max_bit_size(128);
}

#[test]
fn test_assert_gt() {
    assert_gt(1, 0);
    assert_gt(0x100, 0);
    assert_gt((0 - 1), (0 - 2));
    assert_gt(TWO_POW_128, 0);
}

#[test(should_fail)]
fn test_assert_gt_should_fail_eq() {
    assert_gt(0, 0);
}

#[test(should_fail)]
fn test_assert_gt_should_fail_low_lt() {
    assert_gt(0, 0x100);
}

#[test(should_fail)]
fn test_assert_gt_should_fail_high_lt() {
    assert_gt(TWO_POW_128, TWO_POW_128 + 0x100);
}
