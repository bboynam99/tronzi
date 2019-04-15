pragma solidity ^0.4.23;


contract Roi {

    using SafeMath for uint256;

    mapping(address => uint256) investments;
    mapping(address => uint256) joined;
    mapping(address => uint256) withdrawals;
    mapping(address => uint256) referrer;
    mapping(bytes32 => bool) administrators;


    uint256 public minimum = 1000000; // 1 TRX
    uint256 public stakingRequirement = 10000000; // 10 TRX
    uint256 public lockoutTime = 0; // in minutes; default: 7200
    uint256 public rate_ = 10; // percent of return per day
    uint8 public referralFee_ = 20;
    uint8 public devFee_ = 10;
    uint256 public threshold = 10000000000000; // 10 mil TRX
    uint256 public feeMultiplier = 3;

    address internal owner;

    uint256 private withdrawn;

    event Invest(address investor, uint256 amount);
    event Withdraw(address investor, uint256 amount);
    event Bounty(address hunter, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Сonstructor Sets the original roles of the contract
     */

    constructor() public {
        owner = msg.sender;
        withdrawn = 0;
    }

    /**
     * @dev Modifiers
     */

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyAdministrator() {
        address _customerAddress = msg.sender;
        require(administrators[keccak256(abi.encodePacked(_customerAddress))]);
        _;
    }

    function setAdministrator(bytes32 _identifier, bool _status) public onlyAdministrator {
        administrators[_identifier] = _status;
    }


    function setReferralFee(uint8 _amount) public onlyAdministrator {
        referralFee_ = _amount;
    }

    // param: in minute
    function setLockoutTime(uint256 _time) public onlyAdministrator {
        lockoutTime = _time;
    }

    function setDevFee(uint8 _rate) public onlyAdministrator {
        devFee_ = _rate;
    }

    function setThreshold(uint256 _threshold) public onlyAdministrator {
        threshold = _threshold;
    }


    function setWithdrawalRate(uint256 _rate) public onlyAdministrator {
        rate_ = _rate;
    }


    //
    function getTotalTrxWithdrawn() public view onlyAdministrator returns (uint256) {
        return withdrawn;
    }

    /**
     * @dev Allows current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Investments
     */
    function () public payable {

    }

    function buy(address _referredBy) public payable {

        require(msg.value >= minimum);
        address _customerAddress = msg.sender;

        owner.transfer(msg.value.mul(devFee_).div(100));
        if (
        // is this a referred purchase?
            _referredBy != address(0) &&

            // no cheating!
            _referredBy != _customerAddress &&

        // does the referrer have at least X whole tokens?
        investments[_referredBy] >= stakingRequirement
        ) {
            referrer[_referredBy] = referrer[_referredBy].add(msg.value.mul(referralFee_).div(100));
        }

        // amount that actually work as investment
        uint256 investment =
        SafeMath.div(
            SafeMath.mul(msg.value, SafeMath.sub(100, referralFee_).sub(devFee_)), 100);

        // if there was previous investment, withdraw that first
        if (investments[msg.sender] > 0) {
            if (withdraw()) {
                withdrawals[msg.sender] = 0;
            }
        }

        investments[msg.sender] = investments[msg.sender].add(investment);
        joined[msg.sender] = block.timestamp;

        emit Invest(msg.sender, msg.value);
    }

    /**
    * @dev Evaluate current balance
    * @param _address Address of investor
    */
    function getBalance(address _address) view public returns (uint256) {

        uint256 minutesCount = SafeMath.div(SafeMath.sub(now, joined[_address]), 1 minutes);

        if (minutesCount <= lockoutTime) {
            return 0;
        } else if (minutesCount > lockoutTime){
            uint256 percent = SafeMath.div(SafeMath.mul(investments[_address], rate_), 100);
            uint256 different = percent.mul(minutesCount).div(1440);
            uint256 balance = different.sub(withdrawals[_address]);
            return balance;
        }
        return 0;
    }

    /**
    * @dev Withdraw dividends from contract
    */
    function withdraw() public returns (bool) {
        require(joined[msg.sender] > 0, "Non-member.");
        require(address(this).balance > balance, "Treasury cannot support withdrawal.");
        uint256 balance = getBalance(msg.sender);
        uint256 taxedBalance = calculateWithdrawalAmount(balance);

        bounty();

        if (taxedBalance > 0) {
            withdrawn = withdrawn + taxedBalance;
            withdrawals[msg.sender] = withdrawals[msg.sender].add(taxedBalance);
            msg.sender.transfer(taxedBalance);
            emit Withdraw(msg.sender, taxedBalance);
            return true;
        } else {
            return false;
        }
    }

    
    function simulateWithdrawal() public view returns (uint256) {
        uint256 untaxedBalance = getBalance(msg.sender);
        uint256 taxedDividends = calculateWithdrawalAmount(untaxedBalance);

        uint256 refBalance = checkReferral(msg.sender);
        if (refBalance >= minimum) {
            if (address(this).balance > refBalance) {
                taxedDividends = taxedDividends + refBalance;
            }
        }
        return taxedDividends;
    }


    function calculateWithdrawalAmount(uint256 withdrawingAmount) public view returns (uint256){
        uint256 contractBalanceAfterWithdrawal = address(this).balance.sub(withdrawingAmount);
        if (contractBalanceAfterWithdrawal > threshold) {
            return withdrawingAmount;
        } else {
            uint256 percentageOfAmount = SafeMath.div(SafeMath.mul(100, withdrawingAmount), address(this).balance);
            uint256 fee = 100 - (percentageOfAmount * feeMultiplier);
            uint256 withdrawingAmountAfterFee = withdrawingAmount.mul(fee).div(100);
            return withdrawingAmountAfterFee;
        }
    }


    function getDividends(address _player) public view returns (uint256) {
        uint256 refBalance = checkReferral(_player);
        uint256 balance = getBalance(_player);
        return (refBalance + balance);
    }

    /**
    * @dev Bounty reward
    */
    function bounty() public {
        uint256 refBalance = checkReferral(msg.sender);
        if (refBalance >= minimum) {
            if (address(this).balance > refBalance) {
                referrer[msg.sender] = 0;
                msg.sender.transfer(refBalance);
                emit Bounty(msg.sender, refBalance);
            }
        }
    }

    // gets TRX balance of contract
    function totalTronBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
    * @dev Gets balance of the sender address.
    * @return An uint256 representing the amount owned by the msg.sender.
    */
    function checkBalance() public view returns (uint256) {
        return getBalance(msg.sender);
    }


    /**
    * @dev Gets withdrawals of the specified address.
    * @param _investor The address to query the the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    function checkWithdrawals(address _investor) public view returns (uint256) {
        return withdrawals[_investor];
    }

    /**
    * @dev Gets investments of the specified address.
    * @param _investor The address to query the the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
    function checkInvestments(address _investor) public view returns (uint256) {
        return investments[_investor];
    }

    /**
    * @dev Gets referrer balance of the specified address.
    * @param _hunter The address of the referrer
    * @return An uint256 representing the referral earnings.
    */
    function checkReferral(address _hunter) public view returns (uint256) {
        return referrer[_hunter];
    }
}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}
