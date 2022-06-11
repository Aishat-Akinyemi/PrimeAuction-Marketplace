// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

//PrimeAuctionMarket is a marketplace to auction your erc721 tokens.
//you can auction an nft you own by providing the nft address, the tokenId, the startamount, and the auctionEndDate (btwn 1-60 days)
//At the end of the duration of the auction, either the highestBidder or the seller can end the auction
//if anyBid was placed for your nft , ending the auction deposits the nft into the buyer's account, and the price into the seller's account
//otherwise no bids means token transferred back to the seller.

contract PrimeAuctionMarket is Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private auctionId;

    event List(address nftContractAddress,  uint  tokenId);
    event Bid(address nftContractAddress,  uint  tokenId, address indexed sender, uint amount);
    event Withdraw(address nftContractAddress,  uint  tokenId, address indexed bidder, uint amount);
    event End(address nftContractAddress,  uint  tokenId, address winner, uint amount, bool isOwnerEnded, bool isWinnerEnded);
    event Cancel(address nftContractAddress,  uint  tokenId, address owner);

    struct Auction {
        uint  tokenId;
        address  nftContractAddress;
        address  seller;
        uint  endAt;
        bool  ended;
        address  highestBidder;
        uint  highestBid;
        uint startingPrice;
        //maps the amount an account can withdraw to the account
        mapping(address => uint) bids;
    }

    mapping(uint => Auction) public auctions;

    uint numAuctions;

    constructor () {        
    }

    //list token with the token contract address and tokenId. Provide a starting price, and time to end the auction in days. 
    //days between 1-60 days
    function listToken(address _nftAdd, uint _nftId, uint _startingPrice, uint auctionDays) 
                                public payable canAuctionToken(_nftAdd, _nftId, _startingPrice, auctionDays) returns (uint id) {      
        IERC721(_nftAdd).transferFrom(msg.sender, address(this), _nftId);
        uint currentId = auctionId.current();
        auctionId.increment();
        Auction storage auction = auctions[currentId];
        auction.nftContractAddress = _nftAdd;
        auction.tokenId = _nftId;
        auction.seller = msg.sender;
        auction.ended = false;
        auction.startingPrice = _startingPrice;
        auction.endAt = block.timestamp + (auctionDays * 1 days); 
        emit List(_nftAdd, _nftId);

        //check if token has been transfered
        bool contractIsTokenOwner =  IERC721(_nftAdd).ownerOf(_nftId) == address(this) ? true
                                                            : false;
        require(contractIsTokenOwner, "Listing failed as token has not been transferred to contract");  
        return currentId;             
    }

    //bid for token during the duration of the auction. bid must be greater than the highest bid
    // seller cannot bid    
    function bid(uint _auctionId) external payable checkAuctionId(_auctionId) canBid(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        address initialHighestBidder = auction.highestBidder;
        uint initialHighestBid = auction.highestBid;
        //remember bids mapping holds the amount an account can withdraw
        if (auction.highestBidder != address(0)) {
            auction.bids[initialHighestBidder] += initialHighestBid;
        }
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;
        emit Bid(auction.nftContractAddress, auction.tokenId, msg.sender, msg.value);
    }

    //people who took part in the bid without winning can withdraw their money
    function withdrawBids(uint _auctionId) external checkAuctionId(_auctionId) canWithdraw(_auctionId) {
        Auction storage auction = auctions[_auctionId];
        uint bal = auction.bids[msg.sender];
        auction.bids[msg.sender] = 0;
        (bool sent, ) = payable(msg.sender).call{value: bal}("");
        require(sent, "Bid withdrawal failed");
        emit Withdraw(auction.nftContractAddress, auction.tokenId, msg.sender, bal);
    }

   //seller can end the auction and send token to winner, if no bid s/he gets their token back
    function endAuctionAsSeller(uint _auctionId) external checkAuctionId(_auctionId) canEndAuction(_auctionId) returns (bool) {
        (bool success, address nftContractAddress, uint tokenId, address winner, uint amount) = endAuction(_auctionId);
        if (success) {
            emit End(nftContractAddress, tokenId, winner, amount, true, false);
            return true;
        }
        return false;
    }

    //winner can claim the token and end the auction (seller gets the money for sales)
    function claimTokenAsWinner(uint _auctionId) external checkAuctionId(_auctionId) canClaimWinner(_auctionId) returns (bool) {
        (bool success, address nftContractAddress, uint tokenId, address winner, uint amount) = endAuction(_auctionId);
        if (success) {
            emit End(nftContractAddress, tokenId, winner, amount, false, true);
            return true;
        }
        return false;
    }

 
    function endAuction(uint _auctionId) internal checkAuctionId(_auctionId) returns (bool success, address nftContractAddress, uint tokenId, address winner, uint amount){
        Auction storage auction = auctions[_auctionId];
        auction.ended = true;
        if (auction.highestBidder != address(0)) {
            IERC721(auction.nftContractAddress).transferFrom(address(this), auction.highestBidder, auction.tokenId);
            (bool sent, ) = payable(msg.sender).call{value: auction.highestBid}("");
            require(sent, "Could not end auction");
            return (true, auction.nftContractAddress, auction.tokenId,  auction.highestBidder, auction.highestBid);
        } else {
            IERC721(auction.nftContractAddress).transferFrom(address(this), auction.seller, auction.tokenId);
            return (true, auction.nftContractAddress, auction.tokenId, address(0), 0);
        }
    }


    //pure function that returns the constant platform price 500_000 wei
    function getPlatformPrice() internal pure returns (uint) {
        return 500_000;
    }


    modifier canEndAuction(uint _auctionId) {
        Auction storage auction = auctions[_auctionId];
        require(msg.sender == auction.seller, "Only owner can end auction");
        require(block.timestamp >= auction.endAt, "auction duration has not ended");
        require(!auction.ended, "auction already ended");
        _;
    }
    
    modifier canClaimWinner(uint _auctionId){
        Auction storage auction = auctions[_auctionId];
        require(msg.sender == auction.highestBidder, "You are not the Winner");
        require(block.timestamp >= auction.endAt, "auction duration has not ended");
        require(!auction.ended, "auction already ended");        
        _;
    }
   

    modifier canAuctionToken(address _nftAdd, uint _nftId, uint _startingPrice, uint _auctionDays){
        require(msg.value == getPlatformPrice(), "Attach platform fee of 5_00_000 wei");
        require(_nftAdd != address(0), "Enter a valid NFT contract address");
        bool callerIsTokenOwner =  IERC721(_nftAdd).ownerOf(_nftId) == msg.sender ? true : false;
        require(callerIsTokenOwner, "You can only list tokens owned by you");        
        require(_startingPrice > 0, "Starting price must be greater than 0");
        require(_auctionDays > 0 && _auctionDays <60, "auction duration should be between 1 and 60 days");
        _;

    }

    modifier canBid(uint _auctionId){        
        Auction storage auction = auctions[_auctionId];
        require( !auction.ended && (block.timestamp < auction.endAt), "auction has ended");
        require(msg.value > auction.highestBid, "Bid must be greater than the current highest bid");
        require(msg.sender != auction.seller, "owner cannot place a bid");
        require(msg.sender != auction.highestBidder, "you can't outbid yourself");
        _;
    }

    modifier canWithdraw(uint _auctionId){
        Auction storage auction = auctions[_auctionId];
        require(msg.sender != auction.highestBidder, "Highest bidder cannot withdraw");
        require(auction.bids[msg.sender]> 0, "Nothing to withdraw");
        _;
    }

    modifier checkAuctionId(uint _auctionId){
        require(_auctionId >= 0 && _auctionId < numAuctions, "Enter a valid auction id");
        _;
    }


}
