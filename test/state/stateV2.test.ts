import { expect } from "chai";
import { ethers } from "hardhat";
import { publishState } from "../utils/deploy-utils";
import { StateDeployHelper } from "../../helpers/StateDeployHelper";
import bigInt from "big-integer";

const stateTransitions = [
  require("./data/user_state_genesis_transition.json"),
  require("./data/user_state_next_transition.json"),
];

//Split to State and StateLib
describe("State transitions positive cases", () => {
  let state;

  before(async function () {
    this.timeout(5000);
    const deployHelper = await StateDeployHelper.initialize();
    const contracts = await deployHelper.deployStateV2();
    state = contracts.state;
  });

  it("Initial state publishing", async function () {
    this.timeout(5000);

    const params = await publishState(state, stateTransitions[0]);

    const res0 = await state.getStateInfoById(params.id);
    expect(res0.state).to.be.equal(bigInt(params.newState).toString());

    expect(await state.stateExists(params.id, params.newState)).to.be.equal(true);
    const stInfoNew = await state.getStateInfoByIdAndState(params.id, params.newState);
    expect(stInfoNew.id).to.be.equal(params.id);
    expect(stInfoNew.replacedByState).to.be.equal(0);
    expect(stInfoNew.createdAtTimestamp).not.be.empty;
    expect(stInfoNew.replacedAtTimestamp).to.be.equal(0);
    expect(stInfoNew.createdAtBlock).not.be.empty;
    expect(stInfoNew.replacedAtBlock).to.be.equal(0);

    expect(await state.stateExists(params.id, params.oldState)).to.be.equal(true);
    const stInfoOld = await state.getStateInfoByIdAndState(params.id, params.oldState);
    expect(stInfoOld.id).to.be.equal(params.id);
    expect(stInfoOld.replacedByState).to.be.equal(params.newState);
    expect(stInfoOld.createdAtTimestamp).to.be.equal(0);
    expect(stInfoOld.replacedAtTimestamp).to.be.equal(
      stInfoNew.createdAtTimestamp
    );
    expect(stInfoOld.createdAtBlock).to.be.equal(0);
    expect(stInfoOld.replacedAtBlock).to.be.equal(stInfoNew.createdAtBlock);

    expect(await state.idExists(params.id)).to.be.equal(true);
    const latestStInfo = await state.getStateInfoById(params.id);
    expect(latestStInfo.state).to.be.equal(params.newState);
  });

  it("Subsequent state update", async function () {
    this.timeout(5000);
    const stateInfoBeforeUpdate = await state.getStateInfoByIdAndState(
      stateTransitions[1].pub_signals[0],
      stateTransitions[1].pub_signals[1]
    );

    const params = await publishState(state, stateTransitions[1]);
    const res = await state.getStateInfoById(params.id);
    expect(res.state).to.be.equal(params.newState);

    expect(await state.stateExists(params.id, params.newState)).to.be.equal(true);
    const stInfoNew = await state.getStateInfoByIdAndState(params.id, params.newState);
    expect(stInfoNew.replacedAtTimestamp).to.be.equal(0);
    expect(stInfoNew.createdAtTimestamp).not.be.empty;
    expect(stInfoNew.replacedAtBlock).to.be.equal(0);
    expect(stInfoNew.createdAtBlock).not.be.empty;
    expect(stInfoNew.id).to.be.equal(params.id);
    expect(stInfoNew.replacedByState).to.be.equal(0);

    expect(await state.stateExists(params.id, params.oldState)).to.be.equal(true);
    const stInfoOld = await state.getStateInfoByIdAndState(params.id, params.oldState);
    expect(stInfoOld.replacedAtTimestamp).to.be.equal(
      stInfoNew.createdAtTimestamp
    );
    expect(stInfoOld.createdAtTimestamp).to.be.equal(
      stateInfoBeforeUpdate.createdAtTimestamp
    );
    expect(stInfoOld.replacedAtBlock).to.be.equal(stInfoNew.createdAtBlock);
    !expect(stInfoOld.createdAtBlock).to.be.equal(
      stateInfoBeforeUpdate.createdAtBlock
    );
    expect(stInfoOld.id).to.be.equal(params.id);
    expect(stInfoOld.replacedByState).to.be.equal(params.newState);

    expect(await state.idExists(params.id)).to.be.equal(true);
    const latestStInfo = await state.getStateInfoById(params.id);
    expect(latestStInfo.state).to.be.equal(params.newState);
  });
});

