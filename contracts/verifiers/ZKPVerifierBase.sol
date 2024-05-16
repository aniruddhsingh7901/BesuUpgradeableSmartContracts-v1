// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IZKPVerifier} from "../interfaces/IZKPVerifier.sol";
import {ICircuitValidator} from "../interfaces/ICircuitValidator.sol";
import {ArrayUtils} from "../lib/ArrayUtils.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

abstract contract ZKPVerifierBase is IZKPVerifier, ContextUpgradeable {
    /// @dev Struct to store ZKP proof and associated data
    struct Proof {
        bool isProved;
        mapping(string key => uint256 inputIndex) storageFields;
        string validatorVersion;
        uint256 blockNumber;
        uint256 blockTimestamp;
    }

    /// @custom:storage-location erc7201:iden3.storage.ZKPVerifier
    struct ZKPVerifierStorage {
        mapping(address user => mapping(uint64 requestID => Proof)) _proofs;
        mapping(uint64 requestID => IZKPVerifier.ZKPRequest) _requests;
        uint64[] _requestIds;
    }

    // keccak256(abi.encode(uint256(keccak256("iden3.storage.ZKPVerifier")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant ZKPVerifierStorageLocation =
        0x512d18c55869273fec77e70d8a8586e3fb133e90f1db24c6bcf4ff3506ef6a00;

    /// @dev Get the main storage using assembly to ensure specific storage location
    function _getZKPVerifierStorage() private pure returns (ZKPVerifierStorage storage $) {
        assembly {
            $.slot := ZKPVerifierStorageLocation
        }
    }

    /**
     * @dev Max return array length for request queries
     */
    uint256 public constant REQUESTS_RETURN_LIMIT = 1000;

    /// @dev Modifier to check if the validator is set for the request
    modifier checkRequestExistence(uint64 requestId, bool existence) {
        if (existence) {
            require(requestIdExists(requestId), "request id doesn't exist");
        } else {
            require(!requestIdExists(requestId), "request id already exists");
        }
        _;
    }

    /// @notice Submits a ZKP response and updates proof status
    /// @param requestId The ID of the ZKP request
    /// @param inputs The input data for the proof
    /// @param a The first component of the proof
    /// @param b The second component of the proof
    /// @param c The third component of the proof
    function submitZKPResponse(
        uint64 requestId,
        uint256[] calldata inputs,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c
    ) public virtual {
        address sender = _msgSender();
        ICircuitValidator.KeyToInputIndex[] memory pairs = verifyZKPResponse(
            requestId,
            inputs,
            a,
            b,
            c,
            sender
        );

        Proof storage proof = _getZKPVerifierStorage()._proofs[sender][requestId];
        for (uint256 i = 0; i < pairs.length; i++) {
            proof.storageFields[pairs[i].key] = inputs[pairs[i].inputIndex];
        }

        proof.isProved = true;
        proof.validatorVersion = _getZKPVerifierStorage()._requests[requestId].validator.version();
        proof.blockNumber = block.number;
        proof.blockTimestamp = block.timestamp;
    }

    /// @dev Sets a ZKP request
    /// @param requestId The ID of the ZKP request
    /// @param request The ZKP request data
    function setZKPRequest(
        uint64 requestId,
        IZKPVerifier.ZKPRequest calldata request
    ) public virtual checkRequestExistence(requestId, false) {
        ZKPVerifierStorage storage s = _getZKPVerifierStorage();
        s._requests[requestId] = request;
        s._requestIds.push(requestId);
    }

    /// @dev Verifies a ZKP response without updating any proof status
    /// @param requestId The ID of the ZKP request
    /// @param inputs The public inputs for the proof
    /// @param a The first component of the proof
    /// @param b The second component of the proof
    /// @param c The third component of the proof
    /// @param sender The sender on behalf of which the proof is done
    function verifyZKPResponse(
        uint64 requestId,
        uint256[] calldata inputs,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        address sender
    )
        public
        view
        virtual
        checkRequestExistence(requestId, true)
        returns (ICircuitValidator.KeyToInputIndex[] memory)
    {
        IZKPVerifier.ZKPRequest memory request = _getZKPVerifierStorage()._requests[requestId];
        ICircuitValidator.KeyToInputIndex[] memory pairs = request.validator.verify(
            inputs,
            a,
            b,
            c,
            request.data,
            sender
        );
        return pairs;
    }

    /// @dev Gets a specific ZKP request by ID
    /// @param requestId The ID of the ZKP request
    /// @return zkpRequest The ZKP request data
    function getZKPRequest(
        uint64 requestId
    )
        public
        view
        checkRequestExistence(requestId, true)
        returns (IZKPVerifier.ZKPRequest memory zkpRequest)
    {
        return _getZKPVerifierStorage()._requests[requestId];
    }

    /// @dev Gets the count of ZKP requests
    /// @return The count of ZKP requests
    function getZKPRequestsCount() public view returns (uint256) {
        return _getZKPVerifierStorage()._requestIds.length;
    }

    /// @dev Checks if a ZKP request ID exists
    /// @param requestId The ID of the ZKP request
    /// @return Whether the request ID exists
    function requestIdExists(uint64 requestId) public view override returns (bool) {
        return
            _getZKPVerifierStorage()._requests[requestId].validator !=
            ICircuitValidator(address(0));
    }

    /// @dev Gets multiple ZKP requests within a range
    /// @param startIndex The starting index of the range
    /// @param length The length of the range
    /// @return An array of ZKP requests within the specified range
    function getZKPRequests(
        uint256 startIndex,
        uint256 length
    ) public view returns (IZKPVerifier.ZKPRequest[] memory) {
        ZKPVerifierStorage storage s = _getZKPVerifierStorage();
        (uint256 start, uint256 end) = ArrayUtils.calculateBounds(
            s._requestIds.length,
            startIndex,
            length,
            REQUESTS_RETURN_LIMIT
        );

        IZKPVerifier.ZKPRequest[] memory result = new IZKPVerifier.ZKPRequest[](end - start);

        for (uint256 i = start; i < end; i++) {
            result[i - start] = s._requests[s._requestIds[i]];
        }

        return result;
    }

    /// @dev Checks if proof submitted for a given sender and request ID
    /// @param sender The sender's address
    /// @param requestId The ID of the ZKP request
    /// @return true if proof submitted
    function isProofSubmitted(
        address sender,
        uint64 requestId
    ) public view checkRequestExistence(requestId, true) returns (bool) {
        return _getZKPVerifierStorage()._proofs[sender][requestId].isProved;
    }

    /// @dev Checks the proof status for a given user and request ID
    /// @param sender The sender's address
    /// @param requestId The ID of the ZKP request
    /// @return The proof status structure
    function getProofStatus(
        address sender,
        uint64 requestId
    ) public view checkRequestExistence(requestId, true) returns (IZKPVerifier.ProofStatus memory) {
        Proof storage proof = _getZKPVerifierStorage()._proofs[sender][requestId];

        return
            IZKPVerifier.ProofStatus(
                proof.isProved,
                proof.validatorVersion,
                proof.blockNumber,
                proof.blockTimestamp
            );
    }

    /// @dev Gets the proof storage item for a given user, request ID and key
    /// @param user The user's address
    /// @param requestId The ID of the ZKP request
    /// @return The proof
    function getProofStorageField(
        address user,
        uint64 requestId,
        string memory key
    ) public view checkRequestExistence(requestId, true) returns (uint256) {
        return _getZKPVerifierStorage()._proofs[user][requestId].storageFields[key];
    }
}
