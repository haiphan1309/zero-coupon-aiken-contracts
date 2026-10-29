//// Tests for `bid_limit/update_order`: updating and cancelling an order.

use bid_limit/bid_types
use bid_limit/fixture.{
  alice_vk, bid_amount, bid_skh, bob_vk, min_ada, out_ref, yield,
}
use bid_limit/update_order
use cardano/transaction.{Input, Output}
use daken/fixture/output_builder as ob

fn run(
  order_in_idx: Int,
  cont_ou_idx: Int,
  inputs: List<Input>,
  outputs: List<Output>,
  signers: List<ByteArray>,
) -> Bool {
  update_order.verify(
    bid_skh,
    out_ref(0),
    order_in_idx,
    cont_ou_idx,
    inputs,
    outputs,
    signers,
  )
}

fn order() -> List<Input> {
  [fixture.bid_in(0, alice_vk, yield, bid_amount)]
}

/// E1 — cancel: where the money goes once it leaves the script is the owner's
/// business.
test e1_cancel() {
  run(0, -1, order(), [], [alice_vk])
}

/// E2 — change the yield.
test e2_change_yield() {
  run(
    0,
    0,
    order(),
    [fixture.cont_out(alice_vk, yield + 500, bid_amount)],
    [alice_vk],
  )
}

/// E3 — adding more money to the order.
test e3_top_up() {
  run(
    0,
    0,
    order(),
    [fixture.cont_out(alice_vk, yield, bid_amount * 2)],
    [alice_vk],
  )
}

/// E4 — the owner's signature is missing.
test e4_no_signature() fail {
  run(0, -1, order(), [], [bob_vk])
}

/// E5 — somebody else's signature.
test e5_wrong_signer() fail {
  run(0, 0, order(), [fixture.cont_out(bob_vk, yield, bid_amount)], [bob_vk])
}

/// E6 — changing the owner within one transaction: cancel and re-create, do not
/// blur the two.
test e6_change_owner() fail {
  run(0, 0, order(), [fixture.cont_out(bob_vk, yield, bid_amount)], [alice_vk])
}

/// E7 — changing market. On the ask side this comes free because the PT sits in
/// the value; here it sits in the datum and has to be blocked, or one order
/// straddles two PTs.
test e7_change_market() fail {
  run(
    0,
    0,
    order(),
    [
      ob.new(fixture.order_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_amount)
        |> ob.add_inline_datum(
            bid_types.BidDatum {
              owner_vk: alice_vk,
              pt_asset: (fixture.pool_pid, fixture.pt_tn2()),
              offered_yield: yield,
              bid_amount,
            },
          ),
    ],
    [alice_vk],
  )
}

/// E8 — the remainder order is not at the script address.
test e8_continuation_leaves_script() fail {
  run(
    0,
    0,
    order(),
    [
      ob.new(fixture.wallet_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_amount)
        |> ob.add_inline_datum(fixture.datum_of(alice_vk, yield, bid_amount)),
    ],
    [alice_vk],
  )
}

/// E9 — a zero yield in the remainder order: the denominator falls to face
/// value and the order becomes meaningless.
test e9_zero_yield_continuation() fail {
  run(
    0,
    0,
    order(),
    [fixture.cont_out_of(alice_vk, 0, bid_amount, bid_amount, min_ada)],
    [alice_vk],
  )
}

/// E10 — `order_in_idx` points at an input other than the one being validated.
test e10_index_mismatch() fail {
  run(0, -1, [fixture.bid_in(9, alice_vk, yield, bid_amount)], [], [alice_vk])
}

/// E11 — the remainder order carries a reference script: `get_order_in`
/// requires `None`, so the order is unusable at the next fill and the owner is
/// left with nothing but cancelling.
test e11_continuation_has_reference_script() fail {
  run(
    0,
    0,
    order(),
    [
      ob.new(fixture.order_addr(alice_vk))
        |> ob.add_lovelace(min_ada)
        |> ob.add_asset(fixture.origin_pid, fixture.origin_tn, bid_amount)
        |> ob.add_inline_datum(fixture.datum_of(alice_vk, yield, bid_amount))
        |> ob.add_reference_script(fixture.pool_pid),
    ],
    [alice_vk],
  )
}