//State
describe("State transition negative cases", () => {
  let state;

  beforeEach(async () => {
    const deployHelper = await StateDeployHelper.initialize();
    const contracts = await deployHelper.deployStateV2();
    state = contracts.state;
  });

  it("Old state does not match the latest state", async () => {
    await publishState(state, stateTransitions[0]);

    const modifiedStateTransition = JSON.parse(
      JSON.stringify(stateTransitions[1])
    );
    modifiedStateTransition.pub_signals[1] = "1"; // set oldState to 1 to trigger the error

    await expect(publishState(state, modifiedStateTransition)).to.be.revertedWith(
      "Old state does not match the latest state"
    );
  });

  it("Old state is genesis but identity already exists", async () => {
    await publishState(state, stateTransitions[0]);

    const modifiedStateTransition = JSON.parse(
      JSON.stringify(stateTransitions[1])
    );
    modifiedStateTransition.pub_signals[3] = "1"; // set isOldStateGenesis to 1 to trigger the error

    await expect(publishState(state, modifiedStateTransition)).to.be.revertedWith(
      "Old state is genesis but identity already exists"
    );
  });

  it("Old state is not genesis but identity does not yet exist", async () => {
    const modifiedStateTransition = JSON.parse(
      JSON.stringify(stateTransitions[0])
    );
    modifiedStateTransition.pub_signals[3] = "0"; // change isOldStateGenesis to 0 to trigger exception

    await expect(publishState(state, modifiedStateTransition)).to.be.revertedWith(
      "Old state is not genesis but identity does not yet exist"
    );
  });

  it("Zero-knowledge proof of state transition is not valid", async () => {
    const modifiedStateTransition = JSON.parse(
      JSON.stringify(stateTransitions[0])
    );
    modifiedStateTransition.pub_signals[2] = "1"; // change state to make zk proof invalid

    await expect(publishState(state, modifiedStateTransition)).to.be.revertedWith(
      "Zero-knowledge proof of state transition is not valid"
    );
  });

  it("ID should not be zero", async () => {
    const modifiedStateTransition = JSON.parse(
      JSON.stringify(stateTransitions[0])
    );
    modifiedStateTransition.pub_signals[0] = "0"; // set id to 0 to trigger the error

    await expect(publishState(state, modifiedStateTransition)).to.be.revertedWith(
      "ID should not be zero"
    );
  });

  it("New state should not be zero", async () => {
    const modifiedStateTransition = JSON.parse(
      JSON.stringify(stateTransitions[0])
    );
    modifiedStateTransition.pub_signals[2] = "0"; // set new state to 0 to trigger the error

    await expect(publishState(state, modifiedStateTransition)).to.be.revertedWith(
      "New state should not be zero"
    );
  });
});

