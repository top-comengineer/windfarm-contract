// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./InsureWindFarm.sol";

contract WindFarmPolicyDeployer {
    mapping(address => address[]) public policiesByClient;
    mapping(address => address[]) public policiesByInsurer;

    address[] public deployedPolicies;

    function newWindFarm(
        address _link,
        address _oracle,
        // address _secondOracle,
        uint256 _amount,
        address _client,
        uint16 _days,
        string memory _latitude,
        string memory _longitude
    ) external payable {
        InsureWindFarm newFarm = (new InsureWindFarm){value: _amount}(
            _link,
            _oracle,
            // _secondOracle,
            _amount,
            _client,
            msg.sender,
            address(this),
            _days,
            _latitude,
            _longitude
        );
        address policyAddress = address(newFarm);
        deployedPolicies.push(policyAddress);
        policiesByInsurer[msg.sender].push(policyAddress);
        policiesByClient[_client].push(policyAddress);
    }

    /** @dev Called by Chainlink Automation Time-based Upkeep */
    function updatePolicyStates() external {
        for (uint256 i = 0; i < deployedPolicies.length; i++) {
            InsureWindFarm policy = InsureWindFarm(deployedPolicies[i]);
            policy.updateState();
        }
    }

    function getDeployedPolicies() public view returns (address[] memory) {
        return deployedPolicies;
    }

    function getInsurerPolicies() public view returns (address[] memory) {
        return policiesByInsurer[msg.sender];
    }

    function getClientPolicies() public view returns (address[] memory) {
        return policiesByClient[msg.sender];
    }
}
