use aiken/interval.{entirely_after, entirely_before}
use aiken/primitive/bytearray.{concat}
use cardano/address.{Address, VerificationKey}
use cardano/assets.{
  ada_asset_name, ada_policy_id, from_asset, from_asset_list, from_lovelace,
}
use cardano/transaction.{Input, NoDatum, Output, Transaction, placeholder}
use config.{contract_treasury_lovelace}
use empowa_swap.{Exchange}
use env.{
  burn_nft_name, burn_nft_pid, contract_address, contract_policy_id,
  contract_treasury_base_quantity, contract_treasury_marker_name,
  n2a_change_rate, owner_address, payout_asset_name, payout_asset_pid,
  start_change_time, unlock_unclaimed_assets_time, utxo_contract_ref,
  utxo_def_ref,
}

test succeed_exchange_treasury_part_consume() {
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [
              Pair(
                payout_asset_name,
                contract_treasury_base_quantity - n2a_change_rate * 3,
              ),
            ],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [user_output_1, user_output_0, contract_output],
      mint: nft_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test succeed_exchange_treasury_full_consume() {
  // What if the entire treasury is legitimately taken by the user?
  // Its marker should be burned, and the ADA should be sent to `owner_address`.
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              ada_policy_id,
              [Pair(ada_asset_name, contract_treasury_lovelace)],
            ), Pair(payout_asset_pid, [Pair(payout_asset_name, 3_300)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_and_marker_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
        Pair(contract_policy_id, [Pair(contract_treasury_marker_name, -1)]),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The owner takes back the treasury ada
  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(contract_treasury_lovelace),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [user_output_0, user_output_1, owner_output],
      mint: nft_and_marker_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test succeed_exchange_treasury_hybrid_consume() {
  // What if multiple treasury UTXOs were provided as inputs?
  // Was this justified, or is it an attempt to lock them just for fun?
  // Are they sufficient to cover the payout?
  // How many should remain afterwards?
  //
  // If multiple treasury UTXOs were used as inputs, it means one was not enough,
  // so at most one should remain as output (the others have been fully consumed).
  // There must be no "excess" treasury UTXOs among them.
  // Its marker should be burned, and the ADA should be sent to `owner_address`.
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input_0 =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              ada_policy_id,
              [Pair(ada_asset_name, contract_treasury_lovelace)],
            ), Pair(payout_asset_pid, [Pair(payout_asset_name, 1_000)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let contract_input_1 =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              ada_policy_id,
              [Pair(ada_asset_name, contract_treasury_lovelace)],
            ), Pair(payout_asset_pid, [Pair(payout_asset_name, 2_500)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_and_marker_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
        Pair(contract_policy_id, [Pair(contract_treasury_marker_name, -1)]),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The owner takes back the treasury ada
  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(contract_treasury_lovelace),
      datum: NoDatum,
      reference_script: None,
    }
  // The contract takes back the treasury remaining UTXO
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace)],
          ), Pair(payout_asset_pid, [Pair(payout_asset_name, 200)]),
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input_0, contract_input_1],
      outputs: [user_output_0, user_output_1, owner_output, contract_output],
      mint: nft_and_marker_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test succeed_exchange_extra_user_outputs() {
  // What if the transaction contains additional outputs to the users' addresses that provided the inputs?
  // This should not be a problem, since such behavior is normal for single-address wallets.
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )
  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate / 2,
      ),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_2 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate / 2,
      ),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_3 =
    Output {
      address: get_user_addr("1"),
      value: from_lovelace(10_000_000),
      datum: NoDatum,
      reference_script: None,
    }
  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [
              Pair(
                payout_asset_name,
                contract_treasury_base_quantity - n2a_change_rate * 3,
              ),
            ],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [
        user_output_0, user_output_1, contract_output, user_output_2,
        user_output_3,
      ],
      mint: nft_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test succeed_exchange_single_address_wallet() {
  // What if the transaction contains additional outputs to the users' addresses that provided the inputs?
  // This should not be a problem, since such behavior is normal for single-address wallets.
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )
  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 3,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  // let user_output_1 =
  //   Output {
  //     address: get_user_addr("0"),
  //     value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
  //     //^ 1 NFT from the second addr was burned
  //     datum: NoDatum,
  //     reference_script: None,
  //   }
  // let user_output_2 =
  //   Output {
  //     address: get_user_addr("1"),
  //     value: from_asset(
  //       payout_asset_pid,
  //       payout_asset_name,
  //       n2a_change_rate / 2,
  //     ),
  //     //^ 1 NFT from the second addr was burned
  //     datum: NoDatum,
  //     reference_script: None,
  //   }
  let user_output_3 =
    Output {
      address: get_user_addr("0"),
      value: from_lovelace(10_000_000),
      datum: NoDatum,
      reference_script: None,
    }
  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [
              Pair(
                payout_asset_name,
                contract_treasury_base_quantity - n2a_change_rate * 3,
              ),
            ],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [user_output_0, contract_output, user_output_3],
      mint: nft_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test failed_exchange_no_payouts() fail {
  // What if the user creates an "empty" transaction with no payouts in order to lock the treasury UTXO?
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_base_quantity)],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [contract_input],
      outputs: [contract_output],
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test failed_exchange_no_user_inputs() fail {
  // What if the user wants to get some funds from contract for free?
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The user expects to receive EMP according to the established exchange rate.
  let user_output =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [
              Pair(
                payout_asset_name,
                contract_treasury_base_quantity - n2a_change_rate,
              ),
            ],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [contract_input],
      outputs: [user_output, contract_output],
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test failed_exchange_no_nft() fail {
  // What if the user wants to get some funds from contract for free?
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let user_input =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_lovelace(10_000_000),
        datum: NoDatum,
        reference_script: None,
      },
    )
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The user expects to receive EMP according to the established exchange rate.
  let user_output =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [
              Pair(
                payout_asset_name,
                contract_treasury_base_quantity - n2a_change_rate,
              ),
            ],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input, contract_input],
      outputs: [user_output, contract_output],
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test failed_exchange_before_start_time() fail {
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [
              Pair(
                payout_asset_name,
                contract_treasury_base_quantity - n2a_change_rate * 3,
              ),
            ],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [user_output_0, user_output_1, contract_output],
      mint: nft_burning,
      validity_range: entirely_before(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test failed_exchange_treasury_full_consume_marker_not_burned() fail {
  // What if the marker wasn't burned? The user could obtain it.

  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              ada_policy_id,
              [Pair(ada_asset_name, contract_treasury_lovelace)],
            ), Pair(payout_asset_pid, [Pair(payout_asset_name, 3_300)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_and_marker_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_2 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(contract_policy_id, contract_treasury_marker_name, 1),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The owner takes back the treasury ada
  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(contract_treasury_lovelace),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [user_output_0, user_output_1, user_output_2, owner_output],
      mint: nft_and_marker_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test failed_exchange_treasury_hybrid_consume_split_contract_out() fail {
  // What if the user splits Contract's treasury rather than burn a consumed one?
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  //
  // What if multiple treasury UTXOs were provided as inputs?
  // Was this justified, or is it an attempt to lock them just for fun?
  // Are they sufficient to cover the payout?
  // How many should remain afterwards?
  //
  // If multiple treasury UTXOs were used as inputs, it means one was not enough,
  // so at most one should remain as output (the others have been fully consumed).
  // There must be no "excess" treasury UTXOs among them.
  // Its marker should be burned, and the ADA should be sent to `owner_address`.
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input_0 =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              ada_policy_id,
              [Pair(ada_asset_name, contract_treasury_lovelace)],
            ), Pair(payout_asset_pid, [Pair(payout_asset_name, 1_000)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let contract_input_1 =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              ada_policy_id,
              [Pair(ada_asset_name, contract_treasury_lovelace)],
            ), Pair(payout_asset_pid, [Pair(payout_asset_name, 2_500)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The owner takes back the treasury ada
  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(contract_treasury_lovelace),
      datum: NoDatum,
      reference_script: None,
    }
  // The contract takes back the splitted treasury remaining UTXO
  let contract_output_0 =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace)],
          ), Pair(payout_asset_pid, [Pair(payout_asset_name, 100)]),
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
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
            [Pair(ada_asset_name, contract_treasury_lovelace)],
          ), Pair(payout_asset_pid, [Pair(payout_asset_name, 100)]),
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input_0, contract_input_1],
      outputs: [
        user_output_0, user_output_1, owner_output, contract_output_0,
        contract_output_1,
      ],
      mint: nft_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test failed_exchange_treasury_hybrid_consume_redundant_treasury_input() fail {
  // What if multiple treasury UTXOs were provided as inputs?
  // Was this justified, or is it an attempt to lock them just for fun?
  // Are they sufficient to cover the payout?
  // How many should remain afterwards?
  //
  // If multiple treasury UTXOs were used as inputs, it means one was not enough,
  // so at most one should remain as output (the others have been fully consumed).
  // There must be no "excess" treasury UTXOs among them.
  // Its marker should be burned, and the ADA should be sent to `owner_address`.
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input_0 =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              ada_policy_id,
              [Pair(ada_asset_name, contract_treasury_lovelace)],
            ), Pair(payout_asset_pid, [Pair(payout_asset_name, 1_000)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let contract_input_1 =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              ada_policy_id,
              [Pair(ada_asset_name, contract_treasury_lovelace)],
            ), Pair(payout_asset_pid, [Pair(payout_asset_name, 2_500)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let contract_input_2 =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(
              ada_policy_id,
              [Pair(ada_asset_name, contract_treasury_lovelace)],
            ), Pair(payout_asset_pid, [Pair(payout_asset_name, 3_000)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_and_marker_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
        Pair(contract_policy_id, [Pair(contract_treasury_marker_name, -1)]),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The owner takes back the treasury ada
  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(contract_treasury_lovelace),
      datum: NoDatum,
      reference_script: None,
    }
  // The contract takes back the treasury remaining UTXO
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            ada_policy_id,
            [Pair(ada_asset_name, contract_treasury_lovelace)],
          ), Pair(payout_asset_pid, [Pair(payout_asset_name, 3_200)]),
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [
        user_input_0, user_input_1, contract_input_0, contract_input_1,
        contract_input_2,
      ],
      outputs: [user_output_0, user_output_1, owner_output, contract_output],
      mint: nft_and_marker_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test failed_exchange_with_wrong_nft() fail {
  // What if the user tries to exchange an NFT with the wrong name? (e.g., "Empowa v1.1" instead of "Empowa v1.2")
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
                Pair(concat("Wrong NFT name", "01"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
            Pair(concat("Wrong NFT name", "01"), -1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [
              Pair(
                payout_asset_name,
                contract_treasury_base_quantity - n2a_change_rate * 3,
              ),
            ],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [user_output_0, user_output_1, contract_output],
      mint: nft_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test failed_exchange_illegal_minting_attempt() fail {
  // If we sign the minting transaction, the user could try to mint some free NFTs...
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
            Pair(concat(burn_nft_name, "07"), 1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset_list(
        [
          Pair(burn_nft_pid, [Pair(concat(burn_nft_name, "02"), 1)]),
          Pair("any_another_nft", [Pair("any_asset", 10)]),
          Pair(payout_asset_pid, [Pair(payout_asset_name, n2a_change_rate * 2)]),
        ],
      ),
      //^ 2 NFTs from the first addr were burned, payout tokens were added
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset_list(
        [
          Pair(
            burn_nft_pid,
            [
              Pair(concat(burn_nft_name, "04"), 1),
              Pair(concat(burn_nft_name, "05"), 1),
              Pair(concat(burn_nft_name, "07"), 1),
            ],
          ),
          Pair("any_another_nft", [Pair("any_asset", 10)]),
          Pair(payout_asset_pid, [Pair(payout_asset_name, n2a_change_rate)]),
        ],
      ),
      //^ 1 NFT from the second addr was burned, and one more MINTED(!)
      datum: NoDatum,
      reference_script: None,
    }

  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [
              Pair(
                payout_asset_name,
                contract_treasury_base_quantity - n2a_change_rate * 3,
              ),
            ],
          ),
          // ^ 3 NFTs were burned; the treasury balance was reduced accordingly.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [user_output_0, user_output_1, contract_output],
      mint: nft_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}

test failed_exchange_treasury_full_consume_ada_stealing() fail {
  // What if the entire treasury is legitimately taken by the user?
  // Its marker should be burned, and the ADA should be sent to `owner_address`.
  // But what if the user takes it as their change?
  //
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
      Output {
        address: contract_address,
        value: from_asset_list(
          [
            Pair(ada_policy_id, [Pair(ada_asset_name, 5_000_000)]),
            Pair(payout_asset_pid, [Pair(payout_asset_name, 3_300)]),
            Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_and_marker_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
        Pair(contract_policy_id, [Pair(contract_treasury_marker_name, -1)]),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_2 =
    Output {
      address: get_user_addr("1"),
      value: from_lovelace(4_000_000),
      //^ 4ADA stealed
      datum: NoDatum,
      reference_script: None,
    }

  // The owner takes back the treasury ada (reduced by user)
  let owner_output =
    Output {
      address: owner_address,
      value: from_lovelace(1_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [user_output_0, user_output_1, user_output_2, owner_output],
      mint: nft_and_marker_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  and {
    empowa_swap.empowa_swap.spend(
      //datum
      None,
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_utxo: utxo_contract_ref,
      tx: tx,
    ),
    empowa_swap.empowa_swap.mint(
      payout_asset_pid: payout_asset_pid,
      payout_asset_name: payout_asset_name,
      burn_nft_pid: burn_nft_pid,
      burn_nft_name: burn_nft_name,
      n2a_change_rate: n2a_change_rate,
      start_change_time: start_change_time,
      unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
      owner_address: owner_address,
      redeemer: Exchange,
      contract_policy_id: contract_policy_id,
      tx: tx,
    ),
  }
}

test failed_exchange_fake_payout() fail {
  // What if the user's outputs contain only their own EMP, but in the correct total amount?
  // The user provides their own UTXOs as inputs, some of which contain assets with names starting with `burn_nft_pid.burn_nft_name*`.
  let user_input_0 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("0"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "01"), 1),
                Pair(concat(burn_nft_name, "02"), 1),
                Pair(concat(burn_nft_name, "03"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
            Pair(
              payout_asset_pid,
              [Pair(payout_asset_name, n2a_change_rate * 3)],
            ),
          ],
        ),
        //^ user already have some payout asset
        datum: NoDatum,
        reference_script: None,
      },
    )

  let user_input_1 =
    Input(
      utxo_def_ref,
      Output {
        address: get_user_addr("1"),
        value: from_asset_list(
          [
            Pair(
              burn_nft_pid,
              [
                Pair(concat(burn_nft_name, "04"), 1),
                Pair(concat(burn_nft_name, "05"), 1),
                Pair(concat(burn_nft_name, "06"), 1),
              ],
            ),
            Pair("any_another_nft", [Pair("any_asset", 10)]),
          ],
        ),
        datum: NoDatum,
        reference_script: None,
      },
    )

  // The contract provides its own UTXOs as inputs, containing enough EMP to cover the user's payouts.
  let contract_input =
    Input(
      utxo_contract_ref,
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

  // The user requests to burn some of their NFTs (not necessarily all of them).
  let nft_burning =
    from_asset_list(
      [
        Pair(
          burn_nft_pid,
          [
            Pair(concat(burn_nft_name, "01"), -1),
            Pair(concat(burn_nft_name, "03"), -1),
            Pair(concat(burn_nft_name, "06"), -1),
          ],
        ),
      ],
    )

  // The user expects to receive EMP according to the established exchange rate.
  let user_output_0 =
    Output {
      address: get_user_addr("0"),
      value: from_asset(
        payout_asset_pid,
        payout_asset_name,
        n2a_change_rate * 2,
      ),
      //^ 2 NFTs from the first addr were burned
      datum: NoDatum,
      reference_script: None,
    }

  let user_output_1 =
    Output {
      address: get_user_addr("1"),
      value: from_asset(payout_asset_pid, payout_asset_name, n2a_change_rate),
      //^ 1 NFT from the second addr was burned
      datum: NoDatum,
      reference_script: None,
    }

  // The contract expects the change (leftover EMP) to be returned to a treasury UTXO, marked with a treasury marker.
  let contract_output =
    Output {
      address: contract_address,
      value: from_asset_list(
        [
          Pair(
            payout_asset_pid,
            [Pair(payout_asset_name, contract_treasury_base_quantity)],
          ),
          // ^ 3 NFTs were burned; But the treasury balance was not reduced accordingly. User got their own asset back.
          Pair(contract_policy_id, [Pair(contract_treasury_marker_name, 1)]),
        ],
      ),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      inputs: [user_input_0, user_input_1, contract_input],
      outputs: [user_output_0, user_output_1, contract_output],
      mint: nft_burning,
      validity_range: entirely_after(start_change_time),
    }

  // The transaction invokes both the `mint()` and `spend()` subvalidators.
  empowa_swap.empowa_swap.spend(
    //datum
    None,
    payout_asset_pid: payout_asset_pid,
    payout_asset_name: payout_asset_name,
    burn_nft_pid: burn_nft_pid,
    burn_nft_name: burn_nft_name,
    n2a_change_rate: n2a_change_rate,
    start_change_time: start_change_time,
    unlock_unclaimed_assets_time: unlock_unclaimed_assets_time,
    owner_address: owner_address,
    redeemer: Exchange,
    contract_utxo: utxo_contract_ref,
    tx: tx,
  )
}
