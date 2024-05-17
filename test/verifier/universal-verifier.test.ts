import { expect } from "chai";
import { DeployHelper } from "../../helpers/DeployHelper";
import { ethers } from "hardhat";
import { packValidatorParams } from "../utils/validator-pack-utils";
import { prepareInputs } from "../utils/state-utils";
import { Block } from "ethers";

describe("Universal Verifier MTP & SIG validators", function () {
  let verifier: any, sig: any;
  let signer, signer2, signer3, signer4;
  let signerAddress: string, signer2Address: string, signer3Address: string, someAddress: string;
  let deployHelper: DeployHelper;

  const query = {
    schema: BigInt("180410020913331409885634153623124536270"),
    claimPathKey: BigInt(
      "8566939875427719562376598811066985304309117528846759529734201066483458512800"
    ),
    operator: 1n,
    slotIndex: 0n,
    value: [
      1420070400000000000n,
      ...new Array(63).fill("0").map((x) => BigInt(x)),
    ],
    queryHash: BigInt(
      "1496222740463292783938163206931059379817846775593932664024082849882751356658"
    ),
    circuitIds: ["credentialAtomicQuerySigV2OnChain"],
    claimPathNotExists: 0,
  };

  const proofJson = require("../validators/sig/data/valid_sig_user_genesis.json");

  beforeEach(async () => {
    [signer, signer2, signer3, signer4] = await ethers.getSigners();
    signerAddress = await signer.getAddress();
    signer2Address = await signer2.getAddress();
    signer3Address = await signer3.getAddress();
    someAddress = await signer4.getAddress();

    deployHelper = await DeployHelper.initialize(null, true);
    verifier = await deployHelper.deployUniversalVerifier(signer);

    const stub = await deployHelper.deployValidatorStub();

    sig = stub;
    await verifier.approveValidator(await sig.getAddress());
    await verifier.connect();
  });

  it("Test add, get ZKPRequest, requestIdExists, getZKPRequestsCount", async () => {
    const requestsCount = 3;

    for (let i = 0; i < requestsCount; i++) {
      const validatorAddr = await sig.getAddress();
      await expect(
        verifier.setZKPRequest(i, {
          metadata: "metadataN" + i,
          validator: validatorAddr,
          data: "0x0" + i,
        })
      )
        .to.emit(verifier, "ZKPRequestSet")
        .withArgs(i, signerAddress, "metadataN" + i, validatorAddr, "0x0" + i);
      const request = await verifier.getZKPRequest(i);
      expect(request.metadata).to.be.equal("metadataN" + i);
      expect(request.validator).to.be.equal(validatorAddr);
      expect(request.data).to.be.equal("0x0" + i);

      const requestIdExists = await verifier.requestIdExists(i);
      expect(requestIdExists).to.be.true;
      const requestIdDoesntExists = await verifier.requestIdExists(i + 1);
      expect(requestIdDoesntExists).to.be.false;

      await expect(verifier.getZKPRequest(i + 1)).to.be.rejectedWith("request id doesn't exist");
    }

    const count = await verifier.getZKPRequestsCount();
    expect(count).to.be.equal(requestsCount);
  });

  it("Test submit response", async () => {
    const requestId = 0;
    const nonExistingRequestId = 1;
    const data = packValidatorParams(query);

    await verifier.setZKPRequest(0, {
      metadata: "metadata",
      validator: await sig.getAddress(),
      data: data,
    });

    const { inputs, pi_a, pi_b, pi_c } = prepareInputs(proofJson);
    const tx = await verifier.submitZKPResponse(0, inputs, pi_a, pi_b, pi_c);
    const txRes = await tx.wait();
    const filter = verifier.filters.ZKPResponseSubmitted;

    const events = await verifier.queryFilter(filter, -1);
    expect(events[0].eventName).to.be.equal("ZKPResponseSubmitted");
    expect(events[0].args.requestId).to.be.equal(0);
    expect(events[0].args.caller).to.be.equal(signerAddress);

    const { timestamp: txResTimestamp } = await ethers.provider.getBlock(txRes.blockNumber) as Block;

    await expect(
      verifier.verifyZKPResponse(
        0,
        inputs,
        pi_a,
        pi_b,
        pi_c,
        "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
      ),
    ).not.to.be.rejected;

    const status = await verifier.getProofStatus(signerAddress, requestId);
    expect(status.isProved).to.be.true;
    expect(status.validatorVersion).to.be.equal("2.0.0-mock");
    expect(status.blockNumber).to.be.equal(txRes.blockNumber);
    expect(status.blockTimestamp).to.be.equal(txResTimestamp);

    await expect(verifier.getProofStatus(signerAddress, nonExistingRequestId)).to.be.rejectedWith(
      "request id doesn't exist",
    );
  });

  it("Test getZKPRequests pagination", async () => {
    for (let i = 0; i < 30; i++) {
      await verifier.setZKPRequest(i, {
        metadata: "metadataN" + i,
        validator: await sig.getAddress(),
        data: "0x00",
      });
    }
    let queries = await verifier.getZKPRequests(5, 10);
    expect(queries.length).to.be.equal(10);
    expect(queries[0].metadata).to.be.equal("metadataN5");
    expect(queries[9].metadata).to.be.equal("metadataN14");

    queries = await verifier.getZKPRequests(15, 3);
    expect(queries.length).to.be.equal(3);
    expect(queries[0].metadata).to.be.equal("metadataN15");
    expect(queries[1].metadata).to.be.equal("metadataN16");
    expect(queries[2].metadata).to.be.equal("metadataN17");
  });

  it("Check access control", async () => {
    const owner = signer;
    const controller = signer2;
    const someSigner = signer3;
    const requestId = 0;
    const nonExistentRequestId = 1;
    const controllerAddress = await controller.getAddress();
    const someSignerAddress = await someSigner.getAddress();

    await expect(verifier.getRequestOwner(requestId)).to.be.rejectedWith("request id doesn't exist");
    await verifier.connect(controller).setZKPRequest(requestId, {
      metadata: "metadata",
      validator: await sig.getAddress(),
      data: packValidatorParams(query),
    });

    expect(await verifier.getRequestOwner(requestId)).to.be.equal(controllerAddress);
    await expect(
      verifier.connect(someSigner).setController(requestId, someSigner),
    ).to.be.rejectedWith("Only owner or controller can call this function");

    await verifier.connect(controller).setController(requestId, someSigner);
    expect(await verifier.getRequestOwner(requestId)).to.be.equal(someSignerAddress);

    await expect(
      verifier.connect(controller).setController(requestId, controllerAddress),
    ).to.be.rejectedWith("Only owner or controller can call this function");
    await verifier.connect(owner).setController(requestId, controllerAddress);
    expect(await verifier.getRequestOwner(requestId)).to.be.equal(controllerAddress);

    await expect(verifier.getRequestOwner(nonExistentRequestId)).to.be.rejectedWith(
      "request id doesn't exist",
    );
    await expect(
      verifier.setController(nonExistentRequestId, someSignerAddress),
    ).to.be.rejectedWith("request id doesn't exist");
  });

  it("Check disable/enable functionality", async () => {
    const owner = signer;
    const controller = signer2;
    const someSigner = signer3;
    const requestId = 0;
    const nonExistentRequestId = 1;

    await expect(verifier.isZKPRequestEnabled(requestId)).to.be.rejectedWith(
      "request id doesn't exist",
    );

    await verifier.connect(controller).setZKPRequest(requestId, {
      metadata: "metadata",
      validator: await sig.getAddress(),
      data: packValidatorParams(query),
    });
    expect(await verifier.isZKPRequestEnabled(requestId)).to.be.true;

    await expect(verifier.connect(someSigner).disableZKPRequest(requestId)).to.be.rejectedWith(
      "Only owner or controller can call this function",
    );
    expect(await verifier.isZKPRequestEnabled(requestId)).to.be.true;

    await verifier.connect(owner).disableZKPRequest(requestId);
    expect(await verifier.isZKPRequestEnabled(requestId)).to.be.false;

    await expect(verifier.connect(someSigner).enableZKPRequest(requestId)).to.be.rejectedWith(
      "Only owner or controller can call this function",
    );
    await verifier.connect(controller).enableZKPRequest(requestId);
    expect(await verifier.isZKPRequestEnabled(requestId)).to.be.true;

    const { inputs, pi_a, pi_b, pi_c } = prepareInputs(proofJson);
    await verifier.submitZKPResponse(0, inputs, pi_a, pi_b, pi_c);

    await verifier.connect(controller).disableZKPRequest(requestId);
    await expect(verifier.submitZKPResponse(0, inputs, pi_a, pi_b, pi_c)).to.be.rejectedWith(
      "Request is disabled",
    );
    await expect(
      verifier.verifyZKPResponse(
        0,
        inputs,
        pi_a,
        pi_b,
        pi_c,
        "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
      ),
    ).to.be.rejectedWith("Request is disabled");

    await expect(verifier.isZKPRequestEnabled(nonExistentRequestId)).to.be.rejectedWith(
      "request id doesn't exist",
    );
    await expect(verifier.disableZKPRequest(nonExistentRequestId)).to.be.rejectedWith(
      "request id doesn't exist",
    );
    await expect(verifier.enableZKPRequest(nonExistentRequestId)).to.be.rejectedWith(
      "request id doesn't exist",
    );
  });

  it("Check approved validators", async () => {
    const owner = signer;
    const someAddress = signer2;

    const { validator: mtp } = await deployHelper.deployValidatorContracts(
      "VerifierMTPWrapper",
      "CredentialAtomicQueryMTPV2Validator",
    );
    const mtpValAddr = await mtp.getAddress();
    expect(await verifier.isApprovedValidator(mtpValAddr)).to.be.false;

    await expect(
      verifier.setZKPRequest(0, {
        metadata: "metadata",
        validator: mtpValAddr,
        data: "0x00",
      })
    ).to.be.rejectedWith("Validator is not approved");

    await expect(verifier.connect(someAddress).approveValidator(mtpValAddr))
      .to.be.revertedWithCustomError(verifier, "OwnableUnauthorizedAccount")
      .withArgs(someAddress);
    expect(await verifier.isApprovedValidator(mtpValAddr)).to.be.false;

    await verifier.connect(owner).approveValidator(mtpValAddr);
    expect(await verifier.isApprovedValidator(mtpValAddr)).to.be.true;

    await expect(
      verifier.setZKPRequest(0, {
        metadata: "metadata",
        validator: mtpValAddr,
        data: "0x00",
      })
    ).not.to.be.rejected;

    // can't approve validator, which does not support ICircuitValidator interface
    await expect(verifier.approveValidator(someAddress)).to.be.rejected;

    await expect(
      verifier.setZKPRequest(1, {
        metadata: "metadata",
        validator: someAddress,
        data: "0x00",
      })
    ).to.be.rejectedWith("Validator is not approved");
  });
});
