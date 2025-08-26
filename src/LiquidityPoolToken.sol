// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from 'node_modules/openzeppelin/contracts/token/ERC20/ERC20.sol';


contract LiquidityPoolToken is ERC20 {
    address public owner;
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        owner = msg.sender;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the contract owner can call this function");
        _;
    }
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}