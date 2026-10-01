// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CordonGuard} from "../../src/CordonGuard.sol";
import {IPaxosToken} from "../../src/interfaces/IPaxos.sol";
import {MockPaxosToken, MockSupplyControl} from "../mocks/MockPaxos.sol";

/// @notice Symbolic proofs, run with `halmos --match-contract CordonGuardHalmos`. Each `check_`
///         holds for every value of its arguments, not a sample of them.
contract CordonGuardHalmos is Test {
    MockPaxosToken internal token;
    CordonGuard internal guard;
    address internal owner = address(0x0A11);
    address internal reporter = address(0x0B22);
    uint256 internal constant BASE = 100e6;

    function setUp() public {
        vm.warp(1_760_000_000);
        address[] memory c = new address[](1);
        c[0] = address(0xA);
        MockSupplyControl sc = new MockSupplyControl(c);
        token = new MockPaxosToken(address(sc), BASE);
        guard = new CordonGuard(IPaxosToken(address(token)), owner, reporter, 2500, 1500, 1800, 7200, 62 days, 6 hours);
        guard.checkpoint();
        vm.warp(block.timestamp + 1801);
    }

    /// No figure the reporter can post makes the guard halt.
    function check_reporterNeverHalts(uint64 periodEnd, uint256 outstanding, uint256 reserves) public {
        vm.assume(periodEnd > 0 && periodEnd <= block.timestamp);
        vm.prank(reporter);
        guard.postAttestation(periodEnd, outstanding, reserves, bytes32(0), "");
        assert(!guard.isHalted());
    }

    /// No owner action makes the guard halt.
    function check_ownerNeverHalts(uint8 op, address who) public {
        vm.startPrank(owner);
        if (op % 4 == 0) guard.recordControllers();
        else if (op % 4 == 1 && who != address(0)) guard.setReporter(who);
        else if (op % 4 == 2) guard.transferOwnership(who);
        vm.stopPrank();
        assert(!guard.isHalted());
    }

    /// With one baseline, HALT is exactly "supply more than 25% above it".
    function check_haltIffMoreThan25Pct(uint128 supply) public {
        token.setSupply(supply);
        assert(guard.isHalted() == (uint256(supply) * 10_000 > BASE * 12_500));
    }

    /// A latched jump is released only after 6 h of notice and only if supply did not grow.
    function check_releaseNeedsNoticeAndNoGrowth(uint128 jump, uint32 dt, uint128 later) public {
        vm.assume(uint256(jump) * 10_000 > BASE * 12_500);
        token.setSupply(jump);
        guard.checkpoint();
        assert(guard.latchedBaseline() == BASE);
        vm.prank(owner);
        guard.scheduleRelease();
        vm.warp(block.timestamp + dt);
        token.setSupply(later);
        vm.prank(owner);
        try guard.executeRelease() {
            assert(dt >= 6 hours);
            assert(later <= jump);
            assert(guard.latchedBaseline() == 0);
        } catch {
            assert(guard.latchedBaseline() == BASE);
        }
    }

    /// A latch survives any checkpoint that does not bring supply back within 25% of the pre-jump level.
    function check_latchClearsOnlyOnBurn(uint128 jump, uint128 later) public {
        vm.assume(uint256(jump) * 10_000 > BASE * 12_500);
        token.setSupply(jump);
        guard.checkpoint();
        vm.warp(block.timestamp + 1801);
        token.setSupply(later);
        guard.checkpoint();
        assert((guard.latchedBaseline() == 0) == (uint256(later) * 10_000 <= BASE * 12_500));
    }
}
