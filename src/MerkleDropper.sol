// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice MRT native-token Merkle drop — 10% float allocation (24,000,000 MRT)
/// @dev    Leaf = keccak256(abi.encodePacked(index, account, amount))
///         Owner (MULTISIG) sets the Merkle root and can recover unclaimed MRT after deadline.
contract MerkleDropper {

    address public owner;
    bytes32 public merkleRoot;
    uint256 public claimDeadline;   // unix timestamp — 0 = no deadline yet
    uint256 public totalClaimed;

    mapping(uint256 => uint256) private claimedBitMap;

    event RootSet(bytes32 indexed root, uint256 deadline);
    event Claimed(uint256 indexed index, address indexed account, uint256 amount);
    event OwnershipTransferred(address indexed prev, address indexed next);

    modifier onlyOwner() { require(msg.sender == owner, "DROP:owner"); _; }

    constructor() payable {
        owner = msg.sender;
    }

    receive() external payable {}

    // ─── Admin ───────────────────────────────────────────────────────────────

    function setMerkleRoot(bytes32 _root, uint256 _deadlineTimestamp) external onlyOwner {
        merkleRoot = _root;
        claimDeadline = _deadlineTimestamp;
        emit RootSet(_root, _deadlineTimestamp);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "DROP:zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Recover unclaimed MRT after deadline (multisig treasury recovery)
    function recoverUnclaimed(address payable to) external onlyOwner {
        require(claimDeadline > 0 && block.timestamp > claimDeadline, "DROP:deadline");
        uint256 bal = address(this).balance;
        require(bal > 0, "DROP:empty");
        to.transfer(bal);
    }

    // ─── Claim ───────────────────────────────────────────────────────────────

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 word = index / 256;
        uint256 bit  = index % 256;
        return (claimedBitMap[word] >> bit) & 1 == 1;
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata proof)
        external
    {
        require(merkleRoot != bytes32(0), "DROP:root_not_set");
        require(!isClaimed(index), "DROP:already_claimed");
        require(claimDeadline == 0 || block.timestamp <= claimDeadline, "DROP:expired");
        require(address(this).balance >= amount, "DROP:insufficient_balance");

        // Verify Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        require(_verify(proof, merkleRoot, leaf), "DROP:invalid_proof");

        // Mark claimed
        uint256 word = index / 256;
        uint256 bit  = index % 256;
        claimedBitMap[word] |= (1 << bit);

        totalClaimed += amount;

        // Send native MRT
        payable(account).transfer(amount);
        emit Claimed(index, account, amount);
    }

    function _verify(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
        internal pure returns (bool)
    {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 p = proof[i];
            computed = computed < p
                ? keccak256(abi.encodePacked(computed, p))
                : keccak256(abi.encodePacked(p, computed));
        }
        return computed == root;
    }

    // ─── View ────────────────────────────────────────────────────────────────

    function balance() external view returns (uint256) { return address(this).balance; }
}
