// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {CredentialAtomicQueryValidatorBase} from "./CredentialAtomicQueryValidatorBase.sol";
import {IVerifier} from "../interfaces/IVerifier.sol";
import {PrimitiveTypeUtils} from "../lib/PrimitiveTypeUtils.sol";
import {GenesisUtils} from "../lib/GenesisUtils.sol";
import {ICircuitValidator} from "../interfaces/ICircuitValidator.sol";

/**
 * @dev CredentialAtomicQueryV3 validator
 */
contract CredentialAtomicQueryV3Validator is CredentialAtomicQueryValidatorBase {
    struct CredentialAtomicQueryV3 {
        uint256 schema;
        uint256 claimPathKey;
        uint256 operator;
        uint256 slotIndex;
        uint256[] value;
        uint256 queryHash;
        uint256[] allowedIssuers;
        string[] circuitIds;
        bool skipClaimRevocationCheck;
        uint256 groupID;
        uint256 nullifierSessionID;
        uint256 proofType;
        uint256 verifierID;
    }

    struct V3PubSignals {
        uint256 linkID;
        uint256 nullifier;
        uint256 operatorOutput;
        uint256 proofType;
        uint256 isBJJAuthEnabled;
        uint256 userID;
        uint256 issuerState;
        uint256 circuitQueryHash;
        uint256 requestID;
        uint256 challenge;
        uint256 gistRoot;
        uint256 issuerID;
        uint256 issuerClaimNonRevState;
        uint256 timestamp;
    }

    /**
     * @dev Version of contract
     */
    string public constant VERSION = "2.0.0-beta.1";

    string internal constant CIRCUIT_ID = "credentialAtomicQueryV3OnChain-beta.1";

    function initialize(
        address _verifierContractAddr,
        address _stateContractAddr
    ) public override initializer {
        _setInputToIndex("userID", 0);
        _setInputToIndex("circuitQueryHash", 1);
        _setInputToIndex("issuerState", 2);
        _setInputToIndex("linkID", 3);
        _setInputToIndex("nullifier", 4);
        _setInputToIndex("operatorOutput", 5);
        _setInputToIndex("proofType", 6);
        _setInputToIndex("requestID", 7);
        _setInputToIndex("challenge", 8);
        _setInputToIndex("gistRoot", 9);
        _setInputToIndex("issuerID", 10);
        _setInputToIndex("issuerClaimNonRevState", 11);
        _setInputToIndex("timestamp", 12);
        _setInputToIndex("isBJJAuthEnabled", 13);

        MainStorage storage s = _getMainStorage();
        s._supportedCircuitIds = [CIRCUIT_ID];
        s._circuitIdToVerifier[CIRCUIT_ID] = IVerifier(_verifierContractAddr);
        super.initialize(_verifierContractAddr, _stateContractAddr);
    }

    function version() public pure override returns (string memory) {
        return VERSION;
    }

    function parsePubSignals(uint256[] calldata inputs) public pure returns (V3PubSignals memory) {
        V3PubSignals memory pubSignals = V3PubSignals({
            userID: inputs[0],
            circuitQueryHash: inputs[1],
            issuerState: inputs[2],
            linkID: inputs[3],
            nullifier: inputs[4],
            operatorOutput: inputs[5],
            proofType: inputs[6],
            requestID: inputs[7],
            challenge: inputs[8],
            gistRoot: inputs[9],
            issuerID: inputs[10],
            issuerClaimNonRevState: inputs[11],
            timestamp: inputs[12],
            isBJJAuthEnabled: inputs[13]
        });

        return pubSignals;
    }

    function verify(
        uint256[] calldata inputs,
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        bytes calldata data,
        address sender
    ) external view override returns (ICircuitValidator.KeyToInputIndex[] memory) {
        CredentialAtomicQueryV3 memory credAtomicQuery = abi.decode(
            data,
            (CredentialAtomicQueryV3)
        );

        IVerifier verifier = _getMainStorage()._circuitIdToVerifier[credAtomicQuery.circuitIds[0]];

        require(
            credAtomicQuery.circuitIds.length == 1 && verifier != IVerifier(address(0)),
            "Invalid circuit ID"
        );

        // verify that zkp is valid
        require(verifier.verify(a, b, c, inputs), "Proof is not valid");

        V3PubSignals memory signals = parsePubSignals(inputs);

        // check circuitQueryHash
        require(
            signals.circuitQueryHash == credAtomicQuery.queryHash,
            "Query hash does not match the requested one"
        );

        _checkAllowedIssuers(signals.issuerID, credAtomicQuery.allowedIssuers);
        _checkClaimIssuanceState(signals.issuerID, signals.issuerState);
        _checkClaimNonRevState(signals.issuerID, signals.issuerClaimNonRevState);
        _checkProofExpiration(signals.timestamp);

        V3PubSignals memory v3PubSignals = parsePubSignals(inputs);
        _checkLinkID(credAtomicQuery.groupID, v3PubSignals.linkID);
        _checkProofType(credAtomicQuery.proofType, v3PubSignals.proofType);
        _checkNullify(v3PubSignals.nullifier, credAtomicQuery.nullifierSessionID);

        if (v3PubSignals.isBJJAuthEnabled == 1) {
            _checkGistRoot(signals.gistRoot);
        } else {
            _checkAuth(signals.userID, sender);
        }

        // Checking challenge to prevent replay attacks from other addresses
        _checkChallenge(signals.challenge, sender);

        ICircuitValidator.KeyToInputIndex[] memory pairs = _getSpecialInputPairs(
            credAtomicQuery.operator == 16
        );
        return pairs;
    }

    function _checkLinkID(uint256 groupID, uint256 linkID) internal pure {
        require(
            (groupID == 0 && linkID == 0) || (groupID != 0 && linkID != 0),
            "Invalid Link ID pub signal"
        );
    }

    function _checkProofType(uint256 queryProofType, uint256 pubSignalProofType) internal pure {
        require(
            queryProofType == 0 || queryProofType == pubSignalProofType,
            "Proof type should match the requested one in query"
        );
    }

    function _checkNullify(uint256 nullifier, uint256 nullifierSessionID) internal pure {
        require(nullifierSessionID == 0 || nullifier != 0, "Invalid nullify pub signal");
    }

    function _checkAuth(uint256 userID, address ethIdentityOwner) internal view {
        require(
            userID ==
                GenesisUtils.calcIdFromEthAddress(
                    _getMainStorage().state.getDefaultIdType(),
                    ethIdentityOwner
                ),
            "UserID does not correspond to the sender"
        );
    }

    function _getSpecialInputPairs(
        bool hasSelectiveDisclosure
    ) internal pure returns (ICircuitValidator.KeyToInputIndex[] memory) {
        uint256 numPairs = hasSelectiveDisclosure ? 5 : 4;
        ICircuitValidator.KeyToInputIndex[] memory pairs = new ICircuitValidator.KeyToInputIndex[](
            numPairs
        );

        uint i = 0;
        pairs[i++] = ICircuitValidator.KeyToInputIndex({key: "userID", inputIndex: 0});
        pairs[i++] = ICircuitValidator.KeyToInputIndex({key: "linkID", inputIndex: 3});
        pairs[i++] = ICircuitValidator.KeyToInputIndex({key: "nullifier", inputIndex: 4});
        if (hasSelectiveDisclosure) {
            pairs[i++] = ICircuitValidator.KeyToInputIndex({key: "operatorOutput", inputIndex: 5});
        }
        pairs[i++] = ICircuitValidator.KeyToInputIndex({key: "timestamp", inputIndex: 12});

        return pairs;
    }

    function _checkChallenge(uint256 challenge, address sender) internal pure {
        require(
            PrimitiveTypeUtils.int256ToAddress(challenge) == sender,
            "Challenge should match the sender"
        );
    }
}
