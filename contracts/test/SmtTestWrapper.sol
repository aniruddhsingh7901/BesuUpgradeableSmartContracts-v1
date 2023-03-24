// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import "../lib/SmtLib.sol";

contract SmtLibTestWrapper {
    SmtLib.SmtData internal smtData;
    using SmtLib for SmtLib.SmtData;

    constructor(uint256 maxDepth) {
        smtData.setMaxDepth(maxDepth);
    }

    function add(uint256 i, uint256 v) public {
        smtData.add(i, v);
    }

    function getProof(uint256 id) public view returns (SmtLib.Proof memory) {
        return smtData.getProof(id);
    }

    function getProofByRoot(uint256 id, uint256 root) public view returns (SmtLib.Proof memory) {
        return smtData.getProofByRoot(id, root);
    }

    function getProofByTime(uint256 id, uint256 timestamp) public view returns (SmtLib.Proof memory) {
        return smtData.getProofByTime(id, timestamp);
    }

    function getProofByBlock(uint256 id, uint256 block) public view returns (SmtLib.Proof memory) {
        return smtData.getProofByBlock(id, block);
    }

    function getRootHistoryLength() public view returns (uint256) {
        return smtData.getRootHistoryLength();
    }

    function getRoot() public view returns (uint256) {
        return smtData.getRoot();
    }

    function getRootInfo(uint256 root) public view returns (IState.RootInfo memory) {
        return smtData.getRootInfo(root);
    }

    function getRootInfoListLengthByRoot(uint256 root) public view returns (uint256) {
        return smtData.getRootInfoListLengthByRoot(root);
    }

    function getRootInfoListByRoot(uint256 root, uint256 start, uint256 length) public view returns (IState.RootInfo[] memory) {
        return smtData.getRootInfoListByRoot(root, start, length);
    }

    function setMaxDepth(uint256 maxDepth) public {
        smtData.setMaxDepth(maxDepth);
    }

    function getMaxDepth() public view returns (uint256) {
        return smtData.getMaxDepth();
    }
}
