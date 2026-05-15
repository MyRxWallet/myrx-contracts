// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice On-chain DAO governance — proposals voted on with staked MRT balance.
contract MRTGovernor {
    address public owner;

    enum State { ACTIVE, PASSED, REJECTED, EXECUTED, CANCELLED }

    struct Proposal {
        uint256 id;
        address proposer;
        string  description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 startTime;
        uint256 endTime;
        State   state;
        address target;      // contract to call if passed
        bytes   callData;    // encoded function call
    }

    uint256 public constant VOTING_PERIOD   = 3 days;
    uint256 public constant MIN_STAKE_VOTE  = 1 ether; // 1 MRT min to vote
    uint256 public constant QUORUM          = 100 ether; // 100 MRT quorum

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(address => uint256) public votingPower; // set by staking contract
    uint256 public nextProposalId;

    address public stakingContract;

    event ProposalCreated(uint256 indexed id, address proposer, string description);
    event Voted(uint256 indexed id, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCancelled(uint256 indexed id);

    modifier onlyOwner() { require(msg.sender == owner, "GOV:owner"); _; }

    constructor() { owner = msg.sender; }

    function setStakingContract(address staking) external onlyOwner {
        stakingContract = staking;
    }

    function setVotingPower(address voter, uint256 power) external {
        require(msg.sender == stakingContract || msg.sender == owner, "GOV:auth");
        votingPower[voter] = power;
    }

    function propose(
        string calldata description,
        address target,
        bytes calldata callData
    ) external payable returns (uint256 id) {
        require(msg.value >= MIN_STAKE_VOTE || votingPower[msg.sender] >= MIN_STAKE_VOTE, "GOV:min_power");
        id = nextProposalId++;
        proposals[id] = Proposal({
            id: id,
            proposer: msg.sender,
            description: description,
            votesFor: 0,
            votesAgainst: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            state: State.ACTIVE,
            target: target,
            callData: callData
        });
        emit ProposalCreated(id, msg.sender, description);
    }

    function vote(uint256 proposalId, bool support) external payable {
        Proposal storage p = proposals[proposalId];
        require(p.state == State.ACTIVE, "GOV:not_active");
        require(block.timestamp < p.endTime, "GOV:ended");
        require(!hasVoted[proposalId][msg.sender], "GOV:already_voted");
        uint256 weight = msg.value > 0 ? msg.value : votingPower[msg.sender];
        require(weight >= MIN_STAKE_VOTE, "GOV:insufficient_power");
        hasVoted[proposalId][msg.sender] = true;
        if (support) p.votesFor += weight;
        else p.votesAgainst += weight;
        // Refund native MRT used for voting weight
        if (msg.value > 0) {
            votingPower[msg.sender] += msg.value;
            payable(msg.sender).transfer(msg.value);
        }
        emit Voted(proposalId, msg.sender, support, weight);
    }

    function finalize(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(p.state == State.ACTIVE, "GOV:not_active");
        require(block.timestamp >= p.endTime, "GOV:not_ended");
        uint256 total = p.votesFor + p.votesAgainst;
        if (total < QUORUM || p.votesAgainst >= p.votesFor) {
            p.state = State.REJECTED;
        } else {
            p.state = State.PASSED;
        }
    }

    function execute(uint256 proposalId) external onlyOwner {
        Proposal storage p = proposals[proposalId];
        require(p.state == State.PASSED, "GOV:not_passed");
        p.state = State.EXECUTED;
        if (p.target != address(0) && p.callData.length > 0) {
            (bool ok,) = p.target.call(p.callData);
            require(ok, "GOV:exec_failed");
        }
        emit ProposalExecuted(proposalId);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero_owner");
        owner = newOwner;
    }
}
