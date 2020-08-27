const truffleAssert = require("./helpers/truffle-assertions");
const timeWarp = require("./helpers/timeWarp");
var TokenXS2 = artifacts.require("./XS2Token.sol");
var TokenUSDT = artifacts.require("./TetherToken.sol");
var XS2Option = artifacts.require("./XS2Option.sol");
var XS2Vault = artifacts.require("./XS2Vault.sol");

contract("XS2Factory", (accounts) => {
    var xs2;
    var usdt;
    var option1, option2;
    var vault;

    const alice = accounts[1];
    const bob = accounts[2];
    const charlie = accounts[3];

    before(async () => {
        console.log("Deploying XS2 Token");
        xs2 = await TokenXS2.new();
        console.log("Deploying USDT Token");
        usdt = await TokenUSDT.new(1000000000, "Tether", "USDT", 6);

        console.log("Deploying XS2Option");
        vault = await XS2Vault.new((await XS2Option.new()).address);

        const block = await web3.eth.getBlock("latest");
        let option_tx = await vault.deploy(xs2.address, usdt.address, "20000", block.timestamp + 3600);
        option1 = await XS2Option.at(option_tx.receipt.logs[0].args[0]);

        option_tx = await vault.deploy(xs2.address, usdt.address, "40000", block.timestamp + 3600);
        option2 = await XS2Option.at(option_tx.receipt.logs[0].args[0]);

        console.log(await option1.symbol.call());
        //await usdt.transfer(alice, 300);
        //await xs2.transfer(bob, 5000000000000000);
    });

    it("should have 2 totalContracts", async () => {
        assert.equal(await vault.totalContracts.call(), 2);
    });

    /*    it("should show different prices on the option pools", async () => {
            assert.notEqual(await option1.price.call(), await option2.price.call());
        });
    
        it("should allow minting with exactly enough currency", async () => {
            await usdt.approve(option1.address, 50, { from: alice });
            await option1.mint(50, { from: alice });
        });*/
});
