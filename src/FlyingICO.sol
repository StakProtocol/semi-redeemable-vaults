// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
  Flying ICO — Simplified Investment Contract
  - Users deposit accepted assets in form of accepted ERC20s
  - USD value is taken from Chainlink price feeds (aggregators).
  - Mint Tokens at X Tokens per $1 USD contributed.
  - Token maximum supply: X Tokens (with 18 decimals).
  - When minted on primary, Tokens are held by this contract and tracked in a PerpetualPUT Position.
  - Users can Divest (burn Tokens from their position and get back original asset amount)
    or Withdraw (release Tokens to user, invalidating the PUT portion and freeing backing
    to protocol backing pool).
*/

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {ChainlinkLibrary} from "./utils/Chainlink.sol";

contract FlyingICO is ERC20, ERC20Burnable, ERC20Permit, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // ========================================================================
    // Constants ==============================================================
    // ========================================================================

    address public constant ETH_ADDR = address(0);
    uint256 public constant WAD = 1e18;

    uint256 public immutable _TOKENS_CAP;
    uint256 public immutable _TOKENS_PER_USD;
    address public immutable _TREASURY;

    // ========================================================================
    // Structs ===============================================================
    // ========================================================================

    struct Position {
        address user; // owner of the position
        address asset; // asset used at deposit (ETH_ADDR for native)
        uint256 assetAmount; // amount of original asset reserved (in asset decimals)
        uint256 tokenAmount; // amount of FT (in FT units) reserved and locked in PUT
    }

    // ========================================================================
    // Errors =================================================================
    // ========================================================================

    error InvalidArraysLength(uint256 length1, uint256 length2);
    error FlyingICO__ZeroValue();
    error FlyingICO__AssetNotAccepted(address asset);
    error FlyingICO__NoPriceFeedForAsset(address asset);
    error FlyingICO__ZeroUsdValue();
    error FlyingICO__ZeroTokenAmount();
    error FlyingICO__TokensCapExceeded();
    error FlyingICO__ZeroPrice(address asset);
    error FlyingICO__InsufficientBacking();
    error FlyingICO__TransferFailed();
    error FlyingICO__InsufficientAssetAmount();
    error FlyingICO__InsufficientETH();
    error FlyingICO__NotEnoughLockedTokens();
    error FlyingICO__Unauthorized();
    error FlyingICO__ZeroAddress();

    // ========================================================================
    // Events =================================================================
    // ========================================================================

    event FlyingICO__Initialized(
        string name,
        string symbol,
        uint256 tokenCap,
        uint256 tokensPerUsd,
        address[] acceptedAssets,
        address[] priceFeeds
    );
    event FlyingICO__Invested(
        address indexed user, uint256 positionId, address asset, uint256 assetAmount, uint256 tokensMinted
    );
    event FlyingICO__Divested(
        address indexed user,
        uint256 positionId,
        uint256 tokensBurned,
        address assetReturned,
        uint256 assetReturnedAmount
    );
    event FlyingICO__Withdrawn(
        address indexed user,
        uint256 positionId,
        uint256 tokensUnlocked,
        address assetReleased,
        uint256 assetReleasedAmount
    );
    event FlyingICO__BuybackAndBurn(
        address indexed caller, address assetUsed, uint256 assetAmountUsed, uint256 tokensBurned
    );

    // ========================================================================
    // State Variables ========================================================
    // ========================================================================

    uint256 public nextPositionId = 1;
    mapping(uint256 => Position) public positions; // positionId -> position
    mapping(address => uint256[]) public positionsOf; // user -> positionsIds
    mapping(address => uint256) public backingBalances; // Backing assets held as backing for open PUTs (asset -> amount)

    mapping(address => bool) public acceptedAssets; // accepted assets
    mapping(address => address) public priceFeeds; // asset -> chainlink aggregator (USD)

    // ========================================================================
    // Constructor ============================================================
    // ========================================================================

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 tokenCap_, // in tokens, not units
        uint256 tokensPerUsd_, // 10 Tokens per $1
        address[] memory acceptedAssets_,
        address[] memory priceFeeds_,
        address treasury_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (acceptedAssets_.length != priceFeeds_.length) {
            revert InvalidArraysLength(acceptedAssets_.length, priceFeeds_.length);
        }

        // set accepted assets and price feeds
        for (uint256 i = 0; i < acceptedAssets_.length; i++) {
            acceptedAssets[acceptedAssets_[i]] = true;
            priceFeeds[acceptedAssets_[i]] = priceFeeds_[i];
        }

        if (treasury_ == address(0)) {
            revert FlyingICO__ZeroAddress();
        }

        _TOKENS_CAP = tokenCap_ * WAD;
        _TOKENS_PER_USD = tokensPerUsd_ * WAD;
        _TREASURY = treasury_;

        emit FlyingICO__Initialized(name_, symbol_, tokenCap_, tokensPerUsd_, acceptedAssets_, priceFeeds_);
    }

    // ========================================================================
    // External Functions =====================================================
    // ========================================================================

    /// @notice Invest ETH into the contract
    /// @return positionId the id of the position created
    function investEther() external payable nonReentrant returns (uint256 positionId) {
        positionId = _invest(ETH_ADDR, msg.value);
    }

    /// @notice Invest an accepted ERC20 token. Caller must have approved this contract for `assetAmount`.
    /// @param asset the asset to invest
    /// @param assetAmount the amount of asset to invest
    /// @return positionId the id of the position created
    function investERC20(address asset, uint256 assetAmount) external nonReentrant returns (uint256 positionId) {
        positionId = _invest(asset, assetAmount);
        IERC20(asset).safeTransferFrom(msg.sender, address(this), assetAmount);
    }

    /// @notice Divest some or all of your Perpetual PUT (burn Tokens in the position and receive asset at par)
    /// @param positionId Id of the position created at invest
    /// @param tokensToBurn amount of Tokens (in Tokens units) to divest from that position
    /// @dev This function is used to divest some or all of your Perpetual PUT (burn Tokens in the position and receive asset at par)
    /// @param positionId Id of the position created at invest
    function divest(uint256 positionId, uint256 tokensToBurn) external nonReentrant {
        // sanity check
        _divestSanityCheck(positionId, tokensToBurn);
        // compute proportional asset return
        uint256 assetReturn = _computeAssetAmount(positionId, tokensToBurn);

        // Update position
        Position storage position = positions[positionId];
        position.tokenAmount -= tokensToBurn;
        position.assetAmount -= assetReturn;
        // burn the Token from contract balance
        _burn(address(this), tokensToBurn);
        // reduce backing
        backingBalances[position.asset] -= assetReturn;

        // Transfer asset back to user
        if (position.asset == ETH_ADDR) {
            // native ETH
            (bool sent,) = msg.sender.call{value: assetReturn}("");

            if (!sent) {
                revert FlyingICO__TransferFailed();
            }
        } else {
            IERC20(position.asset).safeTransfer(msg.sender, assetReturn);
        }

        emit FlyingICO__Divested(msg.sender, positionId, tokensToBurn, position.asset, assetReturn);
    }

    /// @notice Withdraw (unlock) some or all Tokens from your Perpetual PUT. This invalidates the PUT on that portion forever,
    /// and transfers Tokens to the user. The backing previously reserved becomes available for protocol operations.
    /// @param positionId Id of the position created at invest
    /// @param tokensToUnlock amount of Tokens (in Tokens units) to unlock from that position
    /// @dev This function is used to withdraw some or all of your Perpetual PUT (unlock Tokens from the position and receive asset at par)
    function withdraw(uint256 positionId, uint256 tokensToUnlock) external nonReentrant {
        // sanity check
        _withdrawSanityCheck(positionId, tokensToUnlock);
        // compute proportional asset return
        uint256 assetReleased = _computeAssetAmount(positionId, tokensToUnlock);

        // Update position
        Position storage position = positions[positionId];
        position.tokenAmount -= tokensToUnlock;
        position.assetAmount -= assetReleased;

        // reduce backing
        backingBalances[position.asset] -= assetReleased;

        // Transfer Tokens from contract to user (these Tokens lose the Perpetual PUT)
        // The Tokens are already minted and sitting in this contract
        _transfer(address(this), msg.sender, tokensToUnlock);

        // Released backing becomes available for protocol operations:
        // Backing has been reduced above, so the released assets are now available
        // to the treasury for protocol operations via takeAssetsToTreasury.
        emit FlyingICO__Withdrawn(msg.sender, positionId, tokensToUnlock, position.asset, assetReleased);
    }

    /// @notice Take assets from the contract to the treasury
    /// @param asset asset to take
    /// @param assetAmount amount of asset to take
    function takeAssetsToTreasury(address asset, uint256 assetAmount) external nonReentrant {
        if (assetAmount == 0) {
            revert FlyingICO__ZeroValue();
        }

        if (!acceptedAssets[asset]) {
            revert FlyingICO__AssetNotAccepted(asset);
        }

        if (asset == ETH_ADDR) {
            uint256 availableAssets = address(this).balance - backingBalances[asset];

            if (availableAssets < assetAmount) {
                revert FlyingICO__InsufficientETH();
            }

            (bool sent,) = payable(_TREASURY).call{value: assetAmount}("");
            if (!sent) {
                revert FlyingICO__TransferFailed();
            }
        } else {
            uint256 availableAssets = IERC20(asset).balanceOf(address(this)) - backingBalances[asset];

            if (availableAssets < assetAmount) {
                revert FlyingICO__InsufficientAssetAmount();
            }

            IERC20(asset).safeTransfer(_TREASURY, assetAmount);
        }
    }

    /// @notice Get the positions of a user
    /// @param user the user to get the positions of
    /// @return positions the positions of the user
    function positionsOfUser(address user) external view returns (uint256[] memory) {
        return positionsOf[user];
    }

    // ========================================================================
    // Internal functions =====================================================
    // ========================================================================

    /// @notice Internal function to invest an asset
    /// @param asset the asset to invest
    /// @param assetAmount the amount of asset to invest
    /// @return positionId the id of the position created
    function _invest(address asset, uint256 assetAmount) internal returns (uint256 positionId) {
        // sanity check
        _investSanityCheck(asset, assetAmount);
        // compute token amount
        uint256 tokenAmount = _computeTokenAmount(asset, assetAmount);
        // mint tokens to this contract
        _mint(address(this), tokenAmount);
        // record backing
        backingBalances[asset] += assetAmount;
        // create position
        positionId = nextPositionId++;
        positions[positionId] =
            Position({user: msg.sender, asset: asset, assetAmount: assetAmount, tokenAmount: tokenAmount});
        positionsOf[msg.sender].push(positionId);

        emit FlyingICO__Invested(msg.sender, positionId, asset, assetAmount, tokenAmount);
    }

    /// @notice Internal function to check the sanity of an investment
    /// @param asset the asset to invest
    /// @param assetAmount the amount of asset to invest
    function _investSanityCheck(address asset, uint256 assetAmount) internal view {
        if (assetAmount == 0) {
            revert FlyingICO__ZeroValue();
        }

        if (!acceptedAssets[asset]) {
            revert FlyingICO__AssetNotAccepted(asset);
        }

        if (priceFeeds[asset] == address(0)) {
            revert FlyingICO__NoPriceFeedForAsset(asset);
        }
    }

    /// @notice Internal function to check the sanity of a divestment
    /// @param positionId Id of the position created at invest
    /// @param tokensToBurn amount of Tokens (in Tokens units) to divest from that position
    function _divestSanityCheck(uint256 positionId, uint256 tokensToBurn) internal view {
        if (tokensToBurn == 0) {
            revert FlyingICO__ZeroValue();
        }

        if (positions[positionId].user != msg.sender) {
            revert FlyingICO__Unauthorized();
        }

        if (positions[positionId].tokenAmount < tokensToBurn) {
            revert FlyingICO__NotEnoughLockedTokens();
        }
    }

    /// @notice Internal function to check the sanity of a withdrawal
    /// @param positionId Id of the position created at invest
    /// @param tokensToUnlock amount of Tokens (in Tokens units) to unlock from that position
    function _withdrawSanityCheck(uint256 positionId, uint256 tokensToUnlock) internal view {
        _divestSanityCheck(positionId, tokensToUnlock);
    }

    /// @notice Internal function to compute the token amount for an investment
    /// @param asset the asset to invest
    /// @param assetAmount the amount of asset to invest
    /// @return tokenAmount the amount of tokens to mint
    function _computeTokenAmount(address asset, uint256 assetAmount) internal view returns (uint256 tokenAmount) {
        // compute USD value
        uint256 usdValue = _assetToUsdValue(asset, assetAmount);

        if (usdValue == 0) {
            revert FlyingICO__ZeroUsdValue();
        }

        // Tokens to mint
        tokenAmount = usdValue.mulDiv(_TOKENS_PER_USD, WAD, Math.Rounding.Floor);

        if (tokenAmount == 0) {
            revert FlyingICO__ZeroTokenAmount();
        }

        // Enforce cap
        if (totalSupply() + tokenAmount > _TOKENS_CAP) {
            revert FlyingICO__TokensCapExceeded();
        }
    }

    /// @notice Internal function to compute the asset amount for a divestment
    /// @param positionId Id of the position created at invest
    /// @param tokensToBurn amount of Tokens (in Tokens units) to divest from that position
    /// @return assetAmount the amount of asset to return
    function _computeAssetAmount(uint256 positionId, uint256 tokensToBurn) internal view returns (uint256 assetAmount) {
        Position memory position = positions[positionId];

        if (position.tokenAmount == 0) {
            revert FlyingICO__ZeroTokenAmount();
        }

        assetAmount = tokensToBurn.mulDiv(position.assetAmount, position.tokenAmount, Math.Rounding.Floor);

        if (assetAmount == 0) {
            revert FlyingICO__ZeroValue();
        }

        if (position.assetAmount < assetAmount) {
            // invariant - this should never happen
            revert FlyingICO__InsufficientAssetAmount();
        }

        if (backingBalances[position.asset] < assetAmount) {
            // invariant - this should never happen
            revert FlyingICO__InsufficientBacking();
        }
    }

    // Convert an asset amount (raw asset units) into USD with 18 decimals precision
    /// @param asset the asset to convert
    /// @param assetAmount the amount of asset to convert
    /// @return usdValue the USD value of the asset in USD with 18 decimals precision
    function _assetToUsdValue(address asset, uint256 assetAmount) internal view returns (uint256 usdValue) {
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeeds[asset]);

        // TODO: missing frequency of oracles and sequencer for L2s
        uint256 price = ChainlinkLibrary.getPrice(address(feed));
        uint256 feedUnits = 10 ** uint256(feed.decimals());
        uint256 assetUnits = 10 ** _getDecimals(asset);

        usdValue = assetAmount.mulDiv(price * WAD, assetUnits * feedUnits, Math.Rounding.Floor);
    }

    // Read ERC20 decimals
    /// @param token the token to get the decimals of
    /// @return decimals the decimals of the token
    function _getDecimals(address token) internal view returns (uint256) {
        if (token == ETH_ADDR) return 18;

        return uint256(IERC20Metadata(token).decimals());
    }
}
