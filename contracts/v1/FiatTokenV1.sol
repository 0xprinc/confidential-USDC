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

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { AbstractFiatTokenV1 } from "./AbstractFiatTokenV1.sol";
import { Ownable } from "./Ownable.sol";
import { Pausable } from "./Pausable.sol";
import { Blacklistable } from "./Blacklistable.sol";
import "fhevm/lib/TFHE.sol";
import "fhevm/gateway/GatewayCaller.sol";

/**
 * @title FiatToken
 * @dev ERC20 Token backed by fiat reserves
 */
contract FiatTokenV1 is AbstractFiatTokenV1, Ownable, Pausable, Blacklistable, GatewayCaller {
    using SafeMath for uint256;

    string public name;
    string public symbol;
    uint8 public decimals;
    string public currency;
    address public masterMinter;
    bool internal initialized;

    /// @dev A mapping that stores the balance and blacklist states for a given address.
    /// The first bit defines whether the address is blacklisted (1 if blacklisted, 0 otherwise).
    /// The last 63 bits define the balance for the address.
    mapping(address => euint64) internal balanceAndBlacklistStates;
    mapping(address => mapping(address => euint64)) internal allowed;
    euint64 internal totalSupply_;
    mapping(address => bool) internal minters;
    mapping(address => euint64) internal minterAllowed;

    mapping(uint256 => bool) public requestStatus;
    mapping(uint256 => bool) public requestOutput;

    event Mint(address indexed minter, address indexed to, euint64 amount);
    event Burn(address indexed burner, euint64 amount);
    event MinterConfigured(address indexed minter, euint64 minterAllowedAmount);
    event MinterRemoved(address indexed oldMinter);
    event MasterMinterChanged(address indexed newMasterMinter);

    constructor() {}

    /**
     * @notice Initializes the fiat token contract.
     * @param tokenName       The name of the fiat token.
     * @param tokenSymbol     The symbol of the fiat token.
     * @param tokenCurrency   The fiat currency that the token represents.
     * @param tokenDecimals   The number of decimals that the token uses.
     * @param newMasterMinter The masterMinter address for the fiat token.
     * @param newPauser       The pauser address for the fiat token.
     * @param newBlacklister  The blacklister address for the fiat token.
     * @param newOwner        The owner of the fiat token.
     */
    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        string memory tokenCurrency,
        uint8 tokenDecimals,
        address newMasterMinter,
        address newPauser,
        address newBlacklister,
        address newOwner
    ) public {
        require(!initialized, "FiatToken: contract is already initialized");
        require(newMasterMinter != address(0), "FiatToken: new masterMinter is the zero address");
        require(newPauser != address(0), "FiatToken: new pauser is the zero address");
        require(newBlacklister != address(0), "FiatToken: new blacklister is the zero address");
        require(newOwner != address(0), "FiatToken: new owner is the zero address");

        name = tokenName;
        symbol = tokenSymbol;
        currency = tokenCurrency;
        decimals = tokenDecimals;
        masterMinter = newMasterMinter;
        pauser = newPauser;
        blacklister = newBlacklister;
        setOwner(newOwner);
        initialized = true;
    }

    /**
     * @dev Throws if called by any account other than a minter.
     */
    modifier onlyMinters() {
        require(minters[msg.sender], "FiatToken: caller is not a minter");
        _;
    }

    /**
     * @notice Mints fiat tokens to an address.
     * @param _to The address that will receive the minted tokens.
     * @param amount The amount of tokens to mint. Must be less than or equal
     * to the minterAllowance of the caller.
     * @return True if the operation was successful.
     */

    function mint(
        address _to,
        bytes calldata amount,
        einput eAmount,
        uint256 requestId
    ) external virtual whenNotPaused onlyMinters returns (bool) {
        euint64 _amount = TFHE.asEuint64(eAmount, amount);
        _amount = TFHE.select(isBlacklisted(msg.sender), TFHE.asEuint64(0), _amount);
        _amount = TFHE.select(isBlacklisted(_to), TFHE.asEuint64(0), _amount);
        require(_to != address(0), "FiatToken: mint to the zero address");

        euint64 mintingAllowedAmount = minterAllowed[msg.sender];
        require(requestStatus[requestId], "FiatToken: request not completed");
        require(requestOutput[requestId], "FiatToken: amount more than allowance");

        totalSupply_ = TFHE.add(totalSupply_, _amount);
        _setBalance(_to, TFHE.add(_balanceOf(_to), _amount));
        minterAllowed[msg.sender] = TFHE.sub(mintingAllowedAmount, _amount);
        emit Mint(msg.sender, _to, _amount);
        emit Transfer(address(0), _to, _amount);
        return true;
    }




    function mintInit(
        bytes calldata amount,
        einput eAmount
    ) external virtual whenNotPaused onlyMinters returns (uint requestId) {
        euint64 _amount = TFHE.asEuint64(eAmount, amount);

        euint64 mintingAllowedAmount = minterAllowed[msg.sender];

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(TFHE.le(_amount, mintingAllowedAmount));
        requestId = Gateway.requestDecryption(cts, this.myCustomCallback.selector, 0, block.timestamp + 100, true);
    }

    /**
     * @dev Throws if called by any account other than the masterMinter
     */
    modifier onlyMasterMinter() {
        require(msg.sender == masterMinter, "FiatToken: caller is not the masterMinter");
        _;
    }

    function minterAllowance(address minter) external view returns (euint64) {
        require(minter == msg.sender || minter == owner());
        return minterAllowed[minter];
    }

    /**
     * @notice Checks if an account is a minter.
     * @param account The address to check.
     * @return True if the account is a minter, false if the account is not a minter.
     */
    function isMinter(address account) external view returns (bool) {
        return minters[account];
    }

    function allowance(
        address spender
    ) external view override returns (euint64) {
        address owner = msg.sender;
        return allowed[owner][spender];
    }


    function totalSupply() external view override onlyOwner returns (euint64) {
        return totalSupply_;
    }


    function balanceOf(
        address account
    ) external view override returns (euint64) {
        require(msg.sender == account || msg.sender == owner(), "FiatToken: caller is not the account owner");
        return balanceAndBlacklistStates[account];
    }

    /**
     * @notice Sets a fiat token allowance for a spender to spend on behalf of the caller.
     * @param spender The spender's address.
     * @param value   The allowance amount.
     * @return True if the operation was successful.
     */
    function approve(
        address spender,
        bytes calldata value,
        einput eAmount
    ) external virtual override whenNotPaused returns (bool) {
        euint64 amount = TFHE.asEuint64(eAmount, value);
        amount = TFHE.select(isBlacklisted(msg.sender), TFHE.asEuint64(0), amount);
        amount = TFHE.select(isBlacklisted(spender), TFHE.asEuint64(0), amount);
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev Internal function to set allowance.
     * @param owner     Token owner's address.
     * @param spender   Spender's address.
     * @param value     Allowance amount.
     */
    function _approve(address owner, address spender, euint64 value) internal override {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        allowed[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /**
     * @notice Transfers tokens from an address to another by spending the caller's allowance.
     * @dev The caller must have some fiat token allowance on the payer's tokens.
     * @param from  Payer's address.
     * @param to    Payee's address.
     * @param _value Transfer amount.
     * @return True if the operation was successful.
     */
    function transferFrom(
        address from,
        address to,
        bytes calldata _value,
        einput eAmount,
        uint256 requestId
    )
        external
        virtual
        override
        whenNotPaused
        returns (bool)
    {
        euint64 value = TFHE.asEuint64(eAmount, _value);
        value = TFHE.select(isBlacklisted(msg.sender), TFHE.asEuint64(0), value);
        value = TFHE.select(isBlacklisted(from), TFHE.asEuint64(0), value);
        value = TFHE.select(isBlacklisted(to), TFHE.asEuint64(0), value);
        // require(TFHE.decrypt(TFHE.le(value, allowed[from][msg.sender])), "ERC20: transfer amount exceeds allowance");
        value = TFHE.select(TFHE.le(value, allowed[from][msg.sender]), value, TFHE.asEuint64(0));
        _transfer(from, to, value);
        allowed[from][msg.sender] = TFHE.sub(allowed[from][msg.sender], value);
        return true;
    }

    /**
     * @notice Transfers tokens from the caller.
     * @param to    Payee's address.
     * @param value Transfer amount.
     * @return True if the operation was successful.
     */
    function transfer(
        address to,
        bytes calldata value,
        einput eAmount,
        uint256 requestId
    ) external override whenNotPaused returns (bool) {
        euint64 amount = TFHE.asEuint64(eAmount, value);
        amount = TFHE.select(isBlacklisted(msg.sender), TFHE.asEuint64(0), amount);
        amount = TFHE.select(isBlacklisted(to), TFHE.asEuint64(0), amount);
        _transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @dev Internal function to process transfers.
     * @param from  Payer's address.
     * @param to    Payee's address.
     * @param value Transfer amount.
     */
    function _transfer(address from, address to, euint64 value) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        // require(TFHE.decrypt(TFHE.gt(value, 0)), "ERC20: transfer amount not greater than 0");
        // require(TFHE.decrypt(TFHE.le(value, _balanceOf(from))), "ERC20: transfer amount exceeds balance");
        // value = TFHE.select(TFHE.le(value, _balanceOf(from)), value, TFHE.asEuint64(0));

        require(requestStatus[requestId], "FiatToken: request not completed");
        require(requestOutput[requestId], "FiatToken: amount more than balance");

        _setBalance(from, TFHE.sub(_balanceOf(from), value));
        _setBalance(to, TFHE.add(_balanceOf(to), value));
        emit Transfer(from, to, value);
    }


    function transferInit(
        address to,
        bytes calldata value,
        einput eAmount
    ) external whenNotPaused returns (uint requestId) {
        euint64 amount = TFHE.asEuint64(eAmount, value);
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(TFHE.le(amount, _balanceOf(msg.sender)));
        requestId = Gateway.requestDecryption(cts, this.myCustomCallback.selector, 0, block.timestamp + 100, true);
    }

    /**
     * @notice Adds or updates a new minter with a mint allowance.
     * @param minter The address of the minter.
     * @param minterAllowedAmount The minting amount allowed for the minter.
     * @return True if the operation was successful.
     */
    function configureMinter(
        address minter,
        bytes calldata minterAllowedAmount,
        einput eAmount
    ) external whenNotPaused onlyMasterMinter returns (bool) {
        minters[minter] = true;
        minterAllowed[minter] = TFHE.asEuint64(eAmount, minterAllowedAmount);
        emit MinterConfigured(minter, TFHE.asEuint64(eAmount, minterAllowedAmount));
        return true;
    }

    /**
     * @notice Removes a minter.
     * @param minter The address of the minter to remove.
     * @return True if the operation was successful.
     */
    function removeMinter(address minter) external onlyMasterMinter returns (bool) {
        minters[minter] = false;
        minterAllowed[minter] = TFHE.asEuint64(0);
        emit MinterRemoved(minter);
        return true;
    }

    /**
     * @notice Allows a minter to burn some of its own tokens.
     * @dev The caller must be a minter, must not be blacklisted, and the amount to burn
     * should be less than or equal to the account's balance.
     * @param _amount the amount of tokens to be burned.
     */
    function burn(
        bytes calldata _amount,
        einput eAmount
    ) external virtual whenNotPaused onlyMinters {
        euint64 balance = _balanceOf(msg.sender);
        euint64 amount = TFHE.asEuint64(eAmount, _amount);
        amount = TFHE.select(isBlacklisted(msg.sender), TFHE.asEuint64(0), amount);
        // require(TFHE.decrypt(TFHE.gt(amount, 0)), "FiatToken: burn amount not greater than 0");
        // require(TFHE.decrypt(TFHE.ge(balance, amount)), "FiatToken: burn amount exceeds balance");

        amount = TFHE.select(TFHE.le(amount, balance), amount, TFHE.asEuint64(0));

        totalSupply_ = TFHE.sub(totalSupply_, amount);
        _setBalance(msg.sender, TFHE.sub(balance, amount));
        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    /**
     * @notice Updates the master minter address.
     * @param _newMasterMinter The address of the new master minter.
     */
    function updateMasterMinter(address _newMasterMinter) external onlyOwner {
        require(_newMasterMinter != address(0), "FiatToken: new masterMinter is the zero address");
        masterMinter = _newMasterMinter;
        emit MasterMinterChanged(masterMinter);
    }

    /**
     * @inheritdoc Blacklistable
     */
    function _blacklist(address _account) internal override {
        _setBlacklistState(_account, TFHE.asEbool(true));
    }

    /**
     * @inheritdoc Blacklistable
     */
    function _unBlacklist(address _account) internal override {
        _setBlacklistState(_account, TFHE.asEbool(false));
    }

    /**
     * @dev Helper method that sets the blacklist state of an account.
     * @param _account         The address of the account.
     * @param _shouldBlacklist True if the account should be blacklisted, false if the account should be unblacklisted.
     */
    function _setBlacklistState(address _account, ebool _shouldBlacklist) internal virtual {
        _deprecatedBlacklisted[_account] = _shouldBlacklist;
    }

    /**
     * @dev Helper method that sets the balance of an account.
     * @param _account The address of the account.
     * @param _balance The new fiat token balance of the account.
     */
    function _setBalance(address _account, euint64 _balance) internal virtual {
        balanceAndBlacklistStates[_account] = _balance;
    }

    /**
     * @inheritdoc Blacklistable
     */
    function _isBlacklisted(address _account) internal virtual override returns (ebool) {
        return _deprecatedBlacklisted[_account];
    }

    /**
     * @dev Helper method to obtain the balance of an account.
     * @param _account  The address of the account.
     * @return          The fiat token balance of the account.
     */
    function _balanceOf(address _account) internal virtual returns (euint64) {
        return balanceAndBlacklistStates[_account];
    }

    function myCustomCallback(uint256 requestId, bool decryptedInput) public {
        requestStatus[requestId] = true;
        requestOutput[requestId] = decryptedInput;
    }
}
