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

/// @notice A hostile token whose totalSupply tries to call back into the guard.
contract ReentrantToken {
    address public supplyControl;
    address public target;
    uint256 internal _supply;

    constructor(address sc, uint256 supply) {
        supplyControl = sc;
        _supply = supply;
    }

    function arm(address guard) external {
        target = guard;
    }

    function totalSupply() external returns (uint256) {
        if (target != address(0)) {
            (bool ok,) = target.call(abi.encodeWithSignature("checkpoint()"));
            require(ok, "reentry blocked");
        }
        return _supply;
    }

    function pendingDefaultAdmin() external pure returns (address, uint48) {
        return (address(0), 0);
    }
}
