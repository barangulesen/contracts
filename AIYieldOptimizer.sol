// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AIYieldBase.sol";
import "./AIYieldStrategy.sol";
import "./AIYieldEmergency.sol";

contract AIYieldOptimizer is AIYieldBase, AIYieldStrategy, AIYieldEmergency {
    using SafeMath for uint256;

    constructor(address _priceFeed) 
        AIYieldBase(_priceFeed)
        AIYieldStrategy(_priceFeed)
        AIYieldEmergency(_priceFeed) 
    {}

    function deposit() 
        external 
        payable 
        override 
        nonReentrant 
        whenNotPaused 
    {
        require(msg.value >= MIN_DEPOSIT, "Below minimum");
        require(
            totalValueLocked.add(msg.value) <= MAX_TOTAL_VALUE_LOCKED,
            "TVL limit"
        );

        userBalances[msg.sender] = userBalances[msg.sender].add(msg.value);
        totalValueLocked = totalValueLocked.add(msg.value);

        emit Deposited(msg.sender, msg.value);
        optimizeStrategy(msg.sender);
    }

    function withdraw(uint256 _amount) 
        external 
        override 
        nonReentrant 
        whenNotPaused 
    {
        require(_amount > 0, "Zero amount");
        require(userBalances[msg.sender] >= _amount, "Insufficient");

        userBalances[msg.sender] = userBalances[msg.sender].sub(_amount);
        totalValueLocked = totalValueLocked.sub(_amount);

        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, _amount);
    }

    function optimizeStrategy(address _user) 
        internal 
        override 
    {
        YieldStrategy storage strategy = userStrategies[_user];
        if (!strategy.active) return;

        uint256 currentPrice = getLastPrice();
        if (_shouldRebalance(_user, currentPrice)) {
            rebalancePortfolio(_user);
        }
    }

    function _shouldRebalance(address _user, uint256 _currentPrice) 
        private 
        view 
        returns (bool) 
    {
        YieldStrategy storage strategy = userStrategies[_user];
        return strategy.rebalanceThreshold > 0;
    }

    // Fallback ve receive
    receive() external payable {
        revert("Use deposit()");
    }

    fallback() external payable {
        revert("Function not found");
    }
} 