//StateLib
describe("State history", function () {
  this.timeout(5000);

  let state, user1Inputs, publishedStates1, user1ID, user1HistoryLength;
  let publishedStates: { [key: string]: string | number }[] = [];

  before(async () => {
    const deployHelper = await StateDeployHelper.initialize();
    const contracts = await deployHelper.deployStateV2();
    state = contracts.state;

    publishedStates = [];
    for (const stateTransition of stateTransitions) {
      publishedStates.push(await publishState(state, stateTransition));
    }
    user1Inputs = stateTransitions.slice(0, 2);
    publishedStates1 = publishedStates.slice(0, 2);
    user1ID = user1Inputs[0].pub_signals[0];
    user1HistoryLength = await state.getStateInfoHistoryLengthById(user1ID);
  });

  it("should return state history", async () => {
    expect(user1HistoryLength).to.be.equal(user1Inputs.length + 1);

    const stateInfos = await state.getStateInfoHistoryById(
      user1ID,
      0,
      user1HistoryLength
    );
    expect(stateInfos.length).to.be.equal(user1HistoryLength);

    const publishedState = publishedStates1[0];
    // genesis state info of the first identity (from the contract)
    const [stateInfo] = await state.getStateInfoHistoryById(user1ID, 0, 1);
    expect(stateInfo.id).to.be.equal(publishedState.id);
    expect(stateInfo.state).to.be.equal(publishedState.oldState);
    expect(stateInfo.replacedByState).to.be.equal(publishedState.newState);
    expect(stateInfo.createdAtTimestamp).to.be.equal(0);
    expect(stateInfo.replacedAtTimestamp).to.be.equal(publishedState.timestamp);
    expect(stateInfo.createdAtBlock).to.be.equal(0);
    expect(stateInfo.replacedAtBlock).to.be.equal(publishedState.blockNumber);

    const publishedState2 = publishedStates1[1];
    // genesis state info of the first identity (from the contract)
    const [stateInfo2] = await state.getStateInfoHistoryById(user1ID, 2, 1);
    expect(stateInfo2.id).to.be.equal(publishedState2.id);
    expect(stateInfo2.state).to.be.equal(publishedState2.newState);
    expect(stateInfo2.replacedByState).to.be.equal(0);
    expect(stateInfo2.createdAtTimestamp).to.be.equal(
      publishedState2.timestamp
    );
    expect(stateInfo2.replacedAtTimestamp).to.be.equal(0);
    expect(stateInfo2.createdAtBlock).to.be.equal(publishedState2.blockNumber);
    expect(stateInfo2.replacedAtBlock).to.be.equal(0);
  });

  it("should be reverted if length is zero", async () => {
    await expect(state.getStateInfoHistoryById(user1ID, 0, 0)).to.be.revertedWith(
      "Length should be greater than 0"
    );
  });

  it("should be reverted if length limit exceeded", async () => {
    await expect(state.getStateInfoHistoryById(user1ID, 0, 10 ** 6)).to.be.revertedWith(
      "Length limit exceeded"
    );
  });

  it("should be reverted if startIndex is out of bounds", async () => {
    await expect(
      state.getStateInfoHistoryById(user1ID, user1HistoryLength, 100)
    ).to.be.revertedWith("Start index out of bounds");
  });

  it("should not revert if startIndex + length >= historyLength", async () => {
    let history = await state.getStateInfoHistoryById(user1ID, user1HistoryLength - 1, 100);
    expect(history.length).to.be.equal(1);
    history = await state.getStateInfoHistoryById(user1ID, user1HistoryLength - 2, 100);
    expect(history.length).to.be.equal(2);
  });
});

//StateLib
describe("get StateInfo negative cases", function () {
  this.timeout(5000);

  let state;

  before(async () => {
    const deployHelper = await StateDeployHelper.initialize();
    const contracts = await deployHelper.deployStateV2();
    state = contracts.state;

    for (const stateTransition of stateTransitions) {
      await publishState(state, stateTransition);
    }
  });

  it("getStateInfoByID: should be reverted if identity does not exist", async () => {
    const missingID = stateTransitions[0].pub_signals[0] + 1; // Modify id so it does not exist

    await expect(state.getStateInfoById(missingID)).to.be.revertedWith(
      "Identity does not exist"
    );
  });

  it("getStateInfoHistoryById: should be reverted if identity does not exist", async () => {
    const missingID = stateTransitions[0].pub_signals[0] + 1; // Modify id so it does not exist

    await expect(
      state.getStateInfoHistoryById(missingID, 0, 1)
    ).to.be.revertedWith("Identity does not exist");
  });

  it("getStateInfoHistoryLengthById: should be reverted if identity does not exist", async () => {
    const missingID = stateTransitions[0].pub_signals[0] + 1; // Modify id so it does not exist

    await expect(
      state.getStateInfoHistoryLengthById(missingID)
    ).to.be.revertedWith("Identity does not exist");
  });

  it("getStateInfoByIdAndState: should be reverted if state does not exist", async () => {
    const id = stateTransitions[0].pub_signals[0];
    const missingState = stateTransitions[0].pub_signals[2] + 1; // Modify state so it does not exist

    await expect(state.getStateInfoByIdAndState(id, missingState)).to.be.revertedWith(
      "State does not exist"
    );
  });
});

