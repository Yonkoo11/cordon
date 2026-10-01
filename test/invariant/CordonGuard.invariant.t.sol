// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {CordonGuard} from "../../src/CordonGuard.sol";
import {IPaxosToken} from "../../src/interfaces/IPaxos.sol";
import {MockPaxosToken, MockSupplyControl} from "../mocks/MockPaxos.sol";

/// @notice Drives the guard through random sequences: mints and burns, time passing with a keeper
///         that checkpoints every 30 min to 2 h, reporter posts and every owner action. Records
///         breaches of the guard's promises as ghost flags the invariants read.
contract GuardHandler is Test {
    MockPaxosToken public token;
    CordonGuard public guard;
    address public owner;
    address public reporter;
    bool public immutable supplyMoves;

    struct Point {
        uint64 t;
        uint128 supply;
    }

    Point[] public history;
    uint64 public lastReleaseAt;
    uint64 public scheduledAt;
    uint128 public scheduledCap;
    bool public earlyRelease;
    bool public silentClear;
    // coverage counters: how often each interesting state was actually reached
    uint256 public haltsSeen;
    uint256 public releasesScheduled;
    uint256 public releasesExecuted;
    uint256 public burnClears;

    constructor(MockPaxosToken token_, CordonGuard guard_, address owner_, address reporter_, bool supplyMoves_) {
        token = token_;
        guard = guard_;
        owner = owner_;
        reporter = reporter_;
        supplyMoves = supplyMoves_;
        history.push(Point(uint64(block.timestamp), uint128(token.totalSupply())));
    }

    function historyLength() external view returns (uint256) {
        return history.length;
    }

    /// Mint or burn: a new supply between 50% and 130% of today's.
    function moveSupply(uint256 pct) external {
        if (!supplyMoves) return;
        uint256 next = token.totalSupply() * bound(pct, 50, 130) / 100;
        if (next == 0) next = 1;
        if (next > 1e30) next = 1e30; // stay far inside uint128 so history is exact
        token.setSupply(next);
        history.push(Point(uint64(block.timestamp), uint128(next)));
    }

    /// Time passes and the keeper checkpoints, as the GitHub job does.
    function keeper(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1801, 7199));
        uint128 latchedBefore = guard.latchedBaseline();
        guard.checkpoint();
        uint128 latchedAfter = guard.latchedBaseline();
        // a latch may clear in a checkpoint only when supply is back within 25% of the pre-jump level
        if (latchedBefore != 0 && latchedAfter == 0) {
            if (token.totalSupply() * 10_000 > uint256(latchedBefore) * 12_500) silentClear = true;
            else ++burnClears;
        }
        if (guard.isHalted()) ++haltsSeen;
        history.push(Point(uint64(block.timestamp), uint128(token.totalSupply())));
    }

    function report(uint64 back, uint256 outstanding, uint256 reserves) external {
        (uint64 last,,,,,) = _attestation();
        uint64 periodEnd = uint64(block.timestamp) - uint64(bound(back, 0, 30 days));
        if (periodEnd <= last) return;
        vm.prank(guard.reporter()); // the owner may have rotated it
        guard.postAttestation(periodEnd, outstanding, reserves, bytes32(0), "");
    }

    function ownerAction(uint8 op, address who) external {
        vm.startPrank(owner);
        op = op % 5;
        if (op == 0) guard.recordControllers();
        if (op == 1 && who != address(0)) guard.setReporter(who);
        if (op == 2 && guard.latchedBaseline() != 0) {
            guard.scheduleRelease();
            scheduledAt = uint64(block.timestamp);
            scheduledCap = uint128(token.totalSupply());
            ++releasesScheduled;
        }
        if (op == 3 && guard.releaseSupply() != 0) guard.cancelRelease();
        if (op == 4 && guard.releaseSupply() != 0) _tryRelease();
        vm.stopPrank();
    }

    /// Schedule a release if latched, let 0-8 h pass with the keeper running, then try to execute:
    /// exercises both early (must fail) and on-time attempts.
    function releaseCycle(uint256 wait, uint256 pct) external {
        if (guard.latchedBaseline() == 0) return;
        vm.prank(owner);
        guard.scheduleRelease();
        scheduledAt = uint64(block.timestamp);
        scheduledCap = uint128(token.totalSupply());
        ++releasesScheduled;
        // half the cycles wait out the notice (6-8 h), half try early (0-6 h)
        uint256 end = block.timestamp + (wait % 2 == 0 ? 6 hours + (wait / 2) % 2 hours : (wait / 2) % 6 hours);
        while (block.timestamp + 1801 <= end) {
            vm.warp(block.timestamp + 1801);
            guard.checkpoint();
            history.push(Point(uint64(block.timestamp), uint128(token.totalSupply())));
        }
        vm.warp(end);
        if (supplyMoves && pct % 3 == 0) {
            uint256 next = token.totalSupply() * bound(pct, 90, 110) / 100; // sometimes grow or shrink before executing
            token.setSupply(next);
            history.push(Point(uint64(block.timestamp), uint128(next)));
        }
        vm.prank(owner);
        _tryRelease();
    }

    function _tryRelease() internal {
        try guard.executeRelease() {
            if (block.timestamp < scheduledAt + 6 hours || token.totalSupply() > scheduledCap) earlyRelease = true;
            lastReleaseAt = uint64(block.timestamp);
            ++releasesExecuted;
        } catch {}
    }

    function _attestation() internal view returns (uint64, uint64, uint256, uint256, bytes32, string memory) {
        CordonGuard.Attestation memory a = guard.latestAttestation();
        return (a.periodEnd, a.postedAt, a.outstanding, a.reserves, a.reportSha256, a.uri);
    }

    /// Supply recorded at or before `t` (the latest point not after it).
    function supplyAt(uint64 t) external view returns (bool found, uint128 supply) {
        for (uint256 i = history.length; i > 0; --i) {
            if (history[i - 1].t <= t) return (true, history[i - 1].supply);
        }
    }
}

