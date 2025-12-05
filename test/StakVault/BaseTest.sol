// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/src/Test.sol";
import {StakVault} from "../../src/StakVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title BaseTest
 * @dev Base contract for StakVault tests containing common setup and declarations
 */
contract BaseTest is Test {
    StakVault public vault;
    MockERC20 public asset;

    address public owner = address(0x1);
    address public treasury = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);

    uint256 public constant PERFORMANCE_RATE = 2000; // 20%
    uint256 public constant MAX_PERFORMANCE_RATE = 5000; // 50%
    uint256 public vestingStart;
    uint256 public vestingEnd;

    // Events
    event AssetsTaken(uint256 assets);
    event InvestedAssetsUpdated(uint256 newInvestedAssets, uint256 performanceFee);
    event RedeemsAtNavEnabled();
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public virtual {
        asset = new MockERC20("Test Asset", "TST", 18);

        vestingStart = block.timestamp + 1 days;
        vestingEnd = block.timestamp + 30 days;

        vm.prank(owner);
        vault = new StakVault(
            IERC20(address(asset)), "Vault Token", "VAULT", owner, treasury, PERFORMANCE_RATE, vestingStart, vestingEnd
        );

        // Give users some tokens
        asset.mint(user1, 1000000e18);
        asset.mint(user2, 1000000e18);
        asset.mint(user3, 1000000e18);
        asset.mint(owner, 1000000e18);
    }
}