//State or remove???
describe("GIST proofs", () => {
  let state: any;

  beforeEach(async () => {
    const deployHelper = await StateDeployHelper.initialize();
    const contracts = await deployHelper.deployStateV2();
    state = contracts.state;
  });

  it("Should be correct historical proof by root and the latest root", async function () {
    this.timeout(5000);
    const currentRoots: any[] = [];
    const id = ethers.BigNumber.from(stateTransitions[0].pub_signals[0]);

    for (const issuerStateJson of stateTransitions) {
      await publishState(state, issuerStateJson);
      const currentRoot = await state.getGISTRoot();
      const [lastProofRoot] = await state.getGISTProof(id);
      expect(lastProofRoot).to.equal(currentRoot);
      currentRoots.push(currentRoot);
    }

    const rootHistoryLength = await state.getGISTRootHistoryLength();
    expect(rootHistoryLength).to.equal(currentRoots.length);

    console.log("root history length: ", rootHistoryLength);
    const [obj1, obj2] = await state.getGISTRootHistory(0, 2);

    const [root] = await state.getGISTProofByRoot(id, obj1.root);
    expect(obj1.root).to.equal(root);
    expect(obj1.root).to.equal(currentRoots[0]);

    const [root2] = await state.getGISTProofByRoot(id, obj2.root);
    expect(obj2.root).to.equal(root2);
    expect(obj2.root).to.equal(currentRoots[1]);
  });

  it("Should be correct historical proof by time", async function () {
    this.timeout(5000);
    for (const issuerStateJson of stateTransitions) {
      await publishState(state, issuerStateJson);
    }
    const id = ethers.BigNumber.from(stateTransitions[0].pub_signals[0]);

    const rootHistoryLength = await state.getGISTRootHistoryLength();
    expect(rootHistoryLength).to.equal(stateTransitions.length);

    const [root1info, root2info] = await state.getGISTRootHistory(0, 2);

    console.log(root1info);
    const [r1] = await state.getGISTProofByTime(
      id,
      root1info.createdAtTimestamp
    );

    expect(root1info.root).to.equal(r1);

    console.log(root2info);

    const [r2] = await state.getGISTProofByTime(
      id,
      root2info.createdAtTimestamp
    );
    expect(r2).to.equal(root2info.root);
  });

  it("Should be correct historical proof by block", async function () {
    this.timeout(5000);
    for (const issuerStateJson of stateTransitions) {
      await publishState(state, issuerStateJson);
    }
    const id = ethers.BigNumber.from(stateTransitions[0].pub_signals[0]);

    const rootHistoryLength = await state.getGISTRootHistoryLength();
    expect(rootHistoryLength).to.equal(stateTransitions.length);

    const [root1info, root2info] = await state.getGISTRootHistory(0, 2);

    const [root] = await state.getGISTProofByBlock(
      id,
      root1info.createdAtBlock
    );
    expect(root1info.root).to.equal(root);
    const [root2] = await state.getGISTProofByBlock(
      id,
      root2info.createdAtBlock
    );
    expect(root2info.root).to.equal(root2);
  });
});

