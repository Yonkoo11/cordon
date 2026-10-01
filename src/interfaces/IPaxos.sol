// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The parts of Paxos' USDG token that Backed reads (verified source on Robinhood Chain).
interface IPaxosToken {
    function totalSupply() external view returns (uint256);
    function supplyControl() external view returns (address);
    function pendingDefaultAdmin() external view returns (address newAdmin, uint48 schedule);
}

/// @notice The parts of Paxos' SupplyControl that Backed reads.
interface ISupplyControl {
    function getAllSupplyControllerAddresses() external view returns (address[] memory);
    function pendingDefaultAdmin() external view returns (address newAdmin, uint48 schedule);
}
