use aiken/collection/dict.{filter as d_filter, values}
use aiken/collection/list.{
  all, any, difference, filter as l_filter, foldl as l_foldl, has, length,
  map as l_map, reduce as l_reduce, sort,
}
use aiken/primitive/bytearray.{starts_with}
use cardano/address.{Address, PaymentCredential, Script, VerificationKey}
use cardano/assets.{
  AssetName, PolicyId, flatten, lovelace_of, policies, quantity_of, tokens,
}
use cardano/transaction.{
  Input, Output, OutputReference, Transaction, find_input, find_script_outputs,
}
use config.{contract_treasury_lovelace, contract_treasury_marker_name}

pub type Action {
  Bootstrap
  Exchange
  Recall
}

fn address2pcred_as_bytes(Address { payment_credential, .. }) -> ByteArray {
  when payment_credential is {
    VerificationKey(bytes) -> bytes
    Script(bytes) -> bytes
  }
}

fn sort_payouts_by_addr(
  payouts: List<Pair<Address, Int>>,
) -> List<Pair<Address, Int>> {
  payouts
    |> sort(
        fn(Pair(addr1, _), Pair(addr2, _)) {
          bytearray.compare(
            address2pcred_as_bytes(addr1),
            address2pcred_as_bytes(addr2),
          )
        },
      )
}

fn to_outputs(inputs: List<Input>) -> List<Output> {
  inputs
    |> l_map(fn(Input { output, .. }) { output })
}

fn find_outputs_by_address(
  outputs: List<Output>,
  address: Address,
  invert: Bool,
) -> List<Output> {
  outputs
    |> l_filter(
        fn(Output { address: out_address, .. }) {
          if invert {
            address != out_address
          } else {
            address == out_address
          }
        },
      )
}