//State or remove???
describe("GIST root history", () => {
  let state: any;

  beforeEach(async () => {
    const deployHelper = await StateDeployHelper.initialize();
    const contracts = await deployHelper.deployStateV2();
    state = contracts.state;
  });

  it("Should search by block and by time return same root", async function () {
    this.timeout(5000);
    for (const issuerStateJson of stateTransitions) {
      await publishState(state, issuerStateJson);
    }
    const id = ethers.BigNumber.from(stateTransitions[0].pub_signals[0]);
    const rootHistoryLength = await state.getGISTRootHistoryLength();
    expect(rootHistoryLength).to.equal(stateTransitions.length);

    const [rootInfo] = await state.getGISTRootHistory(0, 1);

    const [rootB] = await state.getGISTProofByBlock(
      id,
      rootInfo.createdAtBlock
    );
    expect(rootInfo.root).to.equal(rootB);
    const [rootT] = await state.getGISTProofByTime(
      id,
      rootInfo.createdAtTimestamp
    );
    expect(rootInfo.root).to.equal(rootT).to.equal(rootB);
  });

  it("Should have correct GIST root transitions info", async function () {
    this.timeout(5000);
    const roots: any[] = [];
    const expRootInfos: any[] = [];
    for (const issuerStateJson of stateTransitions) {
      const { blockNumber, timestamp } = await publishState(
        state,
        issuerStateJson
      );

      const root = await state.getGISTRoot();
      roots.push(root);

      if (expRootInfos.length >= 1) {
        expRootInfos[expRootInfos.length - 1].replacedAtTimestamp = timestamp;
        expRootInfos[expRootInfos.length - 1].replacedAtBlock = blockNumber;
        expRootInfos[expRootInfos.length - 1].replacedByRoot = root;
      }

      expRootInfos.push({
        replacedAtTimestamp: 0,
        createdAtTimestamp: timestamp,
        replacedAtBlock: 0,
        createdAtBlock: blockNumber,
        replacedByRoot: 0,
      });
    }

    const rootInfo0 = await state.getGISTRootInfo(roots[0]);
    const rootInfo1 = await state.getGISTRootInfo(roots[1]);

    expect(rootInfo0.replacedAtTimestamp).to.equal(
      expRootInfos[0].replacedAtTimestamp
    );
    expect(rootInfo0.createdAtTimestamp).to.equal(
      expRootInfos[0].createdAtTimestamp
    );
    expect(rootInfo0.replacedAtBlock).to.equal(expRootInfos[0].replacedAtBlock);
    expect(rootInfo0.createdAtBlock).to.equal(expRootInfos[0].createdAtBlock);
    expect(rootInfo0.replacedByRoot).to.equal(expRootInfos[0].replacedByRoot);

    expect(rootInfo1.replacedAtTimestamp).to.equal(
      expRootInfos[1].replacedAtTimestamp
    );
    expect(rootInfo1.createdAtTimestamp).to.equal(
      expRootInfos[1].createdAtTimestamp
    );
    expect(rootInfo1.replacedAtBlock).to.equal(expRootInfos[1].replacedAtBlock);
    expect(rootInfo1.createdAtBlock).to.equal(expRootInfos[1].createdAtBlock);
    expect(rootInfo1.replacedByRoot).to.equal(expRootInfos[1].replacedByRoot);
  });
});

//State
describe("Set Verifier", () => {
  it("Should set verifier", async () => {
    const deployHelper = await StateDeployHelper.initialize();
    const { state, verifier } = await deployHelper.deployStateV2();

    const verifierAddress = await state.getVerifier();
    expect(verifierAddress).to.equal(verifier.address);

    const newVerifierAddress = ethers.utils.getAddress("0x8ba1f109551bd432803012645ac136ddd64dba72");
    await state.setVerifier(newVerifierAddress);
    const verifierAddress2 = await state.getVerifier();
    expect(verifierAddress2).to.equal(newVerifierAddress);
  });

  it("Should not set verifier if not owner", async () => {
    const deployHelper = await StateDeployHelper.initialize();
    const { state, verifier } = await deployHelper.deployStateV2();

    const verifierAddress = await state.getVerifier();
    expect(verifierAddress).to.equal(verifier.address);

    const notOwner = (await ethers.getSigners())[1];
    const newVerifierAddress = ethers.utils.getAddress("0x8ba1f109551bd432803012645ac136ddd64dba72");
    await expect(state.connect(notOwner).setVerifier(newVerifierAddress)).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
  });

  it("Should allow verifier zero address to block any state transition", async () => {
    const deployHelper = await StateDeployHelper.initialize();
    const { state } = await deployHelper.deployStateV2();

    await state.setVerifier(ethers.constants.AddressZero);
    await expect(publishState(state, stateTransitions[0])).to.be.reverted;
  });
});
