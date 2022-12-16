// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;
pragma abicoder v2;

import "../lib/Smt.sol";

contract SmtTestWrapper {
    Smt.SmtData internal smtData;
    using Smt for Smt.SmtData;

    function add(uint256 _i, uint256 _v) public {
        smtData.add(_i, _v);
    }

    function getSmtProof(uint256 _id) public view returns (Smt.Proof memory) {
        return smtData.getProof(_id);
    }

    function getSmtHistoricalProofByRoot(uint256 _id, uint256 _root)
        public
        view
        returns (Smt.Proof memory)
    {
        return smtData.getProofByRoot(_id, _root);
    }
}
