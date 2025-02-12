// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AIYieldBase.sol";

contract AIYieldStrategy is AIYieldBase {
    // Strateji sabitleri
    uint256 private constant REBALANCE_COOLDOWN = 1 hours;
    uint256 private constant MIN_STRATEGY_CHANGE_INTERVAL = 12 hours;

    // Durum değişkenleri
    mapping(address => uint256) private lastRebalanceTime;
    mapping(address => uint256) private lastStrategyUpdateTime;

    constructor(address _priceFeed) AIYieldBase(_priceFeed) {}

    function setStrategy(uint256 _riskLevel, uint256 _targetAPY) 
        external 
        whenNotPaused 
    {
        require(_riskLevel > 0 && _riskLevel <= MAX_RISK_LEVEL, "Invalid risk");
        require(_targetAPY > 0 && _targetAPY <= MAX_APY, "Invalid APY");
        require(
            block.timestamp >= lastStrategyUpdateTime[msg.sender] + MIN_STRATEGY_CHANGE_INTERVAL,
            "Too frequent"
        );

        YieldStrategy storage strategy = userStrategies[msg.sender];
        strategy.riskLevel = _riskLevel;
        strategy.targetAPY = _targetAPY;
        strategy.rebalanceThreshold = 5;
        strategy.active = true;

        lastStrategyUpdateTime[msg.sender] = block.timestamp;
        emit StrategyUpdated(msg.sender, _riskLevel, _targetAPY);
    }
    
    function rebalancePortfolio(address _user) internal {
        require(
            block.timestamp >= lastRebalanceTime[_user] + REBALANCE_COOLDOWN,
            "Cooldown active"
        );

        YieldStrategy storage strategy = userStrategies[_user];
        require(strategy.active, "No active strategy");

        // Rebalance işlemleri burada yapılacak
        
        lastRebalanceTime[_user] = block.timestamp;
    }
} 