use aiken/collection/dict.{to_pairs}
use aiken/collection/list.{all, filter as l_filter, length, reduce as l_reduce}
use aiken/collection/pairs.{insert_with_by_ascending_key}
use aiken/primitive/bytearray.{compare}
use cardano/address.{Address, PaymentCredential, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId, Value, tokens}
use cardano/transaction.{Output}

pub fn check_if_single_asset_burned(
  tx_mint: Value,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Bool {
  // Verify that, for a specific policy, only assets with a specific name are present in the transaction
  // And that their quantity is negative (i.e., they are being burned)
  expect [Pair(burned_asset_name, asset_quantity)] =
    tx_mint
      |> tokens(policy_id)
      |> to_pairs()

  and {
    (asset_name == burned_asset_name)?,
    (asset_quantity < 0)?,
  }
}

pub fn address2pcred_as_bytes(Address { payment_credential, .. }) -> ByteArray {
  when payment_credential is {
    VerificationKey(bytes) -> bytes
    Script(bytes) -> bytes
  }
}

pub fn find_outputs_by_payment_cred(
  outputs: List<Output>,
  search_payment_cred: PaymentCredential,
  invert: Bool,
) -> List<Output> {
  // Iterate over the list of outputs and select only those that belong to the address associated with `search_payment_cred`
  outputs
    |> l_filter(
        fn(
          Output {
            address: Address { payment_credential: out_payment_credential, .. },
            ..
          },
        ) {
          if invert {
            search_payment_cred != out_payment_credential
          } else {
            search_payment_cred == out_payment_credential
          }
        },
      )
}

pub fn validate_optimality(
  assets_quantity_list: List<Int>,
  optimal_amount: Int,
  start_sum: Int,
  treasury_consumed: Int,
) -> (Bool, Int) {
  // We need to check the optimality of the outputs.
  // Iterate through them, accumulating their value.
  // At each iteration, check whether the accumulated sum satisfies the condition and whether there are remaining elements:
  // - either the sum is satisfied and no elements are left,
  // - or elements remain and the sum is not yet satisfied.
  when assets_quantity_list is {
    [] -> fail
    [x, ..xs] -> {
      let length_xs = length(xs)
      let start_sum = start_sum + x
      if start_sum > optimal_amount && length_xs == 0 {
        (True, treasury_consumed)
      } else if start_sum == optimal_amount && length_xs == 0 {
        (True, treasury_consumed + 1)
      } else if start_sum < optimal_amount && length_xs != 0 {
        validate_optimality(
          xs,
          optimal_amount,
          start_sum,
          treasury_consumed + 1,
        )
      } else {
        (False, -1)
      }
    }
  }
}

pub fn aggregate_payouts(
  payouts: List<Pair<Address, Int>>,
) -> List<Pair<Address, Int>> {
  // Since there may be multiple payouts to the same address, they must be aggregated into a more compact form by merging entries with matching addresses
  payouts
    |> l_reduce(
        [],
        fn(result, Pair(address, amount)) {
          result
            |> insert_with_by_ascending_key(
                key: address,
                value: amount,
                compare: fn(addr1, addr2) {
                  compare(
                    address2pcred_as_bytes(addr1),
                    address2pcred_as_bytes(addr2),
                  )
                },
                with: fn(x, y) { x + y },
              )
        },
      )
}

pub fn verify_payouts(
  real_po: List<Pair<Address, Int>>,
  expected_po: List<Pair<Address, Int>>,
  possible_delta: Int,
  fix_applied: Bool,
) -> Bool {
  // Verify that real payouts correspond to the expected payouts
  when [real_po, expected_po] is {
    [[], []] -> True
    [
      [Pair(real_po_addr, real_po_amount), ..rest_real_po],
      [Pair(expected_po_addr, expected_po_amount), ..rest_expected_po],
    ] -> {
      // Addresses must match
      expect real_po_addr == expected_po_addr

      // Then calculate the delta between real and expected payouts
      let delta = real_po_amount - expected_po_amount

      // It is ok when delta is 0, and acceptable if it equals `possible_delta` once
      if delta == 0 || delta == possible_delta && !fix_applied {
        // Valid real/expected payout delta, next step
        verify_payouts(
          rest_real_po,
          rest_expected_po,
          possible_delta,
          fix_applied || delta == possible_delta,
        )
      } else {
        // Unexpected delta, stop execution
        False
      }
    }
    _ -> fail @"Expected and real payouts must have the same length"
  }
}

pub fn real_all(list: List<a>, predicate: fn(a) -> Bool) -> Bool {
  when list is {
    [] -> False
    _ -> all(list, predicate)
  }
}
