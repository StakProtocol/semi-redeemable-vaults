// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract SemiRedeemable4626PreviewTest is BaseTest {

    function test_PreviewDeposit() public view {
        uint256 assets = 1000e18;
        uint256 shares = vault.previewDeposit(assets);
        assertEq(shares, assets);
    }

    function test_PreviewMint() public view {
        uint256 shares = 1000e18;
        uint256 assets = vault.previewMint(shares);
        assertEq(assets, shares);
    }

    function test_PreviewRedeem() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        uint256 shares = 500e18;
        vm.prank(user1);
        uint256 assets = vault.previewRedeem(shares);
        assertEq(assets, 500e18);
    }

    function test_PreviewWithdraw() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Without setting investedAssets, totalAssets = 1000e18 (balance only)
        // previewWithdraw uses min of standard conversion and user's ledger conversion
        // Standard: 500e18 * 1000e18 / 1000e18 = 500e18 (Ceil)
        // User ledger: 500e18 * 1000e18 / 1000e18 = 500e18 (Ceil)
        // min = 500e18
        uint256 assets = 500e18;
        vm.prank(user1);
        uint256 shares = vault.previewWithdraw(assets);
        assertEq(shares, 500e18);
    }

    function test_ConvertToShares() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        uint256 assets = 500e18;
        uint256 shares = vault.convertToShares(assets, user1);
        assertEq(shares, 500e18);
    }

    function test_ConvertToAssets() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        uint256 shares = 500e18;
        uint256 assets = vault.convertToAssets(shares, user1);
        assertEq(assets, 500e18);
    }
}
