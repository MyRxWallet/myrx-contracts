// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

/// @notice Minimal ERC-20 for LP tokens.
contract MRTLPToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public pair;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    constructor(string memory _name, string memory _symbol) { name=_name; symbol=_symbol; pair=msg.sender; }
    modifier onlyPair { require(msg.sender==pair,"LP:pair"); _; }
    function mint(address to, uint256 amt) external onlyPair { totalSupply+=amt; balanceOf[to]+=amt; emit Transfer(address(0),to,amt); }
    function burn(address from, uint256 amt) external onlyPair { balanceOf[from]-=amt; totalSupply-=amt; emit Transfer(from,address(0),amt); }
    function transfer(address to, uint256 amt) external returns (bool) { balanceOf[msg.sender]-=amt; balanceOf[to]+=amt; emit Transfer(msg.sender,to,amt); return true; }
    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        if(allowance[from][msg.sender]!=type(uint256).max) allowance[from][msg.sender]-=amt;
        balanceOf[from]-=amt; balanceOf[to]+=amt; emit Transfer(from,to,amt); return true;
    }
    function approve(address sp, uint256 amt) external returns (bool) { allowance[msg.sender][sp]=amt; emit Approval(msg.sender,sp,amt); return true; }
}

/// @notice Constant-product AMM pair (x*y=k).
contract MRTPair {
    address public token0;
    address public token1;
    MRTLPToken public lpToken;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32  private blockTimestampLast;
    uint256 private unlocked = 1;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 in0, uint256 in1, uint256 out0, uint256 out1, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    modifier lock() { require(unlocked==1,"PAIR:locked"); unlocked=0; _; unlocked=1; }

    constructor(address _token0, address _token1) {
        token0 = _token0; token1 = _token1;
        lpToken = new MRTLPToken(
            string(abi.encodePacked("MRT-LP")),
            string(abi.encodePacked("MRT-LP"))
        );
    }

    function getReserves() external view returns (uint112 r0, uint112 r1, uint32 ts) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function _update(uint256 bal0, uint256 bal1) private {
        reserve0 = uint112(bal0);
        reserve1 = uint112(bal1);
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }

    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 r0, uint112 r1,) = (reserve0, reserve1, blockTimestampLast);
        uint256 bal0 = IERC20(token0).balanceOf(address(this));
        uint256 bal1 = IERC20(token1).balanceOf(address(this));
        uint256 amt0 = bal0 - r0;
        uint256 amt1 = bal1 - r1;
        uint256 supply = lpToken.totalSupply();
        if (supply == 0) {
            liquidity = _sqrt(amt0 * amt1);
        } else {
            liquidity = _min(amt0 * supply / r0, amt1 * supply / r1);
        }
        require(liquidity > 0, "PAIR:liquidity");
        lpToken.mint(to, liquidity);
        _update(bal0, bal1);
        emit Mint(msg.sender, amt0, amt1);
    }

    function burn(address to) external lock returns (uint256 amt0, uint256 amt1) {
        uint256 liquidity = lpToken.balanceOf(address(this));
        uint256 supply = lpToken.totalSupply();
        uint256 bal0 = IERC20(token0).balanceOf(address(this));
        uint256 bal1 = IERC20(token1).balanceOf(address(this));
        amt0 = liquidity * bal0 / supply;
        amt1 = liquidity * bal1 / supply;
        lpToken.burn(address(this), liquidity);
        IERC20(token0).transfer(to, amt0);
        IERC20(token1).transfer(to, amt1);
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        emit Burn(msg.sender, amt0, amt1, to);
    }

    function swap(uint256 out0, uint256 out1, address to) external lock {
        require(out0 > 0 || out1 > 0, "PAIR:output");
        (uint112 r0, uint112 r1,) = (reserve0, reserve1, blockTimestampLast);
        require(out0 < r0 && out1 < r1, "PAIR:liquidity");
        if (out0 > 0) IERC20(token0).transfer(to, out0);
        if (out1 > 0) IERC20(token1).transfer(to, out1);
        uint256 bal0 = IERC20(token0).balanceOf(address(this));
        uint256 bal1 = IERC20(token1).balanceOf(address(this));
        uint256 in0 = bal0 > r0 - out0 ? bal0 - (r0 - out0) : 0;
        uint256 in1 = bal1 > r1 - out1 ? bal1 - (r1 - out1) : 0;
        require(in0 > 0 || in1 > 0, "PAIR:input");
        // 0.3% fee: adjusted_bal * 1000 - in * 3
        uint256 adj0 = bal0 * 1000 - in0 * 3;
        uint256 adj1 = bal1 * 1000 - in1 * 3;
        require(adj0 * adj1 >= uint256(r0) * uint256(r1) * 1000000, "PAIR:K");
        _update(bal0, bal1);
        emit Swap(msg.sender, in0, in1, out0, out1, to);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) { z = y; uint256 x = y/2+1; while(x<z){z=x;x=(y/x+x)/2;} }
        else if (y != 0) z = 1;
    }
    function _min(uint256 a, uint256 b) internal pure returns (uint256) { return a<b?a:b; }
}

