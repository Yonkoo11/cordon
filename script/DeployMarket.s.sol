// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IMorpho, MarketParams} from "morpho-blue/interfaces/IMorpho.sol";
import {IOracle} from "morpho-blue/interfaces/IOracle.sol";
import {CordonOracleFactory} from "../src/CordonOracleFactory.sol";
import {CordonMorphoOracle} from "../src/CordonMorphoOracle.sol";

/// @notice Robinhood Chain mainnet: wraps the oracle of a live USDG-collateral NVDA market through
///         the factory in env CORDON_FACTORY and creates the same market (same IRM, same LLTV) using the wrapper.
contract DeployMarket is Script {
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address internal constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address internal constant MORPHO = 0x9D53d5E3bd5E8d4Cbfa6DB1ca238AEA02E651010;
    address internal constant IRM = 0x2BD3d5965B26B51814AC95127B2b80dD6CcC0fa1;
    address internal constant LIVE_NVDA_ORACLE = 0x548196c5A7D2127Ae69FBc69e2fEd9686Fdd7A10;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        CordonOracleFactory factory = CordonOracleFactory(vm.envAddress("CORDON_FACTORY"));
        vm.startBroadcast(pk);
        CordonMorphoOracle oracle = factory.create(IOracle(LIVE_NVDA_ORACLE), 5000);
        MarketParams memory m = MarketParams(NVDA, USDG, address(oracle), IRM, 0.625e18);
        IMorpho(MORPHO).createMarket(m);
        vm.stopBroadcast();
        console2.log("oracle", address(oracle));
        console2.logBytes32(keccak256(abi.encode(m)));
    }
}
