// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract InsureWindFarm is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    address public insurer;
    address public client;
    uint public duration;
    string public lat;
    string public lon;
    uint256 public premium;
    uint256 public constant DAYS_IN_SECONDS = 86400;
    uint256 startTime;
    bytes32 jobIdLocationCurrentCondition = "7c276986e23b4b1c990d8659bca7a9d0";
    uint256 paymentToOracle;
    uint public amount;
    bool public active;
    uint256 public requestCount;
    bytes32 public reqId;
    bytes32 public requestIdLocationkey;
    uint16 public premiumCounter;
    uint16 public insuredDays;
    uint16 public totalDailyRequestCount;
    uint16 public latestWindSpeed;
    uint16 public over25kmhCounter;
    uint16 public sub25kmhCounter;
    uint16 public past24hourSlowWindRate;

    modifier ContractActive() {
        require(active, "Contract not active");
        _;
    }

    modifier OnlyOracle() {
        require(
            msg.sender == getOracleAddress(),
            "Only Oracle can call this function"
        );
        _;
    }

    modifier OnlyInsurer() {
        require(msg.sender == insurer, "Only insurer can call this function");
        _;
    }

    error InsureWindFarm__NotExpired();

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

    mapping(bytes32 => CurrentConditionsResult)
        public requestIdCurrentConditionsResult;

    constructor(
        address _link,
        address _oracle,
        uint _amount,
        address _client,
        address _insurer,
        uint16 _days,
        string memory _lat,
        string memory _lon
    ) payable {
        require(
            msg.value >= _amount,
            "Value sent doesn't reflect policy amount"
        );
        insurer = _insurer;
        client = _client;
        duration = _days * DAYS_IN_SECONDS;
        lat = _lat;
        lon = _lon;
        premium = ((_amount * 5) / 1000);
        startTime = block.timestamp;
        amount = _amount;
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        jobIdLocationCurrentCondition = "7c276986e23b4b1c990d8659bca7a9d0";
        paymentToOracle = 100000000000000000;
        active = true;
        premiumCounter = _days;
    }

    //
    function updateState() external {
        string memory metric = "metric";
        requestLocationCurrentConditions(paymentToOracle, lat, lon, metric);
    }

    function requestLocationCurrentConditions(
        uint256 _payment,
        string memory _lat,
        string memory _lon,
        string memory _units
    ) internal {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobIdLocationCurrentCondition,
            address(this),
            this.fulfillLocationCurrentConditions.selector
        );

        req.add("endpoint", "location-current-conditions");
        req.add("lat", _lat);
        req.add("lon", _lon);
        req.add("units", _units);

        reqId = sendChainlinkRequest(req, _payment);
    }

    function checkForfeiture() external {
        uint16 counter = premiumCounter;
        uint256 currentblocktimestamp = block.timestamp;
        uint _duration = duration;
        uint256 starttime = startTime;
        uint16 _days = insuredDays;
        for (uint256 i = _days; i > 0; i--) {
            if (
                currentblocktimestamp > _duration + starttime &&
                counter > _days - i
            ) {
                forfeiture();
            }
        }
    }

    function forfeiture() internal {
        payable(insurer).transfer(address(this).balance);
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
        requestIdCurrentConditionsResult[_requestId] = result;
        latestWindSpeed = result.windSpeed;
        requestCount++;

        totalDailyRequestCount++;
        if (latestWindSpeed < 250) {
            // 15mph * 1.6 = 25kmh. Accuweather returns windspeed at 10x. 25*10=250
            sub25kmhCounter++; // count of measurements indicating quiet wind
        } else {
            over25kmhCounter++; // count of measurements indicating abundant wind
        }

        if (totalDailyRequestCount > 95) {
            // 24 hours * 4 requests hourly = 96 requests
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
        totalDailyRequestCount = 0;
        sub25kmhCounter = 0;
        over25kmhCounter = 0;
    }

    function payoutFunction() internal ContractActive {
        // paying out in increments on the days that wind is scarce
        uint dailyPayout = amount / insuredDays;
        payable(client).transfer(dailyPayout);
        // if policy is over, time to close it and repay insurer remainder of the balance
        if (block.timestamp > duration + startTime) {
            repayInsurer();
        }
    }

    function repayInsurer() internal ContractActive {
        // requiring that the policy is over so that this can't be called by expiryCheck() 10 requests too early
        require(block.timestamp > duration + startTime);
        // total of 2880 requests for a 30 day policy. allowance of 10 unexecuted requests
        if (requestCount >= ((duration * 24 * 4) / DAYS_IN_SECONDS) - 10) {
            payable(insurer).transfer(address(this).balance);
        } else {
            payable(client).transfer(premium * insuredDays * 2);
            payable(insurer).transfer(address(this).balance);
        }
        active = false;
    }

    function expiryCheck() external {
        if (block.timestamp < startTime + duration) {
            revert InsureWindFarm__NotExpired();
        }
        repayInsurer();
    }

    function getLatestWindSpeed() public view returns (uint16) {
        return latestWindSpeed;
    }

    function getOracleAddress() public view returns (address) {
        return chainlinkOracleAddress();
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
        require(msg.value == premium, "Must send exact premium amount");
        premiumCounter -= 1;
    }
}
