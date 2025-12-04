// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./BaseTest.sol";
import {SemiRedeemable4626} from "../../src/SemiRedeemable4626.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract SemiRedeemable4626SetupTest is BaseTest {

    function test_Constructor_Success() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.redeemsAtNav(), false);
        assertEq(vault.highWaterMark(), 1e18);
        assertEq(vault.totalAssets(), 0);
    }

    function test_Constructor_Same_Decimals() public {        
        // Create asset with 7 decimals - vault will also have 6 decimals (they match)
        uint8 decimals = 7;
        MockERC20 asset6Decimals = new MockERC20("Asset6", "AST6", decimals);
        
        // This should succeed because ERC4626 matches asset decimals
        SemiRedeemable4626 vault6 = new SemiRedeemable4626(
            IERC20(address(asset6Decimals)),
            "Vault Token 6",
            "VAULT6",
            owner,
            treasury,
            PERFORMANCE_RATE,
            vestingStart,
            vestingEnd
        );

        assertEq(vault6.decimals(), decimals);
    }

    function test_Constructor_RevertWhen_InvalidPerformanceRate() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SemiRedeemable4626.InvalidPerformanceRate.selector,
                MAX_PERFORMANCE_RATE + 1
            )
        );
        
        new SemiRedeemable4626(
            IERC20(address(asset)),
            "Vault Token",
            "VAULT",
            owner,
            treasury,
            MAX_PERFORMANCE_RATE + 1,
            vestingStart,
            vestingEnd
        );
    }

    function test_Constructor_RevertWhen_InvalidTreasury() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SemiRedeemable4626.InvalidTreasury.selector,
                address(0)
            )
        );
        
        new SemiRedeemable4626(
            IERC20(address(asset)),
            "Vault Token",
            "VAULT",
            owner,
            address(0),
            PERFORMANCE_RATE,
            vestingStart,
            vestingEnd
        );
    }

    function test_Constructor_RevertWhen_InvalidVestingSchedule_StartInPast() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SemiRedeemable4626.InvalidVestingSchedule.selector,
                block.timestamp,
                block.timestamp - 1,
                vestingEnd
            )
        );
        
        new SemiRedeemable4626(
            IERC20(address(asset)),
            "Vault Token",
            "VAULT",
            owner,
            treasury,
            PERFORMANCE_RATE,
            block.timestamp - 1,
            vestingEnd
        );
    }

    function test_Constructor_RevertWhen_InvalidVestingSchedule_EndBeforeStart() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SemiRedeemable4626.InvalidVestingSchedule.selector,
                block.timestamp,
                vestingStart,
                vestingStart - 1
            )
        );
        
        new SemiRedeemable4626(
            IERC20(address(asset)),
            "Vault Token",
            "VAULT",
            owner,
            treasury,
            PERFORMANCE_RATE,
            vestingStart,
            vestingStart - 1
        );
    }
}
