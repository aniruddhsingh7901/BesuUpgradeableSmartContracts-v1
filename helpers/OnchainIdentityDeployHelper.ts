import { ethers, upgrades } from "hardhat";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

export class OnchainIdentityDeployHelper {
  constructor(
    private signers: SignerWithAddress[],
    private readonly enableLogging: boolean = false
  ) {}

  static async initialize(
    signers: SignerWithAddress[] | null = null,
    enableLogging = false
  ): Promise<OnchainIdentityDeployHelper> {
    let sgrs;
    if (signers === null) {
      sgrs = await ethers.getSigners();
    } else {
      sgrs = signers;
    }
    return new OnchainIdentityDeployHelper(sgrs, enableLogging);
  }

  async deployIdentity(
    state: Contract,
    smtLib: Contract,
    poseidon1: Contract,
    poseidon2: Contract,
    poseidon3: Contract,
    poseidon4: Contract
  ): Promise<{
    identity: Contract;
  }> {
    const owner = this.signers[0];

    this.log("======== Identity: deploy started ========");

    const cb = await this.deployClaimBuilder();
    const il = await this.deployIdentityLib(
      await smtLib.getAddress(),
      await poseidon3.getAddress(),
      await poseidon4.getAddress(),
    );

    this.log("deploying Identity...");
    const IdentityFactory = await ethers.getContractFactory("IdentityExample", {
      libraries: {
        ClaimBuilder: await cb.getAddress(),
        IdentityLib: await il.getAddress(),
      },
    });
    // const IdentityFactory = await ethers.getContractFactory("Identity");
    const Identity = await upgrades.deployProxy(IdentityFactory, [await state.getAddress()], {
      unsafeAllowLinkedLibraries: true,
    });
    await Identity.waitForDeployment();
    this.log(
      `Identity contract deployed to address ${await Identity.getAddress()} from ${await owner.getAddress()}`,
    );

    this.log("======== Identity: deploy completed ========");

    return {
      identity: Identity,
    };
  }

  async deployClaimBuilder(): Promise<Contract> {
    const ClaimBuilder = await ethers.getContractFactory("ClaimBuilder");
    const cb = await ClaimBuilder.deploy();
    await cb.waitForDeployment();
    this.enableLogging && this.log(`ClaimBuilder deployed to: ${await cb.getAddress()}`);

    return cb;
  }

  async deployIdentityLib(
    smtpAddress: string,
    poseidonUtil3lAddress: string,
    poseidonUtil4lAddress: string,
  ): Promise<Contract> {
    const Identity = await ethers.getContractFactory("IdentityLib", { libraries: {
      SmtLib: smtpAddress,
      PoseidonUnit3L: poseidonUtil3lAddress,
      PoseidonUnit4L: poseidonUtil4lAddress,
    }});
    const il = await Identity.deploy();
    await il.waitForDeployment();
    this.enableLogging && this.log(`ClaimBuilder deployed to: ${await il.getAddress()}`);

    return il;
  }

  async deployClaimBuilderWrapper(): Promise<{
    address: string;
  }> {

    const cb = await this.deployClaimBuilder();

    const ClaimBuilderWrapper = await ethers.getContractFactory("ClaimBuilderWrapper", {
      libraries: {
        ClaimBuilder: await cb.getAddress(),
      }
    });
    const claimBuilderWrapper = await ClaimBuilderWrapper.deploy();
    console.log("ClaimBuilderWrapper deployed to:", await claimBuilderWrapper.getAddress());
    return { address: await claimBuilderWrapper.getAddress() };
  }

  private log(...args): void {
    this.enableLogging && console.log(args);
  }
}
