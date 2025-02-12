// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

abstract contract AIYieldBase is ReentrancyGuard, Ownable, Pausable {
    using SafeMath for uint256;

    // Temel yapılar
    struct YieldStrategy {
        uint256 riskLevel;        // Risk seviyesi (1-5)
        uint256 targetAPY;        // Hedef yıllık getiri
        uint256 rebalanceThreshold; // Yeniden dengeleme eşiği
        bool active;              // Strateji aktif mi?
    }

    // Durum değişkenleri
    mapping(address => uint256) public userBalances;
    mapping(address => YieldStrategy) public userStrategies;
    AggregatorV3Interface public priceFeed;
    uint256 public totalValueLocked;

    // Sabitler
    uint256 public constant MIN_DEPOSIT = 0.1 ether;
    uint256 public constant MAX_RISK_LEVEL = 5;
    uint256 public constant MAX_APY = 1000; // 1000% APY limiti
    uint256 public constant MAX_TOTAL_VALUE_LOCKED = 100000 ether;

    // Olaylar
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event StrategyUpdated(address indexed user, uint256 riskLevel, uint256 targetAPY);

    constructor(address _priceFeed) {
        require(_priceFeed != address(0), "Invalid price feed");
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    // Soyut fonksiyonlar
    function deposit() external payable virtual;
    function withdraw(uint256 _amount) external virtual;
    function optimizeStrategy(address _user) internal virtual;

    // Yardımcı fonksiyonlar
    function getLastPrice() internal view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }
} 