// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../DamnValuableTokenSnapshot.sol";
import "./ISimpleGovernance.sol"
;
/**
 * @title SimpleGovernance
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract SimpleGovernance is ISimpleGovernance {

    uint256 private constant ACTION_DELAY_IN_SECONDS = 2 days;
    DamnValuableTokenSnapshot private _governanceToken;

    uint256 private _actionCounter; // contatore numero delle governance action
    mapping(uint256 => GovernanceAction) private _actions; // actionId => GovernanceAction parameters

    constructor(address governanceToken) {
        _governanceToken = DamnValuableTokenSnapshot(governanceToken);
        _actionCounter = 1;
    }

    // se msg.sender (immagino il creatore di una proposta) ha ricevuto abbastanza voti può passare la proposta che
    // verrà messa in coda prima di poter essere eseguita... 2 giorni di delay
    function queueAction(address target, uint128 value, bytes calldata data) external returns (uint256 actionId) {
        if (!_hasEnoughVotes(msg.sender)) // msg.sender deve aver raggiunto un minimo di voti
            revert NotEnoughVotes(msg.sender);

        if (target == address(this)) // il target non può essere la governance stessa
            revert InvalidTarget();
        
        if (data.length > 0 && target.code.length == 0) // il target deve essere uno smart contract
            revert TargetMustHaveCode();

        actionId = _actionCounter;

        // aggiungi questa proposta in coda
        _actions[actionId] = GovernanceAction({
            target: target,
            value: value,
            proposedAt: uint64(block.timestamp),
            executedAt: 0,
            data: data
        });

        unchecked { _actionCounter++; } // incrementa il contatore delle proposals

        emit ActionQueued(actionId, msg.sender);
    }

    function executeAction(uint256 actionId) external payable returns (bytes memory) {
        if(!_canBeExecuted(actionId)) // questa proposal può essere eseguita (2 giorni passati dalla messa in coda)
            revert CannotExecute(actionId);

        GovernanceAction storage actionToExecute = _actions[actionId]; // storage pointer alla proposta da eseguire
        actionToExecute.executedAt = uint64(block.timestamp); // aggiorna executedAt con il tempo attuale

        emit ActionExecuted(actionId, msg.sender);

        // esegui la proposta tramite CALL a target con i calldata specificati
        (bool success, bytes memory returndata) = actionToExecute.target.call{value: actionToExecute.value}(actionToExecute.data);
        // se la CALL fallisce
        if (!success) {
            if (returndata.length > 0) { // se c'erano dei return data
                assembly {
                    revert(add(0x20, returndata), mload(returndata)) // @question ??
                }
            } else { // se non c'erano return data
                revert ActionFailed(actionId); // revert classico
            }
        }

        return returndata;
    }

    function getActionDelay() external pure returns (uint256) {
        return ACTION_DELAY_IN_SECONDS;
    }

    function getGovernanceToken() external view returns (address) {
        return address(_governanceToken);
    }

    function getAction(uint256 actionId) external view returns (GovernanceAction memory) {
        return _actions[actionId];
    }

    function getActionCounter() external view returns (uint256) {
        return _actionCounter;
    }

    /**
     * @dev an action can only be executed if:
     * 1) it's never been executed before and
     * 2) enough time has passed since it was first proposed
     */
    function _canBeExecuted(uint256 actionId) private view returns (bool) {
        // @issue [NOT] nessun controllo che actionId < _actionCounter, posso passare un'id nel futuro

        GovernanceAction memory actionToExecute = _actions[actionId]; // copia in memory dei parametri della proposta

        // se proposedAt == 0 è uno stato invalido quindi non possiamo eseguirla
        if (actionToExecute.proposedAt == 0) // early exit
            return false;

        uint64 timeDelta;
        unchecked {
            // differenza tra il tempo attuale e il tempo di proposta
            timeDelta = uint64(block.timestamp) - actionToExecute.proposedAt; // @audit non penso possa mai andare in underflow
        }

        // se non è stata ancora eseguita && sono passati almeno 2 giorni dalla messa in coda... VERO
        return actionToExecute.executedAt == 0 && timeDelta >= ACTION_DELAY_IN_SECONDS;
    }

    // @note per passare, una proposta deve aver ricevuto almeno il 50% dei voti totali, altrimenti non passa
    function _hasEnoughVotes(address who) private view returns (bool) {
        uint256 balance = _governanceToken.getBalanceAtLastSnapshot(who);
        uint256 halfTotalSupply = _governanceToken.getTotalSupplyAtLastSnapshot() / 2;
        return balance > halfTotalSupply;
    }
}
