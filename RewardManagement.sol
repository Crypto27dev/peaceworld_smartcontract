// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./PeaceNFT.sol";
import "./IPancakeRouter02.sol";

abstract contract ERC20Interface {
    function totalSupply() virtual public view returns (uint);
    function balanceOf(address tokenOwner) virtual public view returns (uint balance);
    function allowance(address tokenOwner, address spender) virtual public view returns (uint remaining);
    function transfer(address to, uint tokens) virtual public returns (bool success);
    function approve(address spender, uint tokens) virtual public returns (bool success);
    function transferFrom(address from, address to, uint tokens) virtual public returns (bool success);
    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}

contract RewardManagement is Ownable{
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    uint256 pauseContract;
    uint256 pauseClaim;
    uint256 startPresale;

    enum NFT_TYPE{
        REGIONAL_NFT,
        WORLD_NFT
    }
    
    struct NodeInfo {
        uint256 createTime;
        uint256 reward;
    }
 
    struct NFTInfo {
        uint256     createTime;
        NFT_TYPE    typeOfNFT;
    }

    struct RewardInfo {
        uint256 currentTime;
        uint256 lastClaimTime;
        uint256[] nodeRewards;
        bool[] enableNode;
        bool[] curRegionalNFTEnable;
        bool[] curWorldNFTEnable;
    }

    struct UserInfo {
        uint256 calcTime;
        uint256 rewards;
        uint256 claimedRewards;
    }

    event Received(address, uint);
    event Fallback(address, uint);
    event PurchasedNode(address buyer, uint256 amount);
    event PurchasedNFT(address addr, uint256 typeOfNFT, uint256 nftCount);

    event DeleteUserNode(address addr);
    event ClaimNode(address addr, uint256 nodeId, uint256 reward);
    event ClaimAllNode(address addr, uint256 reward);
    event WithdrawAll(address addr, uint256 fire, uint256 bnb);
    event SetContractStatus(address addr, uint256 _newPauseContract);
    event SetClaimStatus(uint256 _newClaimStatus);
    event SetNodeMaintenanceFee(address addr, uint256 newThreeMonthFee);
    event SetNFTContract(address addr);
    event ClearUserInfo(address addr);
    event SetNodePrice(address addr, uint256 newNodePrice);
    event SetPeaceValue(address addr, uint256 newPeaceValue);
    event SetClaimFee(address addr, uint256 newClaimFee); 
    event SetPresaleStatus(uint256 _newPresaleContract);
    event InsertWhitelist(address addr, uint256 _newInsertedCount);
    event SetPreNodeCount(address addr, uint256 _newPreNodeCount);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 bnbReceived,
        uint256 tokensIntoLiqudity
    );
  
    IPancakeRouter02        public _pancake02Router;

    address payable constant _treasuryWallet        = payable(0xD4648f2ac458c4A19D260cDdF3aA3fA112d320C0);
    address payable constant _maintenanceWallet     = payable(0x0E96118D4A809271abCC5543A68EB66062Ab14FB);
    address public  constant _burnAddress           = 0x000000000000000000000000000000000000dEaD;

    uint256 constant _rewardRateForTreasury         = 3;
    uint256 constant _rewardRateForStake            = 7;
    uint256 constant _rewardRateForLiquidity        = 0;
    uint256 constant REWARD_NODE_PER_SECOND         = 20000 * 10**18 / (uint256)(3600 * 24);  // 20000 PET
    uint256 constant REWARD_REGIONAL_NFT_PER_SECOND   = 2500 * 10**18 / (uint256)(3600 * 24);   // 2500 PET
    uint256 constant REWARD_WORLD_NFT_PER_SECOND    = 4000 * 10**18 / (uint256)(3600 * 24);   // 4000 PET
    uint256 NODE_PRICE                              = 1000000 * 10**18;                          // 1000000 PET
    uint256 constant NODECOUNT_PER_REGIONALNFT        = 10;                                   // 10 NODE
    uint256 constant NODECOUNT_PER_WORLDNFT         = 100;                                  // 100 NODE
    uint256 constant MAX_NODE_PER_USER              = 100;                                  // 100 NODE
    uint256 constant MAX_PRENODE_PER_USER           = 5;                                  // 100 NODE
    uint256 constant ONE_DAY_TIME                   = 43200;                                // seconds for one day
    uint256 EXTRA_NODE_PRICE                        = 5 * 10**16;                          // 0.05 BNB
    uint256 CLAIM_FEE                               = 5 * 10**15;                           // 0.005 BNB
    uint256 DEFAULT_NFT_VALUE                              = 25 * 10**15;                           // 0.025 BNB 
    uint256 MAX_PRENODE_COUNT                       = 1000;
    uint256 constant MAX_REGIONAL_NFT_COUNT           = 10;                                   // maximum regional nft count
    uint256 constant MAX_REWARD_PER_CLAIM           = 10000000 * 10**18;                         // maximum fire count per claim
    ERC20Interface public _tokenContract;
    PeaceNFT public _nftContract;
    
    IERC20 private _busdToken;

    uint256 public totalNodeCount;
    uint256 public presaledCount;
    mapping(address => UserInfo) private _rewardsOfUser;
    mapping(address => uint256) private _lastClaimOfUser;
    mapping(address => NodeInfo[]) private _nodesOfUser;
    mapping(address => NFTInfo[]) private _nftOfUser;
    mapping(address => bool) private _nodeWhitelist;
    
    constructor(address tokenContract, address nftContract) { 
        _tokenContract = ERC20Interface(tokenContract);
        _nftContract = PeaceNFT(nftContract);
        _pancake02Router = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        _busdToken = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
        pauseContract = 1;
        pauseClaim = 0;
        startPresale = 0;
        totalNodeCount = 0;
        presaledCount = 0;
    }
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    fallback() external payable { 
        emit Fallback(msg.sender, msg.value);
    }

    function setNFTContract(address addr) external onlyOwner {
        _nftContract = PeaceNFT(addr);
        emit SetNFTContract(addr);
    }

    function clearUserInfo(address addr) external onlyOwner {
        totalNodeCount -= _nodesOfUser[addr].length;
        delete _nodesOfUser[addr];
        delete _nftOfUser[addr];
        emit ClearUserInfo(addr);
    }
    
    function insertWhitelist(address[] memory addrInfos) external onlyOwner{
        uint256 i;
        uint256 insertedCount = 0;
        for(i=0; i<addrInfos.length; i++) {
            if (_nodeWhitelist[addrInfos[i]] == false) {
                _nodeWhitelist[addrInfos[i]] = true;
                insertedCount++;
            }
        }
        emit InsertWhitelist(msg.sender, insertedCount);
    }

    function isWhitelist(address addr) external view returns(bool){
        return _nodeWhitelist[addr];
    }

    function withdrawAll() external onlyOwner{
        uint256 balance = _tokenContract.balanceOf(address(this));
        if(balance > 0) {
            _tokenContract.transfer(msg.sender, balance);
        }
        
        address payable mine = payable(msg.sender);
        if(address(this).balance > 0) {
            mine.transfer(address(this).balance);
        }
        emit WithdrawAll(msg.sender, balance, address(this).balance);
    }

    function setNodePrice(uint256 _newNodePrice) external onlyOwner () {
        NODE_PRICE = _newNodePrice;
        emit SetNodePrice(msg.sender, _newNodePrice);
    }

    function getNodePrice() external view returns (uint256) {
        return NODE_PRICE;
    }

    function setPreNodeCount(uint256 _newPreNodeCount) external onlyOwner () {
        MAX_PRENODE_COUNT = _newPreNodeCount;
        emit SetPreNodeCount(msg.sender, _newPreNodeCount);
    }

    function getPreNodeCount() external view returns (uint256) {
        return MAX_PRENODE_COUNT;
    }

    function setPeaceValue(uint256 _newPeaceValue) external onlyOwner(){
        DEFAULT_NFT_VALUE = _newPeaceValue;
        emit SetPeaceValue(msg.sender, _newPeaceValue);
    }

    function getPeaceValue() external  view returns(uint256){
        return DEFAULT_NFT_VALUE;
    }

    function getRegionalNFTPrice() external view returns (uint256) {
        return DEFAULT_NFT_VALUE;
    }

    function getWorldNFTPrice() external view returns (uint256) {
        return DEFAULT_NFT_VALUE * 10;
    }

    function setClaimFee(uint256 _newClaimFee) external onlyOwner () {
        CLAIM_FEE = _newClaimFee;
        emit SetClaimFee(msg.sender, _newClaimFee); 
    }

    function getClaimFee() external view returns (uint256) {
        return CLAIM_FEE;        
    }

    function getContractStatus() external view returns (uint256) {
        return pauseContract;
    }

    function setContractStatus(uint256 _newPauseContract) external onlyOwner {
        pauseContract = _newPauseContract;
        emit SetContractStatus(msg.sender, _newPauseContract);
    }

    function getClaimStatus() external view returns (uint256) {
        return pauseClaim;
    }

    function setClaimStatus(uint256 _newClaimContract) external onlyOwner {
        pauseClaim = _newClaimContract;
        emit SetClaimStatus(_newClaimContract);
    }

    function getPresaleStatus() external view returns (uint256) {
        return startPresale;
    }

    function setPresaleStatus(uint256 _newPresaleContract) external onlyOwner {
        startPresale = _newPresaleContract;
        emit SetPresaleStatus(_newPresaleContract);
    }

    function getNodeMaintenanceFee() external view returns (uint256) {
        return EXTRA_NODE_PRICE;
    }

    function setNodeMaintenanceFee(uint256 _newThreeMonthFee) external onlyOwner {
        EXTRA_NODE_PRICE = _newThreeMonthFee;
        emit SetNodeMaintenanceFee(msg.sender, _newThreeMonthFee);
    }
    
    function getTotalNodeCount() external view returns(uint256) {
        return totalNodeCount;
    }
    
    function getNodeList(address addr) view external returns(NodeInfo[] memory result){
        result = _nodesOfUser[addr];
        return result;
    }

    function getNFTList(address addr) view external returns(NFTInfo[] memory result){
        result = _nftOfUser[addr];
        return result;
    }

    function getBNBForBUSD(uint busdAmount) public view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = address(_busdToken);
        path[1] = _pancake02Router.WETH();
        return _pancake02Router.getAmountsOut(busdAmount * 10 ** 18, path)[1];
    }

    function getBNBForPeace(uint peaceAmount) public view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = address(_tokenContract);
        path[1] = _pancake02Router.WETH();
        return _pancake02Router.getAmountsOut(peaceAmount * 10 ** 18, path)[1];
    }

    function getTreasuryAmount() external view returns(uint){
        return address(_treasuryWallet).balance;
    }

    function getTreasuryRate() external view returns(uint){
        uint256 total_balance = address(_treasuryWallet).balance;
        return total_balance.div(_tokenContract.balanceOf(address(this)));
    }
    
    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);
        uint256 initialBalance = address(this).balance;

        swapTokensForBNB(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForBNB(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(_tokenContract);
        path[1] = _pancake02Router.WETH();

        _tokenContract.approve(address(_pancake02Router), tokenAmount);

        _pancake02Router.swapExactTokensForTokens(
            tokenAmount,
            0,
            path,   
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        // approve token transfer to cover all possible scenarios
        _tokenContract.approve(address(_pancake02Router), tokenAmount);

        // add the liquidity
        _pancake02Router.addLiquidityETH{value: bnbAmount}(
            address(_tokenContract),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(_burnAddress),
            block.timestamp
        );
    }

    function buyNode(uint256 numberOfNodes) external payable{
        require(pauseContract == 0, "Contract Paused");
        uint256 numberOfTokens = numberOfNodes * NODE_PRICE;
        uint256 prevNumberOfNode = _nodesOfUser[msg.sender].length;
        
        require(_tokenContract.balanceOf(msg.sender) >= numberOfTokens, "user doesn't have enough token balance");
        require(prevNumberOfNode + numberOfNodes <= MAX_NODE_PER_USER, "can't buy more than 100 nodes");
        
        // send 8 Peace to RewardPool: 7 Peace for rewardPool, 1 Peace for liquidity
        uint256 numberOfStaking;
        numberOfStaking = numberOfTokens * _rewardRateForStake/10;
        if (_rewardRateForLiquidity > 0) {
            numberOfStaking += numberOfTokens * _rewardRateForLiquidity/10;
        }

        _tokenContract.transferFrom(msg.sender, address(this), numberOfStaking);        

        // send 2 Peace _treasuryWallet
        _tokenContract.transferFrom(msg.sender, _treasuryWallet, numberOfTokens * _rewardRateForTreasury / 10);

        // send 1 Peace to liquidity        
        if (_rewardRateForLiquidity > 0) {
            swapAndLiquify(numberOfTokens * _rewardRateForLiquidity / 10);
        }

        // make node for buyer
        for(uint256 i=0; i<numberOfNodes; i++) {
            _nodesOfUser[msg.sender].push(
                NodeInfo({ createTime: block.timestamp, reward:0})
            );
        }

        // pay nodes fee
        require(msg.value == EXTRA_NODE_PRICE * numberOfNodes, "no enough balance");
        _maintenanceWallet.transfer(msg.value);

        totalNodeCount += numberOfNodes;
        
        // emit purchased node event
        emit PurchasedNode(msg.sender, numberOfNodes);
    }

    function preBuyNode(uint256 numberOfNodes) external payable{
        require(startPresale == 1, "Presale is not started");
        require(presaledCount <= MAX_PRENODE_COUNT, "users can buy nodes upto 1000 nodes");
        require(_nodeWhitelist[msg.sender] == true, "only user in whitelist can buy nodes");
        uint256 numberOfTokens = numberOfNodes * NODE_PRICE / 2;
        uint256 prevNumberOfNode = _nodesOfUser[msg.sender].length;
        
        require(_tokenContract.balanceOf(msg.sender) >= numberOfTokens, "user doesn't have enough token balance");
        require(prevNumberOfNode + numberOfNodes <= MAX_PRENODE_PER_USER, "can't buy more than 100 nodes");
        
        // send 8 Peace to RewardPool: 7 Peace for rewardPool, 1 Peace for liquidity
        uint256 numberOfStaking;
        numberOfStaking = numberOfTokens * _rewardRateForStake/10;
        if (_rewardRateForLiquidity > 0) {
            numberOfStaking += numberOfTokens * _rewardRateForLiquidity/10;
        }

        _tokenContract.transferFrom(msg.sender, address(this), numberOfStaking);        

        // send 2 Peace _treasuryWallet
        _tokenContract.transferFrom(msg.sender, _treasuryWallet, numberOfTokens * _rewardRateForTreasury / 10);

        // send 1 Peace to liquidity        
        if (_rewardRateForLiquidity > 0) {
            swapAndLiquify(numberOfTokens * _rewardRateForLiquidity / 10);
        }

        // make node for buyer
        for(uint256 i=0; i<numberOfNodes; i++) {
            _nodesOfUser[msg.sender].push(
                NodeInfo({ createTime: block.timestamp, reward:0})
            );
        }

        // pay nodes fee
        require(msg.value == EXTRA_NODE_PRICE * numberOfNodes, "no enough balance");
        _maintenanceWallet.transfer(msg.value);

        totalNodeCount += numberOfNodes;
        presaledCount += numberOfNodes;
        
        // emit purchased node event
        emit PurchasedNode(msg.sender, numberOfNodes);
    }

    function buyNFT(NFT_TYPE typeOfNFT, uint nftCount) external payable{
        require(pauseContract == 0, "Contract Paused");

        address addr = msg.sender;
        uint avNodeCount = _nodesOfUser[addr].length;
        uint prevNFTCount = _nftOfUser[addr].length;
        uint prevRegionalNFTCount = prevNFTCount == MAX_REGIONAL_NFT_COUNT+1 ? MAX_REGIONAL_NFT_COUNT : prevNFTCount;
        uint prevWorldNFTCount = prevNFTCount == MAX_REGIONAL_NFT_COUNT+1 ? 1 : 0;
        uint remainNodeCount = avNodeCount - prevRegionalNFTCount * NODECOUNT_PER_REGIONALNFT;
        uint256 nftPrice;
        if(typeOfNFT == NFT_TYPE.WORLD_NFT) {
            require(prevWorldNFTCount == 0, "have already world nft");
            require(nftCount == 1, "buy only 1 world nft");
            require(prevRegionalNFTCount == MAX_REGIONAL_NFT_COUNT, "no need world nft for now");
            nftPrice = 10 * DEFAULT_NFT_VALUE;
        } else {
            require(avNodeCount >= prevRegionalNFTCount * NODECOUNT_PER_REGIONALNFT, "no need so many regional");
            require(remainNodeCount / NODECOUNT_PER_REGIONALNFT >= nftCount, "no need so many regional nft");
            require(prevRegionalNFTCount + nftCount <=MAX_REGIONAL_NFT_COUNT, "no need more than 10 regional nft");
            nftPrice = DEFAULT_NFT_VALUE;
        }
        // payment with bnb
        require(msg.value == nftPrice * nftCount, "no enough BNB");
        _maintenanceWallet.transfer(msg.value);     

        for(uint i=0; i<nftCount; i++) {
            _nftContract.mintNFT(msg.sender, uint256(typeOfNFT));
            _nftOfUser[addr].push(NFTInfo({createTime: block.timestamp, typeOfNFT : typeOfNFT}));
        }
        
        emit PurchasedNFT(msg.sender, uint256(typeOfNFT), nftCount);
    }

    function claimByNode(uint256 nodeId) external payable{
        require(pauseContract == 0, "Contract Paused");
        require(pauseClaim == 0, "Claim Paused");
        require(_nodesOfUser[msg.sender].length > nodeId, "invalid Node ID");
        require(msg.value == CLAIM_FEE, "no enough balance");
        require(block.timestamp > _lastClaimOfUser[msg.sender] + ONE_DAY_TIME, "should claim once within 1 day");

        // add rewards and initialize timestamp for all enabled nodes     
        uint256 nodeReward = getRewardAmountByNode(msg.sender, nodeId);
        _nodesOfUser[msg.sender][nodeId].createTime = block.timestamp;
        
        // send PeaceToken rewards of nodeId to msg.sender
        require(nodeReward > 0, "There is no rewards.");
        require(_tokenContract.balanceOf(address(this)) > nodeReward, "no enough balance on peace");

        _nodesOfUser[msg.sender][nodeId].reward = 0;
        if(nodeReward > MAX_REWARD_PER_CLAIM) {
            _nodesOfUser[msg.sender][nodeId].reward = nodeReward - MAX_REWARD_PER_CLAIM;
            nodeReward = MAX_REWARD_PER_CLAIM;
        }
        _rewardsOfUser[msg.sender].claimedRewards.add(nodeReward);
        _tokenContract.transfer(msg.sender, nodeReward);
        
        // set last claim time
        _lastClaimOfUser[msg.sender] = block.timestamp;
        
        // fee payment 5$ to do
        _maintenanceWallet.transfer(msg.value);
        emit ClaimNode(msg.sender, nodeId, nodeReward);
    }

    function claimAll() external payable{
        require(pauseContract == 0, "Contract Paused");
        require(pauseClaim == 0, "Claim Paused");
        require(block.timestamp > _lastClaimOfUser[msg.sender] + ONE_DAY_TIME, "should claim once within 1 day");

        uint256 nodeCount = _nodesOfUser[msg.sender].length;
        NFTInfo[] storage nfts = _nftOfUser[msg.sender];
        //calculate nft count
        uint256 regionalNftCount;
        uint256 worldNftCount;
        if( nfts.length <= MAX_REGIONAL_NFT_COUNT ) {
            regionalNftCount = nfts.length * NODECOUNT_PER_REGIONALNFT;
            worldNftCount = 0;
        } else {
            regionalNftCount = MAX_REGIONAL_NFT_COUNT * NODECOUNT_PER_REGIONALNFT;
            worldNftCount =  NODECOUNT_PER_WORLDNFT;
        }
                
        uint256 rewards = 0;
        uint256 oneReward;
        uint256 nEnableCount = 0;
        uint256 duringTime;
        for(uint i=0; i<nodeCount; i++) {
            oneReward = _nodesOfUser[msg.sender][i].reward;
            oneReward += (block.timestamp - _nodesOfUser[msg.sender][i].createTime) * REWARD_NODE_PER_SECOND;
            if(nEnableCount < regionalNftCount) {
                duringTime = block.timestamp - Math.max(_nodesOfUser[msg.sender][i].createTime, nfts[nEnableCount / NODECOUNT_PER_REGIONALNFT].createTime);
                oneReward += duringTime * REWARD_REGIONAL_NFT_PER_SECOND;
            }
            if(nEnableCount < worldNftCount) {
                duringTime = block.timestamp - Math.max(_nodesOfUser[msg.sender][i].createTime, nfts[nEnableCount / NODECOUNT_PER_WORLDNFT].createTime);
                oneReward += duringTime * REWARD_WORLD_NFT_PER_SECOND;
            }
            
            _nodesOfUser[msg.sender][i].createTime = block.timestamp;
            _nodesOfUser[msg.sender][i].reward = 0;
            nEnableCount++;
            if(rewards + oneReward > MAX_REWARD_PER_CLAIM) {
                _nodesOfUser[msg.sender][i].reward = rewards + oneReward - MAX_REWARD_PER_CLAIM;
                rewards = MAX_REWARD_PER_CLAIM;
                break;
            }
            rewards += oneReward;
        }

        // fee payment 5$ to do
        require(msg.value >= CLAIM_FEE * nodeCount, "no enough balance for claim fee");
        _maintenanceWallet.transfer(msg.value);

        // send PeaceToken rewards to msg.sender
        require(rewards > 0, "There is no rewards.");
        require(_tokenContract.balanceOf(address(this)) > rewards, "no enough balance on peace");
        _tokenContract.transfer(msg.sender, rewards);

        // set last claim time
        _lastClaimOfUser[msg.sender] = block.timestamp;

        // set rewards inforation of User
         _rewardsOfUser[msg.sender].rewards = 0;
         _rewardsOfUser[msg.sender].claimedRewards = 0;
          _rewardsOfUser[msg.sender].calcTime = block.timestamp;
        emit ClaimAllNode(msg.sender, rewards);
    }

    function getRewardAmountByNode(address addr, uint256 nodeId) view private returns(uint256){

        uint256 nftLength = _nftOfUser[addr].length;
        uint256 nodeCreatTime = _nodesOfUser[addr][nodeId].createTime;
        uint256 nodeLength = _nodesOfUser[addr].length;

        uint256 rewardAmount;
        uint256 duringTime;

        //calculate nft count
        uint256 regionalNftCount = nftLength <= MAX_REGIONAL_NFT_COUNT ? nftLength : MAX_REGIONAL_NFT_COUNT;
        uint256 worldNftCount = nftLength <= MAX_REGIONAL_NFT_COUNT ? 0 : 1;

        //node count for nft applying
        uint256 enableRegionalNftCount = Math.min(regionalNftCount, nodeLength / NODECOUNT_PER_REGIONALNFT);
        uint256 enableWorldNftCount = Math.min(worldNftCount, nodeLength / NODECOUNT_PER_WORLDNFT);

        duringTime = block.timestamp - nodeCreatTime;
        rewardAmount = _nodesOfUser[addr][nodeId].reward + duringTime * REWARD_NODE_PER_SECOND;

        //calculate regional nft rewards per nodes
        if(nodeId < enableRegionalNftCount * NODECOUNT_PER_REGIONALNFT) {
            duringTime = block.timestamp - Math.max(nodeCreatTime, _nftOfUser[addr][nodeId / NODECOUNT_PER_REGIONALNFT].createTime);
            rewardAmount += duringTime * REWARD_REGIONAL_NFT_PER_SECOND;
        }
        //calculate world nft rewards per nodes
        if(nodeId < enableWorldNftCount * NODECOUNT_PER_WORLDNFT) {
            duringTime = block.timestamp - Math.max(nodeCreatTime, _nftOfUser[addr][nodeId / NODECOUNT_PER_WORLDNFT].createTime);
            rewardAmount += duringTime * REWARD_WORLD_NFT_PER_SECOND;
        }
        return rewardAmount;
    }

    function getRewardAmount(address addr) view external returns(RewardInfo memory){
        NFTInfo[] memory nfts = _nftOfUser[addr];
        NodeInfo[] memory nodes = _nodesOfUser[addr];

        RewardInfo memory rwInfo;
        rwInfo.currentTime = block.timestamp;
        rwInfo.lastClaimTime = _lastClaimOfUser[addr];
        rwInfo.nodeRewards = new uint256[](nodes.length);
        rwInfo.enableNode = new bool[](nodes.length);
        rwInfo.curRegionalNFTEnable = new bool[](nodes.length);
        rwInfo.curWorldNFTEnable = new bool[](nodes.length);
        uint256 duringTime;

        //initialize node reward
        uint256 enableNodeCount = 0;
        uint256 i;
        for(i=0; i<nodes.length; i++) {
            rwInfo.curRegionalNFTEnable[i] = false;
            rwInfo.curWorldNFTEnable[i] = false;
            rwInfo.nodeRewards[i] = nodes[i].reward;
            rwInfo.enableNode[i] = true;
            enableNodeCount ++;
        }

        //calculate nft count
        uint256 regionalNftCount;
        uint256 worldNftCount;
        regionalNftCount = nfts.length <= MAX_REGIONAL_NFT_COUNT ? nfts.length : MAX_REGIONAL_NFT_COUNT;
        worldNftCount = nfts.length <= MAX_REGIONAL_NFT_COUNT ? 0 : 1;

        //node count for nft applying
        uint256 enableRegionalNftCount = Math.min(regionalNftCount, enableNodeCount / NODECOUNT_PER_REGIONALNFT);
        uint256 enableWorldNftCount = Math.min(worldNftCount, enableNodeCount / NODECOUNT_PER_WORLDNFT);

        uint256 applyRegionalNFT = 0;
        uint256 applyWorldNFT = 0;
        for(i=0; i<nodes.length; i++) {
            if( rwInfo.enableNode[i] == true ) {
                duringTime = block.timestamp - nodes[i].createTime;
                rwInfo.nodeRewards[i] += duringTime * REWARD_NODE_PER_SECOND;

                //calculate regional nft rewards per nodes
                if(applyRegionalNFT < enableRegionalNftCount * NODECOUNT_PER_REGIONALNFT) {
                    duringTime = block.timestamp - Math.max(nodes[i].createTime, nfts[applyRegionalNFT / NODECOUNT_PER_REGIONALNFT].createTime);
                    rwInfo.nodeRewards[i] += duringTime * REWARD_REGIONAL_NFT_PER_SECOND;
                    rwInfo.curRegionalNFTEnable[i] = true;
                    applyRegionalNFT++;
                }
                //calculate world nft rewards per nodes
                if(applyWorldNFT < enableWorldNftCount * NODECOUNT_PER_WORLDNFT) {
                    duringTime = block.timestamp - Math.max(nodes[i].createTime, nfts[applyWorldNFT / NODECOUNT_PER_WORLDNFT].createTime);
                    rwInfo.nodeRewards[i] += duringTime * REWARD_WORLD_NFT_PER_SECOND;
                    rwInfo.curWorldNFTEnable[i] = true;
                    applyWorldNFT++;
                }
            }
        }
        return rwInfo;
    }
}