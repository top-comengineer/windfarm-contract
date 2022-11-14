from brownie import (
    DeployNewWindFarmPolicy,
    InsureWindFarm,
    accounts,
    network,
    config,
    Contract,
)
from web3 import Web3

POLICY_AMOUNT = Web3.toWei(0.03, "ether")
POLICY_LENGTH_IN_DAYS = 30
PREMIUM_AMOUNT = (POLICY_AMOUNT * 5) / 1000
LOCATION_LATITUDE = "49.703168"
LOCATION_LONGITUDE = "-125.630035"


def deploy_wind_farm_policy():
    insurer = accounts.add(config["wallets"]["from_key"])
    client = accounts.add(config["wallets"]["second_key"])
    print("Deploying policy deployer contract...")

    wind_farm_policy_deployer = DeployNewWindFarmPolicy.deploy({"from": insurer})
    print(
        f"Policy deployer contract deployed to:",
        wind_farm_policy_deployer.address,
        "by",
        insurer.address,
    )

    print("Deploying client's wind farm policy contract...")
    tx = wind_farm_policy_deployer.newWindFarm(
        config["networks"][network.show_active()]["link_token"],
        config["networks"][network.show_active()]["accuweather_oracle"],
        POLICY_AMOUNT,
        client.address,
        POLICY_LENGTH_IN_DAYS,
        LOCATION_LATITUDE,
        LOCATION_LONGITUDE,
        {"from": insurer, "value": POLICY_AMOUNT},
    )
    tx.wait(2)
    insurance_policies = wind_farm_policy_deployer.getInsurancePolicies()
    new_farm_address = insurance_policies[-1]
    print(f"New wind farm policy deployed to:", new_farm_address)
    print(f"Insurance policy client:", client.address)
    new_farm_contract = Contract.from_abi(
        "InsureWindFarm", new_farm_address, InsureWindFarm.abi
    )
    print("Attempting to update state on client's contract...")
    tx2 = wind_farm_policy_deployer.updateStateOfAllContracts(
        {"from": insurer, "gasPrice": 100000000000000000}
    )
    # tx2 = new_farm_contract.updateState({"from": insurer})
    tx2.wait(2)
    print("Done... or is it?")

    print("Client is attempting to pay for today's insurance premium...")
    tx3 = new_farm_contract.payPremium({"from": client, "value": PREMIUM_AMOUNT})
    tx3.wait(2)
    print("Insurance premium paid..!")

    print("Attempting to query client's contract for the recent local wind speed...")
    windSpeedInStrathcona = new_farm_contract.getLatestWindSpeed({"from": insurer})
    windSpeedInStrathcona.wait(2)
    speed = windSpeedInStrathcona / 10

    print(f"The current wind speed in Strathcona Park is ", speed, "km/h!")


def main():
    deploy_wind_farm_policy()
