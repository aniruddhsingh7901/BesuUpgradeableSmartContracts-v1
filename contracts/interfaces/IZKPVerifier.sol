// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {ICircuitValidator} from "./ICircuitValidator.sol";
import {IWormhole} from "../validators/wormhole/interfaces/IWormhole.sol";

interface IZKPVerifier {
    struct ZKPRequest {
        string metadata;
        ICircuitValidator validator;
        bytes data;
    }

    function submitZKPResponse(
        uint64 requestId,
        uint256[] memory inputs,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        bytes memory response,
        IWormhole.Signature[] memory signatures
    ) external;

    function setZKPRequest(uint64 requestId, ZKPRequest calldata request) external;

    function getZKPRequestsCount() external view returns (uint256);

    function requestIdExists(uint64 requestId) external view returns (bool);

    function getZKPRequest(uint64 requestId) external view returns (ZKPRequest memory);

    function getZKPRequests(
        uint256 startIndex,
        uint256 length
    ) external view returns (ZKPRequest[] memory);
}