validator empowa_swap(
  payout_asset_pid: PolicyId,
  payout_asset_name: AssetName,
  burn_nft_pid: PolicyId,
  burn_nft_name: AssetName,
  n2a_change_rate: Int,
  start_change_time: Int,
  unlock_unclaimed_assets_time: Int,
  owner_address: Address,
) {
  spend(_d, redeemer: Action, contract_utxo: OutputReference, tx: Transaction) {
    // Contract treasury using validation
    let Transaction {
      inputs: tx_inputs,
      outputs: tx_outputs,
      mint: tx_mint,
      ..
    } = tx

    expect Some(Input { output: Output { address: contract_address, .. }, .. }) =
      find_input(tx_inputs, contract_utxo)

    expect Address { payment_credential: Script(contract_policy_id), .. } =
      contract_address

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
                        starts_with(asset_name, burn_nft_name),
                      },
                    }?,
                  }
                },
              )
        // Then split into to 2 lists: NFTs and treasury_markers
        let burned_nfts =
          flatten_mint
            |> l_filter(
                //Check if partition is better
                fn((policy_id, asset_name, _)) {
                  and {
                    policy_id == burn_nft_pid,
                    starts_with(asset_name, burn_nft_name),
                  }
                },
              )

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
        // Build a list of addresses which hold burned nfts
        let expected_payouts =
          tx_inputs
            |> to_outputs()
            |> find_outputs_by_address(contract_address, invert: True)
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
            |> sort_payouts_by_addr()

        // Then fetch actual payouts
        let real_payouts =
          tx_outputs
            |> find_outputs_by_address(contract_address, invert: True)
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
            |> sort_payouts_by_addr()
        // Then compare actual payouts with expected ones
        let payouts_are_valid = real_payouts == expected_payouts

        // - Inputs:
        // - Outputs:
        //   - Ensure that the EMP difference between the contract's `tx_outputs` and `tx_inputs` equals the sum of all user payouts.
        //   - Ensure that no excess base ADA was withdrawn from the contract address, if any is present.
        //First, collect all contrac's inputs and calculate input EMPs
        let get_payout_assets_sum =
          fn(outputs: List<Output>) -> Int {
            outputs
              |> l_reduce(
                  0,
                  fn(sum, Output { value, .. }) {
                    if quantity_of(
                      value,
                      contract_policy_id,
                      contract_treasury_marker_name,
                    ) == 1 {
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
        let contract_input_payout_assets_amount =
          tx_inputs
            |> to_outputs()
            |> find_outputs_by_address(contract_address, invert: False)
            |> get_payout_assets_sum()
        //The same for the contract's outputs
        let contract_output_payout_assets_amount =
          tx_outputs
            |> find_outputs_by_address(contract_address, invert: False)
            |> get_payout_assets_sum()

        // Calculate the real sum to be paid
        let real_payouts_sum =
          real_payouts
            |> l_reduce(0, fn(sum, Pair(_, amount)) { sum + amount })

        let contract_payout_is_fine =
          contract_input_payout_assets_amount - contract_output_payout_assets_amount == real_payouts_sum

        // If any treasury was consumed and its marker burned, ensure that any remaining base ADA from it was sent to the owner.
        let burned_markers_count =
          flatten_mint
            |> difference(burned_nfts)
            |> length()

        let treasury_ada_sent_back_properly =
          if burned_markers_count == 0 {
            True
          } else {
            // Ensure that there is an owner-related output
            expect [owner_output] =
              tx_outputs
                |> find_outputs_by_address(owner_address, invert: False)

            lovelace_of(owner_output.value) == burned_markers_count * contract_treasury_lovelace
          }

        and {
          contract_payout_is_fine?,
          mint_is_valid?,
          payouts_are_valid?,
          treasury_ada_sent_back_properly?,
        }
      }
      //   - Burning `contract_policy_id.contract_treasury_marker_name` is required if the treasury UTXO was fully consumed and emptied.
      // - Outputs:
      //   - If multiple treasuries were used as `tx_inputs` (because one was insufficient),
      //     only one or none may remain in the `tx_outputs`.
      //   - Ensure that there is at most one contract output with `contract_policy_id.contract_treasury_marker_name` (exactly one item if any).
      Recall ->
        // Treasury destruction (recalling EMP and unlocking base ADA):
        //  Minting:
        //   - `contract_policy_id.contract_treasury_marker_name` < 0;
        // - Delegated to the mint() subvalidator.
        todo @"Recall spend not implemented"
      Bootstrap -> fail
    }
  }

  mint(redeemer: Action, contract_policy_id: PolicyId, tx: Transaction) {
    let Transaction {
      inputs: tx_inputs,
      outputs: tx_outputs,
      mint: tx_mint,
      ..
    } = tx

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
        let script_outputs = find_script_outputs(tx_outputs, contract_policy_id)
        let script_outputs_are_fine =
          script_outputs
            |> all(
                fn(Output { value: script_output_value, .. }) {
                  and {
                    (quantity_of(
                      script_output_value,
                      contract_policy_id,
                      contract_treasury_marker_name,
                    ) == 1)?,
                    (quantity_of(
                      script_output_value,
                      payout_asset_pid,
                      payout_asset_name,
                    ) >= 10_000)?,
                  }
                },
              )

        // - Minting:
        //   - ensure that exactly 1 `contract_policy_id.contract_treasury_marker_name` per script_output was minted;
        let script_outputs_quantity = length(script_outputs)
        let minted_markers_quantity =
          quantity_of(
            tx_mint,
            contract_policy_id,
            contract_treasury_marker_name,
          )
        let minted_markers_match_script_outputs =
          script_outputs_quantity == minted_markers_quantity

        and {
          no_markers_in_inputs?,
          script_outputs_are_fine?,
          minted_markers_match_script_outputs?,
        }
      }
      Recall ->
        // Treasury destruction (recalling EMP, unlocking base ADA, trashing empty treasury):
        // - Redeemer: Recall.
        // - Minting:
        //   - burning is allowed only after `unlock_unclaimed_assets_time`,
        //     or if the treasury UTXO contains no `payout_asset_pid.payout_asset_name` tokens;
        // - Outputs:
        //   - ensure that the only output goes to the address associated with `assets_owner_pcred`;
        //   - ensure that there are no tx_outputs containing `contract_policy_id.contract_treasury_marker_name`.
        todo @"Recall mint not implemented"

      Exchange ->
        // Exchange (sending EMP): 
        // - Ensure that the burned `contract_policy_id.contract_treasury_marker_name` comes from the single UTXO sent to the contract address.        

        todo @"Exchange mint not implemented"
    }
  }

  else(_) {
    fail
  }
}
