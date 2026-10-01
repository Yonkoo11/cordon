// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MockSupplyControl {
    address[] internal _controllers;
    address public pendingAdmin;

    constructor(address[] memory c) {
        _controllers = c;
    }

    function getAllSupplyControllerAddresses() external view returns (address[] memory) {
        return _controllers;
    }

    function addController(address c) external {
        _controllers.push(c);
    }

    function setPendingAdmin(address a) external {
        pendingAdmin = a;
    }

    function pendingDefaultAdmin() external view returns (address, uint48) {
        return (pendingAdmin, 0);
    }
}

contract MockPaxosToken {
    uint256 public totalSupply;
    address public supplyControl;
    address public pendingAdmin;

    constructor(address sc, uint256 supply) {
        supplyControl = sc;
        totalSupply = supply;
    }

    function setSupply(uint256 s) external {
        totalSupply = s;
    }

    function setPendingAdmin(address a) external {
        pendingAdmin = a;
    }

    function pendingDefaultAdmin() external view returns (address, uint48) {
        return (pendingAdmin, 0);
    }
}

contract MockOracle {
    uint256 public price;

    constructor(uint256 p) {
        price = p;
    }
}

contract RevertingGuard {
    function isHalted() external pure returns (bool) {
        revert("down");
    }
}
