import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";

/**
 * This is the first module that will be run. It deploys the proxy and the
 * proxy admin, and returns them so that they can be used by other modules.
 */
const stateProxyModule = buildModule("StateProxyModule", (m) => {
  // This address is the owner of the ProxyAdmin contract,
  // so it will be the only account that can upgrade the proxy when needed.
  const proxyAdminOwner = m.getAccount(0);

  const stateLibAddress = m.getParameter("stateLibAddress");
  const smtLibAddress = m.getParameter("smtLibAddress");
  const poseidonUnit1LAddress = m.getParameter("poseidonUnit1LAddress");

  const stateLib = m.contractAt('StateLib', stateLibAddress);
  const smtLib = m.contractAt('SmtLib', smtLibAddress);
  const poseidonUnit1L = m.contractAt('PoseidonUnit1L', poseidonUnit1LAddress);

  // This is our contract that will be proxied.
  // We will upgrade this contract with a new version later.
  const state = m.contract("State", [], {
    libraries: {
        StateLib: stateLib,
        SmtLib: smtLib,
        PoseidonUnit1L: poseidonUnit1L
    }
  });
 
  // The TransparentUpgradeableProxy contract creates the ProxyAdmin within its constructor.
  // To read more about how this proxy is implemented, you can view the source code and comments here:
  // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/proxy/transparent/TransparentUpgradeableProxy.sol
  const proxy = m.contract("TransparentUpgradeableProxy", [
    state,
    proxyAdminOwner,
    '0x',
  ]);

  // We need to get the address of the ProxyAdmin contract that was created by the TransparentUpgradeableProxy
  // so that we can use it to upgrade the proxy later.
  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin"
  );

  // Here we use m.contractAt(...) to create a contract instance for the ProxyAdmin that we can interact with later to upgrade the proxy.
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  // Return the proxy and proxy admin so that they can be used by other modules.
  return { proxyAdmin, proxy };
});

/**
 * This is the second module that will be run, and it is also the only module exported from this file.
 * It creates a contract instance for the Demo contract using the proxy from the previous module.
 */
export const StateModule = buildModule("StateModule", (m) => {
  // Get the proxy and proxy admin from the previous module.
  const { proxy, proxyAdmin } = m.useModule(stateProxyModule);

  // Here we're using m.contractAt(...) a bit differently than we did above.
  // While we're still using it to create a contract instance, we're now telling Hardhat Ignition
  // to treat the contract at the proxy address as an instance of the Demo contract.
  // This allows us to interact with the underlying Demo contract via the proxy from within tests and scripts.
  const state = m.contractAt("State", proxy);

  // Return the contract instance, along with the original proxy and proxyAdmin contracts
  // so that they can be used by other modules, or in tests and scripts.
  return { state, proxy, proxyAdmin };
});
