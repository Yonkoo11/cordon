// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPaxosToken, ISupplyControl} from "./interfaces/IPaxos.sol";

/// @title CordonGuard
/// @notice Issuer-level circuit breaker for a Paxos stablecoin on one chain.
///         Trustless checks read the token and its SupplyControl directly. Reported checks use the
///         monthly attestation figure posted by `reporter`, labelled as such, and can never clear a
///         trustless reason. Only a supply jump read from the chain can reach HALT: no key held by
///         the operator can create one. The owner can release a latched jump after `releaseDelay`
///         of public notice, and only if supply has not grown since the release was scheduled.
contract CordonGuard {
    enum Level {
        HEALTHY,
        CAUTION,
        HALT
    }

    struct Attestation {
        uint64 periodEnd;
        uint64 postedAt;
        uint256 outstanding; // token units, 6 decimals, all chains
        uint256 reserves; // USD, 6 decimals
        bytes32 reportSha256;
        string uri;
    }

    struct Baseline {
        uint128 supply;
        uint64 timestamp;
    }

    uint256 public constant SUPPLY_JUMP_HALT = 1 << 0;
    uint256 public constant SUPPLY_JUMP_CAUTION = 1 << 1;
    uint256 public constant NO_BASELINE = 1 << 2;
    uint256 public constant MINTER_SET_CHANGED = 1 << 3;
    uint256 public constant ADMIN_TRANSFER_PENDING = 1 << 4;
    uint256 public constant RESERVES_BELOW_OUTSTANDING = 1 << 5;
    uint256 public constant ATTESTATION_STALE = 1 << 6;
    uint256 public constant SUPPLY_ABOVE_ATTESTED_TOTAL = 1 << 7;
    /// @dev Reported reasons (bits 5-7) come from a figure the reporter posts, so they stop at CAUTION.
    uint256 public constant HALT_MASK = SUPPLY_JUMP_HALT;

    uint256 private constant BPS = 10_000;
    /// @notice The slow reference moves forward at most once per ANCHOR_PERIOD, so frequent
    ///         checkpoints cannot walk the reference up with many sub-threshold mints.
    uint64 public constant ANCHOR_PERIOD = 1 days;
    /// @notice An anchor older than this is ignored (organic growth over longer gaps is not a jump).
    uint64 public constant ANCHOR_MAX_AGE = 2 days;

    IPaxosToken public immutable token;
    ISupplyControl public immutable supplyControl;
    uint256 public immutable jumpHaltBps;
    uint256 public immutable jumpCautionBps;
    uint64 public immutable baselineMinAge;
    uint64 public immutable baselineMaxAge;
    uint64 public immutable staleAfter;
    uint64 public immutable releaseDelay;

    address public owner;
    address public pendingOwner;
    address public reporter;
    /// @notice Supply cap recorded by `scheduleRelease`; 0 when no release is scheduled.
    uint128 public releaseSupply;
    uint64 public releaseExecutableAt;
    bytes32 public controllerSetHash;
    /// @notice Baseline supply when a HALT-level jump was seen by `checkpoint`; 0 when not latched.
    ///         Clears only when supply falls back within `jumpHaltBps` of it.
    uint128 public latchedBaseline;

    /// @notice Slow reference for HALT: advanced by `checkpoint` at most once per ANCHOR_PERIOD.
    Baseline public anchor;

    Baseline[2] private _slots;
    uint8 private _newest;
    Attestation private _attestation;

    event Checkpointed(uint256 supply, uint64 timestamp);
    event JumpLatched(uint256 baseline, uint256 supply);
    event JumpCleared(uint256 baseline, uint256 supply);
    event AttestationPosted(
        uint64 indexed periodEnd, uint256 outstanding, uint256 reserves, bytes32 reportSha256, string uri
    );
    event ControllersRecorded(bytes32 setHash, uint256 count);
    event ReporterChanged(address indexed previous, address indexed next);
    event ReleaseScheduled(uint256 supply, uint64 executableAt);
    event ReleaseCancelled();
    event ReleaseExecuted(uint256 baseline, uint256 supply);
    event OwnershipTransferStarted(address indexed previous, address indexed next);
    event OwnershipTransferred(address indexed previous, address indexed next);

    error NotReporter();
    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();
    error BadParams();
    error PeriodNotIncreasing(uint64 last, uint64 next);
    error PeriodInFuture(uint64 periodEnd);
    error CheckpointTooSoon(uint64 newest, uint64 now_);
    error SupplyTooLarge(uint256 supply);
    error NotLatched();
    error NoReleaseScheduled();
    error ReleaseTooEarly(uint64 executableAt);
    error SupplyGrewSinceSchedule(uint256 scheduled, uint256 supply);

    constructor(
        IPaxosToken token_,
        address owner_,
        address reporter_,
        uint256 jumpHaltBps_,
        uint256 jumpCautionBps_,
        uint64 baselineMinAge_,
        uint64 baselineMaxAge_,
        uint64 staleAfter_,
        uint64 releaseDelay_
    ) {
        if (address(token_) == address(0) || owner_ == address(0) || reporter_ == address(0)) revert ZeroAddress();
        if (
            jumpCautionBps_ == 0 || jumpCautionBps_ >= jumpHaltBps_ || baselineMinAge_ >= baselineMaxAge_
                || releaseDelay_ < baselineMaxAge_
        ) {
            revert BadParams();
        }
        token = token_;
        supplyControl = ISupplyControl(token_.supplyControl());
        owner = owner_;
        reporter = reporter_;
        jumpHaltBps = jumpHaltBps_;
        jumpCautionBps = jumpCautionBps_;
        baselineMinAge = baselineMinAge_;
        baselineMaxAge = baselineMaxAge_;
        staleAfter = staleAfter_;
        releaseDelay = releaseDelay_;
        _recordControllers();
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ---------------------------------------------------------------- writes

    /// @notice Anyone may record the current supply as a baseline, at most once per `baselineMinAge`.
    ///         Also latches a HALT-level jump so it survives baseline rotation, and clears the latch
    ///         once the excess has been burned.
    function checkpoint() external {
        uint64 nowTs = uint64(block.timestamp);
        Baseline memory newest = _slots[_newest];
        if (newest.timestamp > 0 && nowTs - newest.timestamp < baselineMinAge) {
            revert CheckpointTooSoon(newest.timestamp, nowTs);
        }
        uint256 supply = token.totalSupply();
        if (supply > type(uint128).max) revert SupplyTooLarge(supply);
        _updateLatch(supply);
        uint8 next = _newest == 0 ? 1 : 0;
        _slots[next] = Baseline(uint128(supply), nowTs);
        _newest = next;
        if (anchor.timestamp < 1 || nowTs - anchor.timestamp >= ANCHOR_PERIOD) anchor = Baseline(uint128(supply), nowTs);
        emit Checkpointed(supply, nowTs);
    }

    function postAttestation(
        uint64 periodEnd,
        uint256 outstanding,
        uint256 reserves,
        bytes32 reportSha256,
        string calldata uri
    ) external {
        if (msg.sender != reporter) revert NotReporter();
        if (periodEnd > block.timestamp) revert PeriodInFuture(periodEnd);
        if (periodEnd <= _attestation.periodEnd) revert PeriodNotIncreasing(_attestation.periodEnd, periodEnd);
        _attestation = Attestation(periodEnd, uint64(block.timestamp), outstanding, reserves, reportSha256, uri);
        emit AttestationPosted(periodEnd, outstanding, reserves, reportSha256, uri);
    }

    function recordControllers() external onlyOwner {
        _recordControllers();
    }

    function setReporter(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit ReporterChanged(reporter, next);
        reporter = next;
    }

    /// @notice Starts the public notice period for releasing a latched jump that turned out to be
    ///         legitimate (a bridge-in, a large customer mint). Caps the release at today's supply.
    function scheduleRelease() external onlyOwner {
        if (latchedBaseline == 0) revert NotLatched();
        uint256 supply = token.totalSupply();
        if (supply > type(uint128).max) revert SupplyTooLarge(supply);
        uint64 executableAt = uint64(block.timestamp) + releaseDelay;
        releaseSupply = uint128(supply);
        releaseExecutableAt = executableAt;
        emit ReleaseScheduled(supply, executableAt);
    }

    function cancelRelease() external onlyOwner {
        if (releaseSupply == 0) revert NoReleaseScheduled();
        _clearRelease();
        emit ReleaseCancelled();
    }

    /// @notice Clears the latch once the notice period has passed, if supply has not grown since.
    function executeRelease() external onlyOwner {
        uint256 cap = releaseSupply;
        if (cap == 0) revert NoReleaseScheduled();
        if (block.timestamp < releaseExecutableAt) revert ReleaseTooEarly(releaseExecutableAt);
        uint256 supply = token.totalSupply();
        if (supply > cap) revert SupplyGrewSinceSchedule(cap, supply);
        emit ReleaseExecuted(latchedBaseline, supply);
        latchedBaseline = 0;
        _clearRelease();
        // the released supply is the new normal; the old anchor would re-latch it
        anchor = Baseline(uint128(supply), uint64(block.timestamp));
    }

    /// @notice Starts a handover; `address(0)` cancels a pending one.
    function transferOwnership(address next) external onlyOwner {
        pendingOwner = next;
        emit OwnershipTransferStarted(owner, next);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    // ---------------------------------------------------------------- reads

    function status() public view returns (Level level, uint256 reasons) {
        uint256 supply = token.totalSupply();
        reasons = _supplyReasons(supply) | _controlReasons() | _reportedReasons(supply);
        if (reasons & HALT_MASK != 0) return (Level.HALT, reasons);
        if (reasons != 0) return (Level.CAUTION, reasons);
        return (Level.HEALTHY, 0);
    }

    /// @notice Reads only the supply checks, the sole HALT source, so a revert in an unrelated
    ///         Paxos read (minter list, admin schedule) cannot switch HALT off.
    function isHalted() external view returns (bool) {
        return _supplyReasons(token.totalSupply()) & HALT_MASK != 0;
    }

    /// @notice The anchor, if it is young enough to compare against.
    function anchorInRange() public view returns (bool ok, Baseline memory a) {
        a = anchor;
        ok = a.timestamp > 0 && block.timestamp - a.timestamp <= ANCHOR_MAX_AGE;
    }

    /// @notice The oldest baseline whose age is within [baselineMinAge, baselineMaxAge].
    function baselineInBand() public view returns (bool ok, Baseline memory b) {
        for (uint256 i; i < 2; ++i) {
            Baseline memory s = _slots[i];
            if (s.timestamp < 1) continue; // slot never written
            uint256 age = block.timestamp - s.timestamp;
            if (age < baselineMinAge || age > baselineMaxAge) continue;
            if (!ok || s.timestamp < b.timestamp) (ok, b) = (true, s);
        }
    }

    function latestAttestation() external view returns (Attestation memory) {
        return _attestation;
    }

    // ---------------------------------------------------------------- internals

    function _supplyReasons(uint256 supply) internal view returns (uint256 reasons) {
        if (latchedBaseline != 0 && _above(supply, latchedBaseline, jumpHaltBps)) reasons |= SUPPLY_JUMP_HALT;
        if (_jumpReference(supply) != 0) reasons |= SUPPLY_JUMP_HALT;
        (bool ok, Baseline memory b) = baselineInBand();
        if (!ok) return reasons | NO_BASELINE;
        if (reasons & SUPPLY_JUMP_HALT == 0 && _above(supply, b.supply, jumpCautionBps)) reasons |= SUPPLY_JUMP_CAUTION;
    }

    function _controlReasons() internal view returns (uint256 reasons) {
        if (_controllerHash() != controllerSetHash) reasons |= MINTER_SET_CHANGED;
        (address tokenNext, uint48 tokenAt) = token.pendingDefaultAdmin();
        (address controlNext, uint48 controlAt) = supplyControl.pendingDefaultAdmin();
        bool pending = tokenNext != address(0) || tokenAt > 0 || controlNext != address(0) || controlAt > 0;
        if (pending) reasons |= ADMIN_TRANSFER_PENDING;
    }

    function _reportedReasons(uint256 supply) internal view returns (uint256 reasons) {
        Attestation storage a = _attestation;
        if (a.periodEnd == 0 || block.timestamp > uint256(a.periodEnd) + staleAfter) reasons |= ATTESTATION_STALE;
        if (a.periodEnd == 0) return reasons;
        if (a.reserves < a.outstanding) reasons |= RESERVES_BELOW_OUTSTANDING;
        if (supply > a.outstanding) reasons |= SUPPLY_ABOVE_ATTESTED_TOTAL;
    }

    function _updateLatch(uint256 supply) internal {
        if (latchedBaseline != 0) {
            if (!_above(supply, latchedBaseline, jumpHaltBps)) {
                emit JumpCleared(latchedBaseline, supply);
                latchedBaseline = 0;
                if (releaseSupply != 0) _clearRelease();
            }
            return;
        }
        uint128 ref = _jumpReference(supply);
        if (ref != 0) {
            latchedBaseline = ref;
            emit JumpLatched(ref, supply);
        }
    }

    /// @dev The reference `supply` jumped from by more than `jumpHaltBps`: the in-band baseline
    ///      (fast, 30 min to 2 h) or else the anchor (slow, up to 2 days). 0 when neither tripped.
    ///      Stored supplies were range-checked when written.
    function _jumpReference(uint256 supply) internal view returns (uint128) {
        (bool ok, Baseline memory b) = baselineInBand();
        if (ok && _above(supply, b.supply, jumpHaltBps)) return b.supply;
        (bool aOk, Baseline memory a) = anchorInRange();
        if (aOk && _above(supply, a.supply, jumpHaltBps)) return a.supply;
        return 0;
    }

    function _clearRelease() internal {
        releaseSupply = 0;
        releaseExecutableAt = 0;
    }

    function _recordControllers() internal {
        controllerSetHash = _controllerHash();
        emit ControllersRecorded(controllerSetHash, supplyControl.getAllSupplyControllerAddresses().length);
    }

    function _controllerHash() internal view returns (bytes32) {
        return keccak256(abi.encode(supplyControl.getAllSupplyControllerAddresses()));
    }

    /// @dev supply > base * (1 + bps / 10_000), without rounding in the guard's favour.
    function _above(uint256 supply, uint256 base, uint256 bps) internal pure returns (bool) {
        return supply * BPS > base * (BPS + bps);
    }
}