/// @notice DEX Factory — creates and tracks trading pairs.
contract MRTDexFactory {
    address public feeTo;
    address public feeToSetter;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 totalPairs);

    constructor(address _feeToSetter) { feeToSetter = _feeToSetter; }

    function allPairsLength() external view returns (uint256) { return allPairs.length; }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "FACTORY:identical");
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(t0 != address(0), "FACTORY:zero");
        require(getPair[t0][t1] == address(0), "FACTORY:exists");
        pair = address(new MRTPair(t0, t1));
        getPair[t0][t1] = pair;
        getPair[t1][t0] = pair;
        allPairs.push(pair);
        emit PairCreated(t0, t1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external { require(msg.sender==feeToSetter,"FACTORY:auth"); feeTo=_feeTo; }
    function setFeeToSetter(address _fts) external { require(msg.sender==feeToSetter,"FACTORY:auth"); feeToSetter=_fts; }
}

/// @notice Simple DEX router for adding liquidity and swapping.
contract MRTDexRouter {
    address public immutable factory;
    address public immutable WMRT;

    constructor(address _factory, address _wmrt) { factory = _factory; WMRT = _wmrt; }

    function _pairFor(address tA, address tB) internal view returns (address) {
        return MRTDexFactory(factory).getPair(tA, tB);
    }

    function addLiquidity(
        address tokenA, address tokenB,
        uint256 amtADesired, uint256 amtBDesired,
        uint256 amtAMin, uint256 amtBMin,
        address to
    ) external returns (uint256 amtA, uint256 amtB, uint256 liquidity) {
        address pair = MRTDexFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) pair = MRTDexFactory(factory).createPair(tokenA, tokenB);
        (uint112 r0, uint112 r1,) = MRTPair(pair).getReserves();
        (address t0,) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint256 rA, uint256 rB) = tokenA == t0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        if (rA == 0 && rB == 0) {
            (amtA, amtB) = (amtADesired, amtBDesired);
        } else {
            uint256 optB = amtADesired * rB / rA;
            if (optB <= amtBDesired) {
                require(optB >= amtBMin, "ROUTER:B_min");
                (amtA, amtB) = (amtADesired, optB);
            } else {
                uint256 optA = amtBDesired * rA / rB;
                require(optA >= amtAMin, "ROUTER:A_min");
                (amtA, amtB) = (optA, amtBDesired);
            }
        }
        IERC20(tokenA).transferFrom(msg.sender, pair, amtA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amtB);
        liquidity = MRTPair(pair).mint(to);
    }

    function swapExactTokensForTokens(
        uint256 amtIn, uint256 amtOutMin,
        address[] calldata path, address to
    ) external returns (uint256[] memory amounts) {
        require(path.length >= 2, "ROUTER:path");
        amounts = new uint256[](path.length);
        amounts[0] = amtIn;
        for (uint256 i; i < path.length-1; i++) {
            address pair = _pairFor(path[i], path[i+1]);
            require(pair != address(0), "ROUTER:pair");
            (uint112 r0, uint112 r1,) = MRTPair(pair).getReserves();
            (address t0,) = path[i] < path[i+1] ? (path[i], path[i+1]) : (path[i+1], path[i]);
            (uint256 rIn, uint256 rOut) = path[i]==t0 ? (uint256(r0),uint256(r1)) : (uint256(r1),uint256(r0));
            uint256 amtInFee = amounts[i] * 997;
            amounts[i+1] = amtInFee * rOut / (rIn * 1000 + amtInFee);
        }
        require(amounts[amounts.length-1] >= amtOutMin, "ROUTER:slippage");
        IERC20(path[0]).transferFrom(msg.sender, _pairFor(path[0], path[1]), amounts[0]);
        for (uint256 i; i < path.length-1; i++) {
            (address t0,) = path[i]<path[i+1]?(path[i],path[i+1]):(path[i+1],path[i]);
            address pairAddr = _pairFor(path[i], path[i+1]);
            address toAddr = i < path.length-2 ? _pairFor(path[i+1], path[i+2]) : to;
            (uint256 out0, uint256 out1) = path[i]==t0 ? (uint256(0), amounts[i+1]) : (amounts[i+1], uint256(0));
            MRTPair(pairAddr).swap(out0, out1, toAddr);
        }
    }
}
