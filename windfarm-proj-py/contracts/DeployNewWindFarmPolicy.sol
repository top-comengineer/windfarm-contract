// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./InsureWindFarm.sol";

contract DeployNewWindFarmPolicy {
    address[] public insurancePolicies;
    mapping(address => address[]) public insurerOwnership;
    mapping(address => address[]) public clientOwnership;

    function newWindFarm(
        address _link,
        address _oracle,
        uint _amount,
        address _client,
        uint16 _days,
        string memory _lat,
        string memory _lon
    ) external payable {
        InsureWindFarm newFarm = (new InsureWindFarm){value: _amount}(
            _link,
            _oracle,
            _amount,
            _client,
            msg.sender,
            _days,
            _lat,
            _lon
        );
        address policyAddress = address(newFarm);
        insurancePolicies.push(policyAddress);
        insurerOwnership[msg.sender].push(policyAddress);
        clientOwnership[_client].push(policyAddress);
    }

    function getInsurancePolicies() public view returns (address[] memory) {
        return insurancePolicies;
    }

    function updateStateOfAllContracts() external {
        for (uint i = 0; i < insurancePolicies.length; i++) {
            InsureWindFarm policy = InsureWindFarm(insurancePolicies[i]);
            policy.updateState();
        }
    }

    function expiryCheckOfAllContracts() external {
        for (uint i = 0; i < insurancePolicies.length; i++) {
            InsureWindFarm policy = InsureWindFarm(insurancePolicies[i]);
            policy.expiryCheck();
        }
    }

    function getInsurerPolicies() public view returns (address[] memory) {
        return insurerOwnership[msg.sender];
    }

    function getClientPolicies() public view returns (address[] memory) {
        return clientOwnership[msg.sender];
    }
}
