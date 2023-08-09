import { DeployHelper } from "../../../helpers/DeployHelper";
import { ethers } from "hardhat";
import { StateContractMigrationHelper } from "../../../helpers/StateContractMigrationHelper";
import fs from "fs";
import { Contract } from "ethers";

/*
1. add contract addtess in `contractAddress` variable and old contract ABI in `oldContractABI`
2. run this script
*/

async function main() {
    const signers = await ethers.getSigners();
    const deployHelper = await DeployHelper.initialize(null, true);
    const network = process.env.HARDHAT_NETWORK;

    const oldContractABI = [];  // abi of contract that will be upgraded
    const contractAddress = "0xaC9fCBA56E42d5960f813B9D0387F3D3bC003338";  // address of contract that will be upgraded
    const mtpValidator = await ethers.getContractAt(
      oldContractABI,
      contractAddress,
      signers[0]
    );

    const validator = await deployHelper.upgradeValidator(contractAddress, 'CredentialAtomicQueryMTPValidator');

    console.log("Contract Upgrade Finished");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
