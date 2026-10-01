// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {IMorpho, MarketParams, Id} from "morpho-blue/interfaces/IMorpho.sol";
import {IOracle} from "morpho-blue/interfaces/IOracle.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {CordonGuard} from "../../src/CordonGuard.sol";
import {CordonMorphoOracle} from "../../src/CordonMorphoOracle.sol";
import {IPaxosToken} from "../../src/interfaces/IPaxos.sol";

interface IPaxosMint {
    function mint(address account, uint256 amount) external;
}

/// @notice Phase 1 Gate. Runs against a fork of Robinhood Chain mainnet at the latest block:
///         forge test --match-path test/fork/OverMint.t.sol --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract OverMintForkTest is Test {
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address internal constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address internal constant MORPHO = 0x9D53d5E3bd5E8d4Cbfa6DB1ca238AEA02E651010;
    address internal constant IRM = 0x2BD3d5965B26B51814AC95127B2b80dD6CcC0fa1;
    address internal constant LIVE_NVDA_ORACLE = 0x548196c5A7D2127Ae69FBc69e2fEd9686Fdd7A10;
    address internal constant CONTROLLER = 0x2fb074FA59c9294c71246825C1c9A0c7782d41a4;
    uint256 internal constant LLTV = 0.625e18;

    // KPMG, USDG Redemption Assets Report, 2026-08-31 (published 2026-09-25)
    uint256 internal constant OUTSTANDING = 3_340_650_602e6;
    uint256 internal constant RESERVES = 3_350_462_467e6;
    bytes32 internal constant REPORT_SHA = 0x384778246b4b117dcf136733334532f60fbf9b1001d15b731348c9c22e96e37e;

    CordonGuard internal guard;
    MarketParams internal market;
    address internal lender = makeAddr("lender");
    address internal borrower = makeAddr("borrower");
    uint256 internal collateral = 100_000e6; // USDG

    function setUp() public {
        if (block.chainid != 4663) vm.skip(true);
        guard = new CordonGuard(IPaxosToken(USDG), address(this), address(this), 2500, 1500, 1800, 7200, 62 days);
        guard.postAttestation(1_788_210_000, OUTSTANDING, RESERVES, REPORT_SHA, "framerusercontent.com/assets/Xn1UQwAte85FnsDveIMX0n1qtVM.pdf");
        guard.checkpoint();
        vm.warp(block.timestamp + 31 minutes);

        CordonMorphoOracle oracle = new CordonMorphoOracle(IOracle(LIVE_NVDA_ORACLE), guard, 5000);
        market = MarketParams({loanToken: NVDA, collateralToken: USDG, oracle: address(oracle), irm: IRM, lltv: LLTV});
        IMorpho(MORPHO).createMarket(market);

        deal(NVDA, lender, 1_000e18);
        vm.startPrank(lender);
        IERC20(NVDA).approve(MORPHO, type(uint256).max);
        IMorpho(MORPHO).supply(market, 1_000e18, 0, lender, "");
        vm.stopPrank();

        deal(USDG, borrower, collateral);
        vm.startPrank(borrower);
        IERC20(USDG).approve(MORPHO, type(uint256).max);
        IMorpho(MORPHO).supplyCollateral(market, collateral, borrower, "");
        vm.stopPrank();
    }

    /// @dev 60% of the borrow limit at the market's normal price: allowed when healthy, over the
    ///      limit once the guard halves the collateral price.
    function _borrowAmount() internal view returns (uint256) {
        uint256 maxBorrow = collateral * IOracle(LIVE_NVDA_ORACLE).price() / 1e36 * LLTV / 1e18;
        return maxBorrow * 60 / 100;
    }

    function _logStatus() internal view {
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        console2.log("block", block.number);
        console2.log("usdg supply", IERC20(USDG).totalSupply());
        console2.log("level", uint8(level));
        console2.log("reasons", reasons);
    }

    function test_healthyAllowsBorrow() public {
        _logStatus();
        (CordonGuard.Level level,) = guard.status();
        assertEq(uint8(level), 0);
        uint256 amount = _borrowAmount();
        vm.prank(borrower);
        IMorpho(MORPHO).borrow(market, amount, 0, borrower, borrower);
        assertEq(IERC20(NVDA).balanceOf(borrower), amount);
        console2.log("borrow succeeded", amount);
    }

    function test_overMintHaltsBorrow() public {
        uint256 before = IERC20(USDG).totalSupply();
        vm.prank(CONTROLLER);
        IPaxosMint(USDG).mint(CONTROLLER, 300_000_000e6);
        assertEq(IERC20(USDG).totalSupply(), before + 300_000_000e6);
        _logStatus();
        (CordonGuard.Level level, uint256 reasons) = guard.status();
        assertEq(uint8(level), 2);
        assertEq(reasons, guard.SUPPLY_JUMP_HALT());

        uint256 amount = _borrowAmount();
        vm.prank(borrower);
        vm.expectRevert();
        IMorpho(MORPHO).borrow(market, amount, 0, borrower, borrower);
        console2.log("borrow reverted");
    }

    function test_repayAndLiquidateStillWorkWhenHalted() public {
        uint256 amount = _borrowAmount();
        vm.prank(borrower);
        IMorpho(MORPHO).borrow(market, amount, 0, borrower, borrower);

        vm.prank(CONTROLLER);
        IPaxosMint(USDG).mint(CONTROLLER, 300_000_000e6);
        assertTrue(guard.isHalted());

        vm.startPrank(borrower);
        IERC20(NVDA).approve(MORPHO, type(uint256).max);
        // repay 5%: the position stays at 57% of the normal limit, above the 50% limit under HALT
        IMorpho(MORPHO).repay(market, amount / 20, 0, borrower, "");
        vm.stopPrank();
        console2.log("repay succeeded under HALT");

        address liquidator = makeAddr("liquidator");
        deal(NVDA, liquidator, 1_000e18);
        vm.startPrank(liquidator);
        IERC20(NVDA).approve(MORPHO, type(uint256).max);
        (uint256 seized,) = IMorpho(MORPHO).liquidate(market, borrower, 1_000e6, 0, "");
        vm.stopPrank();
        assertEq(seized, 1_000e6);
        console2.log("liquidation succeeded under HALT, seized USDG", seized);
    }
}
