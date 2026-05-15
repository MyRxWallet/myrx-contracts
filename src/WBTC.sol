// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Wrapped Bitcoin on MYRX-MAINNET (chain 8472).
///         Mint/burn gated to the registered bridge contract.
///         Follows WMRT pattern: no OpenZeppelin, inline modifiers.
contract WBTC {
    string  public constant name     = "Wrapped Bitcoin";
    string  public constant symbol   = "WBTC";
    uint8   public constant decimals = 8;

    address public bridge;
    address public owner;

    uint256 private _totalSupply;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from,    address indexed to,      uint256 value);
    event Approval(address indexed owner_,  address indexed spender, uint256 value);
    event BridgeUpdated(address indexed newBridge);
    event OwnershipTransferred(address indexed prev, address indexed next);

    modifier onlyBridge() { require(msg.sender == bridge, "WBTC:bridge_only"); _; }
    modifier onlyOwner()  { require(msg.sender == owner,  "WBTC:owner_only");  _; }

    constructor() {
        owner = msg.sender;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    function setBridge(address _bridge) external onlyOwner {
        require(_bridge != address(0), "WBTC:zero_bridge");
        bridge = _bridge;
        emit BridgeUpdated(_bridge);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "WBTC:zero_owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ─── Bridge-gated supply control ─────────────────────────────────────────

    function mint(address to, uint256 amount) external onlyBridge {
        require(to != address(0), "WBTC:mint_to_zero");
        _totalSupply        += amount;
        balanceOf[to]       += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyBridge {
        require(balanceOf[from] >= amount, "WBTC:insufficient_balance");
        balanceOf[from]  -= amount;
        _totalSupply     -= amount;
        emit Transfer(from, address(0), amount);
    }

    // ─── ERC-20 ──────────────────────────────────────────────────────────────

    function totalSupply() external view returns (uint256) { return _totalSupply; }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "WBTC:allowance_exceeded");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(to != address(0), "WBTC:transfer_to_zero");
        require(balanceOf[from] >= amount, "WBTC:insufficient_balance");
        balanceOf[from] -= amount;
        balanceOf[to]   += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
