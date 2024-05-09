// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../DamnValuableToken.sol";

/**
 * @title FlashLoanerPool
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 * @dev A simple pool to get flashloans of DVT
 */
contract FlashLoanerPool is ReentrancyGuard {
    using Address for address;

    DamnValuableToken public immutable liquidityToken;

    error NotEnoughTokenBalance();
    error CallerIsNotContract();
    error FlashLoanNotPaidBack();

    constructor(address liquidityTokenAddress) {
        liquidityToken = DamnValuableToken(liquidityTokenAddress);
    }

    function flashLoan(uint256 amount) external nonReentrant {
        uint256 balanceBefore = liquidityToken.balanceOf(address(this));

        if (amount > balanceBefore) {
            revert NotEnoughTokenBalance();
        }

        if (!msg.sender.isContract()) { // only smart contracts can call this function
            revert CallerIsNotContract();
        }

        liquidityToken.transfer(msg.sender, amount); // transfer flash-loaned DVT to requester

        msg.sender.functionCall(abi.encodeWithSignature("receiveFlashLoan(uint256)", amount)); // callback

        if (liquidityToken.balanceOf(address(this)) < balanceBefore) { // asserting that flashloan has been paid back
            revert FlashLoanNotPaidBack();
        }
    }
}
