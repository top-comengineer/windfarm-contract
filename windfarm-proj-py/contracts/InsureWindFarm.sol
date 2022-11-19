// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract InsureWindFarm is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    /* General variables */
    address public client;
    address public insurer;
    address public deployerContractAddress;
    uint16 public insuredDays;
    string public latitude;
    string public longitude;
    bool public active;

    /* Temporal Variables */
    uint256 public duration;
    uint256 public constant DAYS_IN_SECONDS = 86400;
    uint256 public constant HOURS_IN_SECONDS = 3600;
    uint256 policyStartingTimestamp;
    // uint256 newDailyCycleTimestamp;
    uint256 newHourlyCycleTimestamp;

    /* Chainlink */
    bytes32 chainlinkJobId;
    uint256 paymentToOracle;
    // uint paymentToSecondOracle;
    bytes32 public reqId;

    /* Financials */
    uint256 public policyAmount;
    uint256 public premium;
    uint256 public policyAmountPaidToDate;
    uint256 public pingCount;
    uint16 public premiumPaidCounter;

    /* Wind Variables */
    // uint16 public totalDailyPingCount;
    uint16 public totalHourlyPingCount;
    uint16 public latestWindSpeed;
    uint16 public over25kmhCounter;
    uint16 public sub25kmhCounter;
    // uint16 public past24hourSlowWindRate;
    uint16 public pastHourSlowWindRate;

    /* Modifiers */
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

    modifier OnlyDeployer() {
        if (msg.sender != deployerContractAddress) {
            revert InsureWindFarm__NotDeployer();
        }
        _;
    }

    /* Custom Errors */
    error InsureWindFarm__OverpaidPolicy();
    error InsureWindFarm__PolicyAlreadyPaidInFull();
    error InsureWindFarm__NotActive();
    error InsureWindFarm__NotOracle();
    error InsureWindFarm__NotInsurer();
    error InsureWindFarm__NotDeployer();
    error InsureWindFarm__InvalidAmountSent(uint256 amount);
    error InsureWindFarm__InvalidPolicyDuration(uint16 _days);

    /* Struct returned from AccuWeather Oracle */
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

    /* Constructor */
    /**
    @param _link LINK token address
    @param _oracle AccuWeather Oracle Address (Goerli Testnet)
    @param _amount Policy amount purchased by client
    @param _client Wind Farm Insurance client address
    @param _insurer Wind Farm Insurance issuer
    @param _days Duration of policy in days
    @param _latitude Policy location latitude (WGS84 standard)
    @param _longitude Policy location longitude (WGS84 standard)

     */
    constructor(
        address _link,
        address _oracle,
        // address _secondOracle
        uint256 _amount,
        address _client,
        address _insurer,
        address _deployerContract,
        uint16 _days,
        string memory _latitude,
        string memory _longitude
    ) payable {
        if (msg.value < _amount) {
            revert InsureWindFarm__InvalidAmountSent(_amount);
        }
        if (_days <= 0) {
            revert InsureWindFarm__InvalidPolicyDuration(_days);
        }
        client = _client;
        insurer = _insurer;
        deployerContractAddress = _deployerContract;
        duration = _days * DAYS_IN_SECONDS;
        insuredDays = _days;
        latitude = _latitude;
        longitude = _longitude;
        policyAmount = _amount;
        premium = (_amount / 137);
        policyStartingTimestamp = block.timestamp;
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        chainlinkJobId = "7c276986e23b4b1c990d8659bca7a9d0";
        paymentToOracle = 100000000000000000;
        active = true;
    }

    /** @dev Called by Policy Deployer Contract */
    function updateState() external OnlyDeployer {
        if (totalHourlyPingCount == 0) {
            newHourlyCycleTimestamp = block.timestamp;
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
            chainlinkJobId,
            address(this),
            this.fulfillLocationCurrentConditions.selector
        );

        req.add("endpoint", "location-current-conditions");
        req.add("lat", _latitude);
        req.add("lon", _longitude);
        req.add("units", _units);

        reqId = sendChainlinkRequest(req, _payment);
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
        totalHourlyPingCount++;
        if (latestWindSpeed < 250) {
            // 15mph * 1.6 = 25kmh. Accuweather returns windspeed at 10x. 25*10=250
            sub25kmhCounter++; // count of measurements indicating quiet wind
        } else {
            over25kmhCounter++; // count of measurements indicating abundant wind
        }

        if (
            // 12 pings hourly
            totalHourlyPingCount > 11 &&
            block.timestamp > newHourlyCycleTimestamp + HOURS_IN_SECONDS - 300 // (5 minutes * 60) payout calculated after 55 minutes, e.g., after the 12th chainlink call
        ) {
            timelyPaymentCheck();
            getPayoutBool(sub25kmhCounter, over25kmhCounter);
            resetTheHour();
        }
    }

    function timelyPaymentCheck() internal {
        uint256 elapsedPolicyDurationInDays = (block.timestamp -
            policyStartingTimestamp +
            900) / DAYS_IN_SECONDS;
        if (policyAmountPaidToDate < premium * elapsedPolicyDurationInDays) {
            transferFundsToInsurer();
            active = false;
        }
    }

    function getPayoutBool(uint16 sub25, uint16 over25)
        internal
        returns (bool payoutImminent)
    {
        // % of slow wind today = count of slow winds, divided by total number of counts (96) * 100
        pastHourSlowWindRate = (sub25 * 100) / (sub25 + over25);

        // if wind is slower than 25kmh for 25% of the day (6hr/24+ ping counts), payout is true and called immediately
        payoutImminent = pastHourSlowWindRate >= 25;
        if (payoutImminent == true) {
            payoutFunction();
        }
        return payoutImminent;
    }

    function resetTheHour() internal ContractActive {
        totalHourlyPingCount = 0;
        sub25kmhCounter = 0;
        over25kmhCounter = 0;
    }

    function payoutFunction() internal ContractActive {
        uint256 hourlyPayout = (policyAmount / insuredDays) / 24;
        payable(client).transfer(hourlyPayout);
        // if policy is over, time to close it and send insurer remainder of the balance
        if (block.timestamp > duration + policyStartingTimestamp) {
            concludePolicy();
        }
    }

    function concludePolicy() internal ContractActive {
        // total of 8640 pings for a 30 day policy. allowance of 30 unexecuted pings
        if (pingCount >= ((duration * 24 * 12) / DAYS_IN_SECONDS) - 30) {
            transferFundsToInsurer();
        } else {
            payable(client).transfer(premium * insuredDays * 3);
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

    function getPolicyAmount() public view returns (uint256) {
        return policyAmount;
    }

    function getPremium() public view returns (uint256) {
        return premium;
    }

    function getLatestWindSpeed() public view returns (uint16) {
        return latestWindSpeed;
    }

    function getPolicyAmountPaidToDate() public view returns (uint256) {
        return policyAmountPaidToDate;
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
