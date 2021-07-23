// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.2;

import "./StakingRewardsEvents.sol";

/// @title StakingRewards
/// @author Forked form SetProtocol
/// https://github.com/SetProtocol/index-coop-contracts/blob/master/contracts/staking/StakingRewards.sol
/// @notice The `StakingRewards` contracts allows to stake an ERC20 token to receive as reward another ERC20
/// @dev This contracts is managed by the reward distributor and implements the staking interface
contract StakingRewards is StakingRewardsEvents, IStakingRewards, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BASE = 10**18;
    bytes32 public constant REWARD_DISTRIBUTOR_ROLE = keccak256("REWARD_DISTRIBUTOR_ROLE");

    // ============================ References to contracts ========================

    /// @notice ERC20 token given as reward
    IERC20 public rewardsToken;

    /// @notice ERC20 token used for staking
    IERC20 public stakingToken;

    /// @notice Rewards Distribution contract for this staking contract
    address public rewardsDistribution;

    // ============================ Staking parameters =============================

    /// @notice Time at which distribution ends
    uint256 public periodFinish = 0;

    /// @notice Reward per second given to the staking contract, split among the staked tokens
    uint256 public rewardRate = 0;

    /// @notice Duration of the reward distribution
    uint256 public rewardsDuration;

    /// @notice Last time `rewardPerTokenStored` was updated
    uint256 public lastUpdateTime;

    /// @notice Helps to compute the amount earned by someone
    /// Cumulates rewards accumulated for one token since the beginning.
    /// Stored as a uint so is actually a float times 1e18
    uint256 public rewardPerTokenStored;

    /// @notice Stores for each account the `rewardPerToken`: we do the difference
    /// between the current and the old value to compute what has been earned by an account
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Stores for each account the accumulated rewards
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;

    // ============================ Constructor ====================================

    /// @notice Initializes the staking contract with a first set of parameters
    /// @param _rewardsDistribution Address owning the rewards token
    /// @param _rewardsToken ERC20 token given as reward
    /// @param _stakingToken ERC20 token used for staking
    /// @param _rewardsDuration Duration of the staking contract
    constructor(
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        uint256 _rewardsDuration
    ) {
        require(
            _stakingToken != address(0) && _rewardsToken != address(0) && _rewardsDistribution != address(0),
            "zero address"
        );
        // Parameters
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDuration = _rewardsDuration;
        rewardsDistribution = _rewardsDistribution;

        // Access control
        _setupRole(REWARD_DISTRIBUTOR_ROLE, _rewardsDistribution);
        _setRoleAdmin(REWARD_DISTRIBUTOR_ROLE, REWARD_DISTRIBUTOR_ROLE);
    }

    // ============================ Modifiers ======================================

    /// @notice Checks to see if the calling address is the zero address
    /// @param account Address to check
    modifier zeroCheck(address account) {
        require(account != address(0), "zero address");
        _;
    }

    /// @notice Called frequently to update the staking parameters associated to an address
    /// @param account Address of the account to update
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // ============================ View functions =================================

    /// @notice Accesses the total supply
    /// @dev Used instead of having a public variable to respect the ERC20 standard
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Accesses the number of token staked by an account
    /// @param account Account to query the balance of
    /// @dev Used instead of having a public variable to respect the ERC20 standard
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Queries the last timestamp at which a reward was distributed
    /// @dev Returns the current timestamp if a reward is being distributed and the end of the staking
    /// period if staking is done
    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    /// @notice Used to actualize the `rewardPerTokenStored`
    /// @dev It adds to the reward per token: the time elapsed since the `rewardPerTokenStored` was
    /// last updated multiplied by the `rewardRate` divided by the number of tokens
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * BASE) / _totalSupply);
    }

    /// @notice Returns how much a given account earned rewards
    /// @param account Address for which the request is made
    /// @return How much a given account earned rewards
    /// @dev It adds to the rewards the amount of reward earned since last time that is the difference
    /// in reward per token from now and last time multiplied by the number of tokens staked by the person
    function earned(address account) public view returns (uint256) {
        return (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / BASE + rewards[account];
    }

    // ======================== Mutative functions forked ==========================

    /// @notice Lets someone stake a given amount of `stakingTokens`
    /// @param amount Amount of ERC20 staking token that the `msg.sender` wants to stake
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        _stake(amount, msg.sender);
    }

    /// @notice Lets a user withdraw a given amount of collateral from the staking contract
    /// @param amount Amount of the ERC20 staking token that the `msg.sender` wants to withdraw
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply - amount;
        _balances[msg.sender] = _balances[msg.sender] - amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Triggers a payment of the reward earned to the msg.sender
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Exits someone
    /// @dev This function lets the caller withdraw its staking and claim rewards
    // Attention here, there may be reentrancy attacks because of the following call
    // to an external contract done before other things are modified, yet since the `rewardToken`
    // is mostly going to be a trusted contract controlled by governance (namely the ANGLE token),
    // this is not an issue. If the `rewardToken` changes to an untrusted contract, this need to be updated.
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    // ====================== Functions added by Angle Core Team ===================

    /// @notice Allows to stake on behalf of another address
    /// @param amount Amount to stake
    /// @param onBehalf Address to stake onBehalf of
    function stakeOnBehalf(uint256 amount, address onBehalf)
        external
        nonReentrant
        zeroCheck(onBehalf)
        updateReward(onBehalf)
    {
        _stake(amount, onBehalf);
    }

    /// @notice Internal function to stake called by `stake` and `stakeOnBehalf`
    /// @param amount Amount to stake
    /// @param onBehalf Address to stake on behalf of
    /// @dev Before calling this function, it has already been verified whether this address was a zero address or not
    function _stake(uint256 amount, address onBehalf) internal {
        require(amount > 0, "Cannot stake 0");
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        _totalSupply = _totalSupply + amount;
        _balances[onBehalf] = _balances[onBehalf] + amount;
        emit Staked(onBehalf, amount);
    }

    // ====================== Restricted Functions =================================

    /// @notice Adds rewards to be distributed
    /// @param reward Amount of reward tokens to distribute
    /// @dev This reward will be distributed during `rewardsDuration` set previously
    function notifyRewardAmount(uint256 reward)
        external
        override
        onlyRole(REWARD_DISTRIBUTOR_ROLE)
        nonReentrant
        updateReward(address(0))
    {
        if (block.timestamp >= periodFinish) {
            // If no reward is currently being distributed, the new rate is just `reward / duration`
            rewardRate = reward / rewardsDuration;
        } else {
            // Otherwise, cancel the future reward and add the amount left to distribute to reward
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensures the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of `rewardRate` in the earned and `rewardsPerToken` functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= balance / rewardsDuration, "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration; // Change the duration
        emit RewardAdded(reward);
    }

    /// @notice Withdraws ERC20 tokens that could accrue on this contract
    /// @param tokenAddress Address of the ERC20 token to withdraw
    /// @param to Address to transfer to
    /// @param amount Amount to transfer
    /// @dev A use case would be to claim tokens if the staked tokens accumulate rewards
    function recoverERC20(
        address tokenAddress,
        address to,
        uint256 amount
    ) external override onlyRole(REWARD_DISTRIBUTOR_ROLE) {
        require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
        require(tokenAddress != address(rewardsToken), "Cannot withdraw the rewards token");

        emit Recovered(tokenAddress, to, amount);
        IERC20(tokenAddress).safeTransfer(to, amount);
    }

    /// @notice Changes the rewards distributor associated to this contract
    /// @param newRewardsDistributor Address of the new rewards distributor contract
    /// @dev The staking rewards interface does not implement the access control interface as
    /// it may create conflicts in the `PerpetualManager` contract which implements access control
    /// upgradable. We therefore need to define this function
    /// @dev This function was also added by Angle Core Team
    /// @dev A zero address check is already performed in the current `RewardsDistributor` implementation
    /// which has right to call this function
    function setNewRewardsDistributor(address newRewardsDistributor)
        external
        override
        onlyRole(REWARD_DISTRIBUTOR_ROLE)
    {
        grantRole(REWARD_DISTRIBUTOR_ROLE, newRewardsDistributor);
        revokeRole(REWARD_DISTRIBUTOR_ROLE, rewardsDistribution);
        rewardsDistribution = newRewardsDistributor;
    }
}