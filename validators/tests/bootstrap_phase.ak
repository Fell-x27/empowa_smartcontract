use cardano/assets.{add, from_asset, from_asset_list, from_lovelace}
use cardano/transaction.{Input, NoDatum, Output, Transaction, placeholder}
use empowa_swap.{Bootstrap}
use env.{
  burn_nft_name, burn_nft_pid, contract_address, contract_policy_id,
  contract_treasury_base_quantity, contract_treasury_marker_name,
  n2a_change_rate, owner_address, payout_asset_name, payout_asset_pid,
  start_change_time, unlock_unclaimed_assets_time, user_address, utxo_def_ref,
}

// This section contains a set of tests covering all edge cases related to treasury UTXO creation.
// TODO: what if something other than marker is minted, or marker is burned?

test succeed_bootstrap() {
  // Treasury formation (sending assets, minting the marker token):
  // - Redeemer: Bootstrap.
  // - Inputs:
  //   - ensure that `contract_policy_id.contract_treasury_marker_name` is not present in any input (it may only be minted);
  // - Outputs:
  //   - verify that N EMP are sent to the contract_ address along with the `contract_policy_id.contract_treasury_marker_name` asset;
  // - Minting:
  //   - ensure that exactly 1 `contract_treasury_marker_name` was minted;
  // - AmountLock:
  //   - it's not allowed to create a treasury with less than 10,000 EMP.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_asset(
          payout_asset_pid,
          payout_asset_name,
          contract_treasury_base_quantity,
        ),
        //^Actually, we don't check this value, but it is present for clarity.
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_lovelace(5_000_000),
        //^Actually, we don't check this value, but it is present for clarity.
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_output =
    Output {
      address: user_address,
      value: from_lovelace(2_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_base_quantity)],
          ), Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let mint_treasury_marker =
    from_asset(contract_policy_id, contract_treasury_marker_name, 1)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1],
      outputs: [user_output, contract_output],
      mint: mint_treasury_marker,
    }

  empowa_swap.empowa_swap.mint(
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Bootstrap,
    contract_policy_id: contract_policy_id,
    tx: tx,
  )
}

test failed_bootstrap_wrong_inputs() fail {
  // - Inputs:
  //   - ensure that `contract_policy_id.contract_treasury_marker_name` is not present in any input (it may only be minted);

  // Can only be violated by splitting a treasury UTXO via input.

  let contract_input =
    Input(
      utxo_def_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              payout_asset_pid,
              [Pair(payout_asset_name, contract_treasury_base_quantity)],
            ),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_lovelace(5_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_output =
    Output {
      address: user_address,
      value: from_lovelace(2_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let contract_output_0 =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_base_quantity)],
          ), Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let contract_output_1 =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_base_quantity)],
          ), Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let mint_treasury_marker =
    from_asset(contract_policy_id, contract_treasury_marker_name, 1)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [contract_input, user_input],
      outputs: [user_output, contract_output_0, contract_output_1],
      mint: mint_treasury_marker,
    }

  empowa_swap.empowa_swap.mint(
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Bootstrap,
    contract_policy_id: contract_policy_id,
    tx: tx,
  )
}

test failed_bootstrap_treasury_marker_stealing() fail {
  // - AmountLock:
  //   - it's not allowed to create a treasury with `contract_policy_id.contract_treasury_marker_name` != 1 .

  // If violated, a user could steal the treasury marker and misuse it.
  // Also protects against the case when a user forgets to add the marker to the script output.

  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_asset(
          payout_asset_pid,
          payout_asset_name,
          contract_treasury_base_quantity,
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_lovelace(5_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_output =
    Output {
      address: user_address,
      value: from_lovelace(2_000_000)
        |> add(contract_policy_id, contract_treasury_marker_name, 1),
      datum: NoDatum,
      reference_script: None,
    }

  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_base_quantity)],
          ),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let mint_treasury_marker =
    from_asset(contract_policy_id, contract_treasury_marker_name, 1)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1],
      outputs: [user_output, contract_output],
      mint: mint_treasury_marker,
    }

  empowa_swap.empowa_swap.mint(
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Bootstrap,
    contract_policy_id: contract_policy_id,
    tx: tx,
  )
}

test failed_bootstrap_with_low_treasury_amount() fail {
  // - AmountLock:
  //   - it's not allowed to create a treasury with less than 10,000 EMP;

  // If violated, any user could perform a Sybil attack.

  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_asset(payout_asset_pid, payout_asset_name, 5_000),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_lovelace(5_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_output =
    Output {
      address: user_address,
      value: from_lovelace(2_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(payout_asset_pid, [Pair(payout_asset_name, 5_000)]),
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let mint_treasury_marker =
    from_asset(contract_policy_id, contract_treasury_marker_name, 1)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1],
      outputs: [user_output, contract_output],
      mint: mint_treasury_marker,
    }

  empowa_swap.empowa_swap.mint(
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Bootstrap,
    contract_policy_id: contract_policy_id,
    tx: tx,
  )
}

test failed_bootstrap_treasury_marker_overmint() fail {
  // - Minting:
  //   - ensure that exactly 1 `contract_policy_id.contract_treasury_marker_name` per contract_output was minted;

  // If violated, a user could steal the treasury marker and misuse it.
  // Also prevents accidental overminting of markers.

  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_asset(
          payout_asset_pid,
          payout_asset_name,
          contract_treasury_base_quantity,
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_lovelace(5_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_output =
    Output {
      address: user_address,
      value: from_lovelace(2_000_000)
        |> add(contract_policy_id, contract_treasury_marker_name, 1),
      datum: NoDatum,
      reference_script: None,
    }

  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_base_quantity)],
          ), Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let mint_treasury_marker =
    from_asset(contract_policy_id, contract_treasury_marker_name, 2)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1],
      outputs: [user_output, contract_output],
      mint: mint_treasury_marker,
    }

  empowa_swap.empowa_swap.mint(
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Bootstrap,
    contract_policy_id: contract_policy_id,
    tx: tx,
  )
}

test failed_bootstrap_wrong_contract_outputs() fail {
  // - Outputs:
  //   - verify that N EMP are sent to the contract_ address along with the `contract_policy_id.contract_treasury_marker_name` asset;
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_asset(
          payout_asset_pid,
          payout_asset_name,
          contract_treasury_base_quantity,
        ),
        //^Actually, we don't check this value, but it is present for clarity.
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: user_address,
        value: from_lovelace(5_000_000),
        //^Actually, we don't check this value, but it is present for clarity.
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_output =
    Output {
      address: user_address,
      value: from_lovelace(5_000_000)
        |> add(contract_policy_id, contract_treasury_marker_name, 1),
      datum: NoDatum,
      reference_script: None,
    }

  let mint_treasury_marker =
    from_asset(contract_policy_id, contract_treasury_marker_name, 1)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1],
      outputs: [user_output],
      mint: mint_treasury_marker,
    }

  empowa_swap.empowa_swap.mint(
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Bootstrap,
    contract_policy_id: contract_policy_id,
    tx: tx,
  )
}
