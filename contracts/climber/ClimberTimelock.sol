// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "./ClimberTimelockBase.sol";
import {ADMIN_ROLE, PROPOSER_ROLE, MAX_TARGETS, MIN_TARGETS, MAX_DELAY} from "./ClimberConstants.sol";
import {
    InvalidTargetsCount,
    InvalidDataElementsCount,
    InvalidValuesCount,
    OperationAlreadyKnown,
    NotReadyForExecution,
    CallerNotTimelock,
    NewDelayAboveMax
} from "./ClimberErrors.sol";

/**
 * @title ClimberTimelock
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract ClimberTimelock is ClimberTimelockBase {
    using Address for address;

    /**
     * @notice Initial setup for roles and timelock delay.
     * @param admin address of the account that will hold the ADMIN_ROLE role
     * @param proposer address of the account that will hold the PROPOSER_ROLE role
     */
    constructor(address admin, address proposer) { // @note manca DEFAULT_ADMIN_ROLE
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PROPOSER_ROLE, ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, admin);
        _setupRole(ADMIN_ROLE, address(this)); // self administration
        _setupRole(PROPOSER_ROLE, proposer);

        delay = 1 hours;
    }

    function schedule(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) external onlyRole(PROPOSER_ROLE) {
        if (targets.length == MIN_TARGETS || targets.length >= MAX_TARGETS) { // lenght dev'essere compresa tra 1 e 256
            revert InvalidTargetsCount();
        }

        if (targets.length != values.length) { // targets e values devono avere la stessa lunghezza
            revert InvalidValuesCount();
        }

        if (targets.length != dataElements.length) { // e anche dataElements
            revert InvalidDataElementsCount();
        }

        bytes32 id = getOperationId(targets, values, dataElements, salt);

        if (getOperationState(id) != OperationState.Unknown) { // l'operation dev'essere nuova
            revert OperationAlreadyKnown(id);
        }

        operations[id].readyAtTimestamp = uint64(block.timestamp) + delay; // questa operazione sarà eseguibile tra 1 ora
        operations[id].known = true;
    }

    /**
     * Anyone can execute what's been scheduled via `schedule`
     */
    function execute(address[] calldata targets, uint256[] calldata values, bytes[] calldata dataElements, bytes32 salt)
        external
        payable
    {
        if (targets.length <= MIN_TARGETS) {
            revert InvalidTargetsCount();
        }

        if (targets.length != values.length) {
            revert InvalidValuesCount();
        }

        if (targets.length != dataElements.length) {
            revert InvalidDataElementsCount();
        }

        bytes32 id = getOperationId(targets, values, dataElements, salt);

        // @audit-issue should add a check that getOperationState(id) != OperationState.unknown

        for (uint8 i = 0; i < targets.length;) {
            targets[i].functionCallWithValue(dataElements[i], values[i]);
            console.log(i);
            unchecked {
                ++i;
            }
        }

        if (getOperationState(id) != OperationState.ReadyForExecution) { 
            revert NotReadyForExecution(id);
        }

        operations[id].executed = true;
    }

    // @audit-issue it is possible to pass a proposal that will set delay to 0
    function updateDelay(uint64 newDelay) external { 
        if (msg.sender != address(this)) {
            revert CallerNotTimelock();
        }

        if (newDelay > MAX_DELAY) {
            revert NewDelayAboveMax();
        }

        delay = newDelay;
    }
}
