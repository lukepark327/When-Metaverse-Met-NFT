// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.3/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.3/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.3/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MMN.sol";
import "./governance/vMMN.sol";

/**
 * References
 */
contract Rendezvous is Ownable {
    using SafeERC20 for IERC20;

    MMN internal NFT;
    vMMN internal token;
    
    struct Proposal {
        uint8 state;
        uint248 price;
        uint256 amount;
        uint256 maxAmount;
        uint256 startBlock;
        uint256 endBlock;
    }
    uint256 public proposalCount;
    Proposal[] public proposals;
    
    uint256 internal tokenCount;
    mapping (uint256 => bool) public isUsed;
    
    event ProposalCreated(uint256 indexed proposalId, uint8 state, uint248 price, uint256 amount, uint256 maxAmount, uint256 startBlock, uint256 endBlock);
    event ProposalUpdated(uint256 indexed proposalId, uint8 state, uint248 price, uint256 amount, uint256 maxAmount, uint256 startBlock, uint256 endBlock);
    
    constructor(
        MMN _NftAddr,
        vMMN _tokenAddr
    ) {
        NFT = _NftAddr;
        token = _tokenAddr;
    }
    
    /// @dev Enroll NFT proposal by owner.
    ///
    /// State:
    /// Pending (0)
    ///   |_ Cancle (3)
    ///   |_ Active (1)
    ///      |_ Cancle (3)
    ///      |_ Expired (2)
    ///
    /// @param price_ of required MMN.
    /// @param maxAmount_ of this NFT.
    /// @param startBlock_ of proposal.
    /// @param endBlock_ of proposal.
    /// @return proposal's ID.
    function propose(
        uint248 price_,
        uint256 maxAmount_,
        uint256 startBlock_,
        uint256 endBlock_
    )
        public
        onlyOwner
        returns (uint256)
    {
        require(endBlock_ > block.number, "Rendezvous: Invalid block number.");
        require(endBlock_ > startBlock_, "Rendezvous: Invalid block number.");
        
        uint8 state_ = (startBlock_ <= block.number ? 1 : 0); // Active (1) or Pending (0)
        proposals[proposalCount++] = Proposal({
           state: state_,
           price: price_,
           amount: 0,
           maxAmount: maxAmount_,
           startBlock: startBlock_,
           endBlock: endBlock_
        });
        
        emit ProposalCreated(proposalCount, state_, price_, 0, maxAmount_, startBlock_, endBlock_);
        return proposalCount;
    }
    
    function activate(uint256 proposalId) public onlyOwner {
        Proposal memory p = _update(proposalId, 0);
        require(p.state == 1, "Rendezvous: Fail to activate.");
        
        emit ProposalUpdated(proposalId, p.state, p.price, p.amount, p.maxAmount, p.startBlock, p.endBlock);
    }
    
    function cancle(uint256 proposalId) public onlyOwner {
        Proposal memory p = _update(proposalId, 0);
        require(p.state == 0 || p.state == 1, "Rendezvous: Cannot cancle already cancled or expired proposal.");
        p.state = 3; // Cancle (3)
        proposals[proposalId] = p;
        
        emit ProposalUpdated(proposalId, p.state, p.price, p.amount, p.maxAmount, p.startBlock, p.endBlock);
    }
    
    function _update(uint256 proposalId, uint256 amount) internal returns (Proposal memory){
        Proposal memory p = state(proposalId);
        if (amount != 0) {
            p.amount += amount;
            require(p.amount <= p.maxAmount, "Rendezvous: Cannot exceed max amount.");
        }
        proposals[proposalId] = p;
        return p;
    }
    
    function state(uint256 proposalId) public view returns (Proposal memory){
        Proposal memory p = proposals[proposalId];
        
        uint8 state_;
        if (p.state == 3) {
            state_ = p.state; // Cancle (3)
        }
        else if (p.endBlock <= block.number) {
            state_ = 2; // Expired (2)
        }
        else if (p.startBlock <= block.number) {
            state_ = 1; // Active (1)
        }
        else {
            state_ = p.state; // Pending (0)
        }
        
        return Proposal({
            state: state_,
            price: p.price,
            amount: p.amount,
            maxAmount: p.maxAmount,
            startBlock: p.startBlock,
            endBlock: p.endBlock
        });
    }
    
    /// @dev Claim NFT. Mint from NFT contract.
    function claim(uint256 proposalId, address to) public {
        Proposal memory p = _update(proposalId, 1);
        require(p.state == 1, "Rendezvous: Cannot claim NFT from inactive proposal.");
        
        uint256 blockNumber_ = p.endBlock < block.number ? p.endBlock : block.number;
        uint256 price_ = uint256(p.price);
        require(
            price_ <= token.getPriorVotes(msg.sender, blockNumber_),
            "Rendezvous: Not enough tokens."
        );

        proposals[proposalId] = p;

        NFT.mint(to, tokenCount++);
    }

    /// @dev Use NFT for obtain real-world item, etc.
    function use(uint256 tokenId) public onlyOwner {
        require(!isUsed[tokenId], "Rendezvous: Cannot use twice.");
        isUsed[tokenId] = true;
    }
}
