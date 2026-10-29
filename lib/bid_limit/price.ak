use ask_limit/price as ask_price
use constants
use daken/math
use daken/types.{Basis} as daken_types
use env

// Duration left at the moment of the transaction. Uses tx_START, the lower
// bound, and NOT tx_end.
//
// The rule is not "always use tx_end" but "take the bound that is unfavourable
// to the taker". On the ask side the taker is the buyer; they pick the validity
// range, so anchoring to tx_end stops them widening the window into the past to
// buy cheaply. Here the taker is the SELLER: price falls as duration grows, so
// tx_end would give the smallest duration and the largest price — the taker
// receiving the most and the bidder paying the most. Anchoring to tx_start
// takes that to zero, because tx_start cannot be pushed later than now, and
// pushing it earlier only grows the duration and lowers the price, which costs
// the taker.
pub fn duration_of(supply_maturity: Int, tx_start: Int) -> Int {
  let d = supply_maturity - tx_start
  if d > 0 {
    d
  } else {
    0
  }
}

// price = FLOOR( pt_bought * basis * YEAR / (basis * YEAR + offered_yield * duration) )
//
// FLOOR because the resting order is the BUYER: rounding down means they pay
// less. The opposite direction to ask_limit/price.price_of, where the resting
// order is the seller.
//
// YEAR is env.year_in_ms — the environment's year constant, not the real year.
pub fn price_floor_of(
  pt_bought: Int,
  offered_yield: Basis,
  duration: Int,
) -> Int {
  let num = pt_bought * constants.basis * env.year_in_ms
  let den = constants.basis * env.year_in_ms + offered_yield * duration
  num / den
}

// The bidder's fee, taken on cfg.buyer_fee.
pub fn maker_fee_of(price: Int, rate: Basis) -> Int {
  // FLOOR: the remainder goes to whoever placed the bid.
  price * rate / constants.basis
}

// The taker's fee, the seller's, taken on cfg.seller_fee.
pub fn taker_fee_of(price: Int, rate: Basis) -> Int {
  // CEIL: the remainder goes to the protocol.
  math.ceiling_div(price * rate, constants.basis)
}

// ---------------------------------------------------------------- tests

/// Duration is anchored to tx_start, so moving tx_start earlier only makes the
/// duration LARGER.
test duration_anchors_on_start() {
  and {
    duration_of(1_000, 400) == 600,
    duration_of(1_000, 300) == 700,
    duration_of(1_000, 1_000) == 0,
    duration_of(1_000, 1_400) == 0,
  }
}

// Zero duration means PT trades at face value.
test price_at_maturity_is_par() {
  price_floor_of(1_000_000, 2_000, 0) == 1_000_000
}

// A zero yield discounts nothing, however much duration is left.
test price_with_zero_yield_is_par() {
  price_floor_of(1_000_000, 0, env.year_in_ms) == 1_000_000
}

// Exactly one env year left, 20% yield ==> 1/(1+0.2)
test price_full_year_at_20_percent() {
  price_floor_of(1_200_000, 2_000, env.year_in_ms) == 1_000_000
}

/// FLOOR rounds DOWN: 1 PT at a high yield comes to 0. That is why
/// `sell.verify` has to check `cash_out > 0` and not just `pt_bought > 0`.
test price_can_floor_to_zero() {
  price_floor_of(1, 9_999, env.year_in_ms) == 0
}

const day_in_ms_compressed = 360_000

const example_duration = 90 * day_in_ms_compressed

/// Rounding direction made visible: on the same inputs the two sides differ by
/// exactly one unit. This is the only test that imports both price modules, and
/// it exists to prove they are NOT interchangeable.
test bid_floors_where_ask_ceils() {
  let pt = 1_000_000_000
  let y = 1_500
  and {
    ask_price.price_of(pt, y, example_duration) == 964_332_893,
    price_floor_of(pt, y, example_duration) == 964_332_892,
  }
}

/// Fees flip direction against ask: FLOOR for the maker, CEIL for the taker.
test maker_floors_taker_ceils() {
  and {
    maker_fee_of(482_166_446, 20) == 964_332,
    taker_fee_of(482_166_446, 10) == 482_167,
  }
}

test zero_fee_rate_costs_nothing() {
  and {
    maker_fee_of(482_166_446, 0) == 0,
    taker_fee_of(482_166_446, 0) == 0,
  }
}

/// Conservation: money leaving the order UTxO = what the taker receives + all fees.
test cash_out_splits_exactly() {
  let p = price_floor_of(500_000_000, 1_500, example_duration)
  let b = maker_fee_of(p, 20)
  let s = taker_fee_of(p, 10)
  let cash_out = p + b
  let net = p - s
  and {
    p == 482_166_446,
    cash_out == 483_130_778,
    net == 481_684_279,
    net + ( s + b ) == cash_out,
  }
}

/// FLOOR is subadditive, so slicing one fill up leaves the taker with LESS, not
/// more. The same role CEIL's superadditivity plays on the ask side.
test floor_is_subadditive() {
  let d = env.year_in_ms / 4
  let y = 1_500
  let whole = price_floor_of(1_000_000, y, d)
  let part_a = price_floor_of(400_000, y, d)
  let part_b = price_floor_of(600_000, y, d)
  part_a + part_b <= whole
}

/// Pins down the assumption every price formula rests on.
test env_year_is_365_compressed_days() {
  env.year_in_ms == 365 * day_in_ms_compressed
}
