use cardano/assets.{
  ada_asset_name, ada_policy_id, add, from_asset, from_asset_list, from_lovelace,
}
use cardano/transaction.{Input, NoDatum, Output, Transaction, placeholder}
use config.{
  contract_treasury_asset_quantity, contract_treasury_lovelace_quantity,
  contract_treasury_marker_name, payout_asset_name, payout_asset_pid,
}
use empowa_swap
use env.{contract_address, contract_policy_id, user_address, utxo_def_ref}
use types.{Bootstrap}

// This section contains a set of tests covering all edge cases related to treasury UTXO creation.

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
          contract_treasury_asset_quantity,
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
        value: from_lovelace(contract_treasury_lovelace_quantity),
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
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace_quantity)],
          ),
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_asset_quantity)],
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
              [Pair(payout_asset_name, contract_treasury_asset_quantity)],
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
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace_quantity)],
          ),
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_asset_quantity)],
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
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace_quantity)],
          ),
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_asset_quantity)],
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
    redeemer: Bootstrap,
    contract_policy_id: contract_policy_id,
    tx: tx,
  )
}

test failed_bootstrap_random_asset_instead_marker_minted() fail {
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
          contract_treasury_asset_quantity,
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
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace_quantity)],
          ),
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_asset_quantity)],
          ), Pair(contract_policy_id, [Pair("wrong asset name", 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let mint_treasury_marker =
    from_asset(contract_policy_id, "wrong asset name", 1)

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1],
      outputs: [user_output, contract_output],
      mint: mint_treasury_marker,
    }

  empowa_swap.empowa_swap.mint(
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
          contract_treasury_asset_quantity,
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
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace_quantity)],
          ),
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_asset_quantity)],
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
          Pair(
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace_quantity)],
          ), Pair(payout_asset_pid, [Pair(payout_asset_name, 5_000)]),
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
    redeemer: Bootstrap,
    contract_policy_id: contract_policy_id,
    tx: tx,
  )
}

test failed_bootstrap_with_low_ada_amount() fail {
  // - AmountLock:
  //   - it's not allowed to create a treasury with less than `contract_treasury_lovelace_quantity` lovelaces;

  // If violated, any user could create a not valid treasury.

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
          Pair(
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace_quantity - 1)],
          ),
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_asset_quantity)],
          ),
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
          contract_treasury_asset_quantity,
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
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace_quantity)],
          ),
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_asset_quantity)],
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
          contract_treasury_asset_quantity,
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
    redeemer: Bootstrap,
    contract_policy_id: contract_policy_id,
    tx: tx,
  )
}
