// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Soulbound health identity NFT for patients and providers.
/// Non-transferable by design. ERC-721 metadata compatible for MetaMask/OpenSea.
contract MRXSoulbound {
    string public constant name   = "MyRxWallet Health NFT Rewards";
    string public constant symbol = "MyRxNFT";

    enum Role { NONE, PATIENT, PROVIDER, ADMIN }

    struct Identity {
        uint256 tokenId;
        Role    role;
        string  metadataURI;
        uint256 issuedAt;
        bool    active;
    }

    address public owner;
    uint256 private _nextId = 1;
    mapping(uint256 => address)  public ownerOf;
    mapping(address => uint256)  public tokenOfHolder;
    mapping(uint256 => Identity) public identities;
    mapping(address => bool)     public isIssuer;

    string private _baseURI;

    event Issued(address indexed to, uint256 tokenId, Role role);
    event Revoked(uint256 indexed tokenId);
    event MetadataUpdated(uint256 indexed tokenId, string uri);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    modifier onlyOwner()  { require(msg.sender == owner,  "SB:owner");  _; }
    modifier onlyIssuer() { require(isIssuer[msg.sender], "SB:issuer"); _; }

    constructor(string memory baseURI_) {
        owner = msg.sender;
        isIssuer[msg.sender] = true;
        _baseURI = baseURI_;
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseURI = baseURI_;
    }

    function addIssuer(address issuer) external onlyOwner { isIssuer[issuer] = true; }
    function removeIssuer(address issuer) external onlyOwner { isIssuer[issuer] = false; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "SB:zero_owner");
        owner = newOwner;
    }

    function issue(address to, Role role, string calldata metadataURI)
        external onlyIssuer returns (uint256 tokenId)
    {
        require(tokenOfHolder[to] == 0, "SB:already_issued");
        require(to != address(0), "SB:zero");
        require(role != Role.NONE, "SB:no_role");
        tokenId = _nextId++;
        ownerOf[tokenId]    = to;
        tokenOfHolder[to]   = tokenId;
        identities[tokenId] = Identity(tokenId, role, metadataURI, block.timestamp, true);
        emit Transfer(address(0), to, tokenId);
        emit Issued(to, tokenId, role);
    }

    function revoke(uint256 tokenId) external onlyIssuer {
        require(identities[tokenId].active, "SB:not_active");
        identities[tokenId].active = false;
        address holder = ownerOf[tokenId];
        delete tokenOfHolder[holder];
        emit Revoked(tokenId);
    }

    function updateMetadata(uint256 tokenId, string calldata uri) external onlyIssuer {
        require(identities[tokenId].active, "SB:not_active");
        identities[tokenId].metadataURI = uri;
        emit MetadataUpdated(tokenId, uri);
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(ownerOf[tokenId] != address(0), "SB:no_token");
        string memory base = _baseURI;
        if (bytes(base).length > 0) {
            return string(abi.encodePacked(base, _uint2str(tokenId)));
        }
        return identities[tokenId].metadataURI;
    }

    function totalSupply() external view returns (uint256) { return _nextId - 1; }

    function getIdentity(address holder) external view
        returns (uint256 tokenId, Role role, string memory uri, uint256 issuedAt, bool active)
    {
        tokenId = tokenOfHolder[holder];
        if (tokenId == 0) return (0, Role.NONE, "", 0, false);
        Identity memory id = identities[tokenId];
        return (id.tokenId, id.role, id.metadataURI, id.issuedAt, id.active);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd  // ERC-721
            || interfaceId == 0x5b5e139f  // ERC-721 Metadata
            || interfaceId == 0x01ffc9a7; // ERC-165
    }

    function transferFrom(address, address, uint256) external pure { revert("SB:non_transferable"); }
    function safeTransferFrom(address, address, uint256) external pure { revert("SB:non_transferable"); }
    function safeTransferFrom(address, address, uint256, bytes calldata) external pure { revert("SB:non_transferable"); }

    function _uint2str(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v; uint256 len;
        while (tmp != 0) { len++; tmp /= 10; }
        bytes memory s = new bytes(len);
        while (v != 0) { s[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(s);
    }
}
