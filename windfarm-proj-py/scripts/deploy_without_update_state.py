from brownie import (
    WindFarmPolicyDeployer,
    InsureWindFarm,
    accounts,
    network,
    config,
    Contract,
    interface,
    LinkToken,
)
from web3 import Web3

POLICY_AMOUNT = Web3.toWei(0.03, "ether")
POLICY_LENGTH_IN_DAYS = 30
PREMIUM_AMOUNT = (POLICY_AMOUNT * 5) / 1000
LINK_AMOUNT = 5000000000000000000
LOCATION_LATITUDE = "49.703168"
LOCATION_LONGITUDE = "-125.630035"


def deploy_wind_farm_policy():
    insurer = accounts.add(config["wallets"]["from_key"])
    client = accounts.add(config["wallets"]["second_key"])
    print("Deploying policy deployer contract...")

    wind_farm_policy_deployer = WindFarmPolicyDeployer.deploy({"from": insurer})
    print(
        f"Policy deployer contract deployed to:",
        wind_farm_policy_deployer.address,
        "by",
        insurer.address,
    )

    print("Deploying client's wind farm policy contract...")
    new_farm_contract = wind_farm_policy_deployer.newWindFarm(
        config["networks"][network.show_active()]["link_token"],
        config["networks"][network.show_active()]["accuweather_oracle"],
        POLICY_AMOUNT,
        client.address,
        POLICY_LENGTH_IN_DAYS,
        LOCATION_LATITUDE,
        LOCATION_LONGITUDE,
        {"from": insurer, "value": POLICY_AMOUNT},
    )
    new_farm_contract.wait(2)
    # deployed_policies = wind_farm_policy_deployer.getDeployedPolicies()
    # new_farm_address = deployed_policies[-1]
    print(f"New wind farm policy deployed to:", new_farm_contract.address)
    print(f"Insurance policy client:", client.address)
    # new_farm_contract = Contract.from_abi(
    #     "InsureWindFarm", new_farm_address, InsureWindFarm.abi
    # )
    link_token_fund(
        new_farm_contract.address,
        insurer,
        config["networks"][network.show_active()]["link_token"],
        LINK_AMOUNT,
    )


def main():
    deploy_wind_farm_policy()


def link_token_fund(contract_address, account, link_token, amount):
    print(f"Attempting to fund contract with {LINK_AMOUNT/10**18} LINK...")
    tx = interface.LinkTokenInterface(link_token).transfer(
        contract_address, amount, {"from": account}
    )
    tx.wait(1)
    print(f"Successfully funded policy contract with {amount} LINK.")
    return tx
