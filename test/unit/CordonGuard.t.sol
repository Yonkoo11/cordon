// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CordonGuard} from "../../src/CordonGuard.sol";
import {IPaxosToken} from "../../src/interfaces/IPaxos.sol";
import {MockPaxosToken, MockSupplyControl} from "../mocks/MockPaxos.sol";

contract CordonGuardTest is Test {
    MockPaxosToken internal token;
    MockSupplyControl internal sc;
    CordonGuard internal guard;
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
        guard = new CordonGuard(IPaxosToken(address(token)), owner, reporter, 2500, 1500, 1800, 7200, 62 days, 6 hours);
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
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 0);
        assertEq(reasons, 0);
    }

    function test_noBaselineIsCautionNeverHalt() public {
        _attest(uint64(block.timestamp - 1 days), 1_000e6, 1_001e6);
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertTrue(reasons & guard.NO_BASELINE() != 0);
        assertFalse(guard.isHalted());
    }

    function test_jumpOver25PctHalts() public {
        _healthy();
        token.setSupply(125.000001e6);
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 2);
        assertTrue(reasons & guard.SUPPLY_JUMP_HALT() != 0);
    }

    function test_exactly25PctIsNotHalt() public {
        _healthy();
        token.setSupply(125e6);
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertTrue(reasons & guard.SUPPLY_JUMP_CAUTION() != 0);
    }

    function test_jump15To25PctCautions() public {
        _healthy();
        token.setSupply(116e6);
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertEq(reasons, guard.SUPPLY_JUMP_CAUTION());
    }

    /// @dev The fast baseline expires after 2 h, but the daily anchor still catches the jump, so a
    ///      gap in checkpoints cannot be used to absorb a mint.
    function test_jumpAfterCheckpointGapStillHalts() public {
        _healthy();
        vm.warp(block.timestamp + 7200);
        token.setSupply(200e6);
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 2);
        assertTrue(reasons & guard.NO_BASELINE() != 0);
        assertTrue(reasons & guard.SUPPLY_JUMP_HALT() != 0);
        guard.checkpoint(); // checkpointing the inflated supply latches it instead of absorbing it
        assertEq(guard.latchedBaseline(), BASE);
    }

    function test_anchorOlderThan2DaysIsIgnored() public {
        _healthy();
        vm.warp(block.timestamp + 2 days + 1);
        token.setSupply(200e6);
        (, uint256 reasons) = guard.status();
        assertTrue(reasons & guard.NO_BASELINE() != 0);
        assertEq(reasons & (guard.SUPPLY_JUMP_HALT() | guard.SUPPLY_JUMP_CAUTION()), 0);
    }

    /// @dev Review finding: many sub-25% mints, each checkpointed, walked the fast baseline up
    ///      without limit. The anchor moves at most once a day, so the walk halts within a day.
    function test_slowOverMintHaltsOnAnchor() public {
        _healthy();
        uint256 supply = BASE;
        bool halted;
        for (uint256 i; i < 48 && !halted; ++i) {
            supply = supply * 124 / 100;
            token.setSupply(supply);
            guard.checkpoint();
            halted = guard.isHalted();
            vm.warp(block.timestamp + 1801);
        }
        assertTrue(halted, "a 24%-per-half-hour walk must halt");
        assertLe(supply, BASE * 2, "halts within the first doubling");
    }

    function test_isHaltedIgnoresUnrelatedReadFailure() public {
        _healthy();
        token.setSupply(300e6);
        vm.mockCallRevert(address(sc), abi.encodeWithSignature("getAllSupplyControllerAddresses()"), "");
        assertTrue(guard.isHalted());
    }

    function test_futurePeriodRejected() public {
        vm.prank(reporter);
        vm.expectRevert(abi.encodeWithSelector(CordonGuard.PeriodInFuture.selector, uint64(block.timestamp + 1)));
        guard.postAttestation(uint64(block.timestamp + 1), 1, 1, bytes32(0), "");
    }

    function test_pendingOwnerCanBeCancelled() public {
        vm.startPrank(owner);
        guard.transferOwnership(address(0xCAFE));
        guard.transferOwnership(address(0));
        vm.stopPrank();
        vm.prank(address(0xCAFE));
        vm.expectRevert(CordonGuard.NotPendingOwner.selector);
        guard.acceptOwnership();
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
        guard.checkpoint(); // latched: the inflated supply is not recorded as a reference
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
        (CordonGuard.Level level, uint256 reasons) = guard.status();
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
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertEq(reasons, guard.ADMIN_TRANSFER_PENDING());
    }

    function test_pendingAdminOnSupplyControlCautions() public {
        _healthy();
        sc.setPendingAdmin(address(0xD));
        (, uint256 reasons) = guard.status();
        assertEq(reasons, guard.ADMIN_TRANSFER_PENDING());
    }

    /// @dev Reported figures come from the reporter's key, so they stop at CAUTION.
    function test_reservesBelowOutstandingCautions() public {
        _healthy();
        _attest(uint64(block.timestamp), 1_000e6, 999e6);
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertTrue(reasons & guard.RESERVES_BELOW_OUTSTANDING() != 0);
    }

    function test_staleAttestationCautions() public {
        _healthy();
        vm.warp(block.timestamp + 62 days);
        guard.checkpoint();
        vm.warp(block.timestamp + 1801);
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertEq(reasons, guard.ATTESTATION_STALE());
    }

    function test_noAttestationIsStale() public {
        guard.checkpoint();
        vm.warp(block.timestamp + 1801);
        (, uint256 reasons) = guard.status();
        assertEq(reasons, guard.ATTESTATION_STALE());
    }

    function test_supplyAboveAttestedTotalCautions() public {
        _healthy();
        _attest(uint64(block.timestamp), 90e6, 91e6);
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 1);
        assertTrue(reasons & guard.SUPPLY_ABOVE_ATTESTED_TOTAL() != 0);
    }

    function test_onlyReporterPosts() public {
        vm.expectRevert(CordonGuard.NotReporter.selector);
        guard.postAttestation(1, 1, 1, bytes32(0), "");
    }

    function test_periodMustIncrease() public {
        _attest(100, 1, 1);
        vm.prank(reporter);
        vm.expectRevert(abi.encodeWithSelector(CordonGuard.PeriodNotIncreasing.selector, 100, 100));
        guard.postAttestation(100, 1, 1, bytes32(0), "");
    }

    function test_reporterCannotClearTrustlessHalt() public {
        _healthy();
        token.setSupply(300e6);
        _attest(uint64(block.timestamp), 10_000e6, 10_001e6);
        assertTrue(guard.isHalted());
    }

    function test_onlyOwnerAdmin() public {
        vm.expectRevert(CordonGuard.NotOwner.selector);
        guard.recordControllers();
        vm.expectRevert(CordonGuard.NotOwner.selector);
        guard.setReporter(address(1));
    }

    function test_constructorRejectsBadParams() public {
        vm.expectRevert(CordonGuard.BadParams.selector);
        new CordonGuard(IPaxosToken(address(token)), owner, reporter, 1500, 2500, 1800, 7200, 62 days, 6 hours);
        vm.expectRevert(CordonGuard.ZeroAddress.selector);
        new CordonGuard(IPaxosToken(address(token)), address(0), reporter, 2500, 1500, 1800, 7200, 62 days, 6 hours);
    }

    /// forge-config: default.fuzz.runs = 2000
    function testFuzz_haltOnlyWithHaltReason(uint96 supply, uint96 reserves, uint96 outstanding, uint32 dt) public {
        _attest(uint64(block.timestamp), uint256(outstanding) + 1, reserves);
        guard.checkpoint();
        vm.warp(block.timestamp + dt);
        token.setSupply(supply);
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(level == CordonGuard.Level.HALT, reasons & guard.HALT_MASK() != 0);
        assertEq(level == CordonGuard.Level.HEALTHY, reasons == 0);
    }

    // ------------------------------------------------------------ no key can create HALT

    /// forge-config: default.fuzz.runs = 2000
    function testFuzz_noKeyCreatesHalt(uint96 outstanding, uint96 reserves, uint64 periodEnd, uint8 ownerOps) public {
        _healthy();
        periodEnd = uint64(bound(periodEnd, block.timestamp - 1 days + 1, block.timestamp));
        _attest(periodEnd, outstanding, reserves);
        vm.startPrank(owner);
        if (ownerOps & 1 != 0) guard.recordControllers();
        if (ownerOps & 2 != 0) guard.setReporter(address(0xBEEF));
        if (ownerOps & 4 != 0) guard.transferOwnership(address(0xCAFE));
        vm.stopPrank();
        assertFalse(guard.isHalted(), "only a supply jump read from the chain may halt");
    }

    // ------------------------------------------------------------ release of a legitimate jump

    function _latch(uint256 supply) internal {
        _healthy();
        token.setSupply(supply);
        guard.checkpoint();
        assertEq(guard.latchedBaseline(), BASE);
    }

    function test_scheduleReleaseNeedsLatch() public {
        vm.prank(owner);
        vm.expectRevert(CordonGuard.NotLatched.selector);
        guard.scheduleRelease();
    }

    function test_releaseOnlyOwner() public {
        _latch(130e6);
        vm.expectRevert(CordonGuard.NotOwner.selector);
        guard.scheduleRelease();
        vm.expectRevert(CordonGuard.NotOwner.selector);
        guard.executeRelease();
        vm.expectRevert(CordonGuard.NotOwner.selector);
        guard.cancelRelease();
    }

    function test_releaseTooEarlyReverts() public {
        _latch(130e6);
        vm.prank(owner);
        guard.scheduleRelease();
        uint64 at = guard.releaseExecutableAt();
        vm.warp(at - 1);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CordonGuard.ReleaseTooEarly.selector, at));
        guard.executeRelease();
    }

    /// @dev A 200M bridge-in on a 692M supply (+29%) halts; after notice it can be released.
    function test_bridgeInHaltsThenReleasesAfterNotice() public {
        _healthy();
        token.setSupply(BASE * 892 / 692);
        guard.checkpoint();
        assertTrue(guard.isHalted());
        vm.prank(owner);
        guard.scheduleRelease();
        // the keeper keeps checkpointing through the notice period
        for (uint256 i; i < 12; ++i) {
            vm.warp(block.timestamp + 1801);
            guard.checkpoint();
        }
        assertTrue(guard.isHalted(), "still halted until the release executes");
        vm.prank(owner);
        guard.executeRelease();
        assertEq(guard.latchedBaseline(), 0);
        assertEq(guard.releaseSupply(), 0);
        assertFalse(guard.isHalted());
        vm.warp(block.timestamp + 1801);
        guard.checkpoint();
        assertEq(guard.latchedBaseline(), 0, "must not re-latch on the post-release baseline");
    }

    function test_releaseRefusedIfSupplyGrew() public {
        _latch(130e6);
        vm.prank(owner);
        guard.scheduleRelease();
        token.setSupply(131e6);
        vm.warp(guard.releaseExecutableAt());
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CordonGuard.SupplyGrewSinceSchedule.selector, 130e6, 131e6));
        guard.executeRelease();
    }

    function test_cancelRelease() public {
        _latch(130e6);
        vm.startPrank(owner);
        guard.scheduleRelease();
        guard.cancelRelease();
        vm.warp(block.timestamp + 6 hours);
        vm.expectRevert(CordonGuard.NoReleaseScheduled.selector);
        guard.executeRelease();
        vm.stopPrank();
        assertTrue(guard.isHalted());
    }

    function test_burnClearsLatchAndScheduledRelease() public {
        _latch(130e6);
        vm.prank(owner);
        guard.scheduleRelease();
        token.setSupply(BASE);
        vm.warp(block.timestamp + 1801);
        guard.checkpoint();
        assertEq(guard.latchedBaseline(), 0);
        assertEq(guard.releaseSupply(), 0);
    }

    // ------------------------------------------------------------ ownership

    function test_twoStepOwnership() public {
        address safe = makeAddr("safe");
        vm.prank(owner);
        guard.transferOwnership(safe);
        assertEq(guard.owner(), owner);
        vm.expectRevert(CordonGuard.NotPendingOwner.selector);
        guard.acceptOwnership();
        vm.prank(safe);
        guard.acceptOwnership();
        assertEq(guard.owner(), safe);
        assertEq(guard.pendingOwner(), address(0));
        vm.prank(owner);
        vm.expectRevert(CordonGuard.NotOwner.selector);
        guard.setReporter(address(1));
    }

    function test_releaseDelayMustCoverBaselineWindow() public {
        vm.expectRevert(CordonGuard.BadParams.selector);
        new CordonGuard(IPaxosToken(address(token)), owner, reporter, 2500, 1500, 1800, 7200, 62 days, 7199);
    }

    // ------------------------------------------------------------ re-review: references never absorb a jump

    /// @dev Re-review finding: the checkpoint that latched also moved the anchor to the inflated
    ///      supply, so a small burn cleared the latch and re-minting stayed under the new anchor.
    function test_latchingCheckpointDoesNotMoveAnchor() public {
        _healthy();
        vm.warp(block.timestamp + 1 days); // anchor due to advance
        token.setSupply(130e6);
        guard.checkpoint();
        assertEq(guard.latchedBaseline(), BASE);
        (uint128 anchorSupply,) = guard.anchor();
        assertEq(anchorSupply, BASE, "the latching checkpoint must not move the anchor");
    }

    function test_burnThenRemintStaysBounded() public {
        _healthy();
        vm.warp(block.timestamp + 1 days);
        token.setSupply(BASE * 10 / 7); // 700 -> 1000
        guard.checkpoint();
        token.setSupply(BASE * 875 / 700); // burn to exactly +25%: latch clears
        vm.warp(block.timestamp + 1801);
        guard.checkpoint();
        assertEq(guard.latchedBaseline(), 0);
        token.setSupply(BASE * 900 / 700); // any further mint is over 25% of the pre-attack anchors
        assertTrue(guard.isHalted());
    }

    /// @dev With the previous anchor, growth stays within 25% across a daily advance.
    function test_growthAcrossAnchorAdvanceIsBounded() public {
        _healthy();
        token.setSupply(124e6);
        vm.warp(block.timestamp + 1 days);
        guard.checkpoint(); // anchor advances to 124, previous anchor holds 100
        vm.warp(block.timestamp + 1801);
        token.setSupply(126e6);
        assertTrue(guard.isHalted(), "+26% over the previous anchor must halt");
    }

    function test_releaseResetsBothAnchors() public {
        _healthy();
        vm.warp(block.timestamp + 1 days);
        guard.checkpoint(); // previous anchor = 100
        vm.warp(block.timestamp + 1801);
        token.setSupply(200e6);
        guard.checkpoint();
        vm.prank(owner);
        guard.scheduleRelease();
        vm.warp(block.timestamp + 6 hours);
        vm.prank(owner);
        guard.executeRelease();
        assertFalse(guard.isHalted(), "no stale anchor may keep a released market halted");
        vm.warp(block.timestamp + 1801);
        guard.checkpoint();
        assertEq(guard.latchedBaseline(), 0);
    }

    /// @dev Re-review 3: a latch held past the anchors' 2-day range, then cleared by a burn, must
    ///      measure later growth from the pre-jump supply.
    function test_longLatchThenBurnReanchorsAtPreJump() public {
        _healthy();
        token.setSupply(200e6);
        guard.checkpoint();
        for (uint256 i; i < 150; ++i) { // 75 h of keeper calls while latched
            vm.warp(block.timestamp + 1801);
            guard.checkpoint();
        }
        token.setSupply(125e6); // burn back to +25%: clears
        vm.warp(block.timestamp + 1801);
        guard.checkpoint();
        assertEq(guard.latchedBaseline(), 0);
        (uint128 anchorSupply,) = guard.anchor();
        assertEq(anchorSupply, BASE);
        token.setSupply(126e6);
        assertTrue(guard.isHalted(), "growth past +25% of the pre-jump supply must halt");
    }
}
