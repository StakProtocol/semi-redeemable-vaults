// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {console} from "forge-std/src/Test.sol";

/**
 * @title StakVault (Semi Redeemable 4626)
 * @dev A simple ERC4626 vault implementation with perpetual put option, vesting mechanics and performance fees
 */

contract StakVault is ERC4626, Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // ========================================================================
    // Constants ==============================================================
    // ========================================================================

    uint256 private constant BPS = 10_000; // 100%
    uint256 private constant MAX_PERFORMANCE_RATE = 5000; // 50 %
    uint256 private constant WAD = 1e18;

    address private immutable _TREASURY;
    uint256 private immutable _PERFORMANCE_RATE;
    uint256 private immutable _VESTING_START;
    uint256 private immutable _VESTING_END;

    // ========================================================================
    // Structs ===============================================================
    // ========================================================================

    struct Position {
        uint256 assetAmount;
        uint256 shareAmount;
        uint256 vestingAmount;
    }

    // ========================================================================
    // State Variables ========================================================
    // ========================================================================

    bool public redeemsAtNav; // Whether redemptions are enabled
    uint256 public highWaterMark; // High water mark of the vault for performance fees
    uint256 public backingBalance; // Backing assets held as backing for open PUTs
    uint256 public investedAssets; // Total assets managed by the vault

    uint256 public nextPositionId;
    mapping(address => Position) public positions;

    /* ========================================================================
    * =============================== Events ================================
    * =========================================================================
    */

    event StakVault__Invested(address indexed user, uint256 positionId, uint256 assetAmount, uint256 shareAmount);

    event AssetsTaken(uint256 assets);
    event InvestedAssetsUpdated(uint256 newInvestedAssets, uint256 performanceFee);
    event RedeemsAtNavEnabled();

    /* ========================================================================
    * =============================== Errors ================================
    * =========================================================================
    */

    error StakVault__ZeroValue();
    error InvalidPerformanceRate(uint256 performanceRate);
    error InvalidTreasury(address treasury);
    error InvalidDecimals(uint8 sharesDecimals, uint8 assetsDecimals);
    error InvalidVestingSchedule(uint256 currentTime, uint256 vestingStart, uint256 vestingEnd);
    error VestingAmountNotRedeemable(address user, uint256 shares, uint256 availableShares);
    error InvalidCAller();

    // ========================================================================
    // =============================== Constructor ============================
    // ========================================================================

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address treasury_,
        uint256 performanceRate_,
        uint256 vestingStart_,
        uint256 vestingEnd_
    ) ERC20(name_, symbol_) ERC4626(asset_) Ownable(owner_) {
        if (performanceRate_ > MAX_PERFORMANCE_RATE) {
            revert InvalidPerformanceRate(performanceRate_);
        }

        if (treasury_ == address(0)) {
            revert InvalidTreasury(treasury_);
        }

        uint8 assetsDecimals = IERC20Metadata(address(asset_)).decimals();
        if (assetsDecimals != decimals()) {
            revert InvalidDecimals(decimals(), assetsDecimals);
        }

        if (vestingStart_ < block.timestamp || vestingEnd_ < vestingStart_) {
            revert InvalidVestingSchedule(block.timestamp, vestingStart_, vestingEnd_);
        }

        highWaterMark = 10 ** decimals();

        _TREASURY = treasury_;
        _PERFORMANCE_RATE = performanceRate_;
        _VESTING_START = vestingStart_;
        _VESTING_END = vestingEnd_;
    }

    // ========================================================================
    // ============================= Owner Functions ==========================
    // ========================================================================

    function takeAssets(uint256 assets) external onlyOwner {
        investedAssets += assets;
        IERC20(asset()).safeTransfer(owner(), assets);
        emit AssetsTaken(assets);
    }

    /**
     * @dev Sets the total assets managed by the vault.
     * Can only be called by the owner.
     * @param newInvestedAssets The new invested assets value
     */
    function updateInvestedAssets(uint256 newInvestedAssets) external onlyOwner {
        investedAssets = newInvestedAssets;

        uint256 performanceFee = _calculatePerformanceFee();

        if (performanceFee > 0) {
            IERC20(asset()).safeTransfer(_TREASURY, performanceFee);
        }

        emit InvestedAssetsUpdated(newInvestedAssets, performanceFee);
    }

    /**
     * @dev Enables redemptions at NAV (Net Asset Value).
     *
     * IMPORTANT: This function should be called by the owner when:
     * 1. The vesting period has ended and users need access to their locked shares
     * 2. The owner wants to switch from fair price to current NAV pricing
     *
     * Once enabled, users can redeem shares at current NAV regardless of vesting status.
     * This is the primary mechanism to unlock shares after the vesting period ends.
     *
     * Can only be called by the owner and cannot be reversed.
     */
    function enableRedeemsAtNav() external onlyOwner {
        redeemsAtNav = true;
        emit RedeemsAtNavEnabled();
    }

    // ========================================================================
    // =============================== Getters ================================
    // ========================================================================

    /**
     * @dev Returns the total amount of assets managed by the vault.
     * This can be set externally by the owner and may differ from the contract's balance.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return super.totalAssets() + investedAssets;
    }

    /**
     * @dev Returns the utilization rate of the vault.
     * @return The utilization rate as a percentage in BPS (10000 = 100%)
     */
    function utilizationRate() public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        if (_totalAssets == 0) return 0;
        return BPS.mulDiv(investedAssets, _totalAssets, Math.Rounding.Floor);
    }

    /**
     * @dev Returns the ledger of the vault.
     * @param user The address to query the ledger for
     * @return Position The ledger of the user
     */
    function positionsOfUser(address user) public view returns (Position memory) {
        return positions[user];
    }

    /**
     * @dev Returns the redeemable shares of the user based on the current vesting schedule.
     *
     * IMPORTANT: This function returns 0 after the vesting period ends, effectively
     * locking all shares until NAV redemptions are enabled by the owner.
     *
     * Vesting phases:
     * - Before vesting starts: Returns 100% of user's vesting shares
     * - During vesting: Returns linearly decreasing amount based on time remaining
     * - After vesting ends: Returns 0 (shares are locked until NAV mode is enabled)
     *
     * @param user The address to query the redeemable shares for
     * @return The redeemable shares (0 if vesting period has ended)
     */
    function redeemableShares(address user) public view returns (uint256) {
        return vestingRate().mulDiv(positions[user].vestingAmount, BPS, Math.Rounding.Floor);
    }

    /**
     * @dev Returns the current vesting rate of the vault.
     *
     * The vesting rate determines what percentage of vested shares are currently redeemable:
     * - Before vesting starts: 10000 (100% - all shares redeemable)
     * - During vesting: Decreases linearly from 10000 to 0
     * - After vesting ends: 0 (0% - no shares redeemable via vesting)
     *
     * @return The vesting rate as a percentage in BPS (10000 = 100%, 0 = 0%)
     */
    function vestingRate() public view returns (uint256) {
        return _calculateVestingRate();
    }

    /**
     * @dev Converts assets to shares.
     * @param assets The assets to convert
     * @param user The user of the assets
     * @return The shares
     */
    function convertToShares(uint256 assets, address user) public view returns (uint256) {
        return _convertToShares(assets, user, Math.Rounding.Floor);
    }

    /**
     * @dev Converts shares to assets.
     * @param shares The shares to convert
     * @param user The user of the shares
     * @return The assets
     */
    function convertToAssets(uint256 shares, address user) public view returns (uint256) {
        return _convertToAssets(shares, user, Math.Rounding.Floor);
    }

    // ========================================================================
    // =============================== Overrides ==============================
    // ========================================================================

    /**
     * @dev Override deposit to track deposits per user.
     * @param assets The assets to deposit
     * @param _receiver The receiver of the shares
     * @return shares
     */
    function deposit(uint256 assets, address _receiver) public virtual override returns (uint256 shares) {
        shares = super.deposit(assets, address(this));

        if (!redeemsAtNav) {
            _invest(assets, shares);
        }
    }

    /**
     * @dev Override mint to track deposits per user.
     * @param shares The shares to mint
     * @param _receiver The receiver of the assets
     * @return assets
     */
    function mint(uint256 shares, address _receiver) public virtual override returns (uint256 assets) {
        assets = super.mint(shares, address(this));

        if (!redeemsAtNav) {
            _invest(assets, shares);
        }
    }

    function _invest(uint256 assetAmount, uint256 shareAmount) internal returns (uint256 positionId) {
        if (assetAmount == 0) {
            revert StakVault__ZeroValue();
        }

        backingBalance += assetAmount;

        // update position
        Position storage userPosition = positions[msg.sender];
        userPosition.assetAmount += assetAmount;
        userPosition.shareAmount += shareAmount;
        userPosition.vestingAmount += shareAmount;

        emit StakVault__Invested(msg.sender, positionId, assetAmount, shareAmount);
    }

    /**
     * @dev Override redeem to check if redemptions are enabled.
     * @param shares The shares to redeem
     * @param receiver The receiver of the assets
     * @param user The user of the shares
     * @return The assets
     */
    function redeem(uint256 shares, address receiver, address user) public virtual override returns (uint256) {
        if (_msgSender() != user) revert InvalidCAller();

        uint256 maxShares = maxRedeem(user);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(user, shares, maxShares);
        }

        uint256 assets = _previewRedeem(shares, user);

        if (!redeemsAtNav) {
            uint256 availableShares = redeemableShares(user);

            if (shares > availableShares) {
                revert VestingAmountNotRedeemable(user, shares, availableShares);
            }

            Position storage userPosition = positions[user];
            userPosition.assetAmount -= assets;
            userPosition.shareAmount -= availableShares;
            userPosition.vestingAmount -= availableShares;
        }

        _withdraw(_msgSender(), receiver, address(this), assets, shares);

        return assets;
    }

    /**
     * @dev Override withdraw to update the ledger.
     * @param assets The assets to withdraw
     * @param receiver The receiver of the shares
     * @param user The user of the assets
     * @return The shares
     */
    function withdraw(uint256 assets, address receiver, address user) public virtual override returns (uint256) {
        if (_msgSender() != user) revert InvalidCAller();

        uint256 maxAssets = maxWithdraw(user);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(user, assets, maxAssets);
        }

        uint256 shares = _previewWithdraw(assets, user);

        if (!redeemsAtNav) {
            uint256 availableShares = redeemableShares(user);

            if (shares > availableShares) {
                revert VestingAmountNotRedeemable(user, shares, availableShares);
            }

            Position storage userPosition = positions[user];
            userPosition.assetAmount -= assets;
            userPosition.shareAmount -= availableShares;
            userPosition.vestingAmount -= availableShares;
        }

        _transfer(address(this), receiver, shares);

        return shares;
    }

    /**
     * @dev Preview the shares to withdraw per user
     * @param assets The assets to withdraw
     * @return The shares
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return _previewWithdraw(assets, _msgSender());
    }

    /**
     * @dev Preview the assets to redeem per user
     * @param shares The shares to redeem
     * @return The assets
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return _previewRedeem(shares, _msgSender());
    }

    // ========================================================================
    // =============================== Non Overrides ==========================
    // ========================================================================

    /**
     * @dev Preview the shares to withdraw per user
     * If redemptions are at NAV, return the shares (same as 4626)
     * Otherwise, return the maximum between the shares and the shares of the user (to prevent underflow)
     * @param assets The assets to withdraw
     * @param user The user of the assets
     * @return The shares
     */
    function _previewWithdraw(uint256 assets, address user) private view returns (uint256) {
        uint256 shares = _convertToShares(assets, Math.Rounding.Ceil);
        if (redeemsAtNav) return shares;
        return Math.min(shares, _convertToShares(assets, user, Math.Rounding.Ceil));
    }

    /**
     * @dev Preview the assets to redeem per user
     * If redemptions are at NAV, return the assets (same as 4626)
     * Otherwise, return the minimum between the assets and the assets of the user (to prevent underflow)
     * @param shares The shares to redeem
     * @param user The user of the shares
     * @return The assets
     */
    function _previewRedeem(uint256 shares, address user) private view returns (uint256) {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);
        if (redeemsAtNav) return assets;
        return Math.min(assets, _convertToAssets(shares, user, Math.Rounding.Floor));
    }

    /**
     * @dev Converts assets to shares per user using the ledger as a fair exchange rate
     * @param assets The assets to convert
     * @param user The user of the assets
     * @param rounding The rounding direction
     * @return The shares
     */
    function _convertToShares(uint256 assets, address user, Math.Rounding rounding) private view returns (uint256) {
        uint256 totalVestingShares = positions[user].vestingAmount;
        uint256 totalAssetAmount = positions[user].assetAmount;

        if (assets == 0 || totalVestingShares == 0 || totalAssetAmount == 0) {
            return _convertToShares(assets, rounding);
        }
        return assets.mulDiv(totalVestingShares, totalAssetAmount, rounding);
    }

    /**
     * @dev Converts shares to assets per user using the ledger as a fair exchange rate
     * @param shares The shares to convert
     * @param user The user of the shares
     * @param rounding The rounding direction
     * @return The assets
     */
    function _convertToAssets(uint256 shares, address user, Math.Rounding rounding) private view returns (uint256) {
        uint256 totalVestingShares = positions[user].vestingAmount;
        uint256 totalAssetAmount = positions[user].assetAmount;

        if (shares == 0 || totalVestingShares == 0 || totalAssetAmount == 0) {
            return _convertToAssets(shares, rounding);
        }
        return shares.mulDiv(totalAssetAmount, totalVestingShares, rounding);
    }

    function _burnVestingShares(address user, uint256 sharesToBurn) internal {
        Position storage userPosition = positions[user];
        userPosition.vestingAmount -= sharesToBurn;
    }

    /* ========================================================================
    * =========================== Performance Fees ============================
    * =========================================================================
    */

    /// @dev Calculate the performance fee
    /// @dev The performance is calculated as the difference between the current price per share and the high water mark
    /// @dev The performance fee is calculated as the product of the performance and the performance rate
    function _calculatePerformanceFee() internal returns (uint256 performanceFee) {
        uint256 pricePerShare = _convertToAssets(10 ** decimals(), Math.Rounding.Ceil);

        if (pricePerShare > highWaterMark) {
            uint256 profitPerShare = pricePerShare - highWaterMark;

            uint256 profit = profitPerShare.mulDiv(totalSupply(), 10 ** decimals(), Math.Rounding.Ceil);
            performanceFee = profit.mulDiv(_PERFORMANCE_RATE, BPS, Math.Rounding.Ceil);

            highWaterMark = pricePerShare;
        }
    }

    /* ========================================================================
    * =========================== Vesting Schedule ============================
    * =========================================================================
    */

    /**
     * @dev Calculates the current vesting rate based on the vesting schedule.
     *
     * This function implements the core vesting logic:
     * 1. Pre-vesting: Returns 100% (BPS = 10000)
     * 2. During vesting: Returns linearly decreasing rate
     * 3. Post-vesting: Returns 0% - THIS LOCKS ALL SHARES
     *
     * The post-vesting behavior (returning 0) is intentional and prevents
     * redemptions at potentially stale fair prices after the vesting period.
     * Users must wait for NAV redemptions to be enabled to access their funds.
     *
     * @return The vesting rate in basis points (0-10000)
     */
    function _calculateVestingRate() internal view returns (uint256) {
        if (block.timestamp < _VESTING_START) {
            return BPS;
        }

        if (block.timestamp > _VESTING_END) {
            return 0;
        }

        return BPS.mulDiv(_VESTING_END - block.timestamp, _VESTING_END - _VESTING_START, Math.Rounding.Floor);
    }
}
