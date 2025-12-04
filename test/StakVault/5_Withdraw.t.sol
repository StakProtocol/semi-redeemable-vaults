// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract StakVaultWithdrawTest is BaseTest {
    function test_Withdraw_Success() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Without setting investedAssets, totalAssets = 1000e18 (balance only)
        // previewWithdraw uses min of standard conversion and user's ledger conversion
        // Both are 1:1, so shares = 500e18
        uint256 withdrawAmount = 500e18;

        vm.startPrank(user1);
        uint256 shares = vault.withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();

        assertEq(shares, 500e18);
        assertEq(vault.balanceOf(user1), depositAmount - shares);
        assertEq(asset.balanceOf(user1), 1000000e18 - depositAmount + withdrawAmount);
    }

    function test_Withdraw_RevertWhen_ExceedsMaxWithdraw() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert();
        vault.withdraw(1001e18, user1, user1);
        vm.stopPrank();
    }

    function test_Withdraw_RevertWhen_VestingNotRedeemable() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Move to vesting period
        vm.warp(vestingStart + 15 days);

        vault.redeemableShares(user1);

        vm.startPrank(user1);
        // maxWithdraw might revert due to previewRedeem calculation
        // Let's try withdrawing more than redeemable shares would allow
        uint256 maxWithdraw = vault.maxWithdraw(user1);
        // Try to withdraw slightly more
        vm.expectRevert();
        vault.withdraw(maxWithdraw + 1, user1, user1);
        vm.stopPrank();
    }
}
