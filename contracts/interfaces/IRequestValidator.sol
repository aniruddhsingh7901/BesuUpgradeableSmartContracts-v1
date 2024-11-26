// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import {IState} from "./IState.sol";

/**
 * @dev IRequestValidator. Interface for verification of request query data.
 */
interface IRequestValidator {
    /**
     * @dev ResponseField. Information about response fields from verification. Used in verify function.
     * @param name Name of the response field
     * @param value Value of the response field
     */
    struct ResponseField {
        string name;
        uint256 value;
    }

    /**
     * @dev Get version of the contract
     */
    function version() external view returns (string memory);

    /**
     * @dev Verify the proof with the supported method informed in the request query data
     * packed as bytes and that the proof was generated by the sender.
     * @param proof Proof packed as bytes to verify.
     * @param data Request query data of the credential to verify.
     * @param sender Sender of the proof.
     * @param state State contract to get identities and gist states to check.
     * @return Array of response fields as result.
     */
    function verify(
        bytes calldata proof,
        bytes calldata data,
        address sender,
        IState state
    ) external returns (IRequestValidator.ResponseField[] memory);
}
