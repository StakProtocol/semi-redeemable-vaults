// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IPriceFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

library ChainlinkLibrary {
    error ChainlinkLibrary__InvalidOracle();
    error ChainlinkLibrary__InvalidPrice();
    error ChainlinkLibrary__OldData();
    error ChainlinkLibrary__RoundNotComplete();
    error ChainlinkLibrary__StalePrice();
    error ChainlinkLibrary__SequencerDown();
    error ChainlinkLibrary__GracePeriodNotOver();

    function getPrice(address oracle) internal view returns (uint256) {
        return getPrice(oracle, 0, address(0));
    }

    function getPrice(address oracle, uint256 frequency) internal view returns (uint256) {
        return getPrice(oracle, frequency, address(0));
    }

    function getPrice(address oracle, uint256 frequency, address sequencer) internal view returns (uint256) {
        (uint80 roundId, int256 price,, uint256 updatedAt, uint80 answeredInRound) =
            IPriceFeed(oracle).latestRoundData();

        if (oracle == address(0)) {
            revert ChainlinkLibrary__InvalidOracle();
        }

        if (price <= 0) {
            revert ChainlinkLibrary__InvalidPrice();
        }

        if (answeredInRound < roundId || roundId == 0) {
            revert ChainlinkLibrary__OldData();
        }

        if (updatedAt <= 0) {
            revert ChainlinkLibrary__RoundNotComplete();
        }

        if (frequency > 0) {
            if (block.timestamp - updatedAt > frequency) {
                revert ChainlinkLibrary__StalePrice();
            }
        }

        if (sequencer != address(0)) {
            (, int256 answer, uint256 startedAt,,) = IPriceFeed(sequencer).latestRoundData();

            if (answer > 0) {
                // 0: Sequencer is up, 1: Sequencer is down
                revert ChainlinkLibrary__SequencerDown();
            }

            if (startedAt <= 0) {
                revert ChainlinkLibrary__RoundNotComplete();
            }

            if (block.timestamp - startedAt <= 1 hours) {
                revert ChainlinkLibrary__GracePeriodNotOver();
            }
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(price);
    }
}
