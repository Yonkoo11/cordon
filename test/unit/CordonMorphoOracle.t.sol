// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IOracle} from "morpho-blue/interfaces/IOracle.sol";
import {CordonGuard} from "../../src/CordonGuard.sol";
import {CordonMorphoOracle} from "../../src/CordonMorphoOracle.sol";
import {IPaxosToken} from "../../src/interfaces/IPaxos.sol";
import {MockPaxosToken, MockSupplyControl, MockOracle, RevertingGuard} from "../mocks/MockPaxos.sol";

contract CordonMorphoOracleTest is Test {
    MockPaxosToken internal token;
    CordonGuard internal guard;
    CordonMorphoOracle internal oracle;
    address internal reporter = makeAddr("reporter");
    uint256 internal constant BASE_PRICE = 4.2e36;

    function setUp() public {
        vm.warp(1_760_000_000);
        MockSupplyControl sc = new MockSupplyControl(new address[](0));
        token = new MockPaxosToken(address(sc), 100e6);
        guard = new CordonGuard(IPaxosToken(address(token)), address(this), reporter, 2500, 1500, 1800, 7200, 62 days, 6 hours);
        oracle = new CordonMorphoOracle(IOracle(address(new MockOracle(BASE_PRICE))), guard, 5000);
        vm.prank(reporter);
        guard.postAttestation(uint64(block.timestamp), 1_000e6, 1_001e6, bytes32(0), "");
        guard.checkpoint();
        vm.warp(block.timestamp + 1801);
    }

    function test_priceUnchangedWhenHealthy() public view {
        assertEq(oracle.price(), BASE_PRICE);
    }

    function test_priceDiscountedWhenHalted() public {
        token.setSupply(300e6);
        assertEq(oracle.price(), BASE_PRICE / 2);
    }

    function test_neverRevertsWhenHalted() public {
        token.setSupply(type(uint96).max);
        oracle.price();
    }

    function test_cautionDoesNotTouchPrice() public {
        token.setSupply(116e6);
        assertEq(oracle.price(), BASE_PRICE);
    }

    function test_brokenGuardFallsBackToBasePrice() public {
        CordonMorphoOracle o = new CordonMorphoOracle(
            IOracle(address(new MockOracle(BASE_PRICE))), CordonGuard(address(new RevertingGuard())), 5000
        );
        assertEq(o.price(), BASE_PRICE);
    }
}
