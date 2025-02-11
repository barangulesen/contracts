# Yapay Zeka Destekli Getiri Optimizasyonu (AIYieldOptimizer)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**AIYieldOptimizer**, Ethereum blok zinciri üzerinde çalışan, yapay zeka güdümlü bir getiri optimizasyon platformu sağlayan bir Solidity akıllı kontratıdır. Kullanıcılara, yatırımlarını farklı risk seviyelerinde ve getiri hedeflerinde yönetme olanağı sunar. Kontrat, doğru piyasa verileri için Chainlink fiyat beslemesi ile entegre olur ve yapay zeka modelinin doğrulanması için Merkle kanıt sistemini kullanır.

## İçindekiler

*   [Özellikler](#özellikler)
*   [Güvenlik Özellikleri](#güvenlik-özellikleri)
*   [Kavramlar](#kavramlar)
*   [Kontrat Etkileşimi](#kontrat-etkileşimi)
    *   [Ön Koşullar](#ön-koşullar)
    *   [Para Yatırma](#para-yatırma)
    *   [Strateji Belirleme](#strateji-belirleme)
    *   [Para Çekme](#para-çekme)
    *   [Acil Durum Çekimi](#acil-durum-çekimi)
    *   [Diğer Fonksiyonlar](#diğer-fonksiyonlar)
*   [Kontrat Sahibi ve Roller](#kontrat-sahibi-ve-roller)
*   [Önemli Güvenlik Notları ve Dikkat Edilmesi Gerekenler](#önemli-güvenlik-notları-ve-dikkat-edilmesi-gerekenler)
*   [Olaylar (Events)](#olaylar-events)
*   [Lisans](#lisans)

## Özellikler

*   **Yapay Zeka Güdümlü Optimizasyon:** Piyasa koşullarına göre yatırım kararlarını optimize etmek için harici bir yapay zeka modelinden yararlanır.
*   **Özelleştirilebilir Stratejiler:** Kullanıcılar, risk seviyelerini (1-5) ve hedef Yıllık Yüzde Getiri (APY) oranlarını seçebilirler.
*   **Otomatik Yeniden Dengeleme:** Kontrat, piyasa dalgalanmalarına veya strateji değişikliklerine göre portföyleri otomatik olarak yeniden dengeler.
*   **Para Yatırma ve Çekme:** Kullanıcılar, güvenlik kurallarına ve limitlere tabi olarak ETH yatırabilir ve çekebilirler.
*   **Acil Durum Çekimi:** Kontrat sorunları veya acil durumlar için kullanıcıların fonlarını çekmeleri için bir mekanizma sağlar.
*   **Chainlink Fiyat Beslemesi Entegrasyonu:** Doğru değerleme ve manipülasyonun önlenmesi için güvenilir bir fiyat beslemesi kullanır.
*   **Merkle Kanıt Doğrulaması:** Yapay zeka model çıktılarının bütünlüğünü ve orijinalliğini sağlar.

## Güvenlik Özellikleri

*   **Yeniden Giriş Koruması (Reentrancy Guard):** Yeniden giriş saldırılarını (reentrancy attacks) önler.
*   **Duraklatılabilir (Pausable):** Kontrat sahibi, acil durumlarda işlemleri durdurabilir.
*   **Sahip Olunabilir (Ownable):** Belirli fonksiyonlar yalnızca kontrat sahibi tarafından çağrılabilir.
*   **Kara Liste (Blacklisting):** Şüpheli kullanıcılar kara listeye alınabilir.
*   **Çekim Limitleri:** Günlük ve acil durum çekim limitleri uygulanır.
*   **Bekleme Süreleri (Cooldown Periods):** Strateji değişiklikleri ve para çekme işlemleri arasında bekleme süreleri vardır.
*   **Koruyucu/Risk Yöneticisi Rolleri (Guardian/Risk Manager):** Acil durumları yönetmek ve risk parametrelerini ayarlamak için yükseltilmiş ayrıcalıklara sahip özel roller.
*   **Fiyat Sapma Kontrolü:** Fiyat besleme verilerinde anormal sapmaları izler.
*   **Başarısız Deneme Kilidi:** Birden çok başarısız işlem denemesinden sonra hesapları kilitler.
*   **İşlem Kısıtlaması (Operation Throttle):** Kullanıcı işlemlerinin sıklığını sınırlar.
* **Güvenli Matematik:** Taşmaları (overflow) önlemek için güvenli aritmetik işlemler kullanır.

## Kavramlar

*   **Toplam Kilitli Değer (TVL - Total Value Locked):** Kontrata yatırılan toplam ETH miktarı.
*   **Risk Seviyesi:** 1 (en düşük risk) ile 5 (en yüksek risk) arasında bir ölçek.
*   **Hedef APY:** İstenen yıllık yüzde getiri.
*   **Yeniden Dengeleme Eşiği:** Portföyün yeniden dengelenmesini tetikleyen fiyattaki yüzde değişimi.
*   **Güven Skoru:** Yapay zeka modelinin tahminlerine olan güvenini gösteren bir puan (0-100).
*   **Model Hash'i:** Yapay zeka modelinin kriptografik hash'i.
*   **Doğrulayıcı (Validator):** Yapay zeka modeli verilerini güncelleme yetkisine sahip adres.
*   **Acil Durum Modu:** Kontratın duraklatıldığı ve özel çekim prosedürlerinin geçerli olduğu bir durum.

## Kontrat Etkileşimi

### Ön Koşullar

*   Bir Ethereum cüzdanı (örneğin, MetaMask).
*   Kontratla etkileşim kurmak için cüzdanınızda yeterli ETH (ve gaz ücretlerini ödemek için).
*   Bir Solidity derleyicisi/dağıtım aracı (örneğin, Remix, Truffle).
*   Kontratın blok zinciri üzerindeki adresi.

### Para Yatırma

1.  Kontrattaki `deposit()` fonksiyonunu bulun.
2.  Fonksiyonu çağırın ve "value" alanına yatırmak istediğiniz ETH miktarını girin.  **Önemli:** Minimum para yatırma (MIN_DEPOSIT = 0.01 ETH) ve maksimum para yatırma (TVL'nin %20'si) kurallarına uyun.
3.  İşlemi onaylayın ve gönderin.
4.  Başarılı olursa, yatırdığınız miktar `userBalances` içinde güncellenecek ve bir `Deposited` olayı yayınlanacaktır.

### Strateji Belirleme

1.  `setStrategy(uint256 _riskLevel, uint256 _targetAPY)` fonksiyonunu bulun.
2.  `_riskLevel`: 1 (en düşük risk) ile 5 (en yüksek risk) arasında bir değer girin.
3.  `_targetAPY`: İstediğiniz yıllık getiri yüzdesini girin (maksimum %1000).
4.  İşlemi onaylayın.
5.  Başarılı olursa, bir `StrategyUpdated` olayı yayınlanır ve stratejiniz `userStrategies` içinde saklanır.
6.  **Önemli:** Yüksek bakiyeli hesaplar (100 ETH'den fazla) maksimum 3 risk seviyesi seçebilir. Piyasa volatilitesi yüksekse (50'nin üzerinde), maksimum risk seviyesi 2'dir. Strateji değişiklikleri, son değişiklikten en az 12 saat sonra yapılabilir.

### Para Çekme

1.  `withdraw(uint256 _amount)` fonksiyonunu bulun.
2.  `_amount`: Çekmek istediğiniz ETH miktarını girin.
3.  İşlemi onaylayın.
4.  **Önemli:** Yeterli bakiyeniz olduğundan ve günlük çekim limitini (MAX_DAILY_WITHDRAWAL = 1000 ETH) aşmadığınızdan emin olun. Ayrıca, son çekim işleminizden bu yana en az 1 saat (WITHDRAWAL_COOLDOWN) geçmiş olmalıdır. Başarılı bir çekim işlemi, bir `Withdrawn` olayı yayınlar.

### Acil Durum Çekimi

*Yalnızca acil durum modu etkinken (emergencyMode = true) kullanılabilir.*

1.  `emergencyWithdraw()` fonksiyonunu çağırın. Bu fonksiyon parametre almaz.
2.  Bu çekim işlemi normalde 24 saat sonra (EMERGENCY_WITHDRAWAL_DELAY) kullanılabilir hale gelir. Ancak kontrat sahibi veya "guardian" rolüne sahip bir kullanıcı, çekim işlemini beklemeden onaylayabilir (`approveEmergencyWithdrawal` fonksiyonunu kullanarak).  Çekilebilecek maksimum miktar, bakiyenizin %90'ıdır (MAX_WITHDRAWAL_PERCENT).  Toplam acil durum çekimleri, tanımlanan limiti (emergencyWithdrawalLimit) aşamaz.
3.  Başarılı bir çekim işlemi, `Withdrawn` olayını yayınlar.

### Diğer Fonksiyonlar

* `getEmergencyWithdrawalStatus(address _user)`: Acil durum para çekme talebinin durumunu gösterir.(Talep var mı? Ne zaman çekilebilir? Maksimum ne kadar çekilebilir?)

## Kontrat Sahibi ve Roller

Kontrat sahibi (dağıtımı yapan kişi), belirli fonksiyonları çağırabilir:

*   `pause()` / `unpause()`: Kontratı duraklatır/devam ettirir.
*   `setEmergencyMode(bool _enabled)`: Acil durum modunu etkinleştirir/devre dışı bırakır.
*   `blacklistUser(address _user, string calldata _reason)`: Bir kullanıcıyı kara listeye alır.
*   `updateAIModel(...)`: Yapay zeka modeli verilerini günceller.
*   `setEmergencyWithdrawalLimit(uint256 _limit)`: Acil durum çekim limitini belirler.
*   `cancelEmergencyWithdrawalRequest(address _user)`: Bir kullanıcının acil durum çekim talebini iptal eder.
*   `setGuardian(address _newGuardian)`: "Guardian" rolünü atar.
*   `setRiskManager(address _newManager)`: "Risk Manager" rolünü atar.
*   `setGuardianApproval(bool _required)`: Guardian onayının gerekli olup olmadığını ayarlar.
* `setPriceOracleStatus(bool _active)`: Fiyat oracle'ının aktiflik durumunu ayarlar.
* `resetFailedAttempts(address _user)`: Yanlış deneme sayacını sıfırlar.
**Guardian:** Acil durum çekimlerini onaylayabilir (`approveEmergencyWithdrawal`).

**Risk Manager:** Risk parametrelerini ayarlamak için ek fonksiyonlara sahip olabilir (kontratta tanımlanmamış, ancak rol mevcuttur).

## Önemli Güvenlik Notları ve Dikkat Edilmesi Gerekenler

*   **Minimum ve Maksimum Değerler:** Fonksiyonları çağırırken belirtilen minimum (MIN_) ve maksimum (MAX_) değerlere dikkat edin.
*   **Bekleme Süreleri (Cooldown):** Strateji değiştirme (MIN_STRATEGY_CHANGE_INTERVAL), yeniden dengeleme (REBALANCE_COOLDOWN) ve para çekme (WITHDRAWAL_COOLDOWN) işlemleri arasındaki bekleme sürelerine uyun.
*   **Limitler:** Günlük çekim limiti (MAX_DAILY_WITHDRAWAL), toplam kilitli değer limiti (MAX_TOTAL_VALUE_LOCKED) ve acil durum çekim limitini (emergencyWithdrawalLimit) aşmayın.
*   **Risk Yönetimi:** Risk seviyenizi dikkatli seçin. Yüksek risk, yüksek getiri potansiyeli sunarken, kayıp riskini de artırır.
*   **Fiyat Sapması:** Kontrat, fiyat beslemesinden gelen verilerde büyük sapmalar (%10 - PRICE_DEVIATION_LIMIT) tespit ederse işlemleri reddedebilir.
* **Hesap Kilitlenmesi:** Birden fazla başarısız işlem denemesi, (MAX_FAILED_ATTEMPTS) hesabınızın kilitlenmesine neden olabilir.
*   **Acil Durum Modu:** Kontrat sahibi, acil bir durumda kontratı durdurabilir ve özel çekim prosedürlerini başlatabilir.
* **İşlem Gaz Ücretleri:** Ethereum ağındaki her işlem için gaz ücreti ödemeniz gerekir. Bu ücretler, ağın yoğunluğuna bağlı olarak değişir.
*   **Kontratı İnceleyin:** Herhangi bir işlem yapmadan önce kontrat kodunu dikkatlice inceleyin veya güvendiğiniz bir uzmana inceletin.

## Olaylar (Events)

Kontrat, aşağıdaki olayları yayınlar:

*   `StrategyUpdated(address indexed user, uint256 riskLevel, uint256 targetAPY)`: Bir kullanıcının stratejisi güncellendiğinde yayınlanır.
*   `AIModelUpdated(bytes32 indexed modelHash, uint256 confidenceScore)`: AI modeli güncellendiğinde yayınlanır.
*   `YieldHarvested(address indexed user, uint256 amount)`: Bir kullanıcı getiri elde ettiğinde yayınlanır (kontratta tanımlanmamış).
*   `EmergencyModeActivated(address indexed activator)`: Acil durum modu etkinleştirildiğinde yayınlanır.
*   `UserBlacklisted(address indexed user, string reason)`: Bir kullanıcı kara listeye alındığında yayınlanır.
*   `PortfolioRebalanced(address indexed user, uint256 oldRisk, uint256 newRisk)`: Bir kullanıcının portföyü yeniden dengelendiğinde yayınlanır.
* `Deposited(address indexed user, uint256 amount)`: Kullanıcı para yatırdığında yayınlanır.
* `Withdrawn(address indexed user, uint256 amount)`: Kullanıcı para çektiğinde yayınlanır.
* `EmergencyWithdrawalRequested(address indexed user, uint256 amount, uint256 unlockTime)`: Kullanıcı acil durum para çekme talebinde bulunduğunda yayınlanır. (Fonksiyon kontratta bulunmamaktadır, event bulunmaktadır)
* `StrategyValidationFailed(address indexed user, string reason)`: Bir strateji doğrulama hatası oluştuğunda yayınlanır.
*   `RiskLevelAdjusted(address indexed user, uint256 oldRisk, uint256 newRisk, string reason)`: Bir kullanıcının risk seviyesi ayarlandığında yayınlanır.
*   `GuardianSet(address indexed oldGuardian, address indexed newGuardian)`: Guardian rolü değiştiğinde yayınlanır.
* `RiskManagerSet(address indexed oldManager, address indexed newManager)`: Risk Manager rolü değiştiğinde yayınlanır.
*   `WithdrawalLimitUpdated(uint256 oldLimit, uint256 newLimit)`: Çekim limiti güncellendiğinde yayınlanır.
*   `DailyLimitExceeded(address indexed user, uint256 attempted, uint256 limit)`: Günlük çekim limiti aşıldığında yayınlanır.
* `SecurityLimitUpdated(string limitType, uint256 oldValue, uint256 newValue)`: Güvenlik limiti güncellendiğinde yayınlanır.
* `FailedAttemptRecorded(address indexed user, string reason)`: Hatalı işlem denemesi kaydedildiğinde yayınlanır.
* `AccountLocked(address indexed user, uint256 timestamp)`: Hesap kilitlendiğinde yayınlanır.
* `PriceDeviationDetected(int256 oldPrice, int256 newPrice)`: Fiyat sapması algılandığında yayınlanır.

## Lisans

Bu proje [MIT Lisansı](https://opensource.org/licenses/MIT) altında lisanslanmıştır.
