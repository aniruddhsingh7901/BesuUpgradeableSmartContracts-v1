// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {EmbeddedZKPVerifier} from "../verifiers/EmbeddedZKPVerifier.sol";
import {IState} from "../interfaces/IState.sol";

contract ZKPVerifierWrapper is EmbeddedZKPVerifier {
    function initialize(address initialOwner, IState stateCrossChain) public initializer {
        super.__EmbeddedZKPVerifier_init(initialOwner, stateCrossChain);
    }
}
