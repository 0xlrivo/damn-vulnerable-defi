// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "solady/src/auth/OwnableRoles.sol";
import {TheRewarderPool} from "./TheRewarderPool.sol";

/**
 * @title AccountingToken
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 * @notice A limited pseudo-ERC20 token to keep track of deposits and withdrawals
 *         with snapshotting capabilities.
 */

// @note lo usiamo come shareToken per la RewarderPool con delle funzioni di snapshot aggiunte

contract AccountingToken is ERC20Snapshot, OwnableRoles {
    uint256 public constant MINTER_ROLE = _ROLE_0;
    uint256 public constant SNAPSHOT_ROLE = _ROLE_1;
    uint256 public constant BURNER_ROLE = _ROLE_2;

    error NotImplemented();

    constructor() ERC20("rToken", "rTKN") {
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, MINTER_ROLE | SNAPSHOT_ROLE | BURNER_ROLE); // @question usa gli OR perchè i role sono dei byte-shifts??
    }

    function mint(address to, uint256 amount) external onlyRoles(MINTER_ROLE) { // @note only TheRewarderPool can call this
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRoles(BURNER_ROLE) { // @note only TheRewarderPool can call this
        _burn(from, amount);
    }

    function snapshot() external onlyRoles(SNAPSHOT_ROLE) returns (uint256) { // @note only TheRewarderPool can call this
        return _snapshot(); // standard ERC20Snapshot _snapshot() taking logic that just upgrades the snapshotId internal counter
    }

    function _transfer(address, address, uint256) internal pure override { // impossible to transfer
        revert NotImplemented();
    }

    function _approve(address, address, uint256) internal pure override { // impossible to approve
        revert NotImplemented();
    }
}
