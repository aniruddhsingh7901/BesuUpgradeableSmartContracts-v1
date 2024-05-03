// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {EmbeddedZKPVerifier} from "./EmbeddedZKPVerifier.sol";

/**
 * @dev The ZKPVerifier is deprecated and will be removed in the future major versions
 * Please use EmbeddedZKPVerifier instead
 */
contract ZKPVerifier is EmbeddedZKPVerifier {}
