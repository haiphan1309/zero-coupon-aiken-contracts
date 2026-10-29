use constants
use daken/math
use daken/types.{Basis} as daken_types
use env

// The fee ceiling is hard-coded rather than read from config. Config is mutable
// and whoever holds the license NFT can change it at any time; price is computed
// with the config read at Buy time, so one change is retroactive across every
// resting order.
pub const max_fee_rate: Basis = 500

// Duration left at the moment of the transaction. Uses tx_end, the upper bound,
// and not tx_start: the buyer picks the validity range, and an earlier tx_start
// would mean a longer duration and a lower price. Taking tx_end makes that free
// discount disappear.
pub fn duration_of(supply_maturity: Int, tx_end: Int) -> Int {
  let d = supply_maturity - tx_end
  if d > 0 {
    d
  } else {
    0
  }
}

// price = CEIL( pt_sold * basis * YEAR / (basis * YEAR + requested_yield * duration) )
//
// CEIL because the taker is the buyer: rounding up favours the seller, and the
// validator checks `>=`, so an off-chain figure one unit short fails the whole
// transaction.
//
// YEAR is env.year_in_ms — the environment's year constant, not the real year
// in constants.year_in_ms. On a compressed environment (one day = six minutes)
// the two differ by a factor of 240.
pub fn price_of(pt_sold: Int, requested_yield: Basis, duration: Int) -> Int {
  let num = pt_sold * constants.basis * env.year_in_ms
  let den = constants.basis * env.year_in_ms + requested_yield * duration
  math.ceiling_div(num, den)
}

pub fn seller_fee_of(price: Int, rate: Basis) -> Int {
  // FLOOR: the remainder goes to the seller.
  price * rate / constants.basis
}

pub fn buyer_fee_of(price: Int, rate: Basis) -> Int {
  // CEIL: the remainder goes to the protocol.
  math.ceiling_div(price * rate, constants.basis)
}

// ---------------------------------------------------------------- tests

/// Pins down the rounding direction of `daken/math.ceiling_div`, zero numerator
/// included.
test ceiling_div_rounds_up() {
  and {
    math.ceiling_div(10, 5) == 2,
    math.ceiling_div(11, 5) == 3,
    math.ceiling_div(14, 5) == 3,
    math.ceiling_div(0, 5) == 0,
  }
}

test duration_is_zero_after_maturity() {
  and {
    duration_of(1_000, 400) == 600,
    duration_of(1_000, 1_000) == 0,
    duration_of(1_000, 1_400) == 0,
  }
}

// Zero duration means PT trades at face value.
test price_at_maturity_is_par() {
  price_of(1_000_000, 2_000, 0) == 1_000_000
}

// A zero yield discounts nothing, however much duration is left.
test price_with_zero_yield_is_par() {
  price_of(1_000_000, 0, env.year_in_ms) == 1_000_000
}

// Exactly one env year left, 20% yield ==> 1/(1+0.2)
test price_full_year_at_20_percent() {
  price_of(1_200_000, 2_000, env.year_in_ms) == 1_000_000
}

// Rounding up: 1 PT at any positive yield always comes to 1, never 0.
test price_never_rounds_to_zero() {
  price_of(1, 9_999, env.year_in_ms) == 1
}

// CEIL is superadditive: splitting one fill into several smaller ones always
// costs the same or more, so there is no incentive to slice a fill up and
// shave the seller.
test ceil_is_superadditive() {
  let d = env.year_in_ms / 4
  let y = 1_500
  let whole = price_of(1_000_000, y, d)
  let part_a = price_of(400_000, y, d)
  let part_b = price_of(600_000, y, d)
  part_a + part_b >= whole
}

test seller_fee_floors_buyer_fee_ceils() {
  and {
    // 964_332_893 * 10 / 10_000 = 964_332.893
    seller_fee_of(964_332_893, 10) == 964_332,
    // 964_332_893 * 20 / 10_000 = 1_928_665.786
    buyer_fee_of(964_332_893, 20) == 1_928_666,
  }
}

test zero_fee_rate_costs_nothing() {
  and {
    seller_fee_of(964_332_893, 0) == 0,
    buyer_fee_of(964_332_893, 0) == 0,
  }
}

// One "day" on Preview's compressed calendar. The contract's whole time scale
// follows this number, not a real day.
const day_in_ms_compressed = 360_000

// Pins down the assumption every price formula rests on. If daken's epoch
// config ever changes, this test goes red at once, instead of every trade
// quietly pricing wrong.
test env_year_is_365_compressed_days() {
  env.year_in_ms == 365 * day_in_ms_compressed
}

// A worked example: a pool with "90 days" left on the compressed scale, which
// is 9 real hours. Fees run at 10 bp for the seller and 20 bp for the buyer.
const example_duration = 90 * day_in_ms_compressed

test example_alice_full_fill() {
  let p = price_of(1_000_000_000, 1_500, example_duration)
  and {
    p == 964_332_893,
    seller_fee_of(p, 10) == 964_332,
    buyer_fee_of(p, 20) == 1_928_666,
    p - seller_fee_of(p, 10) == 963_368_561,
  }
}

test example_bob_partial_fill() {
  let p = price_of(200_000_000, 1_800, example_duration)
  and {
    p == 191_500_525,
    seller_fee_of(p, 10) == 191_500,
    buyer_fee_of(p, 20) == 383_002,
    p - seller_fee_of(p, 10) == 191_309_025,
  }
}

// A higher yield means a lower price. That is why the book is ordered by
// ascending yield, cheapest for the buyer first.
test higher_yield_is_cheaper() {
  price_of(1_000_000_000, 1_800, example_duration) < price_of(
    1_000_000_000,
    1_500,
    example_duration,
  )
}
