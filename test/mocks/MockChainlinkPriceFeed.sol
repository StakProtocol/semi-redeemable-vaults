// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

contract MockChainlinkPriceFeed is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _price;
    uint80 private _roundId;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    constructor(uint8 decimals_, int256 price_) {
        _decimals = decimals_;
        _price = price_;
        _roundId = 1;
        _updatedAt = block.timestamp;
        _answeredInRound = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Chainlink Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _answeredInRound);
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
        _roundId++;
        _updatedAt = block.timestamp;
        _answeredInRound = _roundId;
    }

    function setPriceWithTimestamp(int256 newPrice, uint256 timestamp) external {
        _price = newPrice;
        _roundId++;
        _updatedAt = timestamp;
        _answeredInRound = _roundId;
    }

    function setRoundData(uint80 roundId, int256 price, uint256 updatedAt, uint80 answeredInRound) external {
        _roundId = roundId;
        _price = price;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }
}

