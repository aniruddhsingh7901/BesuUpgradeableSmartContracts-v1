import {
  getProviders,
  getStateContractAddress,
  isContract,
  Logger,
} from "../../../helpers/helperUtils";
import { contractsInfo, ORACLE_SIGNING_ADDRESS_PRODUCTION } from "../../../helpers/constants";
import { ethers } from "hardhat";

async function main() {
  const providers = getProviders();

  for (const provider of providers) {
    const jsonRpcProvider = new ethers.JsonRpcProvider(provider.rpcUrl);

    const stateContractAddress = getStateContractAddress();

    let oracleSigningAddressIsValid = true;
    const defaultOracleSigningAddress = ORACLE_SIGNING_ADDRESS_PRODUCTION; // production signing address

    if (!(await isContract(stateContractAddress, jsonRpcProvider))) {
      oracleSigningAddressIsValid = false;
    } else {
      const wallet = new ethers.Wallet(process.env.PRIVATE_KEY as string, jsonRpcProvider);
      const state = await ethers.getContractAt(
        contractsInfo.STATE.name,
        stateContractAddress,
        wallet,
      );
      let oracleSigningAddress;
      try {
        const crossChainProofValidatorAddress = await state.getCrossChainProofValidator();

        const crossChainProofValidator = await ethers.getContractAt(
          contractsInfo.CROSS_CHAIN_PROOF_VALIDATOR.name,
          crossChainProofValidatorAddress,
          wallet,
        );
        oracleSigningAddress = await crossChainProofValidator.getOracleSigningAddress();
      } catch (error) {}
      if (oracleSigningAddress !== defaultOracleSigningAddress) {
        oracleSigningAddressIsValid = false;
      }
    }

    if (!oracleSigningAddressIsValid) {
      Logger.error(`${provider.network}: Oracle signing address is not valid`);
    } else {
      Logger.success(`${provider.network}: Oracle signing address is valid`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
