//// Tests for the Update and Cancel branch.
////
//// This branch runs through no withdraw and reads no config: nobody else's
//// money moves, so the owner's signature is enough.

use ask_limit/fixture.{alice_vk, ask_skh, bob_vk, cont_out, order_in, out_ref}
use ask_limit/update_order
use cardano/assets
use cardano/transaction.{Output}

const pt = 1_000_000_000

/// B7 — change the yield from 15% to 14%, keeping the PT amount.
test b7_update_yield() {
  update_order.verify(
    ask_skh,
    out_ref(0),
    0,
    0,
    [order_in(0, alice_vk, 1_500, pt)],
    [cont_out(alice_vk, 1_400, pt)],
    [alice_vk],
  )
}

/// B7b — withdrawing some PT back to the wallet. The PT belongs to the owner,
/// so reducing the quantity is legitimate.
test b7b_update_reduces_pt() {
  update_order.verify(
    ask_skh,
    out_ref(0),
    0,
    0,
    [order_in(0, alice_vk, 1_500, pt)],
    [cont_out(alice_vk, 1_500, pt / 2)],
    [alice_vk],
  )
}

/// B8 — cancel: no remainder order, and where the PT goes is the owner's
/// business.
test b8_cancel() {
  update_order.verify(
    ask_skh,
    out_ref(0),
    0,
    -1,
    [order_in(0, alice_vk, 1_500, pt)],
    [],
    [alice_vk],
  )
}

/// A17 — updating an order without the owner's signature.
test a17_update_without_signature() fail {
  update_order.verify(
    ask_skh,
    out_ref(0),
    0,
    0,
    [order_in(0, alice_vk, 1_500, pt)],
    [cont_out(alice_vk, 1_400, pt)],
    [],
  )
}

/// A17b — cancelling an order with only somebody else's signature.
test a17b_cancel_signed_by_other() fail {
  update_order.verify(
    ask_skh,
    out_ref(0),
    0,
    -1,
    [order_in(0, alice_vk, 1_500, pt)],
    [],
    [bob_vk],
  )
}

/// A18 — changing the owner during an update. To transfer, cancel and
/// re-create.
test a18_update_changes_owner() fail {
  update_order.verify(
    ask_skh,
    out_ref(0),
    0,
    0,
    [order_in(0, alice_vk, 1_500, pt)],
    [cont_out(bob_vk, 1_500, pt)],
    [alice_vk],
  )
}

/// A19 — order_in_idx points at an input other than the one being spent.
test a19_index_points_elsewhere() fail {
  update_order.verify(
    ask_skh,
    out_ref(0),
    1,
    0,
    [order_in(0, alice_vk, 1_500, pt), order_in(1, bob_vk, 1_800, pt)],
    [cont_out(bob_vk, 1_400, pt)],
    [alice_vk, bob_vk],
  )
}

/// C — the remainder order withdraws all the PT, leaving only ADA.
///
/// It fails at `single_token_of`, not at a quantity check: a Cardano `Value`
/// never carries an entry of quantity 0. To withdraw everything, cancel the
/// order (b8).
test c_update_strips_all_pt() fail {
  update_order.verify(
    ask_skh,
    out_ref(0),
    0,
    0,
    [order_in(0, alice_vk, 1_500, pt)],
    [
      Output {
        ..cont_out(alice_vk, 1_500, pt),
        value: assets.from_lovelace(fixture.min_ada),
      },
    ],
    [alice_vk],
  )
}

/// C — the remainder order is sent to a wallet address instead of the script.
test c_update_sends_to_wallet() fail {
  update_order.verify(
    ask_skh,
    out_ref(0),
    0,
    0,
    [order_in(0, alice_vk, 1_500, pt)],
    [
      Output {
        ..cont_out(alice_vk, 1_500, pt),
        address: fixture.wallet_addr(alice_vk),
      },
    ],
    [alice_vk],
  )
}

/// C — the remainder order carries a non-positive yield.
test c_update_non_positive_yield() fail {
  update_order.verify(
    ask_skh,
    out_ref(0),
    0,
    0,
    [order_in(0, alice_vk, 1_500, pt)],
    [cont_out(alice_vk, 0, pt)],
    [alice_vk],
  )
}
