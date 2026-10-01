// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {CordonGuard} from "../src/CordonGuard.sol";

/// @notice Records a supply baseline on the guard in env CORDON_GUARD. Anyone may call checkpoint().
contract Checkpoint is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        CordonGuard(vm.envAddress("CORDON_GUARD")).checkpoint();
        vm.stopBroadcast();
    }
}
