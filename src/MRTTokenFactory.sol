// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal ERC-20 for sub-tokens (data tokens, partner tokens, reward tokens).
contract MRTSubToken {
    string  public name;
    string  public symbol;
    uint8   public immutable decimals;
    uint256 public totalSupply;
    address public minter;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    modifier onlyMinter() { require(msg.sender == minter, "SUB:minter"); _; }

    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _supply, address _minter) {
        name = _name; symbol = _symbol; decimals = _decimals; minter = _minter;
        if (_supply > 0) { totalSupply = _supply; balanceOf[_minter] = _supply; emit Transfer(address(0), _minter, _supply); }
    }

    function mint(address to, uint256 amount) external onlyMinter {
        totalSupply += amount; balanceOf[to] += amount; emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) external {
        balanceOf[msg.sender] -= amount; totalSupply -= amount; emit Transfer(msg.sender, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount; balanceOf[to] += amount; emit Transfer(msg.sender, to, amount); return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount; balanceOf[to] += amount; emit Transfer(from, to, amount); return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount; emit Approval(msg.sender, spender, amount); return true;
    }
}

/// @notice Factory for deploying MRTSubToken instances.
/// Partners and data providers use this to issue chain-native tokens.
contract MRTTokenFactory {
    address public owner;
    address[] public allTokens;
    mapping(address => address[]) public deployerTokens;

    event TokenCreated(address indexed token, address indexed deployer, string name, string symbol);

    modifier onlyOwner() { require(msg.sender == owner, "TF:owner"); _; }

    constructor() { owner = msg.sender; }

    function createToken(
        string calldata tokenName,
        string calldata tokenSymbol,
        uint8 tokenDecimals,
        uint256 initialSupply
    ) external returns (address token) {
        token = address(new MRTSubToken(tokenName, tokenSymbol, tokenDecimals, initialSupply, msg.sender));
        allTokens.push(token);
        deployerTokens[msg.sender].push(token);
        emit TokenCreated(token, msg.sender, tokenName, tokenSymbol);
    }

    function allTokensLength() external view returns (uint256) { return allTokens.length; }
    function getDeployerTokens(address deployer) external view returns (address[] memory) {
        return deployerTokens[deployer];
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero_owner");
        owner = newOwner;
    }
}
