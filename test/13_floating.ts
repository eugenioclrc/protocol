import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { DefaultEnv } from "./defaultEnv";
import futurePools from "./utils/futurePools";

describe("Smart Pool", function () {
  let exactlyEnv: DefaultEnv;

  let underlyingTokenDAI: Contract;
  let marketDAI: Contract;
  let underlyingTokenWBTC: Contract;
  let marketWBTC: Contract;
  let bob: SignerWithAddress;
  let john: SignerWithAddress;
  const bobBalancePre = parseUnits("2000");
  const johnBalancePre = parseUnits("2000");

  beforeEach(async () => {
    [, bob, john] = await ethers.getSigners();

    exactlyEnv = await DefaultEnv.create({});
    underlyingTokenDAI = exactlyEnv.getUnderlying("DAI");
    marketDAI = exactlyEnv.getMarket("DAI");

    underlyingTokenWBTC = exactlyEnv.getUnderlying("WBTC");
    marketWBTC = exactlyEnv.getMarket("WBTC");

    // From Owner to User
    await underlyingTokenDAI.mint(bob.address, bobBalancePre);
    await underlyingTokenWBTC.mint(bob.address, parseUnits("1", 8));
    await underlyingTokenDAI.mint(john.address, johnBalancePre);
  });

  describe("GIVEN bob and john have 2000DAI in balance, AND deposit 1000DAI each", () => {
    beforeEach(async () => {
      await underlyingTokenDAI.connect(bob).approve(marketDAI.address, bobBalancePre);
      await underlyingTokenDAI.connect(john).approve(marketDAI.address, johnBalancePre);

      await marketDAI.connect(bob).deposit(parseUnits("1000"), bob.address);
      await marketDAI.connect(john).deposit(parseUnits("1000"), john.address);
    });
    it("THEN balance of DAI in contract is 2000", async () => {
      const balanceOfAssetInContract = await underlyingTokenDAI.balanceOf(marketDAI.address);

      expect(balanceOfAssetInContract).to.equal(parseUnits("2000"));
    });
    it("THEN balance of eDAI in BOB's address is 1000", async () => {
      const balanceOfETokenInUserAddress = await marketDAI.balanceOf(bob.address);

      expect(balanceOfETokenInUserAddress).to.equal(parseUnits("1000"));
    });
    it("AND WHEN bob deposits 100DAI more, THEN event Deposit is emitted", async () => {
      await expect(marketDAI.connect(bob).deposit(parseUnits("100"), bob.address)).to.emit(marketDAI, "Deposit");
    });
    describe("AND bob withdraws 500DAI", () => {
      beforeEach(async () => {
        const amountToWithdraw = parseUnits("500");
        await marketDAI.connect(bob).withdraw(amountToWithdraw, bob.address, bob.address);
      });
      it("THEN balance of DAI in contract is 1500", async () => {
        const balanceOfAssetInContract = await underlyingTokenDAI.balanceOf(marketDAI.address);

        expect(balanceOfAssetInContract).to.equal(parseUnits("1500"));
      });
      it("THEN balance of eDAI in BOB's address is 500", async () => {
        const balanceOfETokenInUserAddress = await marketDAI.balanceOf(bob.address);

        expect(balanceOfETokenInUserAddress).to.equal(parseUnits("500"));
      });
      it("AND WHEN bob withdraws 100DAI more, THEN event Withdraw is emitted", async () => {
        await expect(marketDAI.connect(bob).withdraw(parseUnits("100"), bob.address, bob.address)).to.emit(
          marketDAI,
          "Withdraw",
        );
      });
      it("AND WHEN bob wants to withdraw 600DAI more, THEN it reverts because his eDAI balance is not enough", async () => {
        await expect(marketDAI.connect(bob).withdraw(parseUnits("600"), bob.address, bob.address)).to.be.revertedWith(
          "0x11",
        );
      });
      it("AND WHEN bob wants to withdraw all the assets, THEN he uses redeem", async () => {
        await expect(marketDAI.connect(bob).redeem(await marketDAI.balanceOf(bob.address), bob.address, bob.address)).to
          .not.be.reverted;
        const bobBalancePost = await underlyingTokenDAI.balanceOf(bob.address);
        expect(bobBalancePre).to.equal(bobBalancePost);
      });
    });
  });

  describe("GIVEN bob has 1WBTC in balance, AND deposit 1WBTC", () => {
    beforeEach(async () => {
      const bobBalance = parseUnits("1", 8);
      await underlyingTokenWBTC.connect(bob).approve(marketWBTC.address, bobBalance);

      await marketWBTC.connect(bob).deposit(parseUnits("1", 8), bob.address);
    });
    it("THEN balance of WBTC in contract is 1", async () => {
      const balanceOfAssetInContract = await underlyingTokenWBTC.balanceOf(marketWBTC.address);

      expect(balanceOfAssetInContract).to.equal(parseUnits("1", 8));
    });
    it("THEN balance of eWBTC in BOB's address is 1", async () => {
      const balanceOfETokenInUserAddress = await marketWBTC.balanceOf(bob.address);

      expect(balanceOfETokenInUserAddress).to.equal(parseUnits("1", 8));
    });
  });

  describe("GIVEN bob deposits 1WBTC", () => {
    beforeEach(async () => {
      await underlyingTokenWBTC.connect(bob).approve(marketWBTC.address, parseUnits("1", 8));
      await marketWBTC.connect(bob).approve(john.address, parseUnits("1", 8));
      await marketWBTC.connect(bob).deposit(parseUnits("1", 8), bob.address);
    });
    it("THEN bob's eWBTC balance is 1", async () => {
      expect(await marketWBTC.balanceOf(bob.address)).to.equal(parseUnits("1", 8));
    });
    it("AND WHEN bob transfers his eWBTC THEN it does not fail", async () => {
      await expect(marketWBTC.connect(bob).transfer(john.address, marketWBTC.balanceOf(bob.address))).to.not.be
        .reverted;
      expect(await marketWBTC.balanceOf(bob.address)).to.be.equal(0);
      expect(await marketWBTC.balanceOf(john.address)).to.be.equal(parseUnits("1", 8));
    });
    it("AND WHEN john calls transferFrom to transfer bob's eWBTC THEN it does not fail", async () => {
      await expect(marketWBTC.connect(john).transferFrom(bob.address, john.address, marketWBTC.balanceOf(bob.address)))
        .to.not.be.reverted;
      expect(await marketWBTC.balanceOf(bob.address)).to.be.equal(0);
      expect(await marketWBTC.balanceOf(john.address)).to.be.equal(parseUnits("1", 8));
    });
    describe("AND GIVEN bob borrows 0.35 WBTC from a maturity", () => {
      beforeEach(async () => {
        exactlyEnv.switchWallet(bob);
        await exactlyEnv.borrowMP("WBTC", futurePools(3)[2].toNumber(), "0.35");
      });
      it("WHEN bob tries to transfer his eWBTC THEN it fails with InsufficientLiquidity error", async () => {
        await expect(
          marketWBTC.connect(bob).transfer(john.address, marketWBTC.balanceOf(bob.address)),
        ).to.be.revertedWith("InsufficientLiquidity()");
      });
      it("AND WHEN john calls transferFrom to transfer bob's eWBTC THEN it fails with InsufficientLiquidity error", async () => {
        await expect(
          marketWBTC.connect(john).transferFrom(bob.address, john.address, marketWBTC.balanceOf(bob.address)),
        ).to.be.revertedWith("InsufficientLiquidity()");
      });
      it("AND WHEN bob tries to transfer a small amount of eWBTC THEN it does not fail", async () => {
        await expect(marketWBTC.connect(bob).transfer(john.address, parseUnits("0.01", 8))).to.not.be.reverted;
        expect(await marketWBTC.balanceOf(bob.address)).to.be.equal(parseUnits("0.99", 8));
        expect(await marketWBTC.balanceOf(john.address)).to.be.equal(parseUnits("0.01", 8));
      });
      it("AND WHEN john calls transferFrom to transfer a small amount of bob's eWBTC THEN it does not fail", async () => {
        await expect(marketWBTC.connect(john).transferFrom(bob.address, john.address, parseUnits("0.01", 8))).to.not.be
          .reverted;
        expect(await marketWBTC.balanceOf(bob.address)).to.be.equal(parseUnits("0.99", 8));
        expect(await marketWBTC.balanceOf(john.address)).to.be.equal(parseUnits("0.01", 8));
      });
    });
  });

  describe("GIVEN bob deposits 100 DAI (collateralization rate 80%)", () => {
    beforeEach(async () => {
      exactlyEnv.switchWallet(bob);
      await exactlyEnv.depositSP("DAI", "100");
      // we add liquidity to the maturity
      await exactlyEnv.depositMP("DAI", futurePools(3)[2].toNumber(), "60");
    });
    it("WHEN trying to transfer to another user the entire position (100 eDAI) THEN it should not revert", async () => {
      await expect(marketDAI.connect(bob).transfer(john.address, parseUnits("100"))).to.not.be.reverted;
    });
    describe("AND GIVEN bob borrows 60 DAI from a maturity", () => {
      beforeEach(async () => {
        await exactlyEnv.borrowMP("DAI", futurePools(3)[2].toNumber(), "60");
      });
      it("WHEN trying to transfer to another user the entire position (100 eDAI) without repaying first THEN it reverts with INSUFFICIENT_LIQUIDITY", async () => {
        await expect(marketDAI.connect(bob).transfer(john.address, parseUnits("100"))).to.be.revertedWith(
          "InsufficientLiquidity()",
        );
      });
      it("WHEN trying to call transferFrom to transfer to another user the entire position (100 eDAI) without repaying first THEN it reverts with INSUFFICIENT_LIQUIDITY", async () => {
        await expect(
          marketDAI.connect(bob).transferFrom(bob.address, john.address, parseUnits("100")),
        ).to.be.revertedWith("InsufficientLiquidity()");
      });
      it("AND WHEN trying to transfer a small amount that doesnt cause a shortfall (5 eDAI, should move collateralization from 60% to 66%) without repaying first THEN it is allowed", async () => {
        await expect(marketDAI.connect(bob).transfer(john.address, parseUnits("5"))).to.not.be.reverted;
      });
      it("AND WHEN trying to call transferFrom to transfer a small amount that doesnt cause a shortfall (5 eDAI, should move collateralization from 60% to 66%) without repaying first THEN it is allowed", async () => {
        marketDAI.connect(bob).approve(john.address, parseUnits("5"));
        await expect(marketDAI.connect(john).transferFrom(bob.address, john.address, parseUnits("5"))).to.not.be
          .reverted;
      });
      it("WHEN trying to withdraw the entire position (100 DAI) without repaying first THEN it reverts with INSUFFICIENT_LIQUIDITY", async () => {
        await expect(exactlyEnv.withdrawSP("DAI", "100")).to.be.revertedWith("InsufficientLiquidity()");
      });
      it("AND WHEN trying to withdraw a small amount that doesnt cause a shortfall (5 DAI, should move collateralization from 60% to 66%) without repaying first THEN it is allowed", async () => {
        await expect(exactlyEnv.withdrawSP("DAI", "5")).to.not.be.reverted;
      });
    });
  });
});