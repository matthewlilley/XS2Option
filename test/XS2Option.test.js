const truffleAssert = require('./helpers/truffle-assertions');
const timeWarp = require("./helpers/timeWarp");
var TokenXS2 = artifacts.require("./XS2Token.sol");
var TokenUSDT = artifacts.require("./TetherToken.sol");
var XS2Vault = artifacts.require("./XS2Vault.sol");
var XS2Option = artifacts.require("./XS2Option.sol");

function info(tx) {
    console.log('      Gas: ' + tx.receipt.gasUsed);
}

contract("XS2Option", accounts => {
    var xs2;
    var usdt;
    var vault;
    var option;

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

        const block = await web3.eth.getBlock('latest');
        let option_tx = await vault.deploy(xs2.address, usdt.address, "20000", block.timestamp + 3600);
        option = await XS2Option.at(option_tx.receipt.logs[0].args[0]);
        info(option_tx);

        console.log("Seeding Alice with 300 USDT");
        info(await usdt.transfer(alice, 300));

        console.log("Seeding Bob with 5000000000000000 XS2");
        await xs2.transfer(bob, 5000000000000000);
    });

    it("should not allow minting without currency", async () => {
        await truffleAssert.reverts(
            option.mint(1000000, { from: alice })
        );
    });

    it("should not allow withdrawal without funds", async () => {
        await truffleAssert.reverts(
            option.withdraw(1000000, { from: alice })
        );
    });

    it("should not allow exercise without options", async () => {
        await truffleAssert.reverts(
            option.exercise(1000000, { from: alice })
        );
    });

    it("should not allow minting with too little currency", async () => {
        await usdt.approve(vault.address, 99, { from: alice });
        await truffleAssert.reverts(
            option.mint(100, { from: alice })
        );
    });

    it("should allow minting with exactly enough currency", async () => {
        info(await usdt.approve(vault.address, 0, { from: alice }));
        info(await usdt.approve(vault.address, 50, { from: alice }));
        info(await option.mint(50, { from: alice }));
    });

    it("should have minted 50 options", async () => {
        assert.equal((await option.balanceOf.call(alice)).toNumber(), 50);
    });

    it("should've taken 50 currency for minting", async () => {
        assert.equal((await usdt.balanceOf.call(alice)).toNumber(), 250);
    });

    it("should increase totalSupply after minting", async () => {
        assert.equal((await option.totalSupply.call()).toNumber(), 50);
    });

    it("should increase totalIssued after minting", async () => {
        assert.equal((await option.totalIssued.call()).toNumber(), 50);
    });

    it("should not allow withdrawal before expiry", async () => {
        await truffleAssert.reverts(
            option.withdraw(50, { from: alice })
        );
    });

    it("should not allow early withdrawal of more than issued", async () => {
        await truffleAssert.reverts(
            option.withdrawEarly(51, { from: alice })
        );
    });

    it("should allow early withdrawal", async () => {
        info(await option.withdrawEarly(50, { from: alice }));
    });

    it("should allow of some more minting", async () => {
        info(await usdt.approve(vault.address, 0, { from: alice }));
        info(await usdt.approve(vault.address, 200, { from: alice }));
        info(await option.mint(50, { from: alice }));
        info(await option.mint(100, { from: alice }));
    });

    it("should have minted 100 more options", async () => {
        assert.equal((await option.balanceOf.call(alice)).toNumber(), 150);
    });

    it("should've taken 150 currency for minting", async () => {
        assert.equal((await usdt.balanceOf.call(alice)).toNumber(), 150);
    });

    it("should increase totalSupply after minting", async () => {
        assert.equal((await option.totalSupply.call()).toNumber(), 150);
    });

    it("should increase totalIssued after minting", async () => {
        assert.equal((await option.totalIssued.call()).toNumber(), 150);
    });

    it("should be able to transfer some of the minted options to another account", async () => {
        info(await option.transfer(bob, 100, { from: alice }));
    });

    it("should have reduced options for Alice to 50", async () => {
        assert.equal((await option.balanceOf.call(alice)).toNumber(), 50);
    });

    it("should have increased options for Bob to 100", async () => {
        assert.equal((await option.balanceOf.call(bob)).toNumber(), 100);
    });

    it("should allow Bob to exercise some options", async () => {
        info(await xs2.approve(vault.address, 5000000000000000, { from: bob }));
        info(await option.exercise(20, { from: bob }));
    });

    it("should have taken 20/0.02 = 1000 assets from Bob", async () => {
        assert.equal((await xs2.balanceOf.call(bob)).toNumber(), 4000000000000000);
    });

    it("should have decreased options for Bob to 80", async () => {
        assert.equal((await option.balanceOf.call(bob)).toNumber(), 80);
    });

    it("should have given Bob 20 currency", async () => {
        assert.equal((await usdt.balanceOf.call(bob)).toNumber(), 20);
    });

    it("should not allow more minting", async () => {
        await truffleAssert.reverts(
            option.mint(20, { from: alice })
        );
    });

    it("should not allow Bob to exercise more options than he has", async () => {
        await truffleAssert.reverts(
            option.exercise(100, { from: bob })
        );
    });

    it("should allow Bob to exercise his remaining options", async () => {
        info(await option.exercise(80, { from: bob }));
    });

    it("should allow Alice to withdraw after expiry", async () => {
        await timeWarp.advanceTimeAndBlock(3600);

        // Alice withdraws
        info(await option.withdraw(150, { from: alice }));
    });

    it("should have all balances correctly at the end", async () => {
        assert.equal((await usdt.balanceOf.call(alice)).toNumber(), 200);
        assert.equal((await xs2.balanceOf.call(alice)).toNumber(), 5000000000000000);
        assert.equal((await option.balanceOf.call(alice)).toNumber(), 50);
    
        assert.equal((await usdt.balanceOf.call(bob)).toNumber(), 100);
        assert.equal((await xs2.balanceOf.call(bob)).toNumber(), 0);
        assert.equal((await option.balanceOf.call(bob)).toNumber(), 0);
    
        assert.equal((await usdt.balanceOf.call(option.address)).toNumber(), 0);
        assert.equal((await xs2.balanceOf.call(option.address)).toNumber(), 0);
        assert.equal((await option.balanceOf.call(option.address)).toNumber(), 0);
    });

});


        /*assert.equal((await usdt.balanceOf.call(alice)).toNumber(), 0);
        assert.equal((await xs2.balanceOf.call(alice)).toNumber(), 50000000000000000000);
        assert.equal((await option.balanceOf.call(alice)).toNumber(), 0);
    
        assert.equal((await usdt.balanceOf.call(bob)).toNumber(), 1000000);
        assert.equal((await xs2.balanceOf.call(bob)).toNumber(), 0);
        assert.equal((await option.balanceOf.call(bob)).toNumber(), 0);
    
        assert.equal((await usdt.balanceOf.call(option.address)).toNumber(), 0);
        assert.equal((await xs2.balanceOf.call(option.address)).toNumber(), 0);
        assert.equal((await option.balanceOf.call(option.address)).toNumber(), 0);*/

        /*console.log("Alice USDT: " + (await usdt.balanceOf.call(alice)));
        console.log("Bob USDT: " + (await usdt.balanceOf.call(bob)));
        console.log("Option USDT: " + (await usdt.balanceOf.call(option.address)));

        console.log("Alice XS2: " + (await xs2.balanceOf.call(alice)));
        console.log("Bob XS2: " + (await xs2.balanceOf.call(bob)));
        console.log("Option XS2: " + (await xs2.balanceOf.call(option.address)));

        console.log("Alice Options: " + (await option.balanceOf.call(alice)));
        console.log("Bob Options: " + (await option.balanceOf.call(bob)));
        console.log("Option Options: " + (await option.balanceOf.call(option.address)));*/
