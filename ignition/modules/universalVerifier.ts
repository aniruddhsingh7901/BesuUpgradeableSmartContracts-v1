import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { create2AddressesInfo } from "../../helpers/constants";

/**
 * This is the first module that will be run. It deploys the proxy and the
 * proxy admin, and returns them so that they can be used by other modules.
 */
const UniversalVerifierProxyModule = buildModule("UniversalVerifierProxyModule", (m) => {
  // This address is the owner of the ProxyAdmin contract,
  // so it will be the only account that can upgrade the proxy when needed.
  const proxyAdminOwner = m.getAccount(0);

  // This contract is supposed to be deployed to the same address across many networks,
  // so the first implementation address is a dummy contract that does nothing but accepts any calldata.
  // Therefore, it is a mechanism to deploy TransparentUpgradeableProxy contract
  // with constant constructor arguments, so predictable init bytecode and predictable CREATE2 address.
  // Subsequent upgrades are supposed to switch this proxy to the real implementation.

  const proxy = m.contract("TransparentUpgradeableProxy", [
    create2AddressesInfo.anchorAddress,
    proxyAdminOwner,
    create2AddressesInfo.contractsCalldataMap.get("UniversalVerifier") as string,
  ]);

  // We need to get the address of the ProxyAdmin contract that was created by the TransparentUpgradeableProxy
  // so that we can use it to upgrade the proxy later.
  const proxyAdminAddress = m.readEventArgument(proxy, "AdminChanged", "newAdmin");

  // Here we use m.contractAt(...) to create a contract instance for the ProxyAdmin that we can interact with later to upgrade the proxy.
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  // Return the proxy and proxy admin so that they can be used by other modules.
  return { proxyAdmin, proxy };
});

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Demo contract using the proxy from the previous module.
 */
export const UniversalVerifierModule = buildModule("UniversalVerifierModule", (m) => {
  // Get the proxy and proxy admin from the previous module.
  const { proxy, proxyAdmin } = m.useModule(UniversalVerifierProxyModule);

  // Here we're using m.contractAt(...) a bit differently than we did above.
  // While we're still using it to create a contract instance, we're now telling Hardhat Ignition
  // to treat the contract at the proxy address as an instance of the Demo contract.
  // This allows us to interact with the underlying Demo contract via the proxy from within tests and scripts.
  const universalVerifier = m.contractAt("UniversalVerifier", proxy);

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { universalVerifier, proxy, proxyAdmin };
});
