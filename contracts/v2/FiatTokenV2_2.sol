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

pragma solidity 0.8.20;

import { EIP712Domain } from "./EIP712Domain.sol"; // solhint-disable-line no-unused-import
import { Blacklistable } from "../v1/Blacklistable.sol"; // solhint-disable-line no-unused-import
import { FiatTokenV1 } from "../v1/FiatTokenV1.sol"; // solhint-disable-line no-unused-import
import { FiatTokenV2 } from "./FiatTokenV2.sol"; // solhint-disable-line no-unused-import
import { FiatTokenV2_1 } from "./FiatTokenV2_1.sol";
import { EIP712 } from "../util/EIP712.sol";

import { IEncryptedERC20 } from "../interface/IEncryptedERC20.sol";
import "fhevm/lib/TFHE.sol";

// solhint-disable func-name-mixedcase

/**
 * @title FiatToken V2.2
 * @notice ERC20 Token backed by fiat reserves, version 2.2
 */
contract FiatTokenV2_2 is FiatTokenV2_1 {
    constructor(address _originalToken) FiatTokenV2_1(_originalToken) {
        delegateViewer[msg.sender] = true;
    }

    /**
     * @notice Initialize v2.2
     * @param accountsToBlacklist   A list of accounts to migrate from the old blacklist
     * @param newSymbol             New token symbol
     * data structure to the new blacklist data structure.
     */
    function initializeV2_2(address[] calldata accountsToBlacklist, string calldata newSymbol) external {
        // solhint-disable-next-line reason-string
        require(_initializedVersion == 2);

        // Update fiat token symbol
        symbol = newSymbol;

        // Add previously blacklisted accounts to the new blacklist data structure
        // and remove them from the old blacklist data structure.
        for (uint256 i = 0; i < accountsToBlacklist.length; i++) {
            require(
                _deprecatedBlacklisted[accountsToBlacklist[i]],
                "FiatTokenV2_2: Blacklisting previously unblacklisted account!"
            );
            _blacklist(accountsToBlacklist[i]);
            delete _deprecatedBlacklisted[accountsToBlacklist[i]];
        }
        _blacklist(address(this));
        delete _deprecatedBlacklisted[address(this)];

        _initializedVersion = 3;
    }

    /**
     * @dev Internal function to get the current chain id.
     * @return The current chain id.
     */
    function _chainId() internal view virtual returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    /**
     * @inheritdoc EIP712Domain
     */
    function _domainSeparator() internal view override returns (bytes32) {
        return EIP712.makeDomainSeparator(name, "2", _chainId());
    }

    /**
     * @notice Update allowance with a signed permit
     * @dev EOA wallet signatures should be packed in the order of r, s, v.
     * @param owner       Token owner's address (Authorizer)
     * @param spender     Spender's address
     * @param value       Amount of allowance
     * @param deadline    The time at which the signature expires (unix time), or max uint256 value to signal no expiration
     * @param signature   Signature bytes signed by an EOA wallet or a contract wallet
     */
    function permit(
        address owner,
        address spender,
        bytes calldata value,
        uint256 deadline,
        bytes memory signature
    ) external whenNotPaused {
        _permit(owner, spender, TFHE.asEuint32(value), deadline, signature);
    }

    /**
     * @notice Execute a transfer with a signed authorization
     * @dev EOA wallet signatures should be packed in the order of r, s, v.
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param signature     Signature bytes signed by an EOA wallet or a contract wallet
     */
    function transferWithAuthorization(
        address from,
        address to,
        bytes calldata value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external whenNotPaused notBlacklisted(from) notBlacklisted(to) {
        _transferWithAuthorization(from, to, TFHE.asEuint32(value), validAfter, validBefore, nonce, signature);
    }

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev This has an additional check to ensure that the payee's address
     * matches the caller of this function to prevent front-running attacks.
     * EOA wallet signatures should be packed in the order of r, s, v.
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param signature     Signature bytes signed by an EOA wallet or a contract wallet
     */
    function receiveWithAuthorization(
        address from,
        address to,
        bytes calldata value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external whenNotPaused notBlacklisted(from) notBlacklisted(to) {
        _receiveWithAuthorization(from, to, TFHE.asEuint32(value), validAfter, validBefore, nonce, signature);
    }

    /**
     * @notice Attempt to cancel an authorization
     * @dev Works only if the authorization is not yet used.
     * EOA wallet signatures should be packed in the order of r, s, v.
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param signature     Signature bytes signed by an EOA wallet or a contract wallet
     */
    function cancelAuthorization(address authorizer, bytes32 nonce, bytes memory signature) external whenNotPaused {
        _cancelAuthorization(authorizer, nonce, signature);
    }

    /**
     * @dev Helper method that sets the blacklist state of an account on balanceAndBlacklistStates.
     * If _shouldBlacklist is true, we apply a (1 << 255) bitmask with an OR operation on the
     * account's balanceAndBlacklistState. This flips the high bit for the account to 1,
     * indicating that the account is blacklisted.
     *
     * If _shouldBlacklist if false, we reset the account's balanceAndBlacklistStates to their
     * balances. This clears the high bit for the account, indicating that the account is unblacklisted.
     * @param _account         The address of the account.
     * @param _shouldBlacklist True if the account should be blacklisted, false if the account should be unblacklisted.
     */

    /**
     * @dev Helper method that sets the balance of an account on balanceAndBlacklistStates.
     * Since balances are stored in the last 255 bits of the balanceAndBlacklistStates value,
     * we need to ensure that the updated balance does not exceed (2^255 - 1).
     * Since blacklisted accounts' balances cannot be updated, the method will also
     * revert if the account is blacklisted
     * @param _account The address of the account.
     * @param _balance The new fiat token balance of the account (max: (2^255 - 1)).
     */
    function _setBalance(address _account, euint32 _balance) internal override {
        // @changed 255 -> 31
        require(
            TFHE.decrypt(TFHE.le(_balance, TFHE.asEuint32((1 << 31) - 1))),
            "FiatTokenV2_2: Balance exceeds (2^31 - 1)"
        );
        require(!_isBlacklisted(_account), "FiatTokenV2_2: Account is blacklisted");

        balanceAndBlacklistStates[_account] = _balance;
    }

    /**
     * @dev Helper method to obtain the balance of an account. Since balances
     * are stored in the last 255 bits of the balanceAndBlacklistStates value,
     * we apply a ((1 << 255) - 1) bit bitmask with an AND operation on the
     * balanceAndBlacklistState to obtain the balance.
     * @param _account  The address of the account.
     * @return          The fiat token balance of the account.
     */
    function _balanceOf(address _account) internal view override returns (euint32) {
        // @changed 255 -> 31
        return TFHE.and(balanceAndBlacklistStates[_account], TFHE.asEuint32((1 << 31) - 1));
    }

    /**
     * @inheritdoc FiatTokenV1
     */
    function approve(
        address spender,
        bytes calldata value
    ) external override(FiatTokenV1, IEncryptedERC20) whenNotPaused returns (bool) {
        _approve(msg.sender, spender, TFHE.asEuint32(value));
        return true;
    }

    /**
     * @inheritdoc FiatTokenV2
     */
    function permit(
        address owner,
        address spender,
        bytes calldata value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override whenNotPaused {
        _permit(owner, spender, TFHE.asEuint32(value), deadline, v, r, s);
    }

    /**
     * @inheritdoc FiatTokenV2
     */
    function increaseAllowance(
        address spender,
        bytes calldata increment
    ) external override whenNotPaused returns (bool) {
        _increaseAllowance(msg.sender, spender, TFHE.asEuint32(increment));
        return true;
    }

    /**
     * @inheritdoc FiatTokenV2
     */
    function decreaseAllowance(
        address spender,
        bytes calldata decrement
    ) external override whenNotPaused returns (bool) {
        _decreaseAllowance(msg.sender, spender, TFHE.asEuint32(decrement));
        return true;
    }
}
