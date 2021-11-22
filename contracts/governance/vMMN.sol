// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.3/contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.3/contracts/access/Ownable.sol";

/**
 * References
 */
contract vMMN is ERC20VotesComp, Ownable {
    constructor() ERC20("MMN Votes", "vMMN") ERC20Permit("vMMN") {}
    
    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

    // TODO: capped
}
