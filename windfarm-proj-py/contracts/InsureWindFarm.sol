// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract InsureWindFarm is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    address public insurer;
    address public client;
    uint256 public duration;
    string public latitude;
    string public longitude;
    uint256 public constant DAYS_IN_SECONDS = 86400;
    uint256 startTime;
    uint256 todaysStartTime; // timestamp of the new daily cycle
    bytes32 jobIdLocationCurrentCondition = "7c276986e23b4b1c990d8659bca7a9d0";
    uint256 paymentToOracle;
    // uint paymentToSecondOracle;
    uint256 public policyAmount;
    uint256 public premium;
    uint256 public policyAmountPaidToDate;
    bool public active;
    uint256 public pingCount;
    bytes32 public reqId;
    uint16 public premiumPaidCounter;
    uint16 public insuredDays;
    uint16 public totalDailyPingCount;
    uint16 public latestWindSpeed;
    uint16 public over25kmhCounter;
    uint16 public sub25kmhCounter;
    uint16 public past24hourSlowWindRate;

    modifier ContractActive() {
        if (!active) {
            revert InsureWindFarm__NotActive();
        }
        _;
    }

    modifier OnlyOracle() {
        if (msg.sender != getOracleAddress()) {
            revert InsureWindFarm__NotOracle();
        }
        _;
    }

    modifier OnlyInsurer() {
        if (msg.sender != insurer) {
            revert InsureWindFarm__NotInsurer();
        }
        _;
    }

    error InsureWindFarm__OverpaidPolicy();
    error InsureWindFarm__PolicyAlreadyPaidInFull();
    error InsureWindFarm__NotActive();
    error InsureWindFarm__NotOracle();
    error InsureWindFarm__NotInsurer();
    error InsureWindFarm__InvalidAmountSent(uint256 amount);

    struct CurrentConditionsResult {
        uint256 timestamp;
        uint24 precipitationPast12Hours;
        uint24 precipitationPast24Hours;
        uint24 precipitationPastHour;
        uint24 pressure;
        int16 temperature;
        uint16 windDirectionDegrees;
        uint16 windSpeed;
        uint8 precipitationType;
        uint8 relativeHumidity;
        uint8 uvIndex;
        uint8 weatherIcon;
    }

    constructor(
        address _link,
        address _oracle,
        // address _secondOracle
        uint256 _amount,
        address _client,
        address _insurer,
        uint16 _days,
        string memory _latitude,
        string memory _longitude
    ) payable {
        if (msg.value < _amount) {
            revert InsureWindFarm__InvalidAmountSent(_amount);
        }
        insurer = _insurer;
        client = _client;
        duration = _days * DAYS_IN_SECONDS;
        latitude = _latitude;
        longitude = _longitude;
        premium = ((_amount * 5) / 1000);
        startTime = block.timestamp;
        policyAmount = _amount;
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        jobIdLocationCurrentCondition = "7c276986e23b4b1c990d8659bca7a9d0";
        paymentToOracle = 100000000000000000;
        active = true;
    }

    function updateState() external {
        if (totalDailyPingCount == 0) {
            todaysStartTime = block.timestamp;
        }
        string memory metric = "metric";
        requestLocationCurrentConditions(
            paymentToOracle,
            latitude,
            longitude,
            metric
        );
    }

    function requestLocationCurrentConditions(
        uint256 _payment,
        string memory _latitude,
        string memory _longitude,
        string memory _units
    ) internal {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobIdLocationCurrentCondition,
            address(this),
            this.fulfillLocationCurrentConditions.selector
        );

        req.add("endpoint", "location-current-conditions");
        req.add("lat", _latitude);
        req.add("lon", _longitude);
        req.add("units", _units);

        reqId = sendChainlinkRequest(req, _payment);
    }

    // premium should be paid daily, before that day's payout occurs
    // !! unless client pays more than the minimum premium amount !!
    // client is also able to pre-pay, whether that be slightly bigger chunks or all at once in full

    function timelyPaymentCheck() internal {
        uint256 elapsedPolicyDurationInDays = (block.timestamp -
            startTime +
            900) / DAYS_IN_SECONDS;
        if (policyAmountPaidToDate < premium * elapsedPolicyDurationInDays) {
            transferFundsToInsurer();
            active = false;
        }
    }

    function fulfillLocationCurrentConditions(
        bytes32 _requestId,
        bool _locationFound,
        bytes memory _locationResult,
        bytes memory _currentConditionsResult
    ) public recordChainlinkFulfillment(_requestId) OnlyOracle {
        if (_locationFound) {
            storeCurrentConditionsResult(_requestId, _currentConditionsResult);
        }
    }

    function storeCurrentConditionsResult(
        bytes32 _requestId,
        bytes memory _currentConditionsResult
    ) private {
        CurrentConditionsResult memory result = abi.decode(
            _currentConditionsResult,
            (CurrentConditionsResult)
        );
        latestWindSpeed = result.windSpeed;
        pingCount++;

        totalDailyPingCount++;
        if (latestWindSpeed < 250) {
            // 15mph * 1.6 = 25kmh. Accuweather returns windspeed at 10x. 25*10=250
            sub25kmhCounter++; // count of measurements indicating quiet wind
        } else {
            over25kmhCounter++; // count of measurements indicating abundant wind
        }

        if (
            // 24 hours * 4 pings hourly = 96 pings daily
            totalDailyPingCount > 95 &&
            block.timestamp > todaysStartTime + DAYS_IN_SECONDS - 900 // (15 minutes * 60) payout technically calculated after 23 hours 45 minutes, e.g., after the 96th call
        ) {
            timelyPaymentCheck();
            getPayoutBool(sub25kmhCounter, over25kmhCounter);
            resetTheDay();
        }
    }

    function getPayoutBool(uint16 sub25, uint16 over25)
        public
        returns (bool payoutImminent)
    {
        // % of slow wind today = count of slow winds, divided by total number of counts (96) * 100
        past24hourSlowWindRate = (sub25 * 100) / (sub25 + over25);

        // if wind is slower than 25kmh for 25% of the day (6hr), payout is true and called immediately
        payoutImminent = past24hourSlowWindRate >= 25;
        if (payoutImminent == true) {
            payoutFunction();
        }
        return payoutImminent;
    }

    function resetTheDay() internal ContractActive {
        totalDailyPingCount = 0;
        sub25kmhCounter = 0;
        over25kmhCounter = 0;
    }

    function payoutFunction() internal ContractActive {
        // paying out in increments on the days that wind is scarce
        uint256 dailyPayout = policyAmount / insuredDays;
        payable(client).transfer(dailyPayout);
        // if policy is over, time to close it and repay insurer remainder of the balance
        if (block.timestamp > duration + startTime) {
            concludePolicy();
        }
    }

    function concludePolicy() internal ContractActive {
        // total of 2880 pings for a 30 day policy. allowance of 10 unexecuted pings
        if (pingCount >= ((duration * 24 * 4) / DAYS_IN_SECONDS) - 10) {
            transferFundsToInsurer();
        } else {
            payable(client).transfer(premium * insuredDays * 2);
            transferFundsToInsurer();
        }
        active = false;
    }

    function transferFundsToInsurer() internal {
        payable(insurer).transfer(address(this).balance);
    }

    function getCurrentSlowWindRate() public view returns (uint16) {
        uint16 rate = sub25kmhCounter / (sub25kmhCounter + over25kmhCounter);
        return rate;
    }

    function getPolicyCoordinates()
        public
        view
        returns (string memory, string memory)
    {
        return (latitude, longitude);
    }

    function getLatestWindSpeed() public view returns (uint16) {
        return latestWindSpeed;
    }

    function getOracleAddress() public view returns (address) {
        return chainlinkOracleAddress();
    }

    function getLinkBalance() public view returns (uint256) {
        LinkTokenInterface linkToken = LinkTokenInterface(
            chainlinkTokenAddress()
        );
        return linkToken.balanceOf(address(this));
    }

    function withdrawLink() public OnlyInsurer {
        LinkTokenInterface linkToken = LinkTokenInterface(
            chainlinkTokenAddress()
        );
        require(
            linkToken.transfer(msg.sender, linkToken.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    function payPremium() external payable {
        // premium should be paid daily, before that day's payout occurs, unless client pays more than the minimum premium amount
        // client is also able to pre-pay for the rest of his policy in advance
        if (msg.value + policyAmountPaidToDate > policyAmount) {
            revert InsureWindFarm__OverpaidPolicy();
        }
        if (premiumPaidCounter >= insuredDays) {
            revert InsureWindFarm__PolicyAlreadyPaidInFull();
        }
        if ((policyAmount - policyAmountPaidToDate) < premium) {
            recordPayment();
        } else {
            if (msg.value < premium) {
                revert InsureWindFarm__InvalidAmountSent(msg.value);
            } else {
                recordPayment();
            }
        }
    }

    function recordPayment() internal {
        premiumPaidCounter++;
        policyAmountPaidToDate += msg.value;
    }
}
