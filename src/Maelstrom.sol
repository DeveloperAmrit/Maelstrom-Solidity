// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "node_modules/openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "node_modules/openzeppelin/contracts/utils/math/SafeMath.sol";
import {LiquidityPoolToken} from "./LiquidityPoolToken.sol";

contract Maelstrom {
    using SafeMath for uint256;
    mapping(address => uint256) public lastPriceBuy;
    mapping(address => uint256) public lastPriceSell;
    mapping(address => uint256) public lastPriceMid;
    mapping(address => uint256) public lastBuyTimestamp;
    mapping(address => uint256) public lastSellTimestamp;
    mapping(address => uint256) public lastExchangeTimestamp;
    mapping(address => uint256) public averageBuySell; // in USD

    mapping(address => address) public poolToken; // token => LP token of the token/ETH pool
    mapping(address => uint256) public ethBalance; // token => balance of ETH in the token's pool

    function priceBuy(address token) public view returns (uint256){
        if (block.timestamp > lastExchangeTimestamp[token] + 24 hours) {
            uint256 increment = (lastPriceBuy[token] * 20) / 100;
            uint256 price = lastPriceBuy[token] + increment;
            return price;
        }else{
            uint256 currentBuyPrice = lastPriceBuy[token] + ((averageBuySell[token] - lastPriceBuy[token]) * (block.timestamp - lastExchangeTimestamp[token])) / (24 hours);
            uint256 increment = (currentBuyPrice * 20) / 100;
            uint256 price = currentBuyPrice + increment;
            return price;
        }
    }

    function priceSell(address token) public view returns(uint256){
        if (block.timestamp > lastExchangeTimestamp[token] + 24 hours) {
            uint256 decrement = (lastPriceSell[token] * 20) / 100;
            uint256 price = lastPriceBuy[token] - decrement;
            return price;
        }else{
            uint256 currentSellPrice = lastPriceSell[token] + ((averageBuySell[token] - lastPriceSell[token]) * (block.timestamp - lastExchangeTimestamp[token])) / (24 hours);
            uint256 decrement = (currentSellPrice * 20) / 100;
            uint256 price = currentSellPrice - decrement;
            return price;
        }
    }

    function initializePool(
        address token,
        uint256 amount,
        uint256 initialPriceBuy,
        uint256 initialPriceSell
    ) public payable {
        require(poolToken[token] == address(0), "pool already initialized");
        // TODO: create LP token (ERC20) for the pool
        LiquidityPoolToken lpt = new LiquidityPoolToken("LP Token", "LPT");
        poolToken[token] = address(lpt);
        lastPriceBuy[token] = initialPriceBuy;
        lastPriceSell[token] = initialPriceSell;
        lastBuyTimestamp[token] = block.timestamp;
        lastSellTimestamp[token] = block.timestamp;
        lastExchangeTimestamp[token] = block.timestamp;
        averageBuySell[token] = (initialPriceBuy + initialPriceSell) / 2;
        ethBalance[token] = msg.value;
        LiquidityPoolToken(poolToken[token]).mint(msg.sender, amount);
    }

    function reserves(address token) public view returns (uint256, uint256) {
        // (ETH amount in the pool, token amount in the pool)
        return (ethBalance[token], IERC20(token).balanceOf(address(this)));
    }

    function poolUserBalances(
        address token,
        address user
    ) public view returns (uint256, uint256) {
        // (User's ETH amount in the pool, User's token amount in the pool)
        (uint256 rETH, uint256 rToken) = reserves(token);
        IERC20 pt = IERC20(poolToken[token]);
        uint256 ub = pt.balanceOf(user);
        uint256 ts = pt.totalSupply();
        return ((rETH * ub) / ts, (rToken * ub) / ts);
    }

    function tokenPerETHRatio(address token) public view returns (uint256) {
        (uint256 poolETHBalance, uint256 poolTokenBalance) = reserves(
            token
        );
        return poolTokenBalance / poolETHBalance;
    }

    function buy(address token) public payable {
        ethBalance[token] += msg.value;
        uint256 buyPrice = priceBuy(token);
        IERC20(token).transfer(msg.sender, msg.value / priceBuy(token));
        lastPriceBuy[token] = buyPrice;
        lastBuyTimestamp[token] = block.timestamp;
        lastExchangeTimestamp[token] = block.timestamp;
        averageBuySell[token] = (lastPriceBuy[token] + lastPriceSell[token]) / 2;
    }

    function sell(address token, uint256 amount) public {
        // TODO: transfer `amount * priceSell(token)` ETH from this contract to msg.sender
        uint256 sellPrice = priceSell(token);
        ethBalance[token] -= amount * sellPrice;
        IERC20(token).transferFrom(msg.sender,address(this), amount);
        (bool success, ) = msg.sender.call{value: amount * sellPrice}(''); 
        require(success, 'Tranfer failed');
        lastPriceSell[token] = sellPrice;
        lastSellTimestamp[token] = block.timestamp;
        lastExchangeTimestamp[token] = block.timestamp;
        averageBuySell[token] = (lastPriceBuy[token] + lastPriceSell[token]) / 2;
    }

    function deposit(address token) external payable {
        uint256 ethBalanceBefore = ethBalance[token];
        ethBalance[token] += msg.value;
        IERC20(token).transferFrom(
            msg.sender,
            address(this),
            msg.value * tokenPerETHRatio(token)
        );
        LiquidityPoolToken pt = LiquidityPoolToken(poolToken[token]);
        pt.mint(msg.sender, (pt.totalSupply() * msg.value) / ethBalanceBefore);
    }

    function withdraw(address pooledToken, uint256 amount) external {
        // TODO: burn LP tokens and transfer eth and token to msg.sender
        LiquidityPoolToken pt = LiquidityPoolToken(pooledToken);
        require(pt.balanceOf(msg.sender) >= amount, "Not enough LP tokens");
        pt.burn(msg.sender, amount);
        (uint256 rETH, uint256 rToken) = reserves(pooledToken);
        uint256 ts = pt.totalSupply();
        uint256 ethAmount = rETH * amount / ts;
        uint256 tokenAmount = rToken * amount / ts;
        LiquidityPoolToken(pooledToken).transfer(msg.sender, tokenAmount);
        ethBalance[pooledToken] -= (rETH * amount) / ts;
        (bool success, ) = msg.sender.call{value: (ethAmount)}('');
        require(success, "Transfer Failed!");
    }

    function swap(
        address tokenSell,
        address tokenBuy,
        uint256 amountToSell,
        uint256 minimumAmountToBuy
    ) external {
        // TODO: sell tokenSell and then buy TokenBuy with the ETH from the tokenSell you just sold
        uint256 ethReceived = priceSell(tokenSell) * amountToSell;
        uint256 expectedToBought = tokenPerETHRatio(tokenBuy) * ethReceived;
        require(expectedToBought >= minimumAmountToBuy,"Insufficient amount to be recieved");
        sell(tokenSell, amountToSell);
        ethBalance[tokenSell] += ethReceived;
        IERC20(tokenSell).transfer(msg.sender, ethReceived / priceBuy(tokenSell));
    }
}
