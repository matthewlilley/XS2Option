// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) { uint256 c = a + b; require(c >= a, "XS2: Overflow"); return c; }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) { require(b <= a, "XS2: Underflow"); uint256 c = a - b; return c; }
    function mul(uint256 a, uint256 b) internal pure returns (uint256)
        { if (a == 0) {return 0;} uint256 c = a * b; require(c / a == b, "XS2: Overflow"); return c; }
    function div(uint256 a, uint256 b) internal pure returns (uint256) { require(b > 0, "XS2: Div by 0"); uint256 c = a / b; return c; }
}

interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function transfer(address to, uint256 amount) external returns(bool);
    function transferFrom(address from, address to, uint256 amount) external returns(bool);
}

// Supply: Safe... just add
// Withdraw: Delay for liquidity check
// Borrow: Delay for liquidity check

struct Timelock {
    uint256 amount;
    uint256 unlockAt;
}

struct Proof {
    address liquidator;
    uint256 amountA;
    uint256 amountB;
    uint256 openUntil;
    uint256 status; // 0 = new, 1 = swapped, 2 = withdrawn
}

contract BPair {
    using SafeMath for uint256;

    IERC20 public tokenA;
    IERC20 public tokenB;

    uint256 public totalSupplyA;
    uint256 public totalSupplyB;
    uint256 public totalBorrowB;
    uint256 public interest;

    mapping(address => uint256) supplyA;
    mapping(address => uint256) supplyB;
    mapping(address => uint256) borrowB;
    
    mapping(address => Timelock) claimA;
    mapping(address => Timelock) claimB;

    uint256 proofCount;
    mapping(uint256 => Proof) proofs;

    function init(address tokenA_, address tokenB_) public {
        tokenA = IERC20(tokenA_);
        tokenB = IERC20(tokenB_);
    }

    function _incSupplyA(address user, uint256 amount) private { supplyA[user] = supplyA[user].add(amount); totalSupplyA = totalSupplyA.add(amount); }
    function _decSupplyA(address user, uint256 amount) private { supplyA[user] = supplyA[user].sub(amount); totalSupplyA = totalSupplyA.sub(amount); }
    function _incSupplyB(address user, uint256 amount) private { supplyB[user] = supplyB[user].add(amount); totalSupplyB = totalSupplyB.add(amount); }
    function _decSupplyB(address user, uint256 amount) private { supplyB[user] = supplyB[user].sub(amount); totalSupplyB = totalSupplyB.sub(amount); }
    function _incBorrowB(address user, uint256 amount) private { borrowB[user] = borrowB[user].add(amount); totalBorrowB = totalBorrowB.add(amount); }
    function _decBorrowB(address user, uint256 amount) private { borrowB[user] = borrowB[user].sub(amount); totalBorrowB = totalBorrowB.sub(amount); }

    function _depositA(address from, uint256 amount) private { require(tokenA.transferFrom(from, address(this), amount), "B: Transfer failed"); }
    function _depositB(address from, uint256 amount) private { require(tokenB.transferFrom(from, address(this), amount), "B: Transfer failed"); }
    function _withdrawA(address to, uint256 amount) private { require(tokenA.transfer(to, amount), "B: Transfer failed"); }
    function _withdrawB(address to, uint256 amount) private { require(tokenA.transfer(to, amount), "B: Transfer failed"); }

    function supplyTokenA(uint256 amount) public {
        _incSupplyA(msg.sender, amount);
        _depositA(msg.sender, amount);
    }

    function supplyTokenB(uint256 amount) public {
        _incSupplyB(msg.sender, amount);
        _depositB(msg.sender, amount);
    }

    function withdrawTokenA(uint256 amount) public {
        _decSupplyA(msg.sender, amount);
        
        // If there no borrow, just transfer, otherwise create or add to claim
        if (borrowB[msg.sender] == 0) {
            _withdrawA(msg.sender, amount);
        }
        else {
            claimA[msg.sender].amount = claimA[msg.sender].amount.add(amount);
            claimA[msg.sender].unlockAt = block.number + 10;
        }
    }

    function withdrawTokenB(uint256 amount) public {
        _decSupplyB(msg.sender, amount);
        
        // If there no borrow, just transfer, otherwise create or add to claim
        if (borrowB[msg.sender] == 0) {
            _withdrawB(msg.sender, amount);
        }
        else {
            claimB[msg.sender].amount = claimB[msg.sender].amount.add(amount);
            claimB[msg.sender].unlockAt = block.number + 10;
        }
    }

    function borrowTokenB(uint256 amount) public {
        _incBorrowB(msg.sender, amount);
        claimB[msg.sender].amount = claimB[msg.sender].amount.add(amount);
        claimB[msg.sender].unlockAt = block.number + 10;
    }

    function repayTokenB(uint256 amount) public {
        _depositB(msg.sender, amount);
        _decBorrowB(msg.sender, amount);
    }

    function claimTokenA() public {
        require(claimA[msg.sender].unlockAt >= block.number);                           // Check that the claim is unlocked
        uint256 amount = claimA[msg.sender].amount;
        delete claimA[msg.sender];                                                      // Remove the claim
        require(tokenA.transfer(msg.sender, amount), "B: Transfer failed");             // Transfer the tokens
    }

    function claimTokenB() public {
        require(claimB[msg.sender].unlockAt >= block.number);                           // Check that the claim is unlocked
        uint256 amount = claimB[msg.sender].amount;
        delete claimB[msg.sender];                                                      // Remove the claim
        require(tokenB.transfer(msg.sender, amount), "B: Transfer failed");             // Transfer the tokens
    }

    function createProof(uint256 amountA, uint256 amountB) public {
        require(tokenA.transferFrom(msg.sender, address(this), amountA), "B: Transfer failed");
        Proof memory proof = Proof({
            liquidator: msg.sender,
            amountA: amountA,
            amountB: amountB,
            openUntil: block.number + 5,
            status: 0
        });

        proofs[proofCount] = proof;
        proofCount++;
    }

    function swapProof(uint256 proofID) public {
        Proof memory proof = proofs[proofID];
        require(proof.openUntil <= block.number);
        require(tokenB.transferFrom(msg.sender, address(0), proof.amountB), "B: Transfer failed");
        require(tokenA.transfer(msg.sender, proof.amountA), "B: Transfer failed");
        proofs[proofID].status = 1;
    }

    function withdrawProof(uint256 proofID) public {
        Proof memory proof = proofs[proofID];
        require(msg.sender == proof.liquidator);
        require(proof.status != 2);

        if (proof.status == 0) {
            require(tokenA.transfer(msg.sender, proof.amountA), "B: Transfer failed");
        }
        else {
            require(tokenB.transfer(msg.sender, proof.amountB), "B: Transfer failed");
        }
        proofs[proofID].status = 2;
    }

    function _validateProof(Proof memory proof) view private {
        // Only the liquidator can use this proof
        require(msg.sender == proof.liquidator);

        // Proof is valid, not swapped and not too old
        require(proof.openUntil <= block.number);
        require(block.number <= proof.openUntil + 5);
        require(proof.status != 1);
    }

    function _liquidateTarget(address target, uint256 amountB, uint256 proofID) private returns (uint256) {
        Proof memory proof = proofs[proofID];

        uint256 amountA = amountB.mul(proof.amountA).div(proof.amountB);                // Calculate amount of A at proven price
        uint256 balanceB = borrowB[target].sub(supplyB[target]);                        // The net tokenB balance of target
        require(amountB <= balanceB);                                                   // Cannot liquidate more than the net balances of target

        // Account has to be under water
        uint256 amountBNeeded = amountA.mul(75).div(100).mul(amountB).div(amountA);
        require(amountBNeeded > balanceB);

        uint256 rewardA = amountA.mul(114).div(100);                                    // Apply liquidation bonus

        _decSupplyA(target, rewardA);                                                   // Update target's balances
        _decBorrowB(target, amountB);

        proofs[proofID].amountA = proof.amountA.sub(amountA);                           // Reduce proof amounts
        proofs[proofID].amountB = proof.amountB.sub(amountB);

        return rewardA;
    }

    function liquidate(address target, uint256 amountB, uint256 proofID) public {
        Proof memory proof = proofs[proofID];
        _validateProof(proof);

        uint256 amountA = _liquidateTarget(target, amountB, proofID);

        _depositB(msg.sender, amountB);                                                 // Receive tokenB from liquidator
        _withdrawA(msg.sender, amountA);                                                // Pay out tokenA to liquidator
    }

    function liquidateInternal(address target, uint256 amountB, uint256 proofID) public {
        // instead of using actual tokens, the liquidator borrows the B tokens and receives the A tokens for collateral
        // This reduces gas usage and allows the liquidator more flexibility
    }

    function liquidateMultiple() public {
        // liquidate multiple accounts while only testing the proof and transferring once
    }
}