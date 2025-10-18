// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * Flash loans are **unsecured (uncollateralized) loans where a borrower must repay their entire loan back to a lender in the same transaction**.
 * They are unique financial products, only available in the DeFi world because smart contracts can force a user to pay the loan back immediately.
 * 
 * ELEGENT DeFi Platform - Modular Architecture to avoid stack depth issues
 */

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IFlashLoanReceiver {
    function executeOperation(address asset, uint256 amount, uint256 fee, bytes calldata params) external returns (bool);
}

// ============================================================================
// LOAN NFT - Simplified
// ============================================================================
contract LoanNFT {
    string public name = "ELEGENT Loan NFT";
    string public symbol = "ELOAN";
    
    uint256 private _tokenIdCounter;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => uint256) private _loanIds;
    address public platform;
    
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    constructor() {
        platform = msg.sender;
    }
    
    modifier onlyPlatform() {
        require(msg.sender == platform, "Only platform");
        _;
    }
    
    function mint(address to, uint256 loanId, string memory uri) external onlyPlatform returns (uint256) {
        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;
        _owners[tokenId] = to;
        _balances[to]++;
        _tokenURIs[tokenId] = uri;
        _loanIds[tokenId] = loanId;
        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }
    
    function ownerOf(uint256 tokenId) external view returns (address) {
        return _owners[tokenId];
    }
    
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_owners[tokenId] != address(0), "Token does not exist");
        return _tokenURIs[tokenId];
    }
    
    function getLoanId(uint256 tokenId) external view returns (uint256) {
        require(_owners[tokenId] != address(0), "Token does not exist");
        return _loanIds[tokenId];
    }
}

// ============================================================================
// TRUST SCORE NFT - Simplified
// ============================================================================
contract TrustScoreNFT {
    string public name = "ELEGENT Trust Score";
    string public symbol = "ETRUST";
    
    struct TrustScore {
        uint256 score;
        string tier;
        uint256 loanCount;
        uint256 totalBorrowed;
        uint256 totalRepaid;
        uint256 defaults;
        uint256 lastUpdated;
        uint256 stakedAmount;
        uint256 earlyRepayments;
    }
    
    mapping(address => TrustScore) public trustScores;
    mapping(address => uint256) public userTokenId;
    uint256 private _tokenIdCounter;
    address public platform;
    
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    
    constructor() {
        platform = msg.sender;
    }
    
    modifier onlyPlatform() {
        require(msg.sender == platform, "Only platform");
        _;
    }
    
    function createTrustScore(address user) external onlyPlatform returns (uint256) {
        require(userTokenId[user] == 0, "Trust score exists");
        
        _tokenIdCounter++;
        userTokenId[user] = _tokenIdCounter;
        
        trustScores[user] = TrustScore({
            score: 100,
            tier: "Bronze",
            loanCount: 0,
            totalBorrowed: 0,
            totalRepaid: 0,
            defaults: 0,
            lastUpdated: block.timestamp,
            stakedAmount: 0,
            earlyRepayments: 0
        });
        
        emit Transfer(address(0), user, _tokenIdCounter);
        return _tokenIdCounter;
    }
    
    function updateScore(address user, uint256 newScore, string memory newTier) external onlyPlatform {
        require(userTokenId[user] != 0, "No trust score");
        trustScores[user].score = newScore;
        trustScores[user].tier = newTier;
        trustScores[user].lastUpdated = block.timestamp;
    }
    
    function incrementStake(address user, uint256 amount) external onlyPlatform {
        trustScores[user].stakedAmount += amount;
    }
    
    function decrementStake(address user, uint256 amount) external onlyPlatform {
        trustScores[user].stakedAmount -= amount;
    }
    
    function getTrustScore(address user) external view returns (TrustScore memory) {
        return trustScores[user];
    }
}

