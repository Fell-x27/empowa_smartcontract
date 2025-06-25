use aiken/collection/dict.{filter as d_filter, to_pairs, values}
use aiken/collection/list.{
  all, any, difference, filter as l_filter, has, length, map as l_map,
  reduce as l_reduce, sort,
}
use aiken/collection/pairs.{insert_with_by_ascending_key}
use aiken/interval.{is_entirely_after}
use aiken/primitive/bytearray.{compare, starts_with}
use aiken/primitive/int
use cardano/address.{Address, PaymentCredential, Script, VerificationKey}
use cardano/assets.{
  AssetName, PolicyId, Value, flatten, lovelace_of, quantity_of, tokens,
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
  let add_integer =
    fn(x, y) { x + y }
  //
  let addr_compare =
    fn(addr1, addr2) {
      compare(address2pcred_as_bytes(addr1), address2pcred_as_bytes(addr2))
    }
  //
  payouts
    |> l_reduce(
        [],
        fn(result, Pair(address, amount)) {
          result
            |> insert_with_by_ascending_key(
                key: address,
                value: amount,
                compare: addr_compare,
                with: add_integer,
              )
        },
      )
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

    let is_exchange_already_allowed =
      is_entirely_after(tx_validity_range, start_change_time)

    let is_recall_already_allowed =
      is_entirely_after(tx_validity_range, unlock_unclaimed_assets_time)

    expect Some(Input { output: Output { address: contract_address, .. }, .. }) =
      find_input(tx_inputs, contract_utxo)

    let Address { payment_credential: contract_payment_cred, .. } =
      contract_address

    expect Script(contract_policy_id) = contract_payment_cred

    when redeemer is {
      Exchange -> {
        // Exchange (sending EMP):
        // - Minting:
        //   - Ensure that at least one `burn_nft_pid.burn_nft_name...` NFT was burned, and that the resulting payouts
        //     match the number and type of burned NFTs.
        let flatten_mint = flatten(tx_mint)

        // Check that no malicious minting occurred (e.g., extra free NFTs, `contract_policy_id.another_asset`)
        let mint_is_valid =
          flatten_mint
            |> all(
                fn((policy_id, asset_name, mint_amount)) {
                  and {
                    (mint_amount < 0)?,
                    or {
                      and {
                        policy_id == contract_policy_id,
                        asset_name == contract_treasury_marker_name,
                      },
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
        let burned_markers =
          flatten_mint
            |> l_filter(
                //Check if partition is better
                fn((policy_id, asset_name, _)) {
                  and {
                    policy_id == contract_policy_id,
                    asset_name == contract_treasury_marker_name,
                  }
                },
              )
        let burned_nfts =
          flatten_mint
            |> difference(burned_markers)
        // - Inputs:
        //   - Collect the list of addresses holding `burn_nft_pid` NFTs with names starting with `burn_nft_name`,
        //     and associate each with their expected payout amount.
        //   - Ensure that each NFT input used for payout is also present in the transaction's burn list.
        //   - Ensure that the amount of EMP in the contract-owned `tx_inputs` covers the total EMP to be paid to users.
        //
        // - Outputs:
        //   - Ensure that all user `tx_outputs` match their corresponding `tx_inputs` (NFT holders),
        //     both by address and by the expected payout amount calculated from the burned NFTs.
        //
        // Build a list of addresses which hold burned nfts and calculate expected payouts
        let expected_payouts =
          tx_inputs
            |> to_outputs()
            |> find_outputs_by_payment_cred(contract_payment_cred, invert: True)
            |> l_map(
                fn(Output { address: input_addr, value: input_val, .. }) {
                  Pair(
                    input_addr,
                    input_val
                      |> tokens(burn_nft_pid)
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
                      |> values()
                      |> l_reduce(
                          0,
                          fn(sum, val) { sum + val * n2a_change_rate },
                        ),
                  )
                },
              )
            |> l_filter(fn(Pair(_, amount)) { amount > 0 })
            |> aggregate_payouts()
        // Then fetch actual payouts
        let real_payouts =
          tx_outputs
            |> find_outputs_by_payment_cred(contract_payment_cred, invert: True)
            |> l_map(
                fn(Output { address: output_addr, value: output_val, .. }) -> Pair<Address,
                Int> {
                  Pair(
                    output_addr,
                    quantity_of(output_val, payout_asset_pid, payout_asset_name),
                  )
                },
              )
            |> l_filter(fn(Pair(_, amount)) { amount > 0 })
            |> aggregate_payouts()
        // Then compare actual payouts with expected ones
        let payouts_are_valid = real_payouts == expected_payouts

        // - Inputs:
        //   - Ensure that there are no redundant treqsury-UTXO
        // - Outputs:
        //   - Ensure that the EMP difference between the contract's `tx_outputs` and `tx_inputs` equals the sum of all user payouts.
        //   - Ensure that no excess base ADA was withdrawn from the contract address, if any is present.
        //
        // Calculate the real sum to be paid
        let real_payouts_sum =
          real_payouts
            |> l_reduce(0, fn(sum, Pair(_, amount)) { sum + amount })
        //Collect all contract's inputs and calculate input EMPs
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

                    if (markers_amount == 1)? {
                      sum + quantity_of(
                        value,
                        payout_asset_pid,
                        payout_asset_name,
                      )
                    } else {
                      fail @"Invalid UTXO"
                    }
                  },
                )
          }

        let contract_inputs_outs =
          tx_inputs
            |> to_outputs()
            |> find_outputs_by_payment_cred(
                contract_payment_cred,
                invert: False,
              )

        //   - Burning `contract_policy_id.contract_treasury_marker_name` is required if the treasury UTXO was fully consumed and emptied.
        // - Outputs:
        //   - If multiple treasuries were used as `tx_inputs` (because one was insufficient),
        //     only one or none may remain in the `tx_outputs`.
        let (are_contract_inputs_optimal, consumed_treasury_count) =
          contract_inputs_outs
            |> l_map(
                fn(Output { value, .. }) {
                  quantity_of(value, payout_asset_pid, payout_asset_name)
                },
              )
            |> sort(int.compare)
            |> validate_optimality(real_payouts_sum, 0, 0)

        let contract_input_payout_assets_amount =
          contract_inputs_outs
            |> get_payout_assets_sum()
        //The same for the contract's outputs
        let contract_outputs =
          tx_outputs
            |> find_outputs_by_payment_cred(
                contract_payment_cred,
                invert: False,
              )
        let contract_output_payout_assets_amount =
          contract_outputs
            |> get_payout_assets_sum()

        //   - Ensure that there is at most one contract output with `contract_policy_id.contract_treasury_marker_name` (exactly one item if any).
        let is_there_no_more_than_one_contract_out =
          length(contract_outputs) <= 1
        let contract_payout_is_fine = and {
            (contract_input_payout_assets_amount - contract_output_payout_assets_amount == real_payouts_sum)?,
            (real_payouts_sum > 0)?,
          }

        // trace contract_input_payout_assets_amount
        // trace contract_output_payout_assets_amount
        // trace real_payouts_sum
        // If any treasury was consumed and its marker burned, ensure that any remaining base ADA from it was sent to the owner.
        let are_treasuries_removed_properly =
          consumed_treasury_count == length(burned_markers)

        let treasury_ada_sent_back_properly =
          if consumed_treasury_count == 0 {
            True
          } else {
            // Ensure that there is an owner-related output
            expect [owner_output] =
              tx_outputs
                |> find_outputs_by_payment_cred(
                    VerificationKey(owner_key_hash),
                    invert: False,
                  )

            lovelace_of(owner_output.value) == consumed_treasury_count * contract_treasury_lovelace
          }

        and {
          is_exchange_already_allowed?,
          are_contract_inputs_optimal?,
          contract_payout_is_fine?,
          mint_is_valid?,
          payouts_are_valid?,
          are_treasuries_removed_properly?,
          treasury_ada_sent_back_properly?,
          is_there_no_more_than_one_contract_out?,
        }
      }
      Recall -> {
        // Treasury destruction (recalling EMP, unlocking base ADA, trashing empty treasury):
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
        //   - verify that N EMP are sent to the contract address along with the `contract_policy_id.contract_treasury_marker_name` asset;
        // - AmountLock:
        //   - it's not allowed to create a treasury with less than 10,000 EMP;
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
        // Exchange (sending EMP): 
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
        // Treasury destruction (recalling EMP, unlocking base ADA, trashing empty treasury):
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
