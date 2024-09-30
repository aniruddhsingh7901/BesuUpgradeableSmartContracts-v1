import fs from "fs";
import path from "path";
import { DeployHelper } from "../helpers/DeployHelper";
import hre, { ethers, network } from "hardhat";
import { getConfig } from "../helpers/helperUtils";

async function main() {
  const config = getConfig();
  const stateAddress = config.stateContractAddress;
  if (!ethers.isAddress(stateAddress)) {
    throw new Error("STATE_CONTRACT_ADDRESS is not set");
  }

  const validators: ("mtpV2" | "sigV2" | "v3")[] = ["mtpV2", "sigV2", "v3"];
  const deployStrategy: "basic" | "create2" =
    config.deployStrategy == "create2" ? "create2" : "basic";
  const [signer] = await hre.ethers.getSigners();

  const deployHelper = await DeployHelper.initialize(null, true);

  const validatorsInfo: any = [];
  for (const v of validators) {
    const { validator, groth16VerifierWrapper } = await deployHelper.deployValidatorContracts(
      v,
      stateAddress,
      deployStrategy,
    );
    validatorsInfo.push({
      validatorType: v,
      validator: await validator.getAddress(),
      groth16verifier: await groth16VerifierWrapper.getAddress(),
    });
    const blockNumberDeployed = await hre.ethers.provider.getBlockNumber();
    let blockNumber = blockNumberDeployed;
    console.log("Waiting some blocks to expect at least 5 confirmations for ignition...");
    while (blockNumber < blockNumberDeployed + 10) {
      await new Promise((resolve) => setTimeout(resolve, 5000));
      blockNumber = await hre.ethers.provider.getBlockNumber();
    }
  }

  const chainId = parseInt(await network.provider.send("eth_chainId"), 16);
  const networkName = hre.network.name;
  const pathOutputJson = path.join(
    __dirname,
    `./deploy_validators_output_${chainId}_${networkName}.json`,
  );
  const outputJson = {
    proxyAdminOwnerAddress: await signer.getAddress(),
    validatorsInfo,
    network: networkName,
    chainId,
  };
  fs.writeFileSync(pathOutputJson, JSON.stringify(outputJson, null, 1));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