// ============================================================================
// MAIN PLATFORM
// ============================================================================
contract ElegentDeFiPlatform {
    // Roles
    address public admin;
    mapping(address => bool) public moderators;
    mapping(address => bool) public liquidators;
    
    // Constants
    uint256 public constant MAX_TRUST_SCORE = 1000;
    uint256 public constant MIN_LOAN_AMOUNT = 0.01 ether;
    uint256 public constant MAX_LOAN_AMOUNT = 1000 ether;
    uint256 public constant LOAN_DURATION = 30 days;
    uint256 public constant WEEK = 7 days;
    uint256 public constant FLASH_LOAN_FEE_BPS = 9;
    uint256 public constant PLATFORM_FEE_BPS = 100;
    uint256 public constant BPS_DIVISOR = 10000;
    
    enum LoanStatus { Active, Repaid, Defaulted, Liquidated, Extended }
    
    struct Loan {
        address borrower;
        address token;
        uint256 amount;
        uint256 interest;
        uint256 rate;
        uint256 dueDate;
        LoanStatus status;
        uint256 nftId;
    }
    
    struct StakeInfo {
        uint256 amount;
        uint256 rewards;
        uint256 lastRewardTime;
    }
    
    // State
    LoanNFT public loanNFT;
    TrustScoreNFT public trustScoreNFT;
    
    uint256 public totalLoans;
    uint256 public totalVolume;
    uint256 public treasuryBalance;
    uint256 public totalStaked;
    bool public paused;
    
    mapping(uint256 => Loan) public loans;
    mapping(address => uint256[]) public userLoans;
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public tokenLiquidity;
    mapping(address => StakeInfo) public stakes;
    mapping(uint256 => uint256) public refinancedLoans;
    
    // Events
    event LoanCreated(uint256 indexed loanId, address indexed borrower, uint256 amount, uint256 rate);
    event FlashLoanExecuted(address indexed borrower, address token, uint256 amount, uint256 fee);
    event LoanRepaid(uint256 indexed loanId, address indexed borrower, bool early);
    event LoanLiquidated(uint256 indexed loanId, address liquidator);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }
    
    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }
    
    constructor() {
        admin = msg.sender;
        loanNFT = new LoanNFT();
        trustScoreNFT = new TrustScoreNFT();
        supportedTokens[address(0)] = true;
    }
    
    // ============================================================================
    // ADMIN
    // ============================================================================
    
    function addSupportedToken(address token) external onlyAdmin {
        supportedTokens[token] = true;
    }
    
    function setPaused(bool _paused) external onlyAdmin {
        paused = _paused;
    }
    
    function addLiquidator(address liquidator) external onlyAdmin {
        liquidators[liquidator] = true;
    }
    
    // ============================================================================
    // LIQUIDITY
    // ============================================================================
    
    function addLiquidity(address token, uint256 amount) external payable {
        require(supportedTokens[token], "Not supported");
        
        if (token == address(0)) {
            require(msg.value == amount, "Invalid amount");
        } else {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }
        
        tokenLiquidity[token] += amount;
    }
    
    // ============================================================================
    // TRUST SCORE
    // ============================================================================
    
    function createTrustScore() external {
        trustScoreNFT.createTrustScore(msg.sender);
    }
    
    function calculateDynamicRate(uint256 score) public pure returns (uint256) {
        if (score >= 800) return 300;
        if (score >= 600) return 500;
        if (score >= 400) return 700;
        if (score >= 200) return 1000;
        return 1500;
    }
    
    function calculateMaxLoan(address user) public view returns (uint256) {
        TrustScoreNFT.TrustScore memory ts = trustScoreNFT.getTrustScore(user);
        uint256 multiplier = ts.score >= 800 ? 10 : ts.score >= 600 ? 8 : ts.score >= 400 ? 6 : ts.score >= 200 ? 4 : 2;
        uint256 base = (ts.score * 0.001 ether) * multiplier;
        uint256 total = base + (ts.stakedAmount * 2);
        return total > MAX_LOAN_AMOUNT ? MAX_LOAN_AMOUNT : total;
    }
    
    function getTierFromScore(uint256 score) internal pure returns (string memory) {
        if (score >= 800) return "Diamond";
        if (score >= 600) return "Platinum";
        if (score >= 400) return "Gold";
        if (score >= 200) return "Silver";
        return "Bronze";
    }
    
    // ============================================================================
    // FLASH LOAN
    // ============================================================================
    
    function flashLoan(address token, uint256 amount, bytes calldata params) external whenNotPaused {
        require(supportedTokens[token], "Not supported");
        require(tokenLiquidity[token] >= amount, "Insufficient liquidity");
        
        uint256 balBefore = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        uint256 fee = (amount * FLASH_LOAN_FEE_BPS) / BPS_DIVISOR;
        
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }
        
        require(IFlashLoanReceiver(msg.sender).executeOperation(token, amount, fee, params), "Execution failed");
        
        uint256 balAfter = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        require(balAfter >= balBefore + fee, "Not repaid");
        
        treasuryBalance += fee;
        emit FlashLoanExecuted(msg.sender, token, amount, fee);
    }
    
    // ============================================================================
    // STANDARD LOANS
    // ============================================================================
    
    function requestLoan(address token, uint256 amount) external payable whenNotPaused returns (uint256) {
        require(supportedTokens[token], "Not supported");
        require(amount >= MIN_LOAN_AMOUNT && amount <= MAX_LOAN_AMOUNT, "Invalid amount");
        require(tokenLiquidity[token] >= amount, "Insufficient liquidity");
        
        TrustScoreNFT.TrustScore memory ts = trustScoreNFT.getTrustScore(msg.sender);
        require(ts.score > 0, "No trust score");
        require(amount <= calculateMaxLoan(msg.sender), "Exceeds max");
        
        totalLoans++;
        uint256 rate = calculateDynamicRate(ts.score);
        
        loans[totalLoans] = Loan({
            borrower: msg.sender,
            token: token,
            amount: amount,
            interest: (amount * rate) / BPS_DIVISOR,
            rate: rate,
            dueDate: block.timestamp + LOAN_DURATION,
            status: LoanStatus.Active,
            nftId: loanNFT.mint(msg.sender, totalLoans, "")
        });
        
        userLoans[msg.sender].push(totalLoans);
        totalVolume += amount;
        tokenLiquidity[token] -= amount;
        
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }
        
        emit LoanCreated(totalLoans, msg.sender, amount, rate);
        return totalLoans;
    }
    
    function repayLoan(uint256 loanId) external payable {
        Loan storage loan = loans[loanId];
        require(loan.borrower == msg.sender, "Not borrower");
        require(loan.status == LoanStatus.Active, "Not active");
        
        uint256 total = loan.amount + loan.interest;
        bool early = block.timestamp < loan.dueDate - WEEK;
        
        if (loan.token == address(0)) {
            require(msg.value >= total, "Insufficient");
            if (msg.value > total) payable(msg.sender).transfer(msg.value - total);
        } else {
            IERC20(loan.token).transferFrom(msg.sender, address(this), total);
        }
        
        loan.status = LoanStatus.Repaid;
        tokenLiquidity[loan.token] += loan.amount;
        treasuryBalance += (total * PLATFORM_FEE_BPS) / BPS_DIVISOR + loan.interest;
        
        _updateTrustScore(msg.sender, early ? 15 : 10, true);
        
        emit LoanRepaid(loanId, msg.sender, early);
    }
    
    function liquidateLoan(uint256 loanId) external {
        require(liquidators[msg.sender], "Not liquidator");
        Loan storage loan = loans[loanId];
        require(loan.status == LoanStatus.Active, "Not active");
        require(block.timestamp > loan.dueDate + 2 days, "Not overdue");
        
        loan.status = LoanStatus.Liquidated;
        payable(msg.sender).transfer((loan.amount * 500) / BPS_DIVISOR);
        
        _updateTrustScore(loan.borrower, 50, false);
        
        emit LoanLiquidated(loanId, msg.sender);
    }
    
    // ============================================================================
    // STAKING
    // ============================================================================
    
    function stake() external payable {
        require(msg.value > 0, "Invalid");
        
        StakeInfo storage info = stakes[msg.sender];
        
        if (info.amount > 0) {
            uint256 time = block.timestamp - info.lastRewardTime;
            info.rewards += (info.amount * 1000 * time) / (BPS_DIVISOR * 365 days);
        }
        
        info.amount += msg.value;
        info.lastRewardTime = block.timestamp;
        totalStaked += msg.value;
        
        trustScoreNFT.incrementStake(msg.sender, msg.value);
        _updateTrustScore(msg.sender, msg.value / 0.01 ether, true);
        
        emit Staked(msg.sender, msg.value);
    }
    
    function unstake(uint256 amount) external {
        StakeInfo storage info = stakes[msg.sender];
        require(info.amount >= amount, "Insufficient");
        
        uint256 time = block.timestamp - info.lastRewardTime;
        info.rewards += (info.amount * 1000 * time) / (BPS_DIVISOR * 365 days);
        
        uint256 total = amount + info.rewards;
        info.amount -= amount;
        info.rewards = 0;
        info.lastRewardTime = block.timestamp;
        totalStaked -= amount;
        
        trustScoreNFT.decrementStake(msg.sender, amount);
        
        payable(msg.sender).transfer(total);
        
        emit Unstaked(msg.sender, amount);
    }
    
    // ============================================================================
    // INTERNAL
    // ============================================================================
    
    function _updateTrustScore(address user, uint256 change, bool increase) internal {
        TrustScoreNFT.TrustScore memory ts = trustScoreNFT.getTrustScore(user);
        uint256 newScore = increase ? ts.score + change : (ts.score > change ? ts.score - change : 0);
        if (newScore > MAX_TRUST_SCORE) newScore = MAX_TRUST_SCORE;
        trustScoreNFT.updateScore(user, newScore, getTierFromScore(newScore));
    }
    
    // ============================================================================
    // VIEW
    // ============================================================================
    
    function getUserLoans(address user) external view returns (uint256[] memory) {
        return userLoans[user];
    }
    
    function getPendingRewards(address user) external view returns (uint256) {
        StakeInfo memory info = stakes[user];
        if (info.amount == 0) return 0;
        uint256 time = block.timestamp - info.lastRewardTime;
        return info.rewards + (info.amount * 1000 * time) / (BPS_DIVISOR * 365 days);
    }
    
    receive() external payable {}
}
