// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ICircuitValidator} from "../interfaces/ICircuitValidator.sol";
import {IZKPVerifier} from "../interfaces/IZKPVerifier.sol";
import {RequestOwnership} from "./RequestOwnership.sol";
import {RequestDisable} from "./RequestDisable.sol";
import {ValidatorWhitelist} from "./ValidatorWhitelist.sol";
import {ZKPVerifierBase} from "./ZKPVerifierBase.sol";
import {ArrayUtils} from "../lib/ArrayUtils.sol";

/// @title Universal Verifier Contract
/// @notice A contract to manage ZKP (Zero-Knowledge Proof) requests and proofs.
contract UniversalVerifier is
    Ownable2StepUpgradeable,
    RequestOwnership,
    RequestDisable,
    ValidatorWhitelist
{
    /**
     * @dev Version of contract
     */
    string public constant VERSION = "1.0.1";

    /// @dev Event emitted upon submitting a ZKP request
    event ZKPResponseSubmitted(uint64 indexed requestId, address indexed caller);

    /// @dev Event emitted upon adding a ZKP request
    event ZKPRequestSet(
        uint64 indexed requestId,
        address indexed requestOwner,
        string metadata,
        address validator,
        bytes data
    );

    /// @dev Modifier to check if the caller is the contract Owner or ZKP Request Owner
    modifier onlyRequestOwner(uint64 requestId) override {
        address sender = _msgSender();
        require(
            sender == getRequestOwner(requestId) || sender == owner(),
            "Not an owner or request owner"
        );
        _;
    }

    /// @dev Modifier to check if the validator is whitelisted
    modifier approvedValidator(ICircuitValidator validator) {
        require(isWhitelistedValidator(validator), "Validator is not whitelisted");
        _;
    }

    /// @dev Initializes the contract
    function initialize() public initializer {
        __Ownable_init(_msgSender());
    }

    /// @dev Version of contract getter
    function version() public pure returns (string memory) {
        return VERSION;
    }

    /// @dev Submits a ZKP response and updates proof status
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
    ) public override(RequestDisable, ValidatorWhitelist, ZKPVerifierBase) {
        super.submitZKPResponse(requestId, inputs, a, b, c);
        emit ZKPResponseSubmitted(requestId, _msgSender());
    }

    /// @dev Sets a ZKP request
    /// @param requestId The ID of the ZKP request
    /// @param request The ZKP request data
    function setZKPRequest(
        uint64 requestId,
        IZKPVerifier.ZKPRequest calldata request
    ) public override approvedValidator(request.validator) {
        super.setZKPRequest(requestId, request);

        address sender = _msgSender();
        _setRequestOwner(requestId, sender);

        emit ZKPRequestSet(
            requestId,
            sender,
            request.metadata,
            address(request.validator),
            request.data
        );
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
        override
        requestEnabled(requestId)
        returns (ICircuitValidator.KeyToInputIndex[] memory)
    {
        return super.verifyZKPResponse(requestId, inputs, a, b, c, sender);
    }

    /// @dev Sets ZKP Request Owner address
    /// @param requestId The ID of the ZKP request
    /// @param requestOwner ZKP Request Owner address
    function setRequestOwner(
        uint64 requestId,
        address requestOwner
    ) public onlyRequestOwner(requestId) {
        _setRequestOwner(requestId, requestOwner);
    }

    /// @dev Disables ZKP Request
    /// @param requestId The ID of the ZKP request
    function disableZKPRequest(uint64 requestId) public onlyRequestOwner(requestId) {
        _disableZKPRequest(requestId);
    }

    /// @dev Enables ZKP Request
    /// @param requestId The ID of the ZKP request
    function enableZKPRequest(uint64 requestId) public onlyRequestOwner(requestId) {
        _enableZKPRequest(requestId);
    }

    /// @dev Add new validator to the whitelist
    /// @param validator Validator address
    function addValidatorToWhitelist(ICircuitValidator validator) public onlyOwner {
        _addValidatorToWhitelist(validator);
    }

    /// @dev Remove validator from the whitelist
    /// @param validator Validator address
    function removeValidatorFromWhitelist(ICircuitValidator validator) public onlyOwner {
        _removeValidatorFromWhitelist(validator);
    }
}
