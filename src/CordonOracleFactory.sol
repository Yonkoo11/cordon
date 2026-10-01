// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IOracle} from "morpho-blue/interfaces/IOracle.sol";
import {CordonGuard} from "./CordonGuard.sol";
import {CordonMorphoOracle} from "./CordonMorphoOracle.sol";

/// @title CordonOracleFactory
/// @notice Deploys one CordonMorphoOracle per (base oracle, discount) against a single guard, at an
///         address anyone can predict. A market creator calls `create`, then creates a Morpho market
///         with the returned address as its oracle.
contract CordonOracleFactory {
    /// @notice Largest discount the factory will deploy. A discount near 100% prices collateral at
    ///         zero, which blocks Morpho liquidations that are sized by repaid shares.
    uint256 public constant MAX_DISCOUNT_BPS = 5_000;

    CordonGuard public immutable guard;

    mapping(IOracle baseOracle => mapping(uint256 discountBps => CordonMorphoOracle)) public wrapperOf;

    event WrapperCreated(IOracle indexed baseOracle, uint256 discountBps, CordonMorphoOracle wrapper);

    error ZeroAddress();
    error BadDiscount();

    constructor(CordonGuard guard_) {
        if (address(guard_) == address(0)) revert ZeroAddress();
        guard = guard_;
    }

    /// @notice Returns the wrapper for these inputs, deploying it on first use.
    function create(IOracle baseOracle, uint256 discountBps) external returns (CordonMorphoOracle wrapper) {
        if (address(baseOracle) == address(0)) revert ZeroAddress();
        if (discountBps == 0 || discountBps > MAX_DISCOUNT_BPS) revert BadDiscount();
        wrapper = wrapperOf[baseOracle][discountBps];
        if (address(wrapper) != address(0)) return wrapper;
        wrapper = new CordonMorphoOracle{salt: _salt(baseOracle, discountBps)}(baseOracle, guard, discountBps);
        wrapperOf[baseOracle][discountBps] = wrapper;
        emit WrapperCreated(baseOracle, discountBps, wrapper);
    }

    /// @notice The address `create` deploys to, whether or not it exists yet.
    function predict(IOracle baseOracle, uint256 discountBps) external view returns (address) {
        bytes32 initHash = keccak256(
            abi.encodePacked(type(CordonMorphoOracle).creationCode, abi.encode(baseOracle, guard, discountBps))
        );
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt(baseOracle, discountBps), initHash))))
        );
    }

    function _salt(IOracle baseOracle, uint256 discountBps) internal pure returns (bytes32) {
        return keccak256(abi.encode(baseOracle, discountBps));
    }
}
