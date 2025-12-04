// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract StakVaultPerformanceTest is BaseTest {
    function test_PerformanceFee_Calculation() public {
        // Initial deposit
        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Update total assets to create profit
        asset.mint(address(vault), 1000e18);
        uint256 newTotalAssets = 2000e18;

        uint256 treasuryBalanceBefore = asset.balanceOf(treasury);

        vm.prank(owner);
        vault.updateInvestedAssets(newTotalAssets);

        uint256 treasuryBalanceAfter = asset.balanceOf(treasury);
        assertGt(treasuryBalanceAfter, treasuryBalanceBefore);

        // High water mark should be updated
        assertGt(vault.highWaterMark(), 1e18);
    }

    function test_PerformanceFee_NoProfit() public {
        // Initial deposit
        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Set initial totalAssets
        vm.prank(owner);
        vault.updateInvestedAssets(depositAmount);

        // Update total assets to same value (no profit)
        uint256 newTotalAssets = 1000e18;

        uint256 treasuryBalanceBefore = asset.balanceOf(treasury);
        uint256 highWaterMarkBefore = vault.highWaterMark();

        vm.prank(owner);
        vault.updateInvestedAssets(newTotalAssets);

        uint256 treasuryBalanceAfter = asset.balanceOf(treasury);
        uint256 highWaterMarkAfter = vault.highWaterMark();

        assertEq(treasuryBalanceAfter, treasuryBalanceBefore);
        assertEq(highWaterMarkAfter, highWaterMarkBefore); // HWM should not change
    }

    function test_PerformanceFee_PricePerShareEqualsHighWaterMark() public {
        // Initial deposit
        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Set totalAssets to create initial HWM
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        uint256 hwmAfterFirst = vault.highWaterMark();
        uint256 treasuryBalanceBefore = asset.balanceOf(treasury);

        // Update to same totalAssets (price per share equals HWM)
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        uint256 treasuryBalanceAfter = asset.balanceOf(treasury);
        uint256 hwmAfterSecond = vault.highWaterMark();

        // No fee should be charged
        assertEq(treasuryBalanceAfter, treasuryBalanceBefore);
        // HWM should remain the same
        assertEq(hwmAfterSecond, hwmAfterFirst);
    }

    function test_PerformanceFee_HighWaterMarkUpdate() public {
        // Initial deposit
        uint256 depositAmount = 1000e18;

        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        uint256 initialHighWaterMark = vault.highWaterMark();

        // First profit
        asset.mint(address(vault), 1000e18);
        vm.prank(owner);
        vault.updateInvestedAssets(2000e18);

        uint256 highWaterMarkAfterFirst = vault.highWaterMark();
        assertGt(highWaterMarkAfterFirst, initialHighWaterMark);

        // Second profit (smaller)
        asset.mint(address(vault), 500e18);
        vm.prank(owner);
        vault.updateInvestedAssets(2500e18);

        uint256 highWaterMarkAfterSecond = vault.highWaterMark();
        // HWM should not decrease
        assertGe(highWaterMarkAfterSecond, highWaterMarkAfterFirst);
    }
}
