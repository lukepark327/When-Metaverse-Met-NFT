// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

contract remix_vm {
    function blockProgess() public {}

    function getBlockNumber() public view returns(uint256) {
        return block.number;
    }
}
