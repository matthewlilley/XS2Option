// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) { uint256 c = a + b; require(c >= a, "XS2: Overflow"); return c; }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) { require(b <= a, "XS2: Underflow"); uint256 c = a - b; return c; }
    function mul(uint256 a, uint256 b) internal pure returns (uint256)
        { if (a == 0) {return 0;} uint256 c = a * b; require(c / a == b, "XS2: Overflow"); return c; }
    function div(uint256 a, uint256 b) internal pure returns (uint256) { require(b > 0, "XS2: Div by 0"); uint256 c = a / b; return c; }
}

interface IXS2Token {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

struct Stake {
    uint256 duration;
    uint256 end;
    uint256 amount;
    uint256 votes;
}

struct Proposal {
    uint256 start;
    address proposer;
    string description; // Use an IPFS link to JSON data - OK
    address[] targets;
    bytes[] data;

    uint256 forVotes;
    uint256 againstVotes;
    mapping(address => bool) voted;

    bool executed;
}

contract XS2Gov {
    using SafeMath for uint256;

    // Design parameters
    // Lowish gas
    // No entanglement with other parts of the system (stand alone)
    // Timelock built into this contract, no need for a separate one
    address public xs2token;
    uint256 public rewardsPerSecond;

    uint256 public proposalCost;
    uint256 public proposalThreshold;
    uint256 public quorum;
    uint256 public votingDuration;
    uint256 public executeDelay;

    uint256 public rewardPool;
    uint256 public totalVotes;
    mapping(address => Stake) stakes; // Staked tokens per address

    uint8 proposalCount;
    mapping(uint8 => Proposal) public proposals;

    constructor(address xs2token_) {
        xs2token = xs2token_;
        
        // Total reward pool = 5.000.000 * 10^18
        // Total rewards per second = 1.5 * 10^17
        // Your reward per second is votes/totalVotes * rewards per second
        // Your reward is elapsed time * rewards per second * votes / totalVotes
        rewardsPerSecond = 150000000000000000;

        proposalCost = 100000000000000000000; // 100 XS2
        proposalThreshold = 100; // 6 decimals, so this is 0.1%
        quorum = 200000; // 6 decimals, so this is 20%
        votingDuration = 3 days;
        executeDelay = 2 days;
    }

    // Stake XS2 and set a duration. If you already have a stake you cannot set a duration that ends before the current one.
    function stake(uint256 amount, uint256 duration) public returns(bool) {
        require(duration < 365 days, "XS2Gov: Maximum duration is 1 year");
        Stake memory user = stakes[msg.sender];

        if (user.amount > 0) {
            require(block.timestamp + duration > user.end, "XS2Gov: duration cannot end before existing stake");

            // Pay rewards until now and reset
            uint elapsed = block.timestamp.sub(user.end.sub(user.duration));
            uint256 reward = elapsed.mul(rewardsPerSecond).mul(user.votes).div(totalVotes);
            rewardPool = rewardPool.sub(reward);
            user.amount = user.amount.add(reward);
            totalVotes = totalVotes.sub(user.votes);
            user.votes = 0;
        }

        // Create stake
        user.amount.add(amount);
        user.duration = duration;
        user.end = block.timestamp.add(duration);
        user.votes = user.amount.mul(duration).div(365 days);
        totalVotes = totalVotes.add(user.votes);

        stakes[msg.sender] = user;

        require(IXS2Token(xs2token).transferFrom(msg.sender, address(this), amount));
    }

    function collect() public returns(bool) {
        Stake memory user = stakes[msg.sender];
        require(user.amount > 0);

        // Pay rewards until now
        uint elapsed = block.timestamp.sub(user.end.sub(user.duration));
        uint256 reward = elapsed.mul(rewardsPerSecond).mul(user.votes).div(totalVotes);
        rewardPool = rewardPool.sub(reward);

        if (user.end < block.timestamp) {
            user.end = block.timestamp;
        }
        user.duration = user.end.sub(block.timestamp);

        require(IXS2Token(xs2token).transfer(msg.sender, reward));
    }

    // Unstake all and pay all rewards
    function unstake() public returns(bool) {
        Stake memory user = stakes[msg.sender];
        require(user.amount > 0);
        require(block.timestamp > user.end, "XS2Gov: Staking period not ended yet");

        // Reward
        uint elapsed = block.timestamp.sub(user.end.sub(user.duration));
        uint256 reward = elapsed.mul(rewardsPerSecond).mul(user.votes).div(totalVotes);
        rewardPool = rewardPool.sub(reward);
        user.amount = user.amount.add(reward);
        totalVotes = totalVotes.sub(user.votes);
        user.votes = 0;

        uint256 payout = user.amount;
        user.amount = 0;

        stakes[msg.sender] = user;

        require(IXS2Token(xs2token).transfer(msg.sender, payout));
    }

    function propose(string memory description, address[] memory targets, bytes[] memory data) public returns(uint8) {
        require(stakes[msg.sender].votes >= totalVotes.mul(proposalThreshold).div(1e6), "XS2: Not enough votes to propose");
        
        proposalCount++;

        proposals[proposalCount].start = block.timestamp;
        proposals[proposalCount].proposer = msg.sender;
        proposals[proposalCount].description = description;
        proposals[proposalCount].targets = targets;
        proposals[proposalCount].data = data;

        require(IXS2Token(xs2token).transferFrom(msg.sender, address(this), proposalCost));

        return proposalCount;
    }

    function vote(uint8 XIP, bool voteFor) public returns(bool) {
        uint256 start = proposals[XIP].start;
        require(start != 0 && block.timestamp < start.add(votingDuration), "XS2Gov: Voting closed");
        require(!proposals[XIP].voted[msg.sender], "XS2Gov: Already voted");
        if (voteFor) {
            proposals[XIP].forVotes = proposals[XIP].forVotes.add(stakes[msg.sender].votes);
        }
        else {
            proposals[XIP].againstVotes = proposals[XIP].forVotes.add(stakes[msg.sender].votes);
        }
        proposals[XIP].voted[msg.sender] = true;
    }

    function execute(uint8 XIP) public returns(bool) {
        Proposal storage proposal = proposals[XIP];
        require(proposal.start != 0 && block.timestamp < proposal.start.add(votingDuration).add(executeDelay));
        require(proposal.forVotes >= totalVotes.mul(quorum).div(1e6), "XS2: Not enough votes to propose");
        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success,) = proposal.targets[i].call(proposal.data[i]);
            require(success, "XS2Gov: Execution failed");
        }
    }
}