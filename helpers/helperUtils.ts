import { Contract, ContractTransactionResponse, JsonRpcProvider } from "ethers";
import hre, { ethers, network } from "hardhat";
import fs from "fs";
import { CONTRACT_NAMES, NETWORK_NAMES, UNIFIED_CONTRACT_ADDRESSES } from "./constants";
import { poseidonContract } from "circomlibjs";

export function getConfig() {
  return {
    deployStrategy: process.env.DEPLOY_STRATEGY || "",
    ledgerAccount: process.env.LEDGER_ACCOUNT || "",
    stateContractAddress: process.env.STATE_CONTRACT_ADDRESS || "",
  };
}

export async function waitNotToInterfereWithHardhatIgnition(
  tx: ContractTransactionResponse | null | undefined,
): Promise<void> {
  const isLocalNetwork = ["localhost", "hardhat"].includes(network.name);
  const confirmationsNeeded = isLocalNetwork
    ? 1
    : (hre.config.ignition?.requiredConfirmations ?? 1);

  if (tx) {
    console.log(
      `Waiting for ${confirmationsNeeded} confirmations to not interfere with Hardhat Ignition`,
    );
    await tx.wait(confirmationsNeeded);
  } else if (isLocalNetwork) {
    console.log(`Mining ${confirmationsNeeded} blocks not to interfere with Hardhat Ignition`);
    for (const _ of Array.from({ length: confirmationsNeeded })) {
      await hre.ethers.provider.send("evm_mine");
    }
  } else {
    const blockNumberDeployed = await hre.ethers.provider.getBlockNumber();
    let blockNumber = blockNumberDeployed;
    console.log("Waiting some blocks to expect at least 5 confirmations for Hardhat Ignition...");
    while (blockNumber < blockNumberDeployed + 10) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      blockNumber = await hre.ethers.provider.getBlockNumber();
    }
  }
}

export function removeLocalhostNetworkIgnitionFiles(network: string, chainId: number | undefined) {
  if (network === "localhost" || network === "hardhat") {
    console.log("Removing previous ignition files for chain: ", chainId);
    fs.rmSync(`./ignition/deployments/chain-${chainId}`, { recursive: true, force: true });
  }
}

export async function isContract(
  contractAddress: any,
  provider?: JsonRpcProvider,
): Promise<boolean> {
  if (!hre.ethers.isAddress(contractAddress)) {
    return false;
  }
  let result;
  if (provider) {
    result = await provider.getCode(contractAddress);
  } else {
    result = await hre.ethers.provider.getCode(contractAddress);
  }
  if (result === "0x") {
    return false;
  }
  return true;
}

export function getProviders() {
  return [
    { network: NETWORK_NAMES.PRIVADO_TEST, rpcUrl: process.env.PRIVADO_TEST_RPC_URL as string },
    { network: NETWORK_NAMES.PRIVADO_MAIN, rpcUrl: process.env.PRIVADO_MAIN_RPC_URL as string },
    { network: NETWORK_NAMES.POLYGON_AMOY, rpcUrl: process.env.POLYGON_AMOY_RPC_URL as string },
    {
      network: NETWORK_NAMES.POLYGON_MAINNET,
      rpcUrl: process.env.POLYGON_MAINNET_RPC_URL as string,
    },
    {
      network: NETWORK_NAMES.ETHEREUM_SEPOLIA,
      rpcUrl: process.env.ETHEREUM_SEPOLIA_RPC_URL as string,
    },
    {
      network: NETWORK_NAMES.ETHEREUM_MAINNET,
      rpcUrl: process.env.ETHEREUM_MAINNET_RPC_URL as string,
    },
    { network: NETWORK_NAMES.ZKEVM_CARDONA, rpcUrl: process.env.ZKEVM_CARDONA_RPC_URL as string },
    { network: NETWORK_NAMES.ZKEVM_MAINNET, rpcUrl: process.env.ZKEVM_MAINNET_RPC_URL as string },
    { network: NETWORK_NAMES.LINEA_SEPOLIA, rpcUrl: process.env.LINEA_SEPOLIA_RPC_URL as string },
    { network: NETWORK_NAMES.LINEA_MAINNET, rpcUrl: process.env.LINEA_MAINNET_RPC_URL as string },
  ];
}

function getUnifiedContractAddress(contractName: string): string {
  let contractProperty;
  for (const property in CONTRACT_NAMES) {
    if (CONTRACT_NAMES[property] === contractName) {
      contractProperty = property;
      break;
    }
  }
  return UNIFIED_CONTRACT_ADDRESSES[contractProperty];
}

export async function getPoseidonN(nInputs: number): Promise<Contract | null> {
  const abi = poseidonContract.generateABI(nInputs);
  const contractAddress = getUnifiedContractAddress(`PoseidonUnit${nInputs}L`);

  if (!(await isContract(contractAddress))) {
    return null;
  }
  const poseidon = new ethers.Contract(contractAddress, abi);

  return poseidon;
}

export async function getUnifiedContract(contractName: string): Promise<Contract | null> {
  if (contractName.includes("PoseidonUnit")) {
    const nInputs = parseInt(contractName.substring(12, 13));
    return getPoseidonN(nInputs);
  } else {
    const contractAddress = getUnifiedContractAddress(contractName);
    if (!(await isContract(contractAddress))) {
      return null;
    }
    return ethers.getContractAt(contractName, contractAddress);
  }
}

export class Logger {
  static error(message: string) {
    console.log(`\x1b[31m[𐄂] \x1b[0m${message}`);
  }

  static success(message: string) {
    console.log(`\x1b[32m[✓] \x1b[0m${message}`);
  }

  static warning(message: string) {
    console.log(`\x1b[33m[⚠] \x1b[0m${message}`);
  }
}

export class TempContractDeployments {
  contracts: Map<string, string>;
  filePath: string;

  constructor(filePath: string) {
    this.contracts = new Map<string, string>();
    this.filePath = filePath;
    this.load();
  }

  addContract(contractName: string, contractAddress: string) {
    this.contracts.set(contractName, contractAddress);
    this.save();
  }

  async getContract(contractName: string): Promise<Contract | null> {
    if (!this.contracts.has(contractName)) {
      return null;
    }
    const contractAddress = this.contracts.get(contractName) as string;
    if (!(await isContract(contractAddress))) {
      return null;
    }
    return ethers.getContractAt(contractName, contractAddress);
  }

  save() {
    fs.writeFileSync(this.filePath, JSON.stringify(Array.from(this.contracts.entries()), null, 1));
  }

  load() {
    if (fs.existsSync(this.filePath)) {
      const data = fs.readFileSync(this.filePath, "utf8");
      this.contracts = new Map(JSON.parse(data));
    }
  }

  remove() {
    fs.rmSync(this.filePath);
  }
}
