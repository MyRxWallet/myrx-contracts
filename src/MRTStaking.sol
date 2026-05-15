// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice MRT native-token staking with time-weighted yield.
/// Stakers lock MRT and earn rewards from the protocol reward pool.
contract MRTStaking {
    address public owner;

    uint256 public constant MIN_LOCK    = 7 days;
    uint256 public constant APR_BPS     = 1200;   // 12% APR in basis points
    uint256 public constant BPS_DENOM   = 10000;
    uint256 public constant YEAR        = 365 days;

    struct Stake {
        uint256 amount;
        uint256 stakedAt;
        uint256 lockUntil;
        uint256 claimedRewards;
    }

    mapping(address => Stake) public stakes;
    uint256 public totalStaked;
    uint256 public rewardPool;

    event Staked(address indexed user, uint256 amount, uint256 lockUntil);
    event Unstaked(address indexed user, uint256 amount, uint256 rewards);
    event RewardPoolFunded(uint256 amount);

    modifier onlyOwner() { require(msg.sender == owner, "STK:owner"); _; }

    constructor() payable { owner = msg.sender; rewardPool = msg.value; }

    /// @notice Fund the reward pool with native MRT.
    function fundRewardPool() external payable {
        rewardPool += msg.value;
        emit RewardPoolFunded(msg.value);
    }

    /// @notice Stake MRT for at least MIN_LOCK duration.
    function stake(uint256 lockDays) external payable {
        require(msg.value > 0, "STK:zero");
        require(lockDays * 1 days >= MIN_LOCK, "STK:min_lock");
        require(stakes[msg.sender].amount == 0, "STK:already_staked");

        stakes[msg.sender] = Stake({
            amount: msg.value,
            stakedAt: block.timestamp,
            lockUntil: block.timestamp + lockDays * 1 days,
            claimedRewards: 0
        });
        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value, stakes[msg.sender].lockUntil);
    }

    /// @notice Calculate pending rewards for a staker.
    function pendingRewards(address user) public view returns (uint256) {
        Stake memory s = stakes[user];
        if (s.amount == 0) return 0;
        uint256 elapsed = block.timestamp - s.stakedAt;
        uint256 earned  = s.amount * APR_BPS * elapsed / (BPS_DENOM * YEAR);
        return earned > s.claimedRewards ? earned - s.claimedRewards : 0;
    }

    /// @notice Unstake after lock period, receiving principal + rewards.
    function unstake() external {
        Stake memory s = stakes[msg.sender];
        require(s.amount > 0, "STK:no_stake");
        require(block.timestamp >= s.lockUntil, "STK:locked");

        uint256 rewards = pendingRewards(msg.sender);
        uint256 payout  = s.amount + rewards;
        require(rewards <= rewardPool, "STK:insufficient_rewards");

        rewardPool  -= rewards;
        totalStaked -= s.amount;
        delete stakes[msg.sender];

        payable(msg.sender).transfer(payout);
        emit Unstaked(msg.sender, s.amount, rewards);
    }

    /// @notice Claim rewards without unstaking.
    function claimRewards() external {
        Stake storage s = stakes[msg.sender];
        require(s.amount > 0, "STK:no_stake");
        uint256 rewards = pendingRewards(msg.sender);
        require(rewards > 0, "STK:no_rewards");
        require(rewards <= rewardPool, "STK:insufficient_rewards");
        rewardPool          -= rewards;
        s.claimedRewards    += rewards;
        payable(msg.sender).transfer(rewards);
    }

    receive() external payable { rewardPool += msg.value; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero_owner");
        owner = newOwner;
    }
}
