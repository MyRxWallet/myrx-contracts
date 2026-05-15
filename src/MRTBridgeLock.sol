// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice MYRX-MAINNET side of the cross-chain bridge.
/// Users lock MRT here; relayer mints WMRT on destination chain.
/// Relayer burns WMRT on destination; releases MRT here.
contract MRTBridgeLock {
    address public owner;
    address public relayer;     // authorized bridge relayer (CC-operated VPS)
    bool    public paused;

    uint256 public constant MIN_BRIDGE  = 0.01 ether;   // 0.01 MRT minimum
    uint256 public constant BRIDGE_FEE  = 10;            // 0.1% in bps (10/10000)
    uint256 public accruedFees;
    uint256 public nextNonce;

    struct LockRecord {
        address user;
        uint256 amount;         // net amount after fee
        uint256 fee;
        uint256 nonce;
        uint256 lockedAt;
        uint256 destChainId;
        address destAddr;
        bool    released;
    }

    mapping(uint256 => LockRecord) public locks;
    mapping(bytes32 => bool) public processedWithdrawals; // prevent replay

    event Locked(
        uint256 indexed nonce, address indexed user,
        uint256 amount, uint256 fee,
        uint256 destChainId, address destAddr
    );
    event Released(
        uint256 indexed nonce, address indexed to, uint256 amount
    );
    event RelayerUpdated(address newRelayer);

    modifier onlyOwner()   { require(msg.sender == owner,   "BRG:owner");   _; }
    modifier onlyRelayer() { require(msg.sender == relayer, "BRG:relayer"); _; }
    modifier notPaused()   { require(!paused, "BRG:paused"); _; }

    constructor(address _relayer) payable {
        owner   = msg.sender;
        relayer = _relayer;
    }

    /// @notice Lock MRT to bridge to destination chain.
    function lock(uint256 destChainId, address destAddr) external payable notPaused {
        require(msg.value >= MIN_BRIDGE, "BRG:min");
        require(destAddr != address(0), "BRG:dest_zero");
        uint256 fee    = msg.value * BRIDGE_FEE / 10000;
        uint256 net    = msg.value - fee;
        accruedFees   += fee;
        uint256 nonce  = nextNonce++;
        locks[nonce]   = LockRecord(msg.sender, net, fee, nonce, block.timestamp, destChainId, destAddr, false);
        emit Locked(nonce, msg.sender, net, fee, destChainId, destAddr);
    }

    /// @notice Relayer calls this to release MRT on withdrawal from destination chain.
    function release(
        uint256 nonce,
        address to,
        uint256 amount,
        bytes32 withdrawalTxHash
    ) external onlyRelayer notPaused {
        require(!processedWithdrawals[withdrawalTxHash], "BRG:replay");
        processedWithdrawals[withdrawalTxHash] = true;
        require(address(this).balance >= amount, "BRG:insufficient");
        payable(to).transfer(amount);
        emit Released(nonce, to, amount);
    }

    function setRelayer(address _relayer) external onlyOwner {
        relayer = _relayer;
        emit RelayerUpdated(_relayer);
    }

    function setPaused(bool _paused) external onlyOwner { paused = _paused; }

    function withdrawFees() external onlyOwner {
        uint256 amt = accruedFees;
        accruedFees = 0;
        payable(owner).transfer(amt);
    }

    receive() external payable {}
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BRG:zero_owner");
        owner = newOwner;
    }


}
