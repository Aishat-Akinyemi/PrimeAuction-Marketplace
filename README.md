# PrimeAuction-Marketplace
ERC721 tokens auction marketplace 

**PrimeAuctionMarket** is a marketplace to auction your ERC721 tokens.

- You can auction an nft you own by providing the nft address, the tokenId, the startamount, and the auctionEndDate (between 1-60 days).
- At the end of the duration of the auction, either the highestBidder or the seller can end the auction.
- If anyBid was placed for your nft, ending the auction deposits the nft into the buyer's account, and the price into the seller's account, otherwise no bids means token - transferred back to the seller.
