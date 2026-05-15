// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IWBTC {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
}

/// @notice Trusted-relayer BTC↔WBTC bridge on MYRX-MAINNET.
///         Mint flow : relayer submits proof of BTC deposit → WBTC minted.
///         Redeem flow: user burns WBTC → relayer sends BTC on-chain.
///         Follows MRTBridgeLock pattern: no OpenZeppelin, inline modifiers.
contract MyrxBTCBridge {

    address public owner;
    address public relayer;
    address public immutable wbtc;
    bool    public paused;

    string  public custodyBTCAddress;

    uint256 public constant MIN_SATOSHIS  = 10_000;        // 0.0001 BTC
    uint256 public constant MAX_SATOSHIS  = 100_000_000_000; // 1000 BTC

    uint256 public dailyMintCap         = 1_000_000_000;   // 10 BTC default (satoshis)
    uint256 public dailyMintedAmount;
    uint256 public dailyMintWindowStart;

    uint256 public nextRedemptionNonce;

    struct RedemptionRecord {
        address user;
        uint256 satoshis;
        string  btcDestAddress;
        uint256 initiatedAt;
        bytes32 btcTxHash;
        bool    confirmed;
    }

    mapping(uint256 => RedemptionRecord) public redemptions;
    mapping(bytes32  => bool)            public processedBTCTxHashes;

    event WBTCMinted(
        address indexed recipient,
        uint256         satoshis,
        bytes32 indexed btcTxHash
    );
    event RedemptionInitiated(
        uint256 indexed nonce,
        address indexed user,
        uint256         satoshis,
        string          btcDestAddress
    );
    event RedemptionConfirmed(
        uint256 indexed nonce,
        bytes32 indexed btcTxHash
    );
    event RelayerUpdated(address indexed newRelayer);
    event CustodyAddressUpdated(string newAddress);
    event DailyCapUpdated(uint256 newCap);
    event BridgePaused(bool isPaused);
    event OwnershipTransferred(address indexed prev, address indexed next);

    modifier onlyOwner()   { require(msg.sender == owner,   "BTC:owner");   _; }
    modifier onlyRelayer() { require(msg.sender == relayer, "BTC:relayer"); _; }
    modifier notPaused()   { require(!paused,               "BTC:paused");  _; }

    constructor(address _wbtc, address _relayer, string memory _custodyAddr) {
        require(_wbtc    != address(0), "BTC:zero_wbtc");
        require(_relayer != address(0), "BTC:zero_relayer");
        owner              = msg.sender;
        wbtc               = _wbtc;
        relayer            = _relayer;
        custodyBTCAddress  = _custodyAddr;
        dailyMintWindowStart = block.timestamp;
    }

    // ─── Mint flow (BTC → WBTC) ──────────────────────────────────────────────

    function mintWBTC(
        address recipient,
        uint256 satoshis,
        bytes32 btcTxHash
    ) external onlyRelayer notPaused {
        require(recipient != address(0),            "BTC:zero_recipient");
        require(satoshis >= MIN_SATOSHIS,           "BTC:below_min");
        require(satoshis <= MAX_SATOSHIS,           "BTC:above_max");
        require(!processedBTCTxHashes[btcTxHash],   "BTC:replay");

        _refreshDailyWindow();
        require(dailyMintedAmount + satoshis <= dailyMintCap, "BTC:daily_cap");

        processedBTCTxHashes[btcTxHash] = true;
        dailyMintedAmount              += satoshis;

        IWBTC(wbtc).mint(recipient, satoshis);
        emit WBTCMinted(recipient, satoshis, btcTxHash);
    }

    // ─── Redeem flow (WBTC → BTC) ────────────────────────────────────────────

    function initiateRedemption(
        uint256 satoshis,
        string calldata btcDestAddress
    ) external notPaused {
        require(satoshis >= MIN_SATOSHIS, "BTC:below_min");
        require(satoshis <= MAX_SATOSHIS, "BTC:above_max");
        require(bytes(btcDestAddress).length > 0, "BTC:empty_dest");

        uint256 nonce = nextRedemptionNonce++;
        redemptions[nonce] = RedemptionRecord({
            user:           msg.sender,
            satoshis:       satoshis,
            btcDestAddress: btcDestAddress,
            initiatedAt:    block.timestamp,
            btcTxHash:      bytes32(0),
            confirmed:      false
        });

        IWBTC(wbtc).burn(msg.sender, satoshis);
        emit RedemptionInitiated(nonce, msg.sender, satoshis, btcDestAddress);
    }

    function confirmRedemption(
        uint256 nonce,
        bytes32 btcTxHash
    ) external onlyRelayer {
        RedemptionRecord storage r = redemptions[nonce];
        require(r.user != address(0),              "BTC:unknown_nonce");
        require(!r.confirmed,                      "BTC:already_confirmed");
        require(!processedBTCTxHashes[btcTxHash],  "BTC:replay");

        processedBTCTxHashes[btcTxHash] = true;
        r.confirmed  = true;
        r.btcTxHash  = btcTxHash;

        emit RedemptionConfirmed(nonce, btcTxHash);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    function _refreshDailyWindow() internal {
        if (block.timestamp >= dailyMintWindowStart + 1 days) {
            dailyMintWindowStart = block.timestamp;
            dailyMintedAmount    = 0;
        }
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    function setRelayer(address _relayer) external onlyOwner {
        require(_relayer != address(0), "BTC:zero_relayer");
        relayer = _relayer;
        emit RelayerUpdated(_relayer);
    }

    function setCustodyBTCAddress(string calldata addr) external onlyOwner {
        require(bytes(addr).length > 0, "BTC:empty_addr");
        custodyBTCAddress = addr;
        emit CustodyAddressUpdated(addr);
    }

    function setDailyMintCap(uint256 cap) external onlyOwner {
        require(cap > 0, "BTC:zero_cap");
        dailyMintCap = cap;
        emit DailyCapUpdated(cap);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit BridgePaused(_paused);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BTC:zero_owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
