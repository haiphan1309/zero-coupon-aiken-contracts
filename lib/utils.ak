use aiken/builtin
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Input, NoDatum, Output, InlineDatum}
use cardano/assets
use constants

pub fn get_pt_name(pool_id: AssetName) {
  bytearray.concat(constants.prefix_pt, pool_id)
}

pub fn validate_and_get_fee_val(
  fee_ou_idx: Int,
  outputs: List<Output>,
  expected_fee_addr: Address,
) {
  if fee_ou_idx < 0 {
    assets.zero
  } else {
    let Output { address: fee_addr, value: fee_val, datum, reference_script } =
      outputs
        |> tail_list_by_idx(fee_ou_idx)
        |> builtin.head_list
    expect fee_addr == expected_fee_addr
    expect reference_script == None
    expect datum == NoDatum
    fee_val
  }
}

pub fn tail_list_by_idx(self: List<a>, idx: Int) -> List<a> {
  if idx == 0 {
    self
  } else if idx < 3 {
    self
      |> builtin.tail_list
      |> tail_list_by_idx(idx - 1)
  } else if idx >= 10 {
    self
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> tail_list_by_idx(idx - 10)
  } else if idx >= 5 {
    self
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> tail_list_by_idx(idx - 5)
  } else {
    self
      |> builtin.tail_list
      |> builtin.tail_list
      |> builtin.tail_list
      |> tail_list_by_idx(idx - 3)
  }
}

pub fn get_datum_by_idx(
  inputs: List<Input>,
  pid: PolicyId,
  tn: AssetName,
  idx: Int,
) -> Data {
  let Input { output: Output { value, datum, .. }, .. } =
    inputs |> tail_list_by_idx(idx) |> builtin.head_list
  expect assets.quantity_of(value, pid, tn) == 1
  expect InlineDatum(datum) = datum
  datum
}
