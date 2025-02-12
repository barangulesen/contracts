// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AIYieldBase.sol";

contract AIYieldEmergency is AIYieldBase {
    // Acil durum sabitleri
    uint256 private constant EMERGENCY_COOLDOWN = 6 hours;
    uint256 private constant MAX_EMERGENCY_WITHDRAWAL = 90; // %90

    // Durum değişkenleri
    bool public emergencyMode;
    mapping(address => uint256) private lastEmergencyWithdrawal;

    constructor(address _priceFeed) AIYieldBase(_priceFeed) {}
    
    function emergencyWithdraw() 
        external 
        nonReentrant 
        whenPaused 
    {
        require(emergencyMode, "Not emergency");
        require(
            block.timestamp >= lastEmergencyWithdrawal[msg.sender] + EMERGENCY_COOLDOWN,
            "Cooldown active"
        );

        uint256 balance = userBalances[msg.sender];
        require(balance > 0, "No balance");

        uint256 withdrawAmount = balance.mul(MAX_EMERGENCY_WITHDRAWAL).div(100);
        userBalances[msg.sender] = balance.sub(withdrawAmount);
        totalValueLocked = totalValueLocked.sub(withdrawAmount);

        lastEmergencyWithdrawal[msg.sender] = block.timestamp;
        
        (bool success, ) = msg.sender.call{value: withdrawAmount}("");
        require(success, "Transfer failed");
        
        emit Withdrawn(msg.sender, withdrawAmount);
    }
    
    function setEmergencyMode(bool _enabled) 
        external 
        onlyOwner 
    {
        emergencyMode = _enabled;
        if (_enabled) {
            _pause();
        } else {
            _unpause();
        }
    }
} 