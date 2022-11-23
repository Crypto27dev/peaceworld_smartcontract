// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PeaceNFT is ERC721, Ownable {
    address private TreasuryWallet;
    address private RewardWallet;
    address private MaintenanceWallet;

    enum NFT_TYPE{ 
        REGIONAL_NFT, 
        WORLD_NFT
    }
   
    event SetRegionalNFTPrice(address addr, uint256 newNFTPrice);
    event SetWorldNFTPrice(address addr, uint256 newNFTPrice);
    event SetBaseURI(address addr, string newUri);
    event SetRegionNFTURI(address addr, string newUri);
    event SetWorldNFTURI(address addr, string newUri);
    event SetRewardWalletAddress(address addr, address rewardWallet);

    using Strings for uint256;

    address constant _multisignWallet               	= 0x697A32dB1BDEF9152F445b06d6A9Fd6E90c02E3e;
    // address constant _multisignWallet               	= 0x13Bf16A02cF15Cb9059AC93c06bAA58cdB9B2a59;

    uint256 private constant MAX_REGIONAL_NFT_SUPPLY          = 100000;
    uint256 private constant MAX_REGIONAL_NFT_SUPPLY_PER_USER = 10;
    uint256 private REGIONAL_NFT_PRICE                        = 10;     //PEACE token

    uint256 private constant MAX_WORLD_NFT_SUPPLY           = 10000;
    uint256 private constant MAX_WORLD_NFT_SUPPLY_PER_USER  = 1;
    uint256 private WORLD_NFT_PRICE                         = 100;      //PEACE token

    using Counters for Counters.Counter;
    Counters.Counter private _regionalTokenCounter;
    Counters.Counter private _worldTokenCounter;
    
    string private _baseURIExtended;

    string private regionalNFTURI;
    string private worldNFTURI;

    /**
    * @dev Throws if called by any account other than the multi-signer.
    */
    // modifier onlyMultiSignWallet() {
    //     require(owner() == _msgSender(), "Multi-signer: caller is not the multi-signer");
    //     _;
    // }
    
    constructor() ERC721("PEACE NFT","FNFT") {
        _baseURIExtended = "https://ipfs.infura.io/";
    }

    function setRewardWalletAddress(address _newRewardWallet) external onlyOwner{
        RewardWallet = _newRewardWallet;
        emit SetRewardWalletAddress(msg.sender, _newRewardWallet);
    }

    //Set, Get Price Func

    function setRegionalNFTPrice(uint256 _newNFTValue) external onlyOwner{
        REGIONAL_NFT_PRICE = _newNFTValue;
        emit SetRegionalNFTPrice(msg.sender, _newNFTValue);
    }

    function getRegionalNFTPrice() external view returns(uint256){
        return REGIONAL_NFT_PRICE;
    }

    function setWorldNFTPrice(uint256 _newNFTValue) external onlyOwner{
        WORLD_NFT_PRICE = _newNFTValue;
        emit SetWorldNFTPrice(msg.sender, _newNFTValue);
    }

    function getWorldNFTPrice() external view returns(uint256){
        return WORLD_NFT_PRICE;
    }

    function getRegionalNFTURI() external view returns(string memory){
        return regionalNFTURI;
    }

    function setRegionalNFTURI(string memory _regionalNFTURI) external onlyOwner{
        regionalNFTURI = _regionalNFTURI;
        emit SetRegionNFTURI(msg.sender, _regionalNFTURI);
    }

    function getWorldNFTURI() external view returns(string memory){
        return worldNFTURI;
    }

    function setWorldNFTURI(string memory _worldNFTURI) external onlyOwner{
        worldNFTURI = _worldNFTURI;
        emit SetWorldNFTURI(msg.sender, _worldNFTURI);
    }

   /**
    * @dev Mint NFT by customer
    */
    function mintNFT(address sender, uint256 _nftType) external{

        require( msg.sender == RewardWallet, "you can't mint from other account");

        if( _nftType == uint256(NFT_TYPE.REGIONAL_NFT) )
        {
            _mintRegionalNFT(sender);
        }
        else if( _nftType == uint256(NFT_TYPE.WORLD_NFT) )
        {
            _mintWorldNFT(sender);
        }
    }

   /**
    * @dev Mint regionalNFT For Free
    */
    function _mintRegionalNFT(address sender) internal returns(uint256){
        // Test _regionalTokenCounter
        require(_regionalTokenCounter.current() < MAX_REGIONAL_NFT_SUPPLY, "Total Regional NFT Minting has already ended");
        require(balanceOf(sender) < MAX_REGIONAL_NFT_SUPPLY_PER_USER, "User Regional NFT Minting has already ended");

        // Incrementing ID to create new token        
        uint256 newRegionalNFTID = _regionalTokenCounter.current();
        _regionalTokenCounter.increment();

        _safeMint(sender, newRegionalNFTID);    
        return newRegionalNFTID;
    }

    /**
    * @dev Mint worldNFT
    */
    function _mintWorldNFT(address sender) internal returns(uint256){
        // Test _worldTokenCounter
        require(_worldTokenCounter.current() < MAX_WORLD_NFT_SUPPLY, "Total World NFT Minting has already ended");
        require(balanceOf(sender) == MAX_REGIONAL_NFT_SUPPLY_PER_USER, "User Regional NFT Minting hasn't finished");
        require(balanceOf(sender) < MAX_REGIONAL_NFT_SUPPLY_PER_USER + MAX_WORLD_NFT_SUPPLY_PER_USER, "User World NFT Minting has already ended");

        // Incrementing ID to create new token        
        uint256 newWorldNFTID = _worldTokenCounter.current() + MAX_REGIONAL_NFT_SUPPLY;
        _worldTokenCounter.increment();

        _safeMint(sender, newWorldNFTID);   
        return newWorldNFTID;     
    }

    /**
     * @dev Return the base URI
     */
     function _baseURI() internal override view returns (string memory) {
        return _baseURIExtended;
    }

    /**
     * @dev Set the base URI
     */
    function setBaseURI(string memory baseURI_) external onlyOwner() {
        _baseURIExtended = baseURI_;
        emit SetBaseURI(msg.sender, baseURI_);
    }
}