// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Shared logging infrastructure for the script bases: an `isLogging` flag that defaults
/// to on, the `_log` helper every script routes its terminal output through, and the public
/// `disableLogging` affordance a test calls to keep a script run out of its output.
abstract contract LoggedScript is Script {
  bool internal isLogging = true;

  function disableLogging() public {
    isLogging = false;
  }

  function _log(string memory _msg) internal view {
    if (isLogging) {
      console2.log(_msg);
    }
  }
}
