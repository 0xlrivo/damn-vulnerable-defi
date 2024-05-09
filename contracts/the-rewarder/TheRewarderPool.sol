// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "solady/src/utils/FixedPointMathLib.sol";
import "solady/src/utils/SafeTransferLib.sol";
import { RewardToken } from "./RewardToken.sol";
import { AccountingToken } from "./AccountingToken.sol";

/**
 * @title TheRewarderPool
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract TheRewarderPool {
    using FixedPointMathLib for uint256;

    // Minimum duration of each round of rewards in seconds
    uint256 private constant REWARDS_ROUND_MIN_DURATION = 5 days;
    
    uint256 public constant REWARDS = 100 ether;

    // Token deposited into the pool by users
    address public immutable liquidityToken;

    // Token used for internal accounting and snapshots
    // Pegged 1:1 with the liquidity token
    AccountingToken public immutable accountingToken; // @note CANNOT be transferred

    // Token in which rewards are issued
    RewardToken public immutable rewardToken; // @note only this contract can mint them

    // @audit the latest snapshotId taken from AccountingToken:_snapshot()
    uint128 public lastSnapshotIdForRewards;

    // @audit the timestamp of the latest snapshot taken
    uint64 public lastRecordedSnapshotTimestamp;

    uint64 public roundNumber; // Track number of rounds

    mapping(address => uint64) public lastRewardTimestamps;

    error InvalidDepositAmount();

    constructor(address _token) {
        // Assuming all tokens have 18 decimals
        liquidityToken = _token; // DVT token
        accountingToken = new AccountingToken();
        rewardToken = new RewardToken();

        _recordSnapshot();
    }

    /**
     * @notice Deposit `amount` liquidity tokens into the pool, minting accounting tokens in exchange.
     *         Also distributes rewards if available.
     * @param amount amount of tokens to be deposited
     */
    function deposit(uint256 amount) external {
        if (amount == 0) { // non posso depositare 0
            revert InvalidDepositAmount();
        }

        accountingToken.mint(msg.sender, amount); // minta gli accountingToken corrispondenti

        distributeRewards(); // prova a distribuire le rewards

        SafeTransferLib.safeTransferFrom( // pulla i DVT dal depositor (se non ne ho abbastanza reverta qui)
            liquidityToken,
            msg.sender,
            address(this),
            amount
        );
    }

    function withdraw(uint256 amount) external {
        accountingToken.burn(msg.sender, amount); // burna gli accountingToken corrispondenti
        SafeTransferLib.safeTransfer(liquidityToken, msg.sender, amount); // mi ritrasferisce i DVT depositati in precedenza
    }

    function distributeRewards() public returns (uint256 rewards) {
        if (isNewRewardsRound()) { // il round attuale è finito??
            _recordSnapshot(); // se si registra snapshot e avanza al prossimo round
        }

        // quanti accountingToken erano in circolazione nel round precedente ??
        uint256 totalDeposits = accountingToken.totalSupplyAt(lastSnapshotIdForRewards);

        // quanti accountingToken possedeva msg.sender nel round precedente ??
        uint256 amountDeposited = accountingToken.balanceOfAt(msg.sender, lastSnapshotIdForRewards);

        // @audit tramite una flash loan possiamo depositare in una singola transazione e claimare la maggioranza delle rewards
        if (amountDeposited > 0 && totalDeposits > 0) {
            rewards = amountDeposited.mulDiv(REWARDS, totalDeposits);
            if (rewards > 0 && !_hasRetrievedReward(msg.sender)) { // se non hai ancora claimato
                rewardToken.mint(msg.sender, rewards); // minta rewardToken all'utente
                lastRewardTimestamps[msg.sender] = uint64(block.timestamp); // registra il timestamp attuale come l'ultimo claim di questo utente
            }
        }
    }

    function _recordSnapshot() private {
        lastSnapshotIdForRewards = uint128(accountingToken.snapshot()); // @audit questi partono da 1
        lastRecordedSnapshotTimestamp = uint64(block.timestamp);
        unchecked {
            ++roundNumber; // @audit ma questo parte da 0
        }
    }

    function _hasRetrievedReward(address account) private view returns (bool) {
        return (
            lastRewardTimestamps[account] >= lastRecordedSnapshotTimestamp
                && lastRewardTimestamps[account] <= lastRecordedSnapshotTimestamp + REWARDS_ROUND_MIN_DURATION
        );
    }

    // ritorna vero se ci troviamo almeno 5 giorni dopo l'ultimo snapshot (round terminato)
    // in caso, registriamo un nuovo snapshot ed iniziamo il prossimo round, in distributeRewards()  JUMPS
    function isNewRewardsRound() public view returns (bool) {
        return block.timestamp >= lastRecordedSnapshotTimestamp + REWARDS_ROUND_MIN_DURATION;
    }
}
