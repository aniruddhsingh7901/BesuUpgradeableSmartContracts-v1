// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import "../lib/SmtLib.sol";

contract BinarySearchTestWrapper {
    SmtLib.SmtData internal smtData;
    using SmtLib for SmtLib.SmtData;

    function addRootEntry(
        uint256 root,
        uint256 createdAtTimestamp,
        uint256 createdAtBlock
    ) public {
        smtData.rootEntries.push(SmtLib.RootEntry({
            root: root,
            createdAtTimestamp: createdAtTimestamp,
            createdAtBlock: createdAtBlock
        }));

        smtData.rootEntryIndexes[root].push(smtData.rootEntries.length - 1);
    }

    function getRootInfoByTime(uint256 _timestamp) public view returns (IState.RootInfo memory) {
        return smtData.getRootInfoByTime(_timestamp);
    }

    function getHistoricalRootByBlock(uint256 _block) public view returns (IState.RootInfo memory) {
        return smtData.getRootInfoByBlock(_block);
    }
}
