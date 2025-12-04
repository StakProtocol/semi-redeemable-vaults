// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract SemiRedeemable4626DepositTest is BaseTest {

    function test_Deposit_Success() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, user1, depositAmount, depositAmount);
        
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(user1), depositAmount);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        
        (uint256 assets, uint256 userShares) = vault.getLedger(user1);
        assertEq(assets, depositAmount);
        assertEq(userShares, depositAmount);
    }

    function test_Deposit_AfterNavEnabled() public {
        vm.prank(owner);
        vault.enableRedeemsAtNav();
        
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        assertEq(shares, depositAmount);
        (uint256 assets, uint256 userShares) = vault.getLedger(user1);
        assertEq(assets, 0);
        assertEq(userShares, 0);
    }

    function test_Deposit_MultipleUsers() public {
        uint256 depositAmount1 = 1000e18;
        uint256 depositAmount2 = 2000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount1);
        vault.deposit(depositAmount1, user1);
        vm.stopPrank();
        
        // Don't set investedAssets - keep totalAssets = balance only for 1:1 conversion
        // When user2 deposits, totalAssets = 1000e18, totalSupply = 1000e18
        // So shares = 2000e18 * 1000e18 / 1000e18 = 2000e18 (1:1)
        
        vm.startPrank(user2);
        asset.approve(address(vault), depositAmount2);
        vault.deposit(depositAmount2, user2);
        vm.stopPrank();
        
        assertEq(vault.balanceOf(user1), depositAmount1);
        assertEq(vault.balanceOf(user2), depositAmount2);
        
        (uint256 assets1, uint256 shares1) = vault.getLedger(user1);
        (uint256 assets2, uint256 shares2) = vault.getLedger(user2);
        
        assertEq(assets1, depositAmount1);
        assertEq(shares1, depositAmount1);
        assertEq(assets2, depositAmount2);
        assertEq(shares2, depositAmount2);
        
        // Total balance should be sum of both
        assertEq(asset.balanceOf(address(vault)), depositAmount1 + depositAmount2);
        // totalSupply should equal the sum of shares (1:1 in this case)
        assertEq(vault.totalSupply(), depositAmount1 + depositAmount2);
    }
}
