// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BackedGuard} from "../../src/BackedGuard.sol";
import {IPaxosToken} from "../../src/interfaces/IPaxos.sol";
import {MockPaxosToken, MockSupplyControl} from "../mocks/MockPaxos.sol";

contract BackedGuardTest is Test {
    MockPaxosToken internal token;
    MockSupplyControl internal sc;
    BackedGuard internal guard;
    address internal owner = makeAddr("owner");
    address internal reporter = makeAddr("reporter");
    uint256 internal constant BASE = 100e6;

    function setUp() public {
        vm.warp(1_760_000_000);
        address[] memory c = new address[](2);
        c[0] = address(0xA);
        c[1] = address(0xB);
        sc = new MockSupplyControl(c);
        token = new MockPaxosToken(address(sc), BASE);
        guard = new BackedGuard(IPaxosToken(address(token)), owner, reporter, 2500, 1500, 1800, 7200, 62 days);
    }

    function _attest(uint64 periodEnd, uint256 outstanding, uint256 reserves) internal {
        vm.prank(reporter);
        guard.postAttestation(periodEnd, outstanding, reserves, keccak256("report"), "ipfs://report");
    }

    /// @dev A fresh attestation and an in-band baseline: the guard's normal day.
    function _healthy() internal {
        _attest(uint64(block.timestamp - 1 days), 1_000e6, 1_001e6);
        guard.checkpoint();
        vm.warp(block.timestamp + 1801);
    }

    function test_healthyWhenNothingChanged() public {
        _healthy();
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 0);
        assertEq(reasons, 0);
    }

    function test_noBaselineIsCautionNeverHalt() public {
        _attest(uint64(block.timestamp - 1 days), 1_000e6, 1_001e6);
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertTrue(reasons & guard.NO_BASELINE() != 0);
        assertFalse(guard.isHalted());
    }

    function test_jumpOver25PctHalts() public {
        _healthy();
        token.setSupply(125.000001e6);
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 2);
        assertTrue(reasons & guard.SUPPLY_JUMP_HALT() != 0);
    }

    function test_exactly25PctIsNotHalt() public {
        _healthy();
        token.setSupply(125e6);
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertTrue(reasons & guard.SUPPLY_JUMP_CAUTION() != 0);
    }

    function test_jump15To25PctCautions() public {
        _healthy();
        token.setSupply(116e6);
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertEq(reasons, guard.SUPPLY_JUMP_CAUTION());
    }

    function test_baselineOlderThan2hIsIgnored() public {
        _healthy();
        vm.warp(block.timestamp + 7200);
        token.setSupply(200e6);
        (, uint256 reasons) = guard.status();
        assertTrue(reasons & guard.NO_BASELINE() != 0);
        assertEq(reasons & (guard.SUPPLY_JUMP_HALT() | guard.SUPPLY_JUMP_CAUTION()), 0);
    }

    function test_checkpointTooSoonReverts() public {
        guard.checkpoint();
        vm.warp(block.timestamp + 1799);
        vm.expectRevert();
        guard.checkpoint();
    }

    function test_jumpLatchSurvivesBaselineRotation() public {
        _healthy();
        token.setSupply(300e6);
        guard.checkpoint(); // sees the jump, latches it
        assertEq(guard.latchedBaseline(), BASE);
        vm.warp(block.timestamp + 1801);
        guard.checkpoint(); // both slots now hold the inflated supply
        vm.warp(block.timestamp + 1801);
        assertTrue(guard.isHalted(), "latched jump must survive rotation");
    }

    function test_latchClearsWhenExcessBurned() public {
        _healthy();
        token.setSupply(300e6);
        guard.checkpoint();
        token.setSupply(BASE); // issuer burns the excess, as Paxos did with PYUSD
        vm.warp(block.timestamp + 1801);
        guard.checkpoint();
        assertEq(guard.latchedBaseline(), 0);
    }

    function test_minterSetChangeCautions() public {
        _healthy();
        sc.addController(address(0xC));
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertEq(reasons, guard.MINTER_SET_CHANGED());
    }

    function test_recordControllersAcceptsNewSet() public {
        _healthy();
        sc.addController(address(0xC));
        vm.prank(owner);
        guard.recordControllers();
        (, uint256 reasons) = guard.status();
        assertEq(reasons, 0);
    }

    function test_pendingAdminCautions() public {
        _healthy();
        token.setPendingAdmin(address(0xD));
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertEq(reasons, guard.ADMIN_TRANSFER_PENDING());
    }

    function test_pendingAdminOnSupplyControlCautions() public {
        _healthy();
        sc.setPendingAdmin(address(0xD));
        (, uint256 reasons) = guard.status();
        assertEq(reasons, guard.ADMIN_TRANSFER_PENDING());
    }

    function test_reservesBelowOutstandingHalts() public {
        _healthy();
        _attest(uint64(block.timestamp), 1_000e6, 999e6);
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 2);
        assertTrue(reasons & guard.RESERVES_BELOW_OUTSTANDING() != 0);
    }

    function test_staleAttestationCautions() public {
        _healthy();
        vm.warp(block.timestamp + 62 days);
        guard.checkpoint();
        vm.warp(block.timestamp + 1801);
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertEq(reasons, guard.ATTESTATION_STALE());
    }

    function test_noAttestationIsStale() public {
        guard.checkpoint();
        vm.warp(block.timestamp + 1801);
        (, uint256 reasons) = guard.status();
        assertEq(reasons, guard.ATTESTATION_STALE());
    }

    function test_supplyAboveAttestedTotalHalts() public {
        _healthy();
        _attest(uint64(block.timestamp), 90e6, 91e6);
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 2);
        assertTrue(reasons & guard.SUPPLY_ABOVE_ATTESTED_TOTAL() != 0);
    }

    function test_onlyReporterPosts() public {
        vm.expectRevert(BackedGuard.NotReporter.selector);
        guard.postAttestation(1, 1, 1, bytes32(0), "");
    }

    function test_periodMustIncrease() public {
        _attest(100, 1, 1);
        vm.prank(reporter);
        vm.expectRevert(abi.encodeWithSelector(BackedGuard.PeriodNotIncreasing.selector, 100, 100));
        guard.postAttestation(100, 1, 1, bytes32(0), "");
    }

    function test_reporterCannotClearTrustlessHalt() public {
        _healthy();
        token.setSupply(300e6);
        _attest(uint64(block.timestamp), 10_000e6, 10_001e6);
        assertTrue(guard.isHalted());
    }

    function test_onlyOwnerAdmin() public {
        vm.expectRevert(BackedGuard.NotOwner.selector);
        guard.recordControllers();
        vm.expectRevert(BackedGuard.NotOwner.selector);
        guard.setReporter(address(1));
    }

    function test_constructorRejectsBadParams() public {
        vm.expectRevert(BackedGuard.BadParams.selector);
        new BackedGuard(IPaxosToken(address(token)), owner, reporter, 1500, 2500, 1800, 7200, 62 days);
        vm.expectRevert(BackedGuard.ZeroAddress.selector);
        new BackedGuard(IPaxosToken(address(token)), address(0), reporter, 2500, 1500, 1800, 7200, 62 days);
    }

    /// forge-config: default.fuzz.runs = 2000
    function testFuzz_haltOnlyWithHaltReason(uint96 supply, uint96 reserves, uint96 outstanding, uint32 dt) public {
        _attest(uint64(block.timestamp), uint256(outstanding) + 1, reserves);
        guard.checkpoint();
        vm.warp(block.timestamp + dt);
        token.setSupply(supply);
        (BackedGuard.Level level, uint256 reasons) = guard.status();
        assertEq(level == BackedGuard.Level.HALT, reasons & guard.HALT_MASK() != 0);
        assertEq(level == BackedGuard.Level.HEALTHY, reasons == 0);
    }
}
