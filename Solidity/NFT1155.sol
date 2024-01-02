// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract SC1155 is ERC1155 {
    address public owner;

    constructor() payable ERC1155("") {
        owner = msg.sender;
    }

    function mint(
        address receiver,
        uint256 tokenid,
        uint256 amount
    ) public {
        _mint(receiver, tokenid, amount, bytes(""));
    }
}

