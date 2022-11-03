// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../lib/Smt.sol";
import "../lib/Poseidon.sol";

interface IVerifier {
    function verifyProof(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[4] memory input
    ) external view returns (bool r);
}

// /**
//  * @dev Set and get states for each identity
//  */
// contract State is Iden3Helpers {
contract StateV2 is OwnableUpgradeable {
    /**
     * @dev Struct saved information about transition state for identifier.
     * @param replacedAtTimestamp commit time when state was changed.
     * @param createdAtTimestamp commit time when state was saved into blockchain.
     * @param replacedAtBlock commit number of block when state was changed.
     * @param createdAtBlock commit number of block when state was created.
     * @param replacedBy commit  state with which the current state has been replaced.
     * @param id identity.
     */
    struct TransitionsInfo {
        uint256 replacedAtTimestamp;
        uint256 createdAtTimestamp;
        uint256 replacedAtBlock;
        uint256 createdAtBlock;
        uint256 replacedBy;
        uint256 id;
    }

    /**
     * @dev Verifier address
     */
    IVerifier public verifier;

    /**
     * @dev A state histories of each identity.
     */
    mapping(uint256 => uint256[]) public statesHistories;

    /**
     * @dev A state transitions info of each identity.
     */
    mapping(uint256 => TransitionsInfo) public stateTransitions;

    /**
     * @dev event called when a state is updated
     * @param id identity
     * @param blockN Block number when the state has been committed
     * @param timestamp Timestamp when the state has been committed
     * @param state Identity state committed
     */
    event StateUpdated(
        uint256 id,
        uint256 blockN,
        uint256 timestamp,
        uint256 state
    );

    SmtData internal smtData;
    using Smt for SmtData;

    /**
     * @dev Initialize the contract
     * @param _verifierContractAddr Verifier address
     */
    function initialize(IVerifier _verifierContractAddr) public initializer {
        verifier = _verifierContractAddr;
        __Ownable_init();
    }

    /**
     * @dev Set ZKP verifier contract address
     * @param _newVerifierAddr Verifier contract address
     */
    function setVerifier(address _newVerifierAddr) public onlyOwner {
        verifier = IVerifier(_newVerifierAddr);
    }

    /**
     * @dev Get ZKP verifier contract address
     * @return verifier contract address
     */
    function getVerifier() public view returns (address) {
        return address(verifier);
    }

    /**
     * @dev Change the state of an identity (transit to the new state) with ZKP ownership check.
     * @param _id Identity
     * @param _oldState Previous identity state
     * @param _newState New identity state
     * @param _isOldStateGenesis Is the previous state genesis?
     * @param a ZKP proof field
     * @param b ZKP proof field
     * @param c ZKP proof field
     */
    function transitState(
        uint256 _id,
        uint256 _oldState,
        uint256 _newState,
        bool _isOldStateGenesis,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c
    ) public {
        if (_isOldStateGenesis == false) {
            require(
                statesHistories[_id].length > 0,
                "there should be at least one state for identity in smart contract when _isOldStateGenesis == 0"
            );

            uint256 previousIDState = statesHistories[_id][statesHistories[_id].length - 1];

            require(
                stateTransitions[previousIDState].createdAtBlock != block.number,
                "no multiple set in the same block"
            );
            require(
                previousIDState == _oldState,
                "_oldState argument should be equal to the latest identity state in smart contract when isOldStateGenesis == 0"
            );
        } else {
            require(
                statesHistories[_id].length == 0,
                "there should be no states for identity in smart contract when _isOldStateGenesis != 0"
            );
            require(stateTransitions[_oldState].id == 0, "oldState should not exist");
            // link genesis state to Id in the smart contract, but creation time and creation block is unknown
            stateTransitions[_oldState].id = _id;
            // push genesis state to identities as latest state
            statesHistories[_id].push(_oldState);
        }

        require(stateTransitions[_newState].id == 0, "newState should not exist");

        uint256[4] memory input = [
        _id,
        _oldState,
        _newState,
            uint256(_isOldStateGenesis ? 1 : 0)
        ];
        require(
            verifier.verifyProof(a, b, c, input),
            "zero-knowledge proof of state transition is not valid "
        );

        statesHistories[_id].push(_newState);

        // Set create info for new state
        stateTransitions[_newState] = TransitionsInfo(
            0,
            block.timestamp,
            0,
            block.number,
            0,
            _id
        );

        // Set replace info for old state
        stateTransitions[_oldState].replacedAtTimestamp = block.timestamp;
        stateTransitions[_oldState].replacedAtBlock = block.number;
        stateTransitions[_oldState].replacedBy = _newState;

        // put state in smt to recalculate global state
        smtData.add(PoseidonUnit1L.poseidon([_id]), _newState);

        emit StateUpdated(_id, block.number, block.timestamp, _newState);
    }

    /**
     * @dev Retrieve the last state for a given identity
     * @param _id identity
     * @return last state committed
     */
    function getState(uint256 _id) public view returns (uint256) {
        if (statesHistories[_id].length == 0) {
            return 0;
        }
        return statesHistories[_id][statesHistories[_id].length - 1];
    }

    /**
     * @dev Retrieve state information.
     * @param _state A state
     * @return The state info
     */
    function getTransitionInfo(uint256 _state)
        public
        view
        returns (TransitionsInfo memory)
    {
        return stateTransitions[_state];
    }

    /**
     * @dev Retrieve identity latest state information.
     * @param _id Identity
     * @return The latest state info of the identity
     */
    function getStateDataById(uint256 _id)
        public
        view
        returns (TransitionsInfo memory)
    {
        TransitionsInfo memory info;
        if (statesHistories[_id].length == 0) {
            return info;
        }
        uint256 lastIdState = statesHistories[_id][statesHistories[_id].length - 1];

        return stateTransitions[lastIdState];
    }

    /**
     * @dev Retrieve SMT latest root.
     * @return The latest SMT root
     */
    function getSmtCurrentRoot() public view returns (uint256) {
        return smtData.getCurrentRoot();
    }

/**
     * @dev Retrieve SMT inclusion or non-inclusion proof for a given identity.
     * @param _id Identity
     * @return The SMT inclusion or non-inclusion proof for the identity
     */
    function getSmtProof(uint256 _id) public view returns (Proof memory) {
        return smtData.getProof(PoseidonUnit1L.poseidon([_id]));
    }

    /**
     * @dev Retrieve SMT inclusion or non-inclusion proof for a given identity for
     * some SMT root in the past.
     * @param _id Identity
     * @param _root SMT root
     * @return The SMT inclusion or non-inclusion proof for the identity
     */
    function getSmtHistoricalProofByRoot(uint256 _id, uint256 _root)
        public
        view
        returns (Proof memory)
    {
        return
            smtData.getHistoricalProofByRoot(
                PoseidonUnit1L.poseidon([_id]),
                _root
            );
    }

    /**
     * @dev Retrieve SMT inclusion or non-inclusion proof for a given identity
     * for SMT root existed in some block or later.
     * @param _id Identity
     * @param _block Blockchain block number
     * @return The SMT inclusion or non-inclusion proof for the identity
     */
    function getSmtHistoricalProofByBlock(uint256 _id, uint256 _block)
        public
        view
        returns (Proof memory)
    {
        return
            smtData.getHistoricalProofByBlock(
                PoseidonUnit1L.poseidon([_id]),
                _block
            );
    }

/**
     * @dev Retrieve SMT inclusion or non-inclusion proof for a given identity
     * for SMT root existed for some blockchain timestamp or later.
     * @param _id Identity
     * @param _timestamp Blockchain timestamp
     * @return The SMT inclusion or non-inclusion proof for the identity
     */
    function getSmtHistoricalProofByTime(uint256 _id, uint256 _timestamp)
        public
        view
        returns (Proof memory)
    {
        return
            smtData.getHistoricalProofByTime(
                PoseidonUnit1L.poseidon([_id]),
                _timestamp
            );
    }

    /**
     * @dev Retrieve the length of the SMT root history.
     * @return The SMT root history length
     */
    function getSmtRootHistoryLength() public view returns (uint256) {
        return smtData.rootHistory.length;
    }

    /**
     * @dev Retrieve the SMT root history slice.
     * @param _start Start index in the history array
     * @param _end End index in the history array
     * @return SMT roots list.
     */
    function getSmtRootHistory(uint256 _start, uint256 _end)
        public
        view
        returns (RootInfo[] memory)
    {
        return smtData.getRootHistory(_start, _end);
    }

    /**
     * @dev Retrieve the specific SMT root information.
     * @param _root SMT root
     * @return The SMT root info
     */
    function getSmtRootInfo(uint256 _root)
        public
        view
        returns (RootInfo memory)
    {
        return smtData.getRootInfo(_root);
    }

    /**
     * @dev Retrieve the SMT root information, which existed at some block or later.
     * @param _block Blockchain block number
     * @return The SMT root info
     */
    function getHistoricalRootInfoByBlock(uint256 _block)
        public
        view
        returns (RootInfo memory)
    {
        return smtData.getHistoricalRootInfoByBlock(_block);
    }

    /**
     * @dev Retrieve the SMT root information, which existed at some blockchain timestamp or later.
     * @param _timestamp Blockchain timestamp
     * @return The SMT root info
     */
    function getHistoricalRootInfoByTime(uint256 _timestamp)
        public
        view
        returns (RootInfo memory)
    {
        return smtData.getHistoricalRootInfoByTime(_timestamp);
    }

    /**
     * Retrieve all states for a given identity
     * @param _id identity
     * @return A list of identity states
     */
    function getAllStatesById(uint256 _id)
        public
        view
        returns (uint256[] memory)
    {
        return statesHistories[_id];
    }
}
