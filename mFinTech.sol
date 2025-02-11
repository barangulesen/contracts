// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; 

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol"; // Oylama için
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol"; // Güvenli matematik (0.8+ için genelde gereksiz)
import "@openzeppelin/contracts/utils/Counters.sol";  // Gerekirse sayaçlar için


contract mFinTech is ERC20, ERC20Burnable, ERC20Votes, Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    // using Counters for Counters.Counter; //Gerekirse

    // Staking ile ilgili değişkenler
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balances; // Kendi balanceOf'umuzu kullanıyoruz
    mapping(address => uint256) public stakedBalance;
    uint256 public totalStaked;

    // --- Kredi Verme/Alma (ÇOK BASİT ÖRNEK!) ---
    struct Loan {
        address borrower;
        uint256 amount;
        uint256 interestRate; // Yıllık faiz oranı (yüzde olarak, örn. 5 = %5)
        uint256 startDate;
        uint256 duration; // Kredi süresi (saniye cinsinden)
        bool paidBack;
    }

    mapping(uint256 => Loan) public loans;
    // Counters.Counter private _loanIds;  // Kredi ID'leri için sayaç (gerekirse)
    uint256 private _loanCounter;


    // --- Ödeme Sistemi Entegrasyonu (ÇOK BASİT ÖRNEK!) ---
    mapping(address => bool) public authorizedPaymentProcessors; // Yetkilendirilmiş ödeme işlemcileri

    // Olaylar (Events)
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event LoanCreated(uint256 loanId, address borrower, uint256 amount);
    event LoanRepaid(uint256 loanId);
    event PaymentProcessed(address indexed from, address indexed to, uint256 amount);


      // --- Oylama (DAO) ---
    // ERC20Votes, oylama gücünü delege etme (delegation) ve geçmişteki
    // oylama gücünü sorgulama (checkpointing) özelliklerini içerir.
    // OpenZeppelin, oylama için ayrı bir modül de sunar (Governor), ancak
    // bu örnekte basitlik için ERC20Votes kullanıyoruz.

    // Basit bir teklif (proposal) yapısı
    struct Proposal {
        uint256 id;
        string description; // Teklifin açıklaması
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        uint256 deadline; // Oylamanın bitiş zamanı
        mapping(address => bool) hasVoted; // Adreslerin oy kullanıp kullanmadığını takip eder
    }

    mapping(uint256 => Proposal) public proposals;
    // Counters.Counter private _proposalIds;  // Teklif ID'leri için sayaç
    uint256 private _proposalCounter;
    uint256 public votingDelay = 1 days;  // Oylamanın başlaması için gereken süre (örneğin, 1 gün)
    uint256 public votingPeriod = 7 days; // Oylama süresi (örneğin, 7 gün)



    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 _rewardRate
    ) ERC20(name, symbol) ERC20Permit(name) { //ERC20Permit eklendi
        _mint(msg.sender, initialSupply * 10**decimals());
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
        balances[msg.sender] = initialSupply * 10 ** decimals();
    }


     // --- ERC20Votes Override'ları ---
     //  Oy kullanma gücü, toplam token miktarını (stake edilmiş + stake edilmemiş) temel alır.

     function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount); //önce ana fonksiyonu çağırıyoruz
     }


    // --- ERC20 Fonksiyonlarını Override Etme ---

    function _transfer(address sender, address recipient, uint256 amount) internal override(ERC20, ERC20Votes) whenNotPaused {
        require(balances[sender] >= amount, "Transfer amount exceeds balance");
        if (stakedBalance[sender] > 0) {
            require(sender == owner() || amount <= balances[sender] - stakedBalance[sender], "Cannot transfer staked tokens");
        }
        _updateRewards(sender);
        if (recipient != address(0)) {
            _updateRewards(recipient);
        }
        super._transfer(sender, recipient, amount); // Normal ERC20 transferi
        balances[sender] = balances[sender].sub(amount);
        balances[recipient] = balances[recipient].add(amount);
    }
     function balanceOf(address account) public view override returns (uint256) {
        return balances[account];
    }

    // --- Staking Fonksiyonları ---

    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balances[msg.sender] >= amount, "Not enough tokens to stake");
        _updateRewards(msg.sender);

        stakedBalance[msg.sender] = stakedBalance[msg.sender].add(amount);
        totalStaked = totalStaked.add(amount);
        balances[msg.sender] = balances[msg.sender].sub(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(stakedBalance[msg.sender] >= amount, "Not enough staked tokens");
        _updateRewards(msg.sender);

        stakedBalance[msg.sender] = stakedBalance[msg.sender].sub(amount);
        totalStaked = totalStaked.sub(amount);
        balances[msg.sender] = balances[msg.sender].add(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claimReward() external nonReentrant {
        _updateRewards(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            _mint(msg.sender, reward); //Ödülleri mint et
            balances[msg.sender] = balances[msg.sender].add(reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // --- Ödül Hesaplama Fonksiyonları ---
      function _updateRewards(address account) internal {
        rewardPerTokenStored = _rewardPerToken();
        lastUpdateTime = block.timestamp;
        rewards[account] = _earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }

    function _rewardPerToken() internal view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                (block.timestamp.sub(lastUpdateTime)).mul(rewardRate).mul(1e18).div(totalStaked)
            );
    }

    function _earned(address account) internal view returns (uint256) {
        return
            stakedBalance[account]
                .mul(_rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18); //Bölme işleminde hassaslık için
    }

     // --- Kontrat Sahibi (Owner) Fonksiyonları ---
    function setRewardRate(uint256 _newRewardRate) external onlyOwner {
        _updateRewards(address(0));
        rewardRate = _newRewardRate;
        lastUpdateTime = block.timestamp;
    }

    // --- Pausable Fonksiyonları (OpenZeppelin'den) ---
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

      // --- Ek Güvenlik ---
    // Acil durumda stake edilen token'ları çekebilme (SADECE OWNER)
    function emergencyWithdraw(address _to) external onlyOwner {
        uint256 balance = address(this).balance; // Kontratın kendi NATIVE TOKEN bakiyesi (gerekirse)
        payable(_to).transfer(balance); // NATIVE TOKEN transferi (gerekirse)

        uint256 tokenBalance = stakedBalance[msg.sender]+balances[msg.sender]; //Tüm token'lar
        stakedBalance[msg.sender] = 0;
        totalStaked = totalStaked.sub(tokenBalance);
        balances[msg.sender] = tokenBalance; // Tüm balance'ı owner'a aktar
        _transfer(address(this),_to,tokenBalance); //Normal token transferi
    }

    // --- Kredi Verme/Alma Fonksiyonları (ÇOK BASİT ÖRNEK!) ---

    function createLoan(uint256 _amount, uint256 _interestRate, uint256 _duration) external payable {
        require(_amount > 0, "Loan amount must be greater than 0");
        require(_duration > 0, "Loan duration must be greater than 0");
        require(msg.value >= _amount, "Not enough NATIVE TOKEN sent for loan"); //Kredi için yeterli NATIVE gönderilmeli (basitlik için)

        // _loanIds.increment();  // Kredi ID'sini artır (Counters kütüphanesi kullanılıyorsa)
        // uint256 loanId = _loanIds.current(); // Counters kütüphanesi ile
        _loanCounter++;
        uint256 loanId = _loanCounter;


        loans[loanId] = Loan({
            borrower: msg.sender,
            amount: _amount,
            interestRate: _interestRate,
            startDate: block.timestamp,
            duration: _duration,
            paidBack: false
        });

        emit LoanCreated(loanId, msg.sender, _amount);

        // Kredi miktarını borçluya transfer et (basitlik için doğrudan NATIVE TOKEN AL )
        // Daha güvenli bir uygulamada, token'lar kullanılmalı ve borçluya kredi token'ları verilmeli
        payable(msg.sender).transfer(_amount);
    }


    function repayLoan(uint256 _loanId) external payable {
        Loan storage loan = loans[_loanId];
        require(loan.borrower == msg.sender, "Only the borrower can repay the loan");
        require(!loan.paidBack, "Loan has already been repaid");

        uint256 interest = calculateInterest(_loanId);
        uint256 totalAmount = loan.amount.add(interest);

        require(msg.value >= totalAmount, "Not enough NATIVE sent to repay loan");

        loan.paidBack = true;
        emit LoanRepaid(_loanId);

         // Faiz ve anaparayı kontrat sahibine geri gönder (basitlik için)
        payable(owner()).transfer(totalAmount); //Normalde faiz geliri farklı şekillerde yönetilir (örneğin, dağıtılır)
    }

    function calculateInterest(uint256 _loanId) public view returns (uint256) {
        Loan storage loan = loans[_loanId];
        require(_loanId > 0 && _loanId <= _loanCounter, "Invalid loan ID.");
        if (loan.paidBack) {
            return 0; // Kredi ödenmişse faiz hesaplama
        }
        uint256 elapsedTime = block.timestamp.sub(loan.startDate);
        if (elapsedTime >= loan.duration) {
            elapsedTime = loan.duration; // Maksimum süre kredi süresi kadar
        }
        // Basit faiz hesaplaması: (Anapara * Faiz Oranı * Süre) / 100 / (Yılın Saniyesi)
        return (loan.amount.mul(loan.interestRate).mul(elapsedTime)) / 100 / 31536000;
    }

    // --- Ödeme Sistemi Entegrasyonu Fonksiyonları (ÇOK BASİT ÖRNEK!) ---

    function authorizePaymentProcessor(address _processor) external onlyOwner {
        authorizedPaymentProcessors[_processor] = true;
    }

    function revokePaymentProcessor(address _processor) external onlyOwner {
        authorizedPaymentProcessors[_processor] = false;
    }

    // Bu fonksiyon, yetkilendirilmiş bir ödeme işlemcisi tarafından çağrılabilir.
    function processPayment(address _from, address _to, uint256 _amount) external {
        require(authorizedPaymentProcessors[msg.sender], "Unauthorized payment processor");
        require(balances[_from] >= _amount, "Insufficient balance");

        _transfer(_from, _to, _amount); // Normal transfer, staking ödüllerini de günceller.
        emit PaymentProcessed(_from, _to, _amount);
    }

        // --- Oylama (DAO) Fonksiyonları ---

    function createProposal(string memory _description, uint256 _deadline) external {
        require(bytes(_description).length > 0, "Description cannot be empty");
        // _proposalIds.increment();  // Teklif ID'sini artır (Counters kütüphanesi kullanılıyorsa)
        // uint256 proposalId = _proposalIds.current();
        _proposalCounter++;
        uint256 proposalId = _proposalCounter;

        proposals[proposalId] = Proposal({
            id: proposalId,
            description: _description,
            yesVotes: 0,
            noVotes: 0,
            executed: false,
            deadline: block.timestamp + _deadline, //Örnek: 7 days;
            hasVoted:{}
        });
    }

     function vote(uint256 _proposalId, bool _support) external {
        Proposal storage proposal = proposals[_proposalId];
        require(_proposalId > 0 && _proposalId <= _proposalCounter , "Invalid proposal ID");
        require(block.timestamp <= proposal.deadline, "Voting period has ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");

        uint256 votingPower = getVotes(msg.sender); // ERC20Votes'dan gelen fonksiyon
        require(votingPower > 0, "You have no voting power");

        proposal.hasVoted[msg.sender] = true; // Oy kullanıldığını kaydet.

        if (_support) {
            proposal.yesVotes = proposal.yesVotes.add(votingPower);
        } else {
            proposal.noVotes = proposal.noVotes.add(votingPower);
        }
    }

     function executeProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(_proposalId > 0 && _proposalId <= _proposalCounter, "Invalid proposal ID");
        require(block.timestamp > proposal.deadline, "Voting period has not ended");
        require(!proposal.executed, "Proposal already executed");

        // Basit bir çoğunluk kuralı (daha karmaşık kurallar uygulanabilir)
        require(proposal.yesVotes > proposal.noVotes, "Proposal did not pass");

        proposal.executed = true;

        // Teklifin gerektirdiği işlemleri burada gerçekleştirin (bu örnekte sadece işaretleniyor)
        // ÖRNEK: Eğer teklif ödül oranını değiştirmekse:
        // if (proposal.id == 1) {  // Ödül oranı değiştirme teklifinin ID'si 1 varsayalım
        //     setRewardRate(newRewardRate); // Yeni ödül oranını ayarla
        // }
    }
     // Burn fonksiyonunu override ediyoruz.
    function burn(uint256 amount) public virtual override {
        _updateRewards(msg.sender);
        _burn(msg.sender, amount);
        balances[msg.sender] = balances[msg.sender].sub(amount);
    }

    function burnFrom(address account, uint256 amount) public virtual override{
        _updateRewards(account);
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
        balances[account] = balances[account].sub(amount);
    }
}