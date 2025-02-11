// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract AIYieldOptimizer is ReentrancyGuard, Ownable(msg.sender), Pausable {
    // --- Modifier Tanımlamaları ---
    modifier notBlacklisted() {
        require(!blacklistedUsers[msg.sender], "User is blacklisted");
        _;
    }

    modifier canRebalance() {
        require(
            block.timestamp >= lastRebalanceTime[msg.sender] + REBALANCE_COOLDOWN,
            "Rebalance cooldown active"
        );
        _;
    }

    // AI Model ve Oracle yapıları
    struct AIModel {
        bytes32 modelHash;        // AI model hash'i
        uint256 lastUpdate;       // Son güncelleme zamanı
        uint256 confidenceScore;  // Güven skoru (0-100)
        address validator;        // Model doğrulayıcı
    }

    struct YieldStrategy {
        uint256 riskLevel;        // Risk seviyesi (1-5)
        uint256 targetAPY;        // Hedef yıllık getiri
        uint256 rebalanceThreshold; // Yeniden dengeleme eşiği
        bool active;              // Strateji aktif mi?
    }

    // Durum değişkenleri
    mapping(address => uint256) public userBalances;
    mapping(address => YieldStrategy) public userStrategies;
    mapping(bytes32 => AIModel) public aiModels;
    
    AggregatorV3Interface public priceFeed;
    bytes32 public currentModelRoot;
    uint256 public totalValueLocked;

    // Yeni güvenlik sabitleri
    uint256 public constant MAX_CONFIDENCE_SCORE = 100;
    uint256 public constant MIN_DEPOSIT = 0.01 ether;
    uint256 public constant MAX_RISK_LEVEL = 5;
    uint256 public constant REBALANCE_COOLDOWN = 1 hours;
    uint256 public constant MAX_APY = 1000; // 1000% APY limiti

    // Yeni durum değişkenleri
    mapping(address => uint256) public lastRebalanceTime;
    mapping(address => bool) public blacklistedUsers;
    bool public emergencyMode;

    // Güvenlik sabitleri güncellendi
    uint256 private constant EMERGENCY_WITHDRAWAL_DELAY = 24 hours;
    uint256 private constant MAX_WITHDRAWAL_PERCENT = 90; // Max %90 çekilebilir
    uint256 private constant MIN_STRATEGY_CHANGE_INTERVAL = 12 hours;
    uint256 private constant MAX_DAILY_WITHDRAWAL = 1000 ether; // Günlük maksimum çekim
    uint256 private constant WITHDRAWAL_COOLDOWN = 1 hours; // Çekimler arası bekleme
    uint256 private constant MAX_TOTAL_VALUE_LOCKED = 100000 ether; // Maksimum TVL

    // Yeni durum değişkenleri
    mapping(address => uint256) private lastStrategyUpdateTime;
    mapping(address => uint256) private emergencyWithdrawalRequests;
    uint256 private totalEmergencyWithdrawals;
    uint256 private emergencyWithdrawalLimit;
    mapping(address => uint256) private lastWithdrawalTime;
    mapping(address => uint256) private dailyWithdrawals;
    uint256 private dailyWithdrawalReset;
    
    // Güvenlik rolleri
    address private guardian; // Acil durum yöneticisi
    address private riskManager; // Risk yöneticisi
    bool private guardianApprovalRequired;

    // Yeni güvenlik sabitleri
    uint256 private constant MAX_UINT = type(uint256).max;
    uint256 private constant MIN_OPERATION_DELAY = 5 minutes;
    uint256 private constant MAX_FAILED_ATTEMPTS = 3;
    uint256 private constant PRICE_DEVIATION_LIMIT = 10; // %10 maksimum sapma

    // Yeni durum değişkenleri
    mapping(address => uint256) private failedAttempts;
    mapping(address => uint256) private lastOperationTime;
    uint256 private lastPriceUpdate;
    int256 private lastValidPrice;
    bool private priceOracleActive;

    // Olaylar
    event StrategyUpdated(address indexed user, uint256 riskLevel, uint256 targetAPY);
    event AIModelUpdated(bytes32 indexed modelHash, uint256 confidenceScore);
    event YieldHarvested(address indexed user, uint256 amount);
    event EmergencyModeActivated(address indexed activator);
    event UserBlacklisted(address indexed user, string reason);
    event PortfolioRebalanced(address indexed user, uint256 oldRisk, uint256 newRisk);
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event EmergencyWithdrawalRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event StrategyValidationFailed(address indexed user, string reason);
    event RiskLevelAdjusted(address indexed user, uint256 oldRisk, uint256 newRisk, string reason);
    event GuardianSet(address indexed oldGuardian, address indexed newGuardian);
    event RiskManagerSet(address indexed oldManager, address indexed newManager);
    event WithdrawalLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event DailyLimitExceeded(address indexed user, uint256 attempted, uint256 limit);
    event SecurityLimitUpdated(string limitType, uint256 oldValue, uint256 newValue);
    event FailedAttemptRecorded(address indexed user, string reason);
    event AccountLocked(address indexed user, uint256 timestamp);
    event PriceDeviationDetected(int256 oldPrice, int256 newPrice);

    constructor(address _priceFeed) {
        require(_priceFeed != address(0), "Invalid price feed address");
        priceFeed = AggregatorV3Interface(_priceFeed);
        guardian = msg.sender;
        riskManager = msg.sender;
        dailyWithdrawalReset = block.timestamp;
    }

    // AI Model Yönetimi
    function updateAIModel(
        bytes32 _modelHash,
        uint256 _confidenceScore,
        bytes32[] calldata _merkleProof
    ) external onlyOwner {
        require(_confidenceScore <= 100, "Invalid confidence score");
        require(verifyAIModel(_modelHash, _merkleProof), "Invalid AI model proof");

        aiModels[_modelHash] = AIModel({
            modelHash: _modelHash,
            lastUpdate: block.timestamp,
            confidenceScore: _confidenceScore,
            validator: msg.sender
        });

        currentModelRoot = _modelHash;
        emit AIModelUpdated(_modelHash, _confidenceScore);
    }

    // Strateji Yönetimi
    function setStrategy(uint256 _riskLevel, uint256 _targetAPY) 
        external 
        notBlacklisted 
        whenNotPaused 
        validateStrategyChange 
    {
        require(_riskLevel > 0 && _riskLevel <= MAX_RISK_LEVEL, "Invalid risk level");
        require(_targetAPY > 0 && _targetAPY <= MAX_APY, "Invalid APY target");
        
        // Kullanıcının mevcut bakiyesine göre risk kontrolü
        uint256 userBalance = userBalances[msg.sender];
        if (userBalance > 100 ether && _riskLevel > 3) {
            emit StrategyValidationFailed(msg.sender, "High balance requires lower risk");
            revert("Risk level too high for balance");
        }

        // Market volatilitesine göre risk kontrolü
        uint256 volatility = getMarketVolatility();
        if (volatility > 50 && _riskLevel > 2) {
            emit StrategyValidationFailed(msg.sender, "High volatility requires lower risk");
            revert("Risk level too high for current volatility");
        }

        YieldStrategy storage oldStrategy = userStrategies[msg.sender];
        uint256 oldRisk = oldStrategy.riskLevel;

        userStrategies[msg.sender] = YieldStrategy({
            riskLevel: _riskLevel,
            targetAPY: _targetAPY,
            rebalanceThreshold: 5,
            active: true
        });

        lastStrategyUpdateTime[msg.sender] = block.timestamp;
        emit StrategyUpdated(msg.sender, _riskLevel, _targetAPY);
        
        if (oldRisk > 0 && _shouldRebalance(oldRisk, _riskLevel)) {
            rebalancePortfolio(msg.sender);
        }
    }

    // Yield Farming İşlemleri
    function deposit() 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        notBlacklisted 
        checkOperationThrottle
        validateUserStatus
        validatePriceData
    {
        require(!emergencyMode, "Emergency mode active");
        require(msg.value >= MIN_DEPOSIT, "Deposit below minimum");
        require(msg.value <= maxDepositLimit(), "Deposit above maximum");
        
        // TVL limiti kontrolü
        require(
            totalValueLocked + msg.value <= MAX_TOTAL_VALUE_LOCKED,
            "TVL limit exceeded"
        );

        // Overflow kontrolü
        require(
            totalValueLocked + msg.value >= totalValueLocked &&
            userBalances[msg.sender] + msg.value >= userBalances[msg.sender],
            "Arithmetic overflow"
        );

        // Fiyat sapması kontrolü
        require(_validatePrice(), "Price deviation too high");
        
        userBalances[msg.sender] += msg.value;
        totalValueLocked += msg.value;
        
        emit Deposited(msg.sender, msg.value);
        optimizeStrategy(msg.sender);
    }

    function withdraw(uint256 _amount) 
        external 
        nonReentrant 
        notBlacklisted 
        validateWithdrawal(_amount)
    {
        userBalances[msg.sender] -= _amount;
        totalValueLocked -= _amount;
        
        dailyWithdrawals[msg.sender] += _amount;
        lastWithdrawalTime[msg.sender] = block.timestamp;
        
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");
        
        emit Withdrawn(msg.sender, _amount);
    }

    // AI Destekli Optimizasyon
    function optimizeStrategy(address _user) internal {
        YieldStrategy storage strategy = userStrategies[_user];
        require(strategy.active, "No active strategy");

        // Fiyat verisi al
        (, int256 price, , , ) = priceFeed.latestRoundData();
        
        // AI model çıktılarını doğrula ve uygula
        if (shouldRebalance(_user, uint256(price))) {
            rebalancePortfolio(_user);
        }
    }

    // Yardımcı Fonksiyonlar
    function verifyAIModel(bytes32 _modelHash, bytes32[] calldata _proof) 
        internal 
        view 
        returns (bool) 
    {
        bytes32 leaf = keccak256(abi.encodePacked(_modelHash));
        return MerkleProof.verify(_proof, currentModelRoot, leaf);
    }

    function getLastKnownPrice() 
        internal 
        view 
        returns (uint256) 
    {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function getMarketVolatility() 
        internal 
        pure 
        returns (uint256) 
    {
        return 30; // Örnek sabit değer - pure olabilir
    }

    function abs(int256 x) 
        internal 
        pure 
        returns (uint256) 
    {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    // Optimize edilmiş shouldRebalance fonksiyonu
    function shouldRebalance(address _user, uint256 _currentPrice) 
        internal 
        view 
        returns (bool) 
    {
        YieldStrategy storage strategy = userStrategies[_user];
        if (!strategy.active) return false;
        
        if (block.timestamp < lastRebalanceTime[_user] + REBALANCE_COOLDOWN) {
            return false;
        }

        uint256 lastPrice = getLastKnownPrice();
        uint256 priceChange = abs(int256(_currentPrice) - int256(lastPrice));
        uint256 changePercent = (priceChange * 100) / lastPrice;
        
        return changePercent >= strategy.rebalanceThreshold;
    }

    // Optimize edilmiş calculateOptimalRisk fonksiyonu
    function calculateOptimalRisk(uint256 _userBalance) 
        internal 
        pure 
        returns (uint256) 
    {
        if (_userBalance > 100 ether) {
            return 2; // Büyük yatırımcılar için orta-düşük risk
        }
        return 3; // Varsayılan orta risk
    }

    function rebalancePortfolio(address _user) internal canRebalance {
        YieldStrategy storage strategy = userStrategies[_user];
        require(strategy.active, "No active strategy");

        uint256 oldRisk = strategy.riskLevel;
        uint256 newRisk = calculateOptimalRisk(userBalances[_user]);

        // Risk seviyesi değişimi
        if (oldRisk != newRisk) {
            strategy.riskLevel = newRisk;
            emit PortfolioRebalanced(_user, oldRisk, newRisk);
        }

        lastRebalanceTime[_user] = block.timestamp;
    }

    // Yeni yardımcı fonksiyonlar
    function maxDepositLimit() public view returns (uint256) {
        if (emergencyMode) return 0;
        return totalValueLocked * 20 / 100; // TVL'nin max %20'si
    }

    // Acil Durum Fonksiyonları
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setEmergencyMode(bool _enabled) external onlyOwner {
        emergencyMode = _enabled;
        if (_enabled) {
            _pause();
            emit EmergencyModeActivated(msg.sender);
        } else {
            _unpause();
        }
    }

    function blacklistUser(address _user, string calldata _reason) external onlyOwner {
        blacklistedUsers[_user] = true;
        emit UserBlacklisted(_user, _reason);
    }

    function _shouldRebalance(uint256 _oldRisk, uint256 _newRisk) 
        private 
        pure 
        returns (bool) 
    {
        return _oldRisk > _newRisk ? 
            _oldRisk - _newRisk > 2 : 
            _newRisk - _oldRisk > 2;
    }

    function emergencyWithdraw() 
        external 
        nonReentrant 
        validateEmergencyWithdrawal 
        validateUserStatus
    {
        uint256 balance = userBalances[msg.sender];
        require(balance > 0, "No balance to withdraw");

        uint256 maxWithdrawal = _calculateMaxWithdrawal(balance);
        uint256 availableForWithdrawal = maxWithdrawal;

        if (totalEmergencyWithdrawals + availableForWithdrawal > emergencyWithdrawalLimit) {
            availableForWithdrawal = emergencyWithdrawalLimit - totalEmergencyWithdrawals;
        }

        require(availableForWithdrawal > 0, "Withdrawal limit reached");

        userBalances[msg.sender] -= availableForWithdrawal;
        totalValueLocked -= availableForWithdrawal;
        totalEmergencyWithdrawals += availableForWithdrawal;
        emergencyWithdrawalRequests[msg.sender] = 0;

        _safeTransfer(msg.sender, availableForWithdrawal);
        
        emit Withdrawn(msg.sender, availableForWithdrawal);
    }

    // Receive ve Fallback
    receive() external payable {
        revert("Use deposit() function");
    }

    fallback() external payable {
        revert("Function not found");
    }

    // Yeni modifier
    modifier validateStrategyChange() {
        require(
            block.timestamp >= lastStrategyUpdateTime[msg.sender] + MIN_STRATEGY_CHANGE_INTERVAL,
            "Strategy change too frequent"
        );
        _;
    }

    modifier validateEmergencyWithdrawal() {
        require(emergencyMode, "Not in emergency mode");
        require(
            emergencyWithdrawalRequests[msg.sender] > 0 &&
            block.timestamp >= emergencyWithdrawalRequests[msg.sender],
            "Withdrawal not yet unlocked"
        );
        _;
    }

    // Owner fonksiyonları güncellendi
    function setEmergencyWithdrawalLimit(uint256 _limit) external onlyOwner {
        require(_limit > 0, "Invalid limit");
        emergencyWithdrawalLimit = _limit;
    }

    function cancelEmergencyWithdrawalRequest(address _user) external onlyOwner {
        require(emergencyWithdrawalRequests[_user] > 0, "No request exists");
        emergencyWithdrawalRequests[_user] = 0;
    }

    // Yardımcı fonksiyonlar güncellendi
    function getEmergencyWithdrawalStatus(address _user) 
        external 
        view 
        returns (
            bool hasRequest,
            uint256 unlockTime,
            uint256 maxWithdrawable
        ) 
    {
        uint256 requestTime = emergencyWithdrawalRequests[_user];
        uint256 balance = userBalances[_user];
        
        return (
            requestTime > 0,
            requestTime,
            balance > 0 ? (balance * MAX_WITHDRAWAL_PERCENT) / 100 : 0
        );
    }

    // Yeni güvenlik fonksiyonları
    function setGuardian(address _newGuardian) external onlyOwner {
        require(_newGuardian != address(0), "Invalid guardian");
        emit GuardianSet(guardian, _newGuardian);
        guardian = _newGuardian;
    }

    function setRiskManager(address _newManager) external onlyOwner {
        require(_newManager != address(0), "Invalid manager");
        emit RiskManagerSet(riskManager, _newManager);
        riskManager = _newManager;
    }

    function setGuardianApproval(bool _required) external onlyOwner {
        guardianApprovalRequired = _required;
    }

    function approveEmergencyWithdrawal(address _user) 
        external 
        onlyGuardian 
    {
        require(emergencyWithdrawalRequests[_user] > 0, "No request");
        _processEmergencyWithdrawal(_user);
    }

    // Internal fonksiyonlar
    function _processEmergencyWithdrawal(address _user) internal {
        uint256 balance = userBalances[_user];
        uint256 maxWithdrawal = (balance * MAX_WITHDRAWAL_PERCENT) / 100;
        uint256 availableForWithdrawal = maxWithdrawal;

        if (totalEmergencyWithdrawals + availableForWithdrawal > emergencyWithdrawalLimit) {
            availableForWithdrawal = emergencyWithdrawalLimit - totalEmergencyWithdrawals;
        }

        require(availableForWithdrawal > 0, "Withdrawal limit reached");

        userBalances[_user] -= availableForWithdrawal;
        totalValueLocked -= availableForWithdrawal;
        totalEmergencyWithdrawals += availableForWithdrawal;
        emergencyWithdrawalRequests[_user] = 0;

        (bool success, ) = _user.call{value: availableForWithdrawal}("");
        require(success, "Emergency withdrawal failed");
        
        emit Withdrawn(_user, availableForWithdrawal);
    }

    // Yeni modifier'lar
    modifier onlyGuardian() {
        require(msg.sender == guardian, "Only guardian");
        _;
    }

    modifier onlyRiskManager() {
        require(msg.sender == riskManager, "Only risk manager");
        _;
    }

    modifier validateWithdrawal(uint256 _amount) {
        require(_amount > 0, "Zero withdrawal");
        require(_amount <= userBalances[msg.sender], "Insufficient balance");
        
        // Günlük limit kontrolü
        if (block.timestamp >= dailyWithdrawalReset + 1 days) {
            dailyWithdrawals[msg.sender] = 0;
            dailyWithdrawalReset = block.timestamp;
        }
        
        require(
            dailyWithdrawals[msg.sender] + _amount <= MAX_DAILY_WITHDRAWAL,
            "Daily withdrawal limit exceeded"
        );
        
        // Çekimler arası bekleme süresi
        require(
            block.timestamp >= lastWithdrawalTime[msg.sender] + WITHDRAWAL_COOLDOWN,
            "Withdrawal cooldown active"
        );
        _;
    }

    // Yeni güvenlik fonksiyonları
    function recordFailedAttempt(address _user, string calldata _reason) 
        internal 
    {
        failedAttempts[_user]++;
        emit FailedAttemptRecorded(_user, _reason);
        
        if (failedAttempts[_user] >= MAX_FAILED_ATTEMPTS) {
            blacklistedUsers[_user] = true;
            emit AccountLocked(_user, block.timestamp);
        }
    }

    function resetFailedAttempts(address _user) 
        external 
        onlyGuardian 
    {
        require(failedAttempts[_user] > 0, "No failed attempts");
        failedAttempts[_user] = 0;
    }

    function setPriceOracleStatus(bool _active) 
        external 
        onlyGuardian 
    {
        priceOracleActive = _active;
    }

    // Güvenli çekme işlemi
    function _safeTransfer(address _to, uint256 _amount) 
        internal 
    {
        bool success;
        assembly {
            // Transfer ETH ve gas limiti 2300
            success := call(2300, _to, _amount, 0, 0, 0, 0)
        }
        require(success, "Transfer failed");
    }

    // Fiyat doğrulama fonksiyonu
    function _validatePrice() internal returns (bool) {
        (, int256 currentPrice,,,) = priceFeed.latestRoundData();
        
        // İlk fiyat kontrolü
        if (lastValidPrice == 0) {
            lastValidPrice = currentPrice;
            lastPriceUpdate = block.timestamp;
            return true;
        }

        // Fiyat sapması kontrolü
        uint256 deviation = _calculatePriceDeviation(currentPrice, lastValidPrice);
        if (deviation > PRICE_DEVIATION_LIMIT) {
            emit PriceDeviationDetected(lastValidPrice, currentPrice);
            return false;
        }

        lastValidPrice = currentPrice;
        lastPriceUpdate = block.timestamp;
        return true;
    }

    function _calculatePriceDeviation(int256 _newPrice, int256 _oldPrice) 
        internal 
        pure 
        returns (uint256) 
    {
        if (_newPrice == _oldPrice) return 0;
        
        uint256 diff;
        if (_newPrice > _oldPrice) {
            diff = uint256(_newPrice - _oldPrice);
        } else {
            diff = uint256(_oldPrice - _newPrice);
        }
        
        return (diff * 100) / uint256(_oldPrice);
    }

    // Güvenli matematik işlemleri için yardımcı fonksiyonlar
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        // 512-bit çarpım sonucu
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(x, y, not(0))
            prod0 := mul(x, y)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            return prod0 / denominator;
        }

        // Make sure the result is less than 2^256
        require(prod1 < denominator, "OVERFLOW");

        uint256 remainder;
        assembly {
            remainder := mulmod(x, y, denominator)
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // Factor powers of two out of denominator
        unchecked {
            // Compute largest power of two divisor of denominator
            uint256 twos = denominator & (~denominator + 1);
            // Divide denominator by power of two
            assembly {
                denominator := div(denominator, twos)
            }

            // Divide [prod1, prod0] by the factors of two
            assembly {
                prod0 := div(prod0, twos)
            }
            // Shift in bits from prod1 into prod0
            prod0 |= prod1 * ((~twos + 1) / twos + 1);

            // Invert denominator mod 2^256
            uint256 inverse = (3 * denominator) ^ 2;
            // inverse *= 2 - denominator * inverse
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            // result = prod0 * inverse
            result = prod0 * inverse;
        }
    }

    // Maksimum çekilebilir miktar hesaplama
    function _calculateMaxWithdrawal(uint256 _balance) 
        internal 
        pure 
        returns (uint256) 
    {
        return (_balance * MAX_WITHDRAWAL_PERCENT) / 100;
    }

    // Yeni modifier'lar
    modifier checkOperationThrottle() {
        require(
            block.timestamp >= lastOperationTime[msg.sender] + MIN_OPERATION_DELAY,
            "Operation too frequent"
        );
        _;
        lastOperationTime[msg.sender] = block.timestamp;
    }

    modifier validateUserStatus() {
        require(failedAttempts[msg.sender] < MAX_FAILED_ATTEMPTS, "Account locked");
        _;
    }

    modifier validatePriceData() {
        require(priceOracleActive, "Price oracle inactive");
        _;
    }
}
