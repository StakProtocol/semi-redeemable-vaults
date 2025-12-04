// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";

contract StakVaultMintTest is BaseTest {
    function test_Mint_Success() public {
        uint256 shares = 1000e18;
        uint256 assets = vault.previewMint(shares);

        vm.startPrank(user1);
        asset.approve(address(vault), assets);

        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, user1, assets, shares);

        uint256 assetsDeposited = vault.mint(shares, user1);
        vm.stopPrank();

        assertEq(assetsDeposited, assets);
        assertEq(vault.balanceOf(user1), shares);

        (uint256 userAssets, uint256 userShares) = vault.getLedger(user1);
        assertEq(userAssets, assets);
        assertEq(userShares, shares);
    }

    function test_Mint_AfterNavEnabled() public {
        vm.prank(owner);
        vault.enableRedeemsAtNav();

        uint256 shares = 1000e18;
        uint256 assets = vault.previewMint(shares);

        vm.startPrank(user1);
        asset.approve(address(vault), assets);
        vault.mint(shares, user1);
        vm.stopPrank();

        (uint256 userAssets, uint256 userShares) = vault.getLedger(user1);
        assertEq(userAssets, 0);
        assertEq(userShares, 0);
    }
}
