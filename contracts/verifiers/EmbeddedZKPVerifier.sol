// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ICircuitValidator} from "../interfaces/ICircuitValidator.sol";
import {IZKPVerifier} from "../interfaces/IZKPVerifier.sol";
import {ZKPVerifierBase} from "./ZKPVerifierBase.sol";
import {IState} from "../interfaces/IState.sol";

abstract contract EmbeddedZKPVerifier is Ownable2StepUpgradeable, ZKPVerifierBase {
    /**
     * @dev Sets the value for Owner
     */
    function __EmbeddedZKPVerifier_init(
        address initialOwner,
        IState state
    ) internal onlyInitializing {
        __Ownable_init(initialOwner);
        ___EmbeddedZKPVerifier_init_unchained(initialOwner);
        __ZKPVerifierBase_init(state);
    }

    function ___EmbeddedZKPVerifier_init_unchained(
        address initialOwner
    ) internal onlyInitializing {}

    /// @dev Sets a ZKP request
    /// @param requestId The ID of the ZKP request
    /// @param request The ZKP request data
    function setZKPRequest(
        uint64 requestId,
        IZKPVerifier.ZKPRequest calldata request
    ) public virtual override onlyOwner {
        super.setZKPRequest(requestId, request);
    }

    /// @dev Submits a ZKP response and updates proof status
    /// @param requestId The ID of the ZKP request
    /// @param inputs The input data for the proof
    /// @param a The first component of the proof
    /// @param b The second component of the proof
    /// @param c The third component of the proof
    function submitZKPResponse(
        uint64 requestId,
        uint256[] memory inputs,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c
    ) public virtual override {
        IZKPVerifier.ZKPRequest memory request = getZKPRequest(requestId);
        _beforeProofSubmit(requestId, inputs, request.validator);
        super.submitZKPResponse(requestId, inputs, a, b, c);
        _afterProofSubmit(requestId, inputs, request.validator);
    }

    /**
     * @dev Hook that is called before any proof response submit
     */
    function _beforeProofSubmit(
        uint64 requestId,
        uint256[] memory inputs,
        ICircuitValidator validator
    ) internal virtual {}

    /**
     * @dev Hook that is called after any proof response submit
     */
    function _afterProofSubmit(
        uint64 requestId,
        uint256[] memory inputs,
        ICircuitValidator validator
    ) internal virtual {}
}
