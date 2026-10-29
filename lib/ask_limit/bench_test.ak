//// Ex-unit benchmark against the number of orders per transaction.
////
//// A Buy runs the spend branch N times plus withdraw once, and every spend
//// redeemer repeats the whole fill list, so cost does not grow linearly in N.
////
//// The figures `aiken check` prints are higher than a real transaction, as
//// they include the fixture's own cost. Use the difference between adjacent N.
//// Per-transaction ceiling on Cardano: mem 14,000,000, cpu 10,000,000,000.

use aiken/collection/list
use ask_limit/ask_types.{AskLimitAction, AskLimitConfig, Buy, BuyMulti, Fill}
use ask_limit/fixture.{
  alice_vk, ask_skh, cfg_pid, cfg_tn, config, config_ref, fee_out, order_in,
  out_ref, payout_out, pool_ref, supply_maturity,
}
use cardano/address.{Script}
use daken/fixture/tx_builder as tb
use sc/sc_ask_limit

const pt_per_order = 1_000_000_000

const price_one = 964_332_893

const s_fee_one = 964_332

const b_fee_one = 1_928_666

fn measure(n: Int) -> Bool {
  let idxs = list.range(0, n - 1)
  let inputs =
    list.map(idxs, fn(i) { order_in(i, alice_vk, 1_500, pt_per_order) })
  let refs = [pool_ref(0, supply_maturity()), config_ref(1, config())]
  let fills =
    list.map(
      idxs,
      fn(i) { Fill { order_in_idx: i, owner_ou_idx: i, cont_ou_idx: -1 } },
    )
  let payouts =
    list.map(
      idxs,
      fn(_i) { payout_out(alice_vk, price_one - s_fee_one, fixture.min_ada) },
    )
  let outputs = list.concat(payouts, [fee_out(( s_fee_one + b_fee_one ) * n)])
  let action =
    AskLimitAction {
      indexers: BuyMulti([(0, fills)]),
      order_in_idx: 0,
      config_ref_idx: 1,
      fee_ou_idx: n,
    }
  let tx =
    fixture.mk_tx(inputs, refs, outputs, [])
      |> tb.add_zero_withdrawal_script(ask_skh, action)
  let cfg = AskLimitConfig { config_nft: (cfg_pid, cfg_tn) }
  and {
    sc_ask_limit.withdraw(cfg, action, Script(ask_skh), tx),
    list.all(
      idxs,
      fn(i) {
        sc_ask_limit.spend(
          AskLimitAction {
            indexers: Buy,
            order_in_idx: i,
            config_ref_idx: 0,
            fee_ou_idx: 0,
          },
          out_ref(i),
          tx,
        )
      },
    ),
  }
}

test bench_n1() {
  measure(1)
}

test bench_n2() {
  measure(2)
}

test bench_n3() {
  measure(3)
}

test bench_n4() {
  measure(4)
}

test bench_n5() {
  measure(5)
}

test bench_n6() {
  measure(6)
}
