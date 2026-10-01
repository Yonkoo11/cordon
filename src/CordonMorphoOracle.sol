// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IOracle} from "morpho-blue/interfaces/IOracle.sol";
import {CordonGuard} from "./CordonGuard.sol";

/// @title CordonMorphoOracle
/// @notice Wraps a Morpho market's existing oracle for USDG collateral. On HALT the collateral
///         price is discounted by `haltDiscountBps`; it never reverts, so repayments and
///         liquidations keep working.
contract CordonMorphoOracle is IOracle {
    uint256 private constant BPS = 10_000;

    IOracle public immutable baseOracle;
    CordonGuard public immutable guard;
    uint256 public immutable haltDiscountBps;

    error ZeroAddress();
    error BadDiscount();

    constructor(IOracle baseOracle_, CordonGuard guard_, uint256 haltDiscountBps_) {
        if (address(baseOracle_) == address(0) || address(guard_) == address(0)) revert ZeroAddress();
        if (haltDiscountBps_ == 0 || haltDiscountBps_ > BPS) revert BadDiscount();
        baseOracle = baseOracle_;
        guard = guard_;
        haltDiscountBps = haltDiscountBps_;
    }

    /// @dev If the guard call itself fails, the base price is returned: a broken guard must not
    ///      block liquidations. This is a stated trade-off, not an oversight.
    function price() external view returns (uint256) {
        uint256 p = baseOracle.price();
        try guard.isHalted() returns (bool halted) {
            if (!halted) return p;
        } catch {
            return p;
        }
        return p * (BPS - haltDiscountBps) / BPS;
    }
}
