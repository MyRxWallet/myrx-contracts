// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Healthcare data licensing marketplace.
/// Providers list data records; patients authorize access; purchasers pay MRT.
contract HealthDataMarket {
    address public owner;
    uint256 public protocolFeeBps = 300; // 3%
    uint256 public accruedFees;

    struct Listing {
        address provider;
        string  dataHash;       // IPFS CID of encrypted data package
        string  dataType;       // e.g. "rx_history", "lab_results", "vitals"
        uint256 priceWei;       // price in MRT wei
        bool    requireConsent; // if true, patient must pre-authorize
        bool    active;
        uint256 purchases;
    }

    struct Access {
        address buyer;
        uint256 listingId;
        uint256 paidAt;
        string  decryptionKeyHash; // encrypted key delivered off-chain
    }

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Access[]) public listingAccess;
    mapping(address => uint256[]) public providerListings;
    mapping(address => mapping(uint256 => bool)) public patientConsent; // patient => listingId => consent
    uint256 public nextListingId;

    event Listed(uint256 indexed id, address indexed provider, string dataType, uint256 price);
    event Purchased(uint256 indexed id, address indexed buyer, uint256 paid);
    event ConsentGranted(address indexed patient, uint256 indexed listingId);
    event ConsentRevoked(address indexed patient, uint256 indexed listingId);

    modifier onlyOwner() { require(msg.sender == owner, "HDM:owner"); _; }

    constructor() { owner = msg.sender; }

    function list(
        string calldata dataHash,
        string calldata dataType,
        uint256 priceWei,
        bool requireConsent
    ) external returns (uint256 id) {
        id = nextListingId++;
        listings[id] = Listing(msg.sender, dataHash, dataType, priceWei, requireConsent, true, 0);
        providerListings[msg.sender].push(id);
        emit Listed(id, msg.sender, dataType, priceWei);
    }

    function grantConsent(uint256 listingId) external {
        patientConsent[msg.sender][listingId] = true;
        emit ConsentGranted(msg.sender, listingId);
    }

    function revokeConsent(uint256 listingId) external {
        patientConsent[msg.sender][listingId] = false;
        emit ConsentRevoked(msg.sender, listingId);
    }

    function purchase(uint256 listingId, address patient) external payable {
        Listing storage l = listings[listingId];
        require(l.active, "HDM:not_active");
        require(msg.value >= l.priceWei, "HDM:underpaid");
        if (l.requireConsent) {
            require(patientConsent[patient][listingId], "HDM:no_consent");
        }
        uint256 fee     = msg.value * protocolFeeBps / 10000;
        uint256 payout  = msg.value - fee;
        accruedFees    += fee;
        l.purchases++;
        listingAccess[listingId].push(Access(msg.sender, listingId, block.timestamp, ""));
        payable(l.provider).transfer(payout);
        emit Purchased(listingId, msg.sender, msg.value);
        // Refund excess
        if (msg.value > l.priceWei) payable(msg.sender).transfer(msg.value - l.priceWei);
    }

    function delist(uint256 listingId) external {
        require(listings[listingId].provider == msg.sender, "HDM:not_provider");
        listings[listingId].active = false;
    }

    function withdrawFees() external onlyOwner {
        uint256 amt = accruedFees;
        accruedFees = 0;
        payable(owner).transfer(amt);
    }

    function setFee(uint256 bps) external onlyOwner {
        require(bps <= 1000, "HDM:max_10pct");
        protocolFeeBps = bps;
    }

    function getProviderListings(address provider) external view returns (uint256[] memory) {
        return providerListings[provider];
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero_owner");
        owner = newOwner;
    }
}
