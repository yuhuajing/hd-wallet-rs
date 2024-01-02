// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SC20 is ERC20 {
    address public owner;

    constructor(string memory name, string memory symbol) payable ERC20(name,symbol) {
        owner = msg.sender;
    }

    function mint(
        address receiver,
        uint256 amount
    ) public {
        _mint(receiver, amount);
    }
}

