////////////////////
////////////////////

use aiken/collection/dict.{filter as d_filter, to_pairs, values}
use aiken/collection/list.{
  all, any, difference, filter as l_filter, has, length, map as l_map,
  map2 as l_map2, reduce as l_reduce, sort,
}
use aiken/collection/pairs.{insert_with_by_ascending_key, keys}
use aiken/interval.{is_entirely_after}
use aiken/primitive/bytearray.{compare, starts_with}
use aiken/primitive/int
use cardano/address.{Address, PaymentCredential, Script, VerificationKey}
use cardano/assets.{
  AssetName, PolicyId, Value, flatten, is_zero, lovelace_of, quantity_of,
  reduce as v_reduce, tokens,
}
use cardano/transaction.{
  Input, Output, OutputReference, Transaction, find_input, find_script_outputs,
}
use config.{
  burn_nft_name, burn_nft_pid, contract_treasury_base_quantity,
  contract_treasury_lovelace, contract_treasury_marker_name, n2a_change_rate,
  owner_key_hash, payout_asset_name, payout_asset_pid, start_change_time,
  unlock_unclaimed_assets_time,
}

pub type Action {
  Bootstrap
  Exchange
  Recall
}

fn check_if_single_asset_burned(
  tx_mint: Value,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Bool {
  expect [Pair(burned_asset_name, asset_quantity)] =
    tx_mint
      |> tokens(policy_id)
      |> to_pairs()

  and {
    (asset_name == burned_asset_name)?,
    (asset_quantity < 0)?,
  }
}

fn address2pcred_as_bytes(Address { payment_credential, .. }) -> ByteArray {
  when payment_credential is {
    VerificationKey(bytes) -> bytes
    Script(bytes) -> bytes
  }
}

fn to_outputs(inputs: List<Input>) -> List<Output> {
  inputs
    |> l_map(fn(Input { output, .. }) { output })
}

fn find_outputs_by_payment_cred(
  outputs: List<Output>,
  search_payment_cred: PaymentCredential,
  invert: Bool,
) -> List<Output> {
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

fn validate_optimality(
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

fn aggregate_payouts(
  payouts: List<Pair<Address, Int>>,
) -> List<Pair<Address, Int>> {
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

fn verify_payouts(
  real_po: List<Pair<Address, Int>>,
  expected_po: List<Pair<Address, Int>>,
  possible_delta: Int,
  fix_applied: Bool,
) -> Bool {
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

fn real_all(list: List<a>, predicate: fn(a) -> Bool) -> Bool {
  when list is {
    [] -> False
    _ -> all(list, predicate)
  }
}

validator empowa_swap {
  spend(_d, redeemer: Action, contract_utxo: OutputReference, tx: Transaction) {
    // Contract treasury using validation
    let Transaction {
      inputs: tx_inputs,
      outputs: tx_outputs,
      mint: tx_mint,
      validity_range: tx_validity_range,
      ..
    } = tx

    // Check if the transaction's validity range is after start_change_time (i.e., the Exchange phase is open)
    let is_exchange_already_allowed =
      is_entirely_after(tx_validity_range, start_change_time)

    // Check if the transaction's validity range is after unlock_unclaimed_assets_time (i.e., the Recall phase is open)
    let is_recall_already_allowed =
      is_entirely_after(tx_validity_range, unlock_unclaimed_assets_time)

    // Extract contract's payment credential from its UTxO
    expect Some(Input {
      output: Output {
        address: Address { payment_credential: contract_payment_cred, .. },
        ..
      },
      ..
    }) = find_input(tx_inputs, contract_utxo)

    let input_outputs =
      tx_inputs
        |> to_outputs()

    let contract_inputs_outputs =
      input_outputs
        |> find_outputs_by_payment_cred(contract_payment_cred, invert: False)

    let user_inputs_outputs =
      input_outputs
        |> find_outputs_by_payment_cred(contract_payment_cred, invert: True)

    let contract_outputs =
      tx_outputs
        |> find_outputs_by_payment_cred(contract_payment_cred, invert: False)

    let user_outputs =
      tx_outputs
        |> find_outputs_by_payment_cred(contract_payment_cred, invert: True)

    // Extract contract's policy ID from its payment credential (the policy ID is the hash of the contract's script, which is used as the payment credential)
    expect Script(contract_policy_id) = contract_payment_cred

    // Determine the contract's phase
    when redeemer is {
      Exchange -> {
        // Exchange phase (burning NFT, sending `PO_asset`):
        // - Definitions:
        //   - PO_asset = the `payout_asset_pid.payout_asset_name` asset
        //   - Receipt_NFT = NFT with the `burn_nft_pid` policy and a name starting with `burn_nft_name`
        //   - Treasury_marker = a service token marking a Treasury_UTxO at the smart contract address
        //   - Treasury_UTxO = a UTxO belonging to the smart contract, containing 1 `Treasury_marker` and some amount of `PO_asset`
        //   - Exchange_rate = the exchange rate from Receipt_NFT to PO_asset, defined as a contract parameter
        //   - Base_ada = a certain amount of ada required to create a UTxO with an asset; it may be returned in raw form if the asset is burned
        //
        // -----------------------------
        //
        // TX structure
        // - Inputs:
        //   - [REQUIRED (>=1)] `Treasury_UTxO`
        //   - [REQUIRED (>=1)] User’s UTxO(s) containing some amount of `Receipt_NFT` (could contain some user's `PO_asset`)
        //   - [OPTIONAL (>=0)] User’s UTxO(s) containing any other assets (e.g., to cover transaction fees) (could contain some user's `PO_asset`)
        //
        // - Outputs:
        //   - [REQUIRED (>=1)] User outputs containing `PO_asset` in an amount equal to the number of burned `Receipt_NFT` × `Exchange_rate`,
        //                      with one output per each address that held a burned `Receipt_NFT`
        //
        //   - [REQUIRED (0 ≤ n ≤ 1)] Smart contract output containing the remaining `Treasury_UTxO`
        //                            only if `PO_asset` remains; otherwise, the `Treasury_UTxO` must be destroyed
        //
        //   - [OPTIONAL (1)] Smart contract owner’s output containing any `Base_ada` left after the destruction of a `Treasury_UTxO`, if applicable
        //
        // - Minting:
        //   - [REQUIRED (>=1)] `Receipt_NFT` with a negative quantity (burned)
        //   - [OPTIONAL (>=0)] `Treasury_marker` with a negative quantity (burned), but only if a `Treasury_UTxO` must be destroyed
        //
        // - Time range:
        //   - [REQUIRED] A timestamp indicating when exchange operations are allowed to begin
        //
        // -----------------------------
        //
        // - Logic:
        //   - Collect the list of burned `Receipt_NFT` (not necessarily equal to the full list of input `Receipt_NFT`)
        //   - Ensure that at least one `Receipt_NFT` was burned
        //   - Use the burn list and inputs to build a payouts map of the form "address:amount"
        //   - If the user included their own `PO_asset` in the inputs, the full amount must be sent to one of their outputs and accounted for in the payout calculations
        //   - Ensure that the amount of `PO_asset` in the `Treasury_UTxO` inputs covers the total amount to be paid to users
        //   - Ensure that there are no redundant `Treasury_UTxOs`
        //   - Ensure that the difference in `PO_asset` between the contract’s `tx_outputs` and `tx_inputs` equals the total user payouts
        //   - Ensure that no excess base ADA was withdrawn from the contract address, if any is present
        //   - Ensure that the real user payouts match their corresponding expected payouts, both by address and by the expected payout amount calculated from the burned NFTs
        //   - If multiple `Treasury_UTxO` were used as `tx_inputs` (because one was insufficient), no more than one may remain in `tx_outputs`
        //   - If one or more `Treasury_UTxO` were emptied, the `Treasury_marker` must be burned
        //   - If one or more `Treasury_UTxO` were emptied, ensure that their `Base_ada` is returned to the contract owner's address
        //   - Ensure that there is at most one contract output with `Treasury_marker` (exactly one item if any).

        //
        // Flatten the mint value to a list of (policy_id, asset_name, amount) tuples for further validation
        let flatten_mint = flatten(tx_mint)

        // Check that no malicious minting occurred (e.g., extra free `Receipt_NFT`, `Treasury_marker`)
        // Only negative mint amounts (<0) for `Receipt_NFT`, `Treasury_marker` are permitted; all other minting is disallowed for security.
        let mint_is_valid =
          flatten_mint
            |> real_all(
                fn((policy_id, asset_name, mint_amount)) {
                  and {
                    // Check if it is burning only
                    (mint_amount < 0)?,
                    or {
                      // Check if the asset is a `Treasury_marker`
                      and {
                        policy_id == contract_policy_id,
                        asset_name == contract_treasury_marker_name,
                      },
                      // Check if the asset is a `Receipt_NFT` with the correct policy and prefix
                      and {
                        policy_id == burn_nft_pid,
                        asset_name
                          |> starts_with(burn_nft_name),
                      },
                    }?,
                  }
                },
              )
        // Then split into to 2 lists: NFTs and treasury_markers
        // If any markers were burned, extract them first — it's more efficient in terms of CPU usage.
        let burned_markers =
          flatten_mint
            |> l_filter(
                fn((policy_id, asset_name, _)) {
                  and {
                    policy_id == contract_policy_id,
                    asset_name == contract_treasury_marker_name,
                  }
                },
              )

        // So the burned NFTs are the remaining part.
        let burned_nfts =
          flatten_mint
            |> difference(burned_markers)

        // There must be at least one burned NFT in the transaction.
        expect length(burned_nfts) > 0

        // Build a list of addresses which hold burned nfts and calculate `expected payouts`
        let expected_payouts =
          user_inputs_outputs
            // Scan their values and build the payouts list based on `burned_nfts` list
            |> l_map(
                fn(Output { address: input_addr, value: input_val, .. }) {
                  Pair(
                    input_addr,
                    input_val
                      // Extract `Receipt_NFT` tokens from values
                      |> tokens(burn_nft_pid)
                      // Filter them by checking if they are present in the `burned_nfts` list
                      |> d_filter(
                          fn(input_nft_name, input_nft_amount) {
                            burned_nfts
                              |> has(
                                  (
                                    burn_nft_pid,
                                    input_nft_name,
                                    -input_nft_amount,
                                  ),
                                )
                          },
                        )
                      // Extract `Receipt_NFT` amounts
                      |> values()
                      // Summarize them
                      |> l_reduce(
                          0,
                          fn(sum, val) { sum + val * n2a_change_rate },
                        ),
                  )
                },
              )
            // There could be zero-valued payouts if address had no burned `Receipt_NFT`, so we need to remove them
            |> l_filter(fn(Pair(_, amount)) { amount > 0 })
            // There could be many payouts with the same address, so squash them into sorted list
            |> aggregate_payouts()

        // Extract the payouts addresses list from `expected_payouts`
        let expected_payouts_addrs =
          expected_payouts
            |> keys()

        // If the user already has some `PO_asset`, we need to account for it for future calculations
        let user_own_payout_assets_quantity =
          user_inputs_outputs
            // Scan their values and calculate the `user_own_payout_assets_quantity`
            |> l_reduce(
                0,
                fn(result, Output { value, .. }) {
                  result + quantity_of(
                    value,
                    payout_asset_pid,
                    payout_asset_name,
                  )
                },
              )

        // Then fetch `real payouts`
        // At the same time, compare them with the expected payouts — if the sequence completes successfully, the real payouts are valid
        let real_payouts_are_ok =
          user_outputs
            // Scan user outputs values and build the payouts list based on `PO_asset` quantity
            |> l_map(
                fn(Output { address: output_addr, value: output_val, .. }) -> Pair<Address,
                Int> {
                  Pair(
                    output_addr,
                    quantity_of(output_val, payout_asset_pid, payout_asset_name),
                  )
                },
              )
            // Remove items with zero payouts and addresses not present in `expected_payouts_addrs`
            |> l_filter(
                fn(Pair(addr, amount)) {
                  and {
                    amount > 0,
                    expected_payouts_addrs
                      |> has(addr),
                  }
                },
              )
            // There could be many payouts with the same address, so squash them into sorted list
            |> aggregate_payouts()
            // Then we need to compare them with the expected values (they should match)
            // Also, if any of the real payouts includes a portion of `PO_asset` coming from the user's inputs, we have to account for that
            |> verify_payouts(
                expected_po: expected_payouts,
                possible_delta: user_own_payout_assets_quantity,
                fix_applied: False,
              )

        // Calculate the sum to be paid out
        let expected_payouts_sum =
          expected_payouts
            |> l_reduce(0, fn(sum, Pair(_, amount)) { sum + amount })

        // Local helper for calculating the total amount of `PO_assets` in the given outputs
        let get_payout_assets_sum =
          fn(outputs: List<Output>) -> Int {
            outputs
              |> l_reduce(
                  0,
                  fn(sum, Output { value, .. }) {
                    let markers_amount =
                      quantity_of(
                        value,
                        contract_policy_id,
                        contract_treasury_marker_name,
                      )

                    // Verify if contract's input is a valid `Treasury_UTxO`
                    if (markers_amount == 1)? {
                      sum + quantity_of(
                        value,
                        payout_asset_pid,
                        payout_asset_name,
                      )
                    } else {
                      // Users may try to include previously sent garbage UTxOs at the contract address
                      // Only legitimate contract-owned UTxOs should be used in the exchange logic
                      fail @"Invalid UTXO"
                    }
                  },
                )
          }

        // Inspect the contract's inputs to verify their optimality and return the count of consumed `Treasury_UTxO`s
        let (are_contract_inputs_optimal, consumed_treasury_count) =
          contract_inputs_outputs
            // Convert each contract input to the amount of `PO_asset` it contains
            |> l_map(
                fn(Output { value, .. }) {
                  quantity_of(value, payout_asset_pid, payout_asset_name)
                },
              )
            // Sort them
            |> sort(int.compare)
            // Check if they are optimal
            |> validate_optimality(expected_payouts_sum, 0, 0)

        // Calculate total contract's inputs sum with the local helper
        let contract_input_payout_assets_amount =
          contract_inputs_outputs
            |> get_payout_assets_sum()

        // The same for the contract's outputs
        let contract_output_payout_assets_amount =
          contract_outputs
            |> get_payout_assets_sum()

        // Check if there is 1 contract output at most
        let is_there_no_more_than_one_contract_out =
          length(contract_outputs) <= 1

        // Verify that the difference between inputs and outputs equals the expected payout to ensure that the contract actually provided the funds
        // Otherwise, the user could satisfy the payout checks using their own assets
        let contract_payout_is_fine =
          (contract_input_payout_assets_amount - contract_output_payout_assets_amount == expected_payouts_sum)?

        // Check whether the `Treasury_markers` were properly burned
        let are_treasuries_removed_properly =
          consumed_treasury_count == length(burned_markers)

        // If any `Treasury_UTxO` was consumed and its `Treasury_marker` burned, ensure that any remaining base ADA was sent to the contract owner
        let treasury_ada_sent_back_properly =
          if consumed_treasury_count == 0 {
            True
          } else {
            // Ensure that there is exactly one output related to the contract owner
            expect [owner_output] =
              tx_outputs
                |> find_outputs_by_payment_cred(
                    VerificationKey(owner_key_hash),
                    invert: False,
                  )
            // Ensure that the owner received the full amount of released base ADA
            lovelace_of(owner_output.value) == consumed_treasury_count * contract_treasury_lovelace
          }

        and {
          is_exchange_already_allowed?,
          are_contract_inputs_optimal?,
          mint_is_valid?,
          real_payouts_are_ok?,
          is_there_no_more_than_one_contract_out?,
          contract_payout_is_fine?,
          are_treasuries_removed_properly?,
          treasury_ada_sent_back_properly?,
        }
      }
      Recall -> {
        // Treasury destruction (recalling `PO_asset`, unlocking base ADA, trashing empty treasury):
        // - Redeemer: Recall.
        // - Minting:
        //   - burning is allowed only after `unlock_unclaimed_assets_time`;
        // - Outputs:
        //   - ensure that the only output goes to the address associated with `assets_owner_pcred`;
        //   - ensure that there are no tx_outputs containing `contract_policy_id.contract_treasury_marker_name`.

        expect [
          Output {
            address: Address {
              payment_credential: VerificationKey(out_payment_cred),
              ..
            },
            value: output_value,
            ..
          },
        ] = tx_outputs

        let is_output_fine = and {
            (out_payment_cred == owner_key_hash)?,
            (quantity_of(
              output_value,
              contract_policy_id,
              contract_treasury_marker_name,
            ) == 0)?,
          }

        // If there are no markers in a particular output, we don't need to check if they were burned.
        // This is implicitly guaranteed, otherwise the transaction would be unbalanced.
        // It also allows us to recall any unclaimed UTxOs without requiring a marker at all.
        and {
          is_recall_already_allowed?,
          is_output_fine?,
        }
      }
      Bootstrap -> fail
    }
  }

  mint(redeemer: Action, contract_policy_id: PolicyId, tx: Transaction) {
    let Transaction {
      inputs: tx_inputs,
      outputs: tx_outputs,
      mint: tx_mint,
      validity_range: tx_validity_range,
      ..
    } = tx

    let is_exchange_already_allowed =
      is_entirely_after(tx_validity_range, start_change_time)

    let is_recall_already_allowed =
      is_entirely_after(tx_validity_range, unlock_unclaimed_assets_time)

    when redeemer is {
      Bootstrap -> {
        // Treasury formation (sending assets, minting the marker token):
        // - Redeemer: Bootstrap.
        // - Inputs:
        //   - ensure that `contract_policy_id.contract_treasury_marker_name` is not present in any input (it may only be minted);

        let no_markers_in_inputs =
          !any(
            tx_inputs,
            fn(Input { output: Output { value, .. }, .. }) {
              quantity_of(
                value,
                contract_policy_id,
                contract_treasury_marker_name,
              ) > 0
            },
          )

        // - Outputs:
        //   - verify that N `PO_asset` are sent to the contract address along with the `contract_policy_id.contract_treasury_marker_name` asset;
        // - AmountLock:
        //   - it's not allowed to create a treasury with less than 10,000 `PO_asset`;
        //   - it's not allowed to create a treasury with `contract_policy_id.contract_treasury_marker_name` != 1 .
        let contract_outputs =
          find_script_outputs(tx_outputs, contract_policy_id)
        let contract_outputs_are_fine =
          contract_outputs
            |> all(
                fn(Output { value: contract_output_value, .. }) {
                  and {
                    (quantity_of(
                      contract_output_value,
                      contract_policy_id,
                      contract_treasury_marker_name,
                    ) == 1)?,
                    (quantity_of(
                      contract_output_value,
                      payout_asset_pid,
                      payout_asset_name,
                    ) >= contract_treasury_base_quantity)?,
                  }
                },
              )

        // - Minting:
        //   - ensure that exactly 1 `contract_policy_id.contract_treasury_marker_name` per contract_output was minted;
        let contract_outputs_quantity = length(contract_outputs)
        let minted_markers_quantity =
          quantity_of(
            tx_mint,
            contract_policy_id,
            contract_treasury_marker_name,
          )
        let minted_markers_match_contract_outputs =
          contract_outputs_quantity == minted_markers_quantity

        and {
          no_markers_in_inputs?,
          contract_outputs_are_fine?,
          minted_markers_match_contract_outputs?,
        }
      }

      Exchange ->
        // Exchange (sending `PO_asset`): 
        // - Ensure that the burned `contract_policy_id.contract_treasury_marker_name` comes from the single UTXO sent to the contract address.        
        //
        // Actually, there is no way to burn any marker without spending the contract's UTxO, 
        // so the entire validation logic resides in the spending validator.
        // Here, we only need to ensure that this is a burning transaction, not minting.

        and {
          check_if_single_asset_burned(
            tx_mint,
            contract_policy_id,
            contract_treasury_marker_name,
          )?,
          is_exchange_already_allowed?,
        }
      Recall ->
        // Treasury destruction (recalling `PO_asset`, unlocking base ADA, trashing empty treasury):
        //
        // Actually, there is no way to burn any marker without spending the contract's UTxO, 
        // so the entire validation logic resides in the spending validator.
        // Here, we only need to ensure that this is a burning transaction, not minting.

        and {
          check_if_single_asset_burned(
            tx_mint,
            contract_policy_id,
            contract_treasury_marker_name,
          )?,
          is_recall_already_allowed?,
        }
    }
  }

  else(_) {
    fail
  }
}
