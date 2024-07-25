/**
 * Copyright 2023 Circle Internet Financial, LTD. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

pragma solidity 0.8.24;

import { FiatTokenV1_1 } from "../v1.1/FiatTokenV1_1.sol";
import { EIP712 } from "../util/EIP712.sol";
import { EIP3009 } from "./EIP3009.sol";
import { EIP2612 } from "./EIP2612.sol";
import "fhevm/lib/TFHE.sol";

/**
 * @title FiatToken V2
 * @notice ERC20 Token backed by fiat reserves, version 2
 */
contract FiatTokenV2 is FiatTokenV1_1, EIP3009, EIP2612 {
    uint8 internal _initializedVersion;

    /**
     * @notice Initialize v2
     * @param newName   New token name
     */
    function initializeV2(string calldata newName) external {
        // solhint-disable-next-line reason-string
        require(initialized && _initializedVersion == 0);
        name = newName;
        _DEPRECATED_CACHED_DOMAIN_SEPARATOR = EIP712.makeDomainSeparator(newName, "2");
        _initializedVersion = 1;
    }

    /**
     * @notice Increase the allowance by a given increment
     * @param spender   Spender's address
     * @param increment Amount of increase in allowance
     * @return True if successful
     */
    function increaseAllowance(
        address spender,
        bytes calldata increment,
        einput eAmount
    ) external virtual whenNotPaused returns (bool) {
        euint64 amount = TFHE.asEuint64(eAmount, increment);
        amount = TFHE.select(isBlacklisted(msg.sender), TFHE.asEuint64(0), amount);
        amount = TFHE.select(isBlacklisted(spender), TFHE.asEuint64(0), amount);
        _increaseAllowance(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Decrease the allowance by a given decrement
     * @param spender   Spender's address
     * @param decrement Amount of decrease in allowance
     * @return True if successful
     */
    function decreaseAllowance(
        address spender,
        bytes calldata decrement,
        einput eAmount
    ) external virtual whenNotPaused returns (bool) {
        euint64 amount = TFHE.asEuint64(eAmount, decrement);
        amount = TFHE.select(isBlacklisted(msg.sender), TFHE.asEuint64(0), amount);
        amount = TFHE.select(isBlacklisted(spender), TFHE.asEuint64(0), amount);
        _decreaseAllowance(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Execute a transfer with a signed authorization
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function transferWithAuthorization(
        address from,
        address to,
        bytes calldata value,
        einput eAmount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        euint64 amount = TFHE.asEuint64(eAmount, value);
        amount = TFHE.select(isBlacklisted(from), TFHE.asEuint64(0), amount);
        amount = TFHE.select(isBlacklisted(to), TFHE.asEuint64(0), amount);
        _transferWithAuthorization(from, to, amount, validAfter, validBefore, nonce, v, r, s);
    }

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev This has an additional check to ensure that the payee's address
     * matches the caller of this function to prevent front-running attacks.
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function receiveWithAuthorization(
        address from,
        address to,
        bytes calldata value,
        einput eAmount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        euint64 amount = TFHE.asEuint64(eAmount, value);
        amount = TFHE.select(isBlacklisted(from), TFHE.asEuint64(0), amount);
        amount = TFHE.select(isBlacklisted(to), TFHE.asEuint64(0), amount);
        _receiveWithAuthorization(from, to, amount, validAfter, validBefore, nonce, v, r, s);
    }

    /**
     * @notice Attempt to cancel an authorization
     * @dev Works only if the authorization is not yet used.
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        _cancelAuthorization(authorizer, nonce, v, r, s);
    }

    /**
     * @notice Update allowance with a signed permit
     * @param owner       Token owner's address (Authorizer)
     * @param spender     Spender's address
     * @param value       Amount of allowance
     * @param deadline    The time at which the signature expires (unix time), or max uint256 value to signal no expiration
     * @param v           v of the signature
     * @param r           r of the signature
     * @param s           s of the signature
     */
    function permit(
        address owner,
        address spender,
        bytes calldata value,
        einput eAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual whenNotPaused {
        euint64 amount = TFHE.asEuint64(eAmount, value);
        amount = TFHE.select(isBlacklisted(owner), TFHE.asEuint64(0), amount);
        amount = TFHE.select(isBlacklisted(spender), TFHE.asEuint64(0), amount);
        _permit(owner, spender, amount, deadline, v, r, s);
    }

    /**
     * @dev Internal function to increase the allowance by a given increment
     * @param owner     Token owner's address
     * @param spender   Spender's address
     * @param increment Amount of increase
     */
    function _increaseAllowance(address owner, address spender, euint64 increment) internal override {
        _approve(owner, spender, TFHE.add(allowed[owner][spender], increment));
    }

    /**
     * @dev Internal function to decrease the allowance by a given decrement
     * @param owner     Token owner's address
     * @param spender   Spender's address
     * @param decrement Amount of decrease
     */
    function _decreaseAllowance(address owner, address spender, euint64 decrement) internal override {
        _approve(owner, spender, TFHE.sub(allowed[owner][spender], decrement));
    }
}
