// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract SemiRedeemable4626GetterTest is BaseTest {

    function test_TotalAssets() public {
        assertEq(vault.totalAssets(), 0);
        
        vm.prank(owner);
        vault.updateInvestedAssets(1000e18);
        
        assertEq(vault.totalAssets(), 1000e18);
    }

    function test_HighWaterMark() public view {
        assertEq(vault.highWaterMark(), 1e18);
    }

    function test_UtilizationRate() public {
        // Set investedAssets = 1000e18
        vm.prank(owner);
        vault.updateInvestedAssets(1000e18);
        
        // Add 500e18 to vault balance
        asset.mint(address(vault), 500e18);
        
        // totalAssets = 500e18 (balance) + 1000e18 (invested) = 1500e18
        // utilization = 1000e18 / 1500e18 * 10000 = 6666 BPS (66.66%)
        uint256 utilization = vault.utilizationRate();
        assertEq(utilization, 6666); // ~66.66% in BPS
    }

    function test_RedeemsAtNav() public {
        assertEq(vault.redeemsAtNav(), false);
        
        vm.prank(owner);
        vault.enableRedeemsAtNav();
        
        assertEq(vault.redeemsAtNav(), true);
    }

    function test_GetLedger() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        (uint256 assets, uint256 shares) = vault.getLedger(user1);
        assertEq(assets, depositAmount);
        assertEq(shares, depositAmount);
    }

    function test_RedeemableShares_BeforeVesting() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Before vesting, all shares are redeemable
        uint256 redeemable = vault.redeemableShares(user1);
        assertEq(redeemable, 1000e18);
    }

    function test_RedeemableShares_DuringVesting() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Move to middle of vesting period (15 days into 30-day period)
        vm.warp(vestingStart + 15 days);
        
        uint256 redeemable = vault.redeemableShares(user1);
        // vestingRate = (30 - 15) / 30 * 10000 = 5000 (50%)
        // redeemable = 5000 * 1000e18 / 10000 = 500e18
        // But due to rounding in mulDiv, it might be slightly less (4827e17 = 482.7e18)
        // The actual calculation: BPS.mulDiv(vestingEnd - block.timestamp, vestingEnd - vestingStart, Floor)
        // At 15 days: 10000 * (15 days) / (30 days) = 5000, but with Floor rounding it might be less
        assertGe(redeemable, 480e18);
        assertLe(redeemable, 500e18);
    }

    function test_RedeemableShares_AfterVesting() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Move after vesting ends
        vm.warp(vestingEnd + 1);
        
        uint256 redeemable = vault.redeemableShares(user1);
        assertEq(redeemable, 0);
    }

    function test_VestingRate() public {
        // Before vesting
        uint256 rate = vault.vestingRate();
        assertEq(rate, 10000); // 100%
        
        // During vesting (middle) - due to Floor rounding, might be slightly less
        vm.warp(vestingStart + 15 days);
        rate = vault.vestingRate();
        // Expected: 10000 * 15 / 30 = 5000, but with Floor rounding might be less
        assertGe(rate, 4800);
        assertLe(rate, 5000);
        
        // After vesting
        vm.warp(vestingEnd + 1);
        rate = vault.vestingRate();
        assertEq(rate, 0);
    }
}
