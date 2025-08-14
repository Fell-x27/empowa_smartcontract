use aiken/collection/dict.{filter as d_filter, values}
use aiken/collection/list.{
  all, any, difference, filter as l_filter, has, length, map as l_map,
  reduce as l_reduce, sort,
}
use aiken/collection/pairs.{keys}
use aiken/interval.{is_entirely_after}
use aiken/primitive/bytearray.{starts_with}
use aiken/primitive/int
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId, flatten, lovelace_of, quantity_of, tokens}
use cardano/transaction.{Input,
  Output, OutputReference, Transaction, find_input}
use config.{
  burn_nft_name, burn_nft_pid, contract_treasury_asset_quantity,
  contract_treasury_lovelace_quantity, contract_treasury_marker_name,
  n2a_change_rate, owner_key_hash, payout_asset_name, payout_asset_pid,
  start_change_time, unlock_unclaimed_assets_time,
}
use helpers.{
  aggregate_payouts, check_if_single_asset_minted, find_outputs_by_payment_cred,
  real_all, validate_optimality, verify_payouts,
}
use types.{Action, Bootstrap, Exchange, Recall}

validator empowa_swap {
  spend(_d, redeemer: Action, contract_utxo: OutputReference, tx: Transaction) {
    // Contract treasury using validation
    //
    // Extract some inportant fields from the transaction's body
    let Transaction {
      inputs: tx_inputs,
      outputs: tx_outputs,
      mint: tx_mint,
      validity_range: tx_validity_range,
      ..
    } = tx

    // Check if the transaction's validity range is after start_change_time (i.e., the Exchange phase is open)
    let exchange_is_already_allowed =
      is_entirely_after(tx_validity_range, start_change_time)

    // Check if the transaction's validity range is after unlock_unclaimed_assets_time (i.e., the Recall phase is open)
    let recall_is_already_allowed =
      is_entirely_after(tx_validity_range, unlock_unclaimed_assets_time)

    // Extract contract's payment credential from its UTxO
    let current_utxo = find_input(tx_inputs, contract_utxo)
    expect Some(Input {
      output: Output {
        address: Address { payment_credential: contract_payment_cred, .. },
        reference_script: None,
        ..
      },
      ..
    }) = current_utxo

    // Extract contract's policy ID from its payment credential (the policy ID is the hash of the contract's script, which is used as the payment credential)
    expect Script(contract_policy_id) = contract_payment_cred

    // Extract UTxOs from Inputs
    let input_outputs =
      tx_inputs
        |> l_map(fn(Input { output, .. }) { output })

    // Extract contract's inputs UTxOs
    let contract_inputs_outputs =
      input_outputs
        |> find_outputs_by_payment_cred(contract_payment_cred, invert: False)

    // Extract user's inputs UTxOs
    let user_inputs_outputs =
      input_outputs
        |> find_outputs_by_payment_cred(contract_payment_cred, invert: True)

    // Extract contract's outputs
    let contract_outputs =
      tx_outputs
        |> find_outputs_by_payment_cred(contract_payment_cred, invert: False)

    // Extract user's outputs
    let user_outputs =
      tx_outputs
        |> find_outputs_by_payment_cred(contract_payment_cred, invert: True)

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
        //   - [OPTIONAL (0 <= n <= 1)] Smart contract output containing the remaining `Treasury_UTxO`
        //                            only if `PO_asset` remains; otherwise, the `Treasury_UTxO` must be destroyed
        //
        //   - [OPTIONAL (exactly 1)] Smart contract owner’s output containing any `Base_ada` left after the destruction of a `Treasury_UTxO`, if applicable
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
        //   - Ensure that only the exact number of PO_asset required for payouts was moved from the treasury.

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
        let real_payouts_are_fine =
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
        let (contract_inputs_are_optimal, consumed_treasury_count) =
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
        let there_is_no_more_than_one_contract_out =
          length(contract_outputs) <= 1

        // Check if the `Base_ada` of `Treasury_UTxO`s remains untouched
        let contract_output_ada_is_fine =
          if length(contract_outputs) == 1 {
            expect [Output { value, .. }] = contract_outputs
            lovelace_of(value) == contract_treasury_lovelace_quantity
          } else {
            True
          }

        // Verify that the difference between inputs and outputs equals the expected payout to ensure that the contract actually provided the funds
        // Otherwise, the user could satisfy the payout checks using their own assets
        let contract_payout_is_fine =
          (contract_input_payout_assets_amount - contract_output_payout_assets_amount == expected_payouts_sum)?

        // Check whether the `Treasury_markers` were properly burned
        let burned_markers_count =
          when burned_markers is {
            [] -> 0
            [(_, _, count)] -> count * -1
            _ -> fail
          }
        let treasuries_are_removed_properly =
          consumed_treasury_count == burned_markers_count

        // If any `Treasury_UTxO` was consumed and its `Treasury_marker` burned, ensure that any remaining base ADA was sent to the contract owner
        let treasury_ada_are_sent_back_properly =
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
            lovelace_of(owner_output.value) == consumed_treasury_count * contract_treasury_lovelace_quantity
          }

        // Make a decision about the validity of input usage
        and {
          exchange_is_already_allowed?,
          contract_inputs_are_optimal?,
          mint_is_valid?,
          real_payouts_are_fine?,
          there_is_no_more_than_one_contract_out?,
          contract_payout_is_fine?,
          treasuries_are_removed_properly?,
          treasury_ada_are_sent_back_properly?,
          contract_output_ada_is_fine?,
        }
      }
      Recall -> {
        // Treasury destruction (recalling `PO_asset`, unlocking base ADA, trashing empty treasury):
        // - Definitions:
        //   - Treasury_marker = a service token marking a Treasury_UTxO at the smart contract address
        //   - `owner_key_hash` – the key hash of the contract owner, defined in the contract’s config file
        //
        // -----------------------------
        //
        // TX structure
        // - Inputs:
        //   - [REQUIRED (>=1)] Any UTxO from the contract’s address
        //   - [OPTIONAL (>=0)] Any UTxO(s) containing any assets (e.g., to cover transaction fees)
        //
        // - Outputs:
        //   - [REQUIRED (exactly 1)] Output to the contract owner's address, derived from `owner_key_hash` in the config file
        //
        // - Minting:
        //   - [OPTIONAL (>=0)] `Treasury_marker` with a negative quantity (burned), as any such token in the outputs is prohibited
        //
        // - Time range:
        //   - [REQUIRED] A timestamp indicating when recall operations are permitted to begin

        //
        // -----------------------------
        //
        // - Logic:
        //   - Burning is allowed only after `unlock_unclaimed_assets_time`
        //   - Ensure that the only output is sent to the address associated with `owner_key_hash`
        //   - Ensure that no `tx_outputs` contain `contract_policy_id.contract_treasury_marker_name`

        //
        // Extract the only output's address payment credential to check if it is correct
        // Extract its value to check that it doesn't contain any `Treasury_marker`
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

        // Check if the output belongs to the owner and does not contain any `Treasury_marker`
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
        //
        // Make a decision about the validity of input usage
        and {
          recall_is_already_allowed?,
          is_output_fine?,
        }
      }
      // Bootstrap is not related to spending and cannot be used in this context
      Bootstrap -> fail @"Wrong redeemer!"
    }
  }

  mint(redeemer: Action, contract_policy_id: PolicyId, tx: Transaction) {
    // Contract treasury minting/burning validation
    //
    // Extract some inportant fields from the transaction's body
    let Transaction {
      inputs: tx_inputs,
      outputs: tx_outputs,
      mint: tx_mint,
      validity_range: tx_validity_range,
      ..
    } = tx

    // Check if the transaction's validity range is after start_change_time (i.e., the Exchange phase is open)
    let exchange_is_already_allowed =
      is_entirely_after(tx_validity_range, start_change_time)

    // Check if the transaction's validity range is after unlock_unclaimed_assets_time (i.e., the Recall phase is open)
    let recall_is_already_allowed =
      is_entirely_after(tx_validity_range, unlock_unclaimed_assets_time)

    let contract_payment_cred = Script(contract_policy_id)

    // Extract contract's outputs
    let contract_outputs =
      tx_outputs
        |> find_outputs_by_payment_cred(contract_payment_cred, invert: False)

    when redeemer is {
      Bootstrap -> {
        // Treasury formation (sending assets, minting the marker token):
        // - Definitions:
        //   - PO_asset = the `payout_asset_pid.payout_asset_name` asset
        //   - Treasury_marker = a service token marking a Treasury_UTxO at the smart contract address
        //   - Treasury_UTxO = a UTxO belonging to the smart contract, containing 1 `Treasury_marker` and some amount of `PO_asset`
        //   - Base_ada = a certain amount of ada required to create a UTxO with an asset; it may be returned in raw form if the asset is burned
        //
        // -----------------------------
        //
        // TX structure
        // - Inputs:
        //   - [REQUIRED (>=1)] Any UTxO(s) containing some amount of `PO_asset` and ada
        //
        // - Outputs:
        //   - [REQUIRED (>=1)] Contract address output(s) with `Treasury_UTxO`, 
        //                      each containing exactly `contract_treasury_lovelace_quantity` of `Base_ada` and `contract_treasury_asset_quantity` of `PO_asset`
        //
        //   - [OPTIONAL (>=0)] User's change
        //
        // - Minting:
        //   - [OPTIONAL (>=1)] `Treasury_marker` with a positive quantity (minted), equal to the number of contract address outputs
        //
        //
        // -----------------------------
        //
        // - Logic:
        //   - Ensure that `Treasury_marker` is not present in any input (it may only be minted);
        //   - Ensure that exactly one `Treasury_marker` is minted per contract output;
        //   - Treasury creation with less than `contract_treasury_asset_quantity` of `PO_asset` is not allowed;
        //   - Treasury creation with less than `contract_treasury_lovelace_quantity` lovelaces is not allowed;
        //   - Treasury creation with `contract_treasury_marker`>1 is not allowed.

        // Inspect contract
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
        let contract_outputs_are_fine =
          // Check if all contract outputs satisfy the following conditions:
          contract_outputs
            |> all(
                fn(Output { value: contract_output_value, .. }) {
                  and {
                    // Contain exactly 1 `Treasury_marker`
                    (quantity_of(
                      contract_output_value,
                      contract_policy_id,
                      contract_treasury_marker_name,
                    ) == 1)?,
                    // Contain at least `contract_treasury_asset_quantity` of `PO_asset`
                    (quantity_of(
                      contract_output_value,
                      payout_asset_pid,
                      payout_asset_name,
                    ) >= contract_treasury_asset_quantity)?,
                    // Contain exactly `contract_treasury_lovelace_quantity` of lovelace (Base ADA)
                    (lovelace_of(contract_output_value) == contract_treasury_lovelace_quantity)?,
                  }
                },
              )

        // Count the number of contract outputs to verify whether `Treasury_marker`s were minted correctly
        let contract_outputs_quantity = length(contract_outputs)
        // And the same for minted `Treasury_marker`s
        let minting_is_fine =
          check_if_single_asset_minted(
            tx_mint,
            contract_policy_id,
            contract_treasury_marker_name,
            burned: False,
          )?
        let minted_markers_quantity =
          quantity_of(
            tx_mint,
            contract_policy_id,
            contract_treasury_marker_name,
          )
        // And then compare them
        let minted_markers_match_contract_outputs =
          contract_outputs_quantity == minted_markers_quantity

        // Make a decision about the validity of input usage
        and {
          minting_is_fine?,
          no_markers_in_inputs?,
          contract_outputs_are_fine?,
          minted_markers_match_contract_outputs?,
        }
      }

      Exchange ->
        // Exchange (sending `PO_asset` with Treasury destruction):
        //
        // - Definitions:
        //   - Treasury_marker = a service token marking a Treasury_UTxO at the smart contract address
        //   - Treasury_UTxO = a UTxO belonging to the smart contract, containing 1 `Treasury_marker` and some amount of `PO_asset`
        //
        // Not a standalone action.
        // This is a helper validator, used only when burning a `Treasury_marker` as part of an exchange.
        // See the transaction structure in `spend -> Exchange`.

        // Actually, there is no way to burn any marker without spending the contract's UTxO,
        // so the full validation logic resides in the spending validator.
        // Here, we only need to ensure that this is a burning transaction, not minting, and that it is allowed by the timelock.

        and {
          check_if_single_asset_minted(
            tx_mint,
            contract_policy_id,
            contract_treasury_marker_name,
            burned: True,
          )?,
          exchange_is_already_allowed?,
        }
      Recall ->
        // Treasury destruction (recalling `PO_asset`, unlocking base ADA, trashing empty treasury):
        //
        // - Definitions:
        //   - Treasury_marker = a service token marking a Treasury_UTxO at the smart contract address
        //   - Treasury_UTxO = a UTxO belonging to the smart contract, containing 1 `Treasury_marker` and some amount of `PO_asset`
        //
        // Not a standalone action.
        // This is a helper validator, used only when burning a `Treasury_marker` as part of an recalling.
        // See the transaction structure in `spend -> Recall`.

        // Actually, there is no way to burn any marker without spending the contract's UTxO,
        // so the full validation logic resides in the spending validator.
        // Here, we only need to ensure that this is a burning transaction, not minting, and that it is allowed by the timelock.

        and {
          check_if_single_asset_minted(
            tx_mint,
            contract_policy_id,
            contract_treasury_marker_name,
            burned: True,
          )?,
          recall_is_already_allowed?,
        }
    }
  }

  else(_) {
    fail
  }
}
