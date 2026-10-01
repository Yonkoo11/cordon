// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {CordonGuard} from "../src/CordonGuard.sol";
import {IPaxosToken} from "../src/interfaces/IPaxos.sol";

/// @notice Deploys CordonGuard for the USDG token in env USDG_TOKEN, posts the attestation when
///         POST_ATTESTATION=true (mainnet only: the KPMG figures describe mainnet supply), and takes
///         the first baseline.
///         Key: env DEPLOYER_PRIVATE_KEY, never on the command line.
contract Deploy is Script {
    function run() external returns (CordonGuard guard) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        IPaxosToken token = IPaxosToken(vm.envAddress("USDG_TOKEN"));

        vm.startBroadcast(pk);
        guard = new CordonGuard(token, deployer, deployer, 2500, 1500, 1800, 7200, 62 days);
        if (vm.envOr("POST_ATTESTATION", false)) {
            guard.postAttestation(
                1_788_210_000,
                3_340_650_602e6,
                3_350_462_467e6,
                0x384778246b4b117dcf136733334532f60fbf9b1001d15b731348c9c22e96e37e,
                "https://framerusercontent.com/assets/Xn1UQwAte85FnsDveIMX0n1qtVM.pdf"
            );
        }
        guard.checkpoint();
        vm.stopBroadcast();

        console2.log("guard", address(guard));
    }
}
