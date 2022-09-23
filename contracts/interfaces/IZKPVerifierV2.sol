pragma solidity ^0.8.0;

import "./ICircuitValidatorV2.sol";

interface IZKPVerifierV2 {
    function submitZKPResponse(
        uint64 requestId,
        uint256[] memory inputs,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c
    ) external returns (bool);

    function setZKPRequest(
        uint64 requestId,
        ICircuitValidatorV2 validator,
        uint256 schema,
        uint256 slotIndex,
        uint256 operator,
        uint256[] memory value
    ) external returns (bool);

    function getZKPRequest(uint64 requestId)
        external
        returns (ICircuitValidatorV2.CircuitQuery memory);
}
