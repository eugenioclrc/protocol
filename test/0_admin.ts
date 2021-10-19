import { expect } from "chai";
import { ethers } from "hardhat";
import { formatUnits, parseUnits } from "@ethersproject/units";
import { Contract } from "ethers";
import { BigNumber } from "@ethersproject/bignumber";
import { ProtocolError, ExactlyEnv, ExaTime, parseSupplyEvent, errorGeneric } from "./exactlyUtils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("Auditor Admin", function () {
  let auditor: Contract;
  let exactlyEnv: ExactlyEnv;
  let notAnExafinAddress: string;
  let nextPoolID: number;

  let owner: SignerWithAddress;
  let user: SignerWithAddress;

  let tokensCollateralRate = new Map([
    ["DAI", parseUnits("0.8", 18)],
    ["ETH", parseUnits("0.7", 18)],
  ]);

  // Oracle price is in 10**6
  let tokensUSDPrice = new Map([
    ["DAI", parseUnits("1", 6)],
    ["ETH", parseUnits("3000", 6)],
  ]);

  let closeFactor = parseUnits("0.4");

  beforeEach(async () => {
    [owner, user] = await ethers.getSigners();

    exactlyEnv = await ExactlyEnv.create(tokensUSDPrice, tokensCollateralRate);
    auditor = exactlyEnv.auditor;
    notAnExafinAddress = "0x6D88564b707518209a4Bea1a57dDcC23b59036a8";
    nextPoolID = (new ExaTime()).nextPoolID();

    // From Owner to User
    await exactlyEnv.getUnderlying("DAI").transfer(user.address, parseUnits("10000"));
  });

  it("EnableMarket should fail from third parties", async () => {
    await expect(
      auditor.connect(user).enableMarket(exactlyEnv.getExafin("DAI").address, 0, "DAI", "DAI")
    ).to.be.revertedWith("AccessControl");
  });

  it("It reverts when trying to list a market twice", async () => {
    await expect(
      auditor.enableMarket(exactlyEnv.getExafin("DAI").address, 0, "DAI", "DAI")
    ).to.be.revertedWith(errorGeneric(ProtocolError.MARKET_ALREADY_LISTED));
  });

  it("It reverts when trying to set an exafin with different auditor", async () => {

    const Auditor = await ethers.getContractFactory("Auditor", {
      libraries: {
        TSUtils: exactlyEnv.tsUtils.address
      }
    });
    let newAuditor = await Auditor.deploy(exactlyEnv.oracle.address);
    await newAuditor.deployed();

    const Exafin = await ethers.getContractFactory("Exafin", {
      libraries: {
        TSUtils: exactlyEnv.tsUtils.address
      }
    });
    const exafin = await Exafin.deploy(
      exactlyEnv.getUnderlying("DAI").address,
      "DAI",
      newAuditor.address,
      exactlyEnv.interestRateModel.address
    );
    await exafin.deployed();

    await expect(
      auditor.enableMarket(exafin.address, 0, "DAI", "DAI")
    ).to.be.revertedWith(errorGeneric(ProtocolError.AUDITOR_MISMATCH));
  });


  it("It should emit an event when listing a new market", async () => {
    const TSUtilsLib = await ethers.getContractFactory("TSUtils");
    let tsUtils = await TSUtilsLib.deploy();
    await tsUtils.deployed();

    const Exafin = await ethers.getContractFactory("Exafin", {
      libraries: {
        TSUtils: tsUtils.address
      }
    });
    const exafin = await Exafin.deploy(
      exactlyEnv.getUnderlying("DAI").address,
      "DAI2",
      auditor.address,
      exactlyEnv.interestRateModel.address
    );
    await exafin.deployed();

    await expect(
      auditor.enableMarket(exafin.address, parseUnits("0.5"), "DAI2", "DAI2")
    ).to.emit(auditor, "MarketListed").withArgs(exafin.address);
  });

  it("SetOracle should fail from third parties", async () => {
    await expect(
      auditor.connect(user).setOracle(exactlyEnv.oracle.address)
    ).to.be.revertedWith("AccessControl");
  });

  it("SetOracle should emit event", async () => {
    await expect(
      auditor.setOracle(exactlyEnv.oracle.address)
    ).to.emit(auditor, "OracleChanged");
  });

});