abstract contract GuardInvariantBase is Test {
    MockPaxosToken internal token;
    CordonGuard internal guard;
    GuardHandler internal handler;
    address internal owner = makeAddr("owner");
    address internal reporter = makeAddr("reporter");

    function _deploy(bool supplyMoves) internal {
        vm.warp(1_760_000_000);
        address[] memory c = new address[](1);
        c[0] = address(0xA);
        MockSupplyControl sc = new MockSupplyControl(c);
        token = new MockPaxosToken(address(sc), 700_000_000e6);
        guard = new CordonGuard(IPaxosToken(address(token)), owner, reporter, 2500, 1500, 1800, 7200, 62 days, 6 hours);
        guard.checkpoint();
        vm.warp(block.timestamp + 1801);
        handler = new GuardHandler(token, guard, owner, reporter, supplyMoves);
        targetContract(address(handler));
    }
}

/// Supply never changes; only keys and time act. The guard must never halt.
contract NoKeyHaltsInvariant is GuardInvariantBase {
    function setUp() public {
        _deploy(false);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_noKeyCausesHalt() public view {
        assertFalse(guard.isHalted());
    }
}

/// Supply moves freely; the guard's latch, release and status promises must hold throughout.
contract GuardPromisesInvariant is GuardInvariantBase {
    function setUp() public {
        _deploy(true);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_releaseOnlyAfterNoticeWithoutGrowth() public view {
        assertFalse(handler.earlyRelease());
    }

    function invariant_latchClearsOnlyOnBurn() public view {
        assertFalse(handler.silentClear());
    }

    function invariant_statusAgreesWithIsHalted() public view {
        (CordonGuard.Level level,) = guard.status();
        assertEq(level == CordonGuard.Level.HALT, guard.isHalted());
    }

    function invariant_latchedAndAboveIsHalted() public view {
        uint256 latched = guard.latchedBaseline();
        if (latched != 0 && token.totalSupply() * 10_000 > latched * 12_500) assertTrue(guard.isHalted());
    }

    /// The documented ceiling: without a release in the window, supply that is not halted is at
    /// most 1.5625x (two 25% steps) what it was 48 h earlier.
    function invariant_growthOver48hIsBounded() public view {
        uint64 nowTs = uint64(block.timestamp);
        if (nowTs < 1_760_000_000 + 2 days + 1801) return;
        if (handler.lastReleaseAt() != 0 && nowTs - handler.lastReleaseAt() <= 2 days) return;
        if (guard.isHalted()) return;
        (bool found, uint128 then) = handler.supplyAt(nowTs - 2 days);
        if (!found || then == 0) return;
        assertLe(token.totalSupply() * 10_000, uint256(then) * 15_625, "more than +56.25% in 48 h without HALT");
    }

    /// The release action can actually execute (guards against a vacuous release invariant).
    function test_releaseCycleExecutes() public {
        handler.moveSupply(130);
        handler.keeper(1801);
        assertGt(guard.latchedBaseline(), 0, "jump latched");
        handler.releaseCycle(8 hours, 1);
        assertEq(handler.releasesExecuted(), 1);
        assertFalse(handler.earlyRelease());
    }

    function afterInvariant() external view {
        console2.log("halts seen", handler.haltsSeen());
        console2.log("releases scheduled", handler.releasesScheduled());
        console2.log("releases executed", handler.releasesExecuted());
        console2.log("latches cleared by burn", handler.burnClears());
    }
}
