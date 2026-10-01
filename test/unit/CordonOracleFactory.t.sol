// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IOracle} from "morpho-blue/interfaces/IOracle.sol";
import {CordonGuard} from "../../src/CordonGuard.sol";
import {CordonMorphoOracle} from "../../src/CordonMorphoOracle.sol";
import {CordonOracleFactory} from "../../src/CordonOracleFactory.sol";
import {IPaxosToken} from "../../src/interfaces/IPaxos.sol";
import {MockPaxosToken, MockSupplyControl, MockOracle} from "../mocks/MockPaxos.sol";

contract CordonOracleFactoryTest is Test {
    CordonGuard internal guard;
    CordonOracleFactory internal factory;
    IOracle internal base;

    function setUp() public {
        address[] memory c = new address[](1);
        c[0] = address(0xA);
        MockSupplyControl sc = new MockSupplyControl(c);
        MockPaxosToken token = new MockPaxosToken(address(sc), 100e6);
        guard = new CordonGuard(IPaxosToken(address(token)), address(this), address(this), 2500, 1500, 1800, 7200, 62 days, 6 hours);
        factory = new CordonOracleFactory(guard);
        base = IOracle(address(new MockOracle(1e36)));
    }

    function test_createDeploysAtPredictedAddress() public {
        address predicted = factory.predict(base, 2000);
        CordonMorphoOracle w = factory.create(base, 2000);
        assertEq(address(w), predicted);
        assertEq(address(w.baseOracle()), address(base));
        assertEq(address(w.guard()), address(guard));
        assertEq(w.haltDiscountBps(), 2000);
        assertEq(w.price(), 1e36);
    }

    function test_createIsIdempotent() public {
        CordonMorphoOracle a = factory.create(base, 2000);
        CordonMorphoOracle b = factory.create(base, 2000);
        assertEq(address(a), address(b));
        assertTrue(address(factory.create(base, 3000)) != address(a));
    }

    function test_rejectsBadInputs() public {
        vm.expectRevert(CordonOracleFactory.BadDiscount.selector);
        factory.create(base, 0);
        vm.expectRevert(CordonOracleFactory.BadDiscount.selector);
        factory.create(base, 5001);
        vm.expectRevert(CordonOracleFactory.ZeroAddress.selector);
        factory.create(IOracle(address(0)), 2000);
    }
}
