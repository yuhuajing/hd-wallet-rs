// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "erc721a/contracts/ERC721A.sol";

contract SC721 is ERC721A {
    address public owner;

    constructor(string memory name, string memory symbol) payable ERC721A(name,symbol) {
        owner = msg.sender;
    }

    function mint(
        address receiver,
        uint256 amount
    ) public {
        _mint(receiver, amount);
    }
}
