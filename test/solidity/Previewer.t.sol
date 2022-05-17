// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { Vm } from "forge-std/Vm.sol";
import { Test } from "forge-std/Test.sol";
import { FixedPointMathLib } from "@rari-capital/solmate-v6/src/utils/FixedPointMathLib.sol";
import { InterestRateModel } from "../../contracts/InterestRateModel.sol";
import { Auditor, ExactlyOracle } from "../../contracts/Auditor.sol";
import { MockToken } from "../../contracts/mocks/MockToken.sol";
import { MockOracle } from "../../contracts/mocks/MockOracle.sol";
import { FixedLender } from "../../contracts/FixedLender.sol";
import { Previewer } from "../../contracts/periphery/Previewer.sol";

contract PreviewerTest is Test {
  using FixedPointMathLib for uint256;
  address internal constant BOB = address(69);
  address internal constant ALICE = address(70);

  FixedLender internal fixedLender;
  Previewer internal previewer;
  MockToken internal mockToken;
  Auditor internal auditor;
  MockOracle internal mockOracle;
  InterestRateModel internal interestRateModel;

  function setUp() external {
    mockToken = new MockToken("DAI", "DAI", 18, 150_000 ether);
    mockOracle = new MockOracle();
    mockOracle.setPrice("DAI", 1e18);
    auditor = new Auditor(ExactlyOracle(address(mockOracle)), 1.1e18);
    interestRateModel = new InterestRateModel(0.72e18, -0.22e18, 3e18, 2e18, 0.1e18);

    fixedLender = new FixedLender(mockToken, "DAI", 12, 1e18, auditor, interestRateModel, 0.02e18 / uint256(1 days), 0);
    auditor.enableMarket(fixedLender, 0.8e18, "DAI", "DAI", 18);

    vm.label(BOB, "Bob");
    vm.label(ALICE, "Alice");
    mockToken.transfer(BOB, 50_000 ether);
    mockToken.transfer(ALICE, 50_000 ether);
    mockToken.approve(address(fixedLender), 50_000 ether);
    vm.prank(BOB);
    mockToken.approve(address(fixedLender), 50_000 ether);
    vm.prank(ALICE);
    mockToken.approve(address(fixedLender), 50_000 ether);

    previewer = new Previewer(auditor);
  }

  function testPreviewDepositAtMaturityReturningAccurateAmount() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(maturity, 1 ether, 2 ether, address(this), address(this));

    vm.warp(3 days);
    uint256 positionAssetsPreviewed = previewer.previewDepositAtMaturity(fixedLender, maturity, 1 ether);
    fixedLender.depositAtMaturity(maturity, 1 ether, 1 ether, address(this));
    (uint256 principalAfterDeposit, uint256 earningsAfterDeposit) = fixedLender.mpUserSuppliedAmount(
      maturity,
      address(this)
    );

    assertEq(positionAssetsPreviewed, principalAfterDeposit + earningsAfterDeposit);
  }

  function testPreviewDepositAtMaturityWithZeroAmount() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(maturity, 1 ether, 2 ether, address(this), address(this));

    vm.warp(3 days);
    uint256 earningsPreviewed = previewer.previewDepositAtMaturity(fixedLender, maturity, 0);

    assertEq(earningsPreviewed, 0);
  }

  function testPreviewDepositAtMaturityWithOneUnit() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(maturity, 1 ether, 2 ether, address(this), address(this));

    vm.warp(3 days);
    uint256 positionAssetsPreviewed = previewer.previewDepositAtMaturity(fixedLender, maturity, 1);

    assertEq(positionAssetsPreviewed, 1);
  }

  function testPreviewDepositAtMaturityReturningAccurateAmountWithIntermediateOperations() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(maturity, 1 ether, 2 ether, address(this), address(this));

    vm.warp(2 days);
    fixedLender.borrowAtMaturity(maturity, 2.3 ether, 3 ether, address(this), address(this));

    vm.warp(3 days);
    uint256 positionAssetsPreviewed = previewer.previewDepositAtMaturity(fixedLender, maturity, 0.47 ether);
    fixedLender.depositAtMaturity(maturity, 0.47 ether, 0.47 ether, address(this));
    (uint256 principalAfterDeposit, uint256 earningsAfterDeposit) = fixedLender.mpUserSuppliedAmount(
      maturity,
      address(this)
    );
    assertEq(positionAssetsPreviewed, principalAfterDeposit + earningsAfterDeposit);

    vm.warp(5 days);
    positionAssetsPreviewed = previewer.previewDepositAtMaturity(fixedLender, maturity, 1 ether);
    fixedLender.depositAtMaturity(maturity, 1 ether, 1 ether, BOB);
    (principalAfterDeposit, earningsAfterDeposit) = fixedLender.mpUserSuppliedAmount(maturity, BOB);
    assertEq(positionAssetsPreviewed, principalAfterDeposit + earningsAfterDeposit);

    vm.warp(6 days);
    positionAssetsPreviewed = previewer.previewDepositAtMaturity(fixedLender, maturity, 20 ether);
    fixedLender.depositAtMaturity(maturity, 20 ether, 20 ether, ALICE);
    (principalAfterDeposit, earningsAfterDeposit) = fixedLender.mpUserSuppliedAmount(maturity, ALICE);
    assertEq(positionAssetsPreviewed, principalAfterDeposit + earningsAfterDeposit);
  }

  function testPreviewDepositAtMaturityWithEmptyMaturity() external {
    assertEq(previewer.previewDepositAtMaturity(fixedLender, 7 days, 1 ether), 1 ether);
  }

  function testPreviewDepositAtMaturityWithEmptyMaturityAndZeroAmount() external {
    assertEq(previewer.previewDepositAtMaturity(fixedLender, 7 days, 0), 0);
  }

  function testPreviewDepositAtMaturityWithInvalidMaturity() external {
    assertEq(previewer.previewDepositAtMaturity(fixedLender, 376 seconds, 1 ether), 1 ether);
  }

  function testPreviewDepositAtMaturityWithSameTimestamp() external {
    uint256 maturity = 7 days;
    vm.warp(maturity);
    assertEq(previewer.previewDepositAtMaturity(fixedLender, maturity, 1 ether), 1 ether);
  }

  function testFailPreviewDepositAtMaturityWithMaturedMaturity() external {
    uint256 maturity = 7 days;
    vm.warp(maturity + 1);
    previewer.previewDepositAtMaturity(fixedLender, maturity, 1 ether);
  }

  function testPreviewBorrowAtMaturityReturningAccurateAmount() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    uint256 positionAssetsPreviewed = previewer.previewBorrowAtMaturity(fixedLender, maturity, 1 ether);
    fixedLender.borrowAtMaturity(maturity, 1 ether, 2 ether, address(this), address(this));
    (uint256 principalAfterBorrow, uint256 feesAfterBorrow) = fixedLender.mpUserBorrowedAmount(maturity, address(this));

    assertEq(positionAssetsPreviewed, principalAfterBorrow + feesAfterBorrow);
  }

  function testPreviewBorrowAtMaturityWithZeroAmount() external {
    fixedLender.deposit(10 ether, address(this));
    assertEq(previewer.previewBorrowAtMaturity(fixedLender, 7 days, 0), 0);
  }

  function testPreviewBorrowAtMaturityWithOneUnit() external {
    fixedLender.deposit(10 ether, address(this));
    assertEq(previewer.previewBorrowAtMaturity(fixedLender, 7 days, 1), 1);
  }

  function testPreviewBorrowAtMaturityWithFiveUnits() external {
    fixedLender.deposit(10 ether, address(this));
    assertEq(previewer.previewBorrowAtMaturity(fixedLender, 7 days, 5), 5);
  }

  function testPreviewBorrowAtMaturityReturningAccurateAmountWithIntermediateOperations() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.deposit(10 ether, BOB);
    fixedLender.deposit(50 ether, ALICE);

    vm.warp(2 days);
    uint256 positionAssetsPreviewed = previewer.previewBorrowAtMaturity(fixedLender, maturity, 2.3 ether);
    fixedLender.borrowAtMaturity(maturity, 2.3 ether, 3 ether, address(this), address(this));
    (uint256 principalAfterBorrow, uint256 feesAfterBorrow) = fixedLender.mpUserBorrowedAmount(maturity, address(this));
    assertEq(positionAssetsPreviewed, principalAfterBorrow + feesAfterBorrow);

    vm.warp(3 days);
    fixedLender.depositAtMaturity(maturity, 1.47 ether, 1.47 ether, address(this));

    vm.warp(5 days);
    positionAssetsPreviewed = previewer.previewBorrowAtMaturity(fixedLender, maturity, 1 ether);
    vm.prank(BOB);
    fixedLender.borrowAtMaturity(maturity, 1 ether, 2 ether, BOB, BOB);
    (principalAfterBorrow, feesAfterBorrow) = fixedLender.mpUserBorrowedAmount(maturity, BOB);
    assertEq(positionAssetsPreviewed, principalAfterBorrow + feesAfterBorrow);

    vm.warp(6 days);
    positionAssetsPreviewed = previewer.previewBorrowAtMaturity(fixedLender, maturity, 20 ether);
    vm.prank(ALICE);
    fixedLender.borrowAtMaturity(maturity, 20 ether, 30 ether, ALICE, ALICE);
    (principalAfterBorrow, feesAfterBorrow) = fixedLender.mpUserBorrowedAmount(maturity, ALICE);
    assertEq(positionAssetsPreviewed, principalAfterBorrow + feesAfterBorrow);
  }

  function testPreviewBorrowAtMaturityWithInvalidMaturity() external {
    fixedLender.deposit(10 ether, address(this));
    uint256 positionAssetsPreviewed = previewer.previewBorrowAtMaturity(fixedLender, 376 seconds, 1 ether);
    assertGe(positionAssetsPreviewed, 1 ether);
  }

  function testFailPreviewBorrowAtMaturityWithSameTimestamp() external {
    uint256 maturity = 7 days;
    vm.warp(maturity);
    previewer.previewBorrowAtMaturity(fixedLender, maturity, 1 ether);
  }

  function testFailPreviewBorrowAtMaturityWithMaturedMaturity() external {
    uint256 maturity = 7 days;
    vm.warp(maturity + 1);
    previewer.previewBorrowAtMaturity(fixedLender, maturity, 1 ether);
  }

  function testPreviewRepayAtMaturityReturningAccurateAmount() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.deposit(10 ether, BOB);
    fixedLender.borrowAtMaturity(maturity, 1 ether, 2 ether, address(this), address(this));

    vm.prank(BOB);
    fixedLender.borrowAtMaturity(maturity, 2 ether, 3 ether, BOB, BOB);

    vm.warp(3 days);
    uint256 repayAssetsPreviewed = previewer.previewRepayAtMaturity(fixedLender, maturity, 1 ether, address(this));
    uint256 balanceBeforeRepay = mockToken.balanceOf(address(this));
    fixedLender.repayAtMaturity(maturity, 1 ether, 1 ether, address(this));
    uint256 discountAfterRepay = 1 ether - (balanceBeforeRepay - mockToken.balanceOf(address(this)));

    assertEq(repayAssetsPreviewed, 1 ether - discountAfterRepay);
  }

  function testPreviewRepayAtMaturityWithZeroAmount() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(maturity, 1 ether, 2 ether, address(this), address(this));

    vm.warp(3 days);
    uint256 repayAssetsPreviewed = previewer.previewRepayAtMaturity(fixedLender, maturity, 0, address(this));

    assertEq(repayAssetsPreviewed, 0);
  }

  function testPreviewRepayAtMaturityWithOneUnit() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(maturity, 1 ether, 2 ether, address(this), address(this));
    vm.warp(3 days);

    assertEq(previewer.previewRepayAtMaturity(fixedLender, maturity, 1, address(this)), 1);
  }

  function testPreviewRepayAtMaturityReturningAccurateAmountWithIntermediateOperations() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.deposit(10 ether, BOB);
    fixedLender.borrowAtMaturity(maturity, 3 ether, 4 ether, address(this), address(this));

    vm.warp(2 days);
    vm.prank(BOB);
    fixedLender.borrowAtMaturity(maturity, 2.3 ether, 3 ether, BOB, BOB);

    vm.warp(3 days);
    uint256 repayAssetsPreviewed = previewer.previewRepayAtMaturity(fixedLender, maturity, 0.47 ether, address(this));
    uint256 balanceBeforeRepay = mockToken.balanceOf(address(this));
    fixedLender.repayAtMaturity(maturity, 0.47 ether, 0.47 ether, address(this));
    uint256 discountAfterRepay = 0.47 ether - (balanceBeforeRepay - mockToken.balanceOf(address(this)));
    assertEq(repayAssetsPreviewed, 0.47 ether - discountAfterRepay);

    vm.warp(5 days);
    repayAssetsPreviewed = previewer.previewRepayAtMaturity(fixedLender, maturity, 1.1 ether, address(this));
    balanceBeforeRepay = mockToken.balanceOf(address(this));
    fixedLender.repayAtMaturity(maturity, 1.1 ether, 1.1 ether, address(this));
    discountAfterRepay = 1.1 ether - (balanceBeforeRepay - mockToken.balanceOf(address(this)));
    assertEq(repayAssetsPreviewed, 1.1 ether - discountAfterRepay);

    vm.warp(6 days);
    (uint256 bobOwedPrincipal, uint256 bobOwedFee) = fixedLender.mpUserBorrowedAmount(maturity, BOB);
    uint256 totalOwedBob = bobOwedPrincipal + bobOwedFee;
    repayAssetsPreviewed = previewer.previewRepayAtMaturity(fixedLender, maturity, totalOwedBob, BOB);
    balanceBeforeRepay = mockToken.balanceOf(BOB);
    vm.prank(BOB);
    fixedLender.repayAtMaturity(maturity, totalOwedBob, totalOwedBob, BOB);
    discountAfterRepay = totalOwedBob - (balanceBeforeRepay - mockToken.balanceOf(BOB));
    (bobOwedPrincipal, ) = fixedLender.mpUserBorrowedAmount(maturity, BOB);
    assertEq(repayAssetsPreviewed, totalOwedBob - discountAfterRepay);
    assertEq(bobOwedPrincipal, 0);
  }

  function testPreviewRepayAtMaturityWithEmptyMaturity() external {
    assertEq(previewer.previewRepayAtMaturity(fixedLender, 7 days, 1 ether, address(this)), 1 ether);
  }

  function testPreviewRepayAtMaturityWithEmptyMaturityAndZeroAmount() external {
    assertEq(previewer.previewRepayAtMaturity(fixedLender, 7 days, 0, address(this)), 0);
  }

  function testPreviewRepayAtMaturityWithInvalidMaturity() external {
    assertEq(previewer.previewRepayAtMaturity(fixedLender, 376 seconds, 1 ether, address(this)), 1 ether);
  }

  function testPreviewRepayAtMaturityWithSameTimestamp() external {
    uint256 maturity = 7 days;
    vm.warp(maturity);

    assertEq(previewer.previewRepayAtMaturity(fixedLender, maturity, 1 ether, address(this)), 1 ether);
  }

  function testPreviewRepayAtMaturityWithMaturedMaturity() external {
    uint256 maturity = 7 days;
    vm.warp(maturity + 100);
    uint256 penalties = uint256(1 ether).fmul(100 * fixedLender.penaltyRate(), 1e18);

    assertEq(previewer.previewRepayAtMaturity(fixedLender, maturity, 1 ether, address(this)), 1 ether + penalties);
  }

  function testPreviewWithdrawAtMaturityReturningAccurateAmount() external {
    uint256 maturity = 7 days;
    fixedLender.depositAtMaturity(maturity, 10 ether, 10 ether, address(this));

    vm.warp(3 days);
    uint256 withdrawAssetsPreviewed = previewer.previewWithdrawAtMaturity(fixedLender, maturity, 10 ether);
    uint256 balanceBeforeWithdraw = mockToken.balanceOf(address(this));
    fixedLender.withdrawAtMaturity(maturity, 10 ether, 0.9 ether, address(this), address(this));
    uint256 feeAfterWithdraw = 10 ether - (mockToken.balanceOf(address(this)) - balanceBeforeWithdraw);

    assertEq(withdrawAssetsPreviewed, 10 ether - feeAfterWithdraw);
  }

  function testPreviewWithdrawAtMaturityWithZeroAmount() external {
    uint256 maturity = 7 days;
    fixedLender.depositAtMaturity(maturity, 1 ether, 1 ether, address(this));

    vm.warp(3 days);
    assertEq(previewer.previewWithdrawAtMaturity(fixedLender, maturity, 0), 0);
  }

  function testPreviewWithdrawAtMaturityWithOneUnit() external {
    uint256 maturity = 7 days;
    fixedLender.depositAtMaturity(maturity, 1 ether, 1 ether, address(this));

    vm.warp(3 days);
    uint256 feesPreviewed = previewer.previewWithdrawAtMaturity(fixedLender, maturity, 1);

    assertEq(feesPreviewed, 1 - 1);
  }

  function testPreviewWithdrawAtMaturityWithFiveUnits() external {
    uint256 maturity = 7 days;
    fixedLender.depositAtMaturity(maturity, 1 ether, 1 ether, address(this));

    vm.warp(3 days);
    uint256 feesPreviewed = previewer.previewWithdrawAtMaturity(fixedLender, maturity, 5);

    assertEq(feesPreviewed, 5 - 1);
  }

  function testPreviewWithdrawAtMaturityReturningAccurateAmountWithIntermediateOperations() external {
    uint256 maturity = 7 days;
    fixedLender.deposit(10 ether, address(this));
    fixedLender.deposit(10 ether, BOB);
    fixedLender.depositAtMaturity(maturity, 5 ether, 5 ether, address(this));

    vm.warp(2 days);
    vm.prank(BOB);
    fixedLender.borrowAtMaturity(maturity, 2.3 ether, 3 ether, BOB, BOB);

    vm.warp(3 days);
    uint256 withdrawAssetsPreviewed = previewer.previewWithdrawAtMaturity(fixedLender, maturity, 0.47 ether);
    uint256 balanceBeforeWithdraw = mockToken.balanceOf(address(this));
    fixedLender.withdrawAtMaturity(maturity, 0.47 ether, 0.4 ether, address(this), address(this));
    uint256 feeAfterWithdraw = 0.47 ether - (mockToken.balanceOf(address(this)) - balanceBeforeWithdraw);
    assertEq(withdrawAssetsPreviewed, 0.47 ether - feeAfterWithdraw);

    vm.warp(5 days);
    withdrawAssetsPreviewed = previewer.previewWithdrawAtMaturity(fixedLender, maturity, 1.1 ether);
    balanceBeforeWithdraw = mockToken.balanceOf(address(this));
    fixedLender.withdrawAtMaturity(maturity, 1.1 ether, 1 ether, address(this), address(this));
    feeAfterWithdraw = 1.1 ether - (mockToken.balanceOf(address(this)) - balanceBeforeWithdraw);
    assertEq(withdrawAssetsPreviewed, 1.1 ether - feeAfterWithdraw);

    vm.warp(6 days);
    (uint256 contractPositionPrincipal, uint256 contractPositionEarnings) = fixedLender.mpUserSuppliedAmount(
      maturity,
      address(this)
    );
    uint256 contractPosition = contractPositionPrincipal + contractPositionEarnings;
    withdrawAssetsPreviewed = previewer.previewWithdrawAtMaturity(fixedLender, maturity, contractPosition);
    balanceBeforeWithdraw = mockToken.balanceOf(address(this));
    fixedLender.withdrawAtMaturity(
      maturity,
      contractPosition,
      contractPosition - 1 ether,
      address(this),
      address(this)
    );
    feeAfterWithdraw = contractPosition - (mockToken.balanceOf(address(this)) - balanceBeforeWithdraw);
    (contractPositionPrincipal, ) = fixedLender.mpUserSuppliedAmount(maturity, address(this));

    assertEq(withdrawAssetsPreviewed, contractPosition - feeAfterWithdraw);
  }

  function testFailPreviewWithdrawAtMaturityWithEmptyMaturity() external view {
    previewer.previewWithdrawAtMaturity(fixedLender, 7 days, 1 ether);
  }

  function testFailPreviewWithdrawAtMaturityWithEmptyMaturityAndZeroAmount() external view {
    previewer.previewWithdrawAtMaturity(fixedLender, 7 days, 0);
  }

  function testFailPreviewWithdrawAtMaturityWithInvalidMaturity() external view {
    previewer.previewWithdrawAtMaturity(fixedLender, 376 seconds, 1 ether);
  }

  function testPreviewWithdrawAtMaturityWithSameTimestamp() external {
    uint256 maturity = 7 days;
    vm.warp(maturity);

    assertEq(previewer.previewWithdrawAtMaturity(fixedLender, maturity, 1 ether), 1 ether);
  }

  function testPreviewWithdrawAtMaturityWithMaturedMaturity() external {
    uint256 maturity = 7 days;
    vm.warp(maturity + 1);
    assertEq(previewer.previewWithdrawAtMaturity(fixedLender, maturity, 1 ether), 1 ether);
  }

  function testExtendedAccountDataReturningAccurateAmounts() external {
    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(7 days, 1 ether, 2 ether, address(this), address(this));

    Previewer.ExtendedAccountMarketData[] memory data = previewer.extendedAccountData(address(this));

    // We sum all the collateral prices
    uint256 sumCollateral = data[0].smartPoolAssets.fmul(data[0].oraclePrice, 10**data[0].decimals).fmul(
      data[0].collateralFactor,
      1e18
    );

    // We sum all the debt
    uint256 sumDebt = (data[0].maturityBorrowPositions[0].position.principal +
      data[0].maturityBorrowPositions[0].position.fee).fmul(data[0].oraclePrice, 10**data[0].decimals);

    (uint256 realCollateral, uint256 realDebt) = auditor.accountLiquidity(address(this), FixedLender(address(0)), 0);

    assertEq(sumCollateral, realCollateral);
    assertEq(sumDebt, realDebt);
  }

  function testAccountLiquidityWithIntermediateOperationsReturningAccurateAmounts() external {
    // we deploy a new token for more liquidity combinations
    MockToken mockTokenWETH = new MockToken("WETH", "WETH", 18, 150_000 ether);
    mockOracle.setPrice("WETH", 2800e18);
    FixedLender fixedLenderWETH = new FixedLender(
      mockTokenWETH,
      "WETH",
      12,
      1e18,
      auditor,
      interestRateModel,
      0.02e18 / uint256(1 days),
      0
    );
    auditor.enableMarket(fixedLenderWETH, 0.7e18, "WETH", "WETH", 18);
    mockTokenWETH.approve(address(fixedLenderWETH), 50_000 ether);

    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(7 days, 1 ether, 2 ether, address(this), address(this));
    fixedLender.borrowAtMaturity(7 days, 1.321 ether, 2 ether, address(this), address(this));
    fixedLender.deposit(2 ether, address(this));

    Previewer.ExtendedAccountMarketData[] memory data = previewer.extendedAccountData(address(this));

    // We sum all the collateral prices
    uint256 sumCollateral = data[0].smartPoolAssets.fmul(data[0].oraclePrice, 10**data[0].decimals).fmul(
      data[0].collateralFactor,
      1e18
    );

    // We sum all the debt
    uint256 sumDebt = (data[0].maturityBorrowPositions[0].position.principal +
      data[0].maturityBorrowPositions[0].position.fee).fmul(data[0].oraclePrice, 10**data[0].decimals);

    (uint256 realCollateral, uint256 realDebt) = auditor.accountLiquidity(address(this), FixedLender(address(0)), 0);
    assertEq(sumCollateral - sumDebt, realCollateral - realDebt);
    assertEq(data[0].isCollateral, true);

    fixedLenderWETH.deposit(100 ether, address(this));
    data = previewer.extendedAccountData(address(this));
    assertEq(data[1].smartPoolAssets, 100 ether);
    assertEq(data[1].isCollateral, false);
    assertEq(data.length, 2);

    FixedLender[] memory fixedLenders = new FixedLender[](1);
    fixedLenders[0] = fixedLenderWETH;
    auditor.enterMarkets(fixedLenders);
    data = previewer.extendedAccountData(address(this));
    sumCollateral += data[1].smartPoolAssets.fmul(data[1].oraclePrice, 10**data[1].decimals).fmul(
      data[1].collateralFactor,
      1e18
    );
    (realCollateral, realDebt) = auditor.accountLiquidity(address(this), FixedLender(address(0)), 0);
    assertEq(sumCollateral - sumDebt, realCollateral - realDebt);
    assertEq(data[1].isCollateral, true);

    mockOracle.setPrice("WETH", 2800e18);
    fixedLenderWETH.borrowAtMaturity(14 days, 33 ether, 40 ether, address(this), address(this));
    data = previewer.extendedAccountData(address(this));

    sumCollateral =
      data[0].smartPoolAssets.fmul(data[0].oraclePrice, 10**data[0].decimals).fmul(data[0].collateralFactor, 1e18) +
      data[1].smartPoolAssets.fmul(data[1].oraclePrice, 10**data[1].decimals).fmul(data[1].collateralFactor, 1e18);

    sumDebt += (data[1].maturityBorrowPositions[0].position.principal + data[1].maturityBorrowPositions[0].position.fee)
      .fmul(data[1].oraclePrice, 10**data[1].decimals);

    (realCollateral, realDebt) = auditor.accountLiquidity(address(this), FixedLender(address(0)), 0);
    assertEq(sumCollateral - sumDebt, realCollateral - realDebt);

    mockOracle.setPrice("WETH", 1831e18);
    data = previewer.extendedAccountData(address(this));
    assertEq(data[1].oraclePrice, 1831e18);
  }

  function testExtendedAccountDataWithAccountThatHasBalances() external {
    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(7 days, 1 ether, 2 ether, address(this), address(this));
    fixedLender.depositAtMaturity(7 days, 1 ether, 1 ether, address(this));
    fixedLender.borrowAtMaturity(14 days, 2.33 ether, 3 ether, address(this), address(this));
    fixedLender.depositAtMaturity(14 days, 1.19 ether, 1.19 ether, address(this));
    (uint256 firstMaturitySupplyPrincipal, uint256 firstMaturitySupplyFee) = fixedLender.mpUserSuppliedAmount(
      7 days,
      address(this)
    );
    (uint256 secondMaturitySupplyPrincipal, uint256 secondMaturitySupplyFee) = fixedLender.mpUserSuppliedAmount(
      14 days,
      address(this)
    );
    (uint256 firstMaturityBorrowPrincipal, uint256 firstMaturityBorrowFee) = fixedLender.mpUserBorrowedAmount(
      7 days,
      address(this)
    );
    (uint256 secondMaturityBorrowPrincipal, uint256 secondMaturityBorrowFee) = fixedLender.mpUserBorrowedAmount(
      14 days,
      address(this)
    );

    Previewer.ExtendedAccountMarketData[] memory data = previewer.extendedAccountData(address(this));

    assertEq(data[0].assetSymbol, "DAI");
    assertEq(data[0].smartPoolAssets, 10 ether);
    assertEq(data[0].smartPoolShares, fixedLender.convertToShares(data[0].smartPoolAssets));

    assertEq(data[0].maturitySupplyPositions[0].maturity, 7 days);
    assertEq(data[0].maturitySupplyPositions[0].position.principal, firstMaturitySupplyPrincipal);
    assertEq(data[0].maturitySupplyPositions[0].position.fee, firstMaturitySupplyFee);
    assertEq(data[0].maturitySupplyPositions[1].maturity, 14 days);
    assertEq(data[0].maturitySupplyPositions[1].position.principal, secondMaturitySupplyPrincipal);
    assertEq(data[0].maturitySupplyPositions[1].position.fee, secondMaturitySupplyFee);
    assertEq(data[0].maturitySupplyPositions.length, 2);
    assertEq(data[0].maturityBorrowPositions[0].maturity, 7 days);
    assertEq(data[0].maturityBorrowPositions[0].position.principal, firstMaturityBorrowPrincipal);
    assertEq(data[0].maturityBorrowPositions[0].position.fee, firstMaturityBorrowFee);
    assertEq(data[0].maturityBorrowPositions[1].maturity, 14 days);
    assertEq(data[0].maturityBorrowPositions[1].position.principal, secondMaturityBorrowPrincipal);
    assertEq(data[0].maturityBorrowPositions[1].position.fee, secondMaturityBorrowFee);
    assertEq(data[0].maturityBorrowPositions.length, 2);

    assertEq(data[0].oraclePrice, 1e18);
    assertEq(data[0].collateralFactor, 0.8e18);
    assertEq(data[0].penaltyRate, fixedLender.penaltyRate());
    assertEq(data[0].decimals, 18);
    assertEq(data[0].isCollateral, true);
  }

  function testExtendedAccountDataWithAccountOnlyDeposit() external {
    fixedLender.deposit(10 ether, address(this));
    Previewer.ExtendedAccountMarketData[] memory data = previewer.extendedAccountData(address(this));

    assertEq(data[0].assetSymbol, "DAI");
    assertEq(data[0].smartPoolAssets, 10 ether);
    assertEq(data[0].smartPoolShares, fixedLender.convertToShares(10 ether));
    assertEq(data[0].maturitySupplyPositions.length, 0);
    assertEq(data[0].maturityBorrowPositions.length, 0);
    assertEq(data[0].oraclePrice, 1e18);
    assertEq(data[0].collateralFactor, 0.8e18);
    assertEq(data[0].decimals, 18);
    assertEq(data[0].isCollateral, false);
  }

  function testExtendedAccountDataWithEmptyAccount() external {
    Previewer.ExtendedAccountMarketData[] memory data = previewer.extendedAccountData(address(this));

    assertEq(data[0].assetSymbol, "DAI");
    assertEq(data[0].smartPoolAssets, 0);
    assertEq(data[0].smartPoolShares, 0);
    assertEq(data[0].maturitySupplyPositions.length, 0);
    assertEq(data[0].maturityBorrowPositions.length, 0);
    assertEq(data[0].oraclePrice, 1e18);
    assertEq(data[0].collateralFactor, 0.8e18);
    assertEq(data[0].decimals, 18);
    assertEq(data[0].penaltyRate, fixedLender.penaltyRate());
    assertEq(data[0].isCollateral, false);
  }

  function testAccountDataWithAccountThatHasBalances() external {
    fixedLender.deposit(10 ether, address(this));
    fixedLender.borrowAtMaturity(7 days, 1 ether, 2 ether, address(this), address(this));
    (uint256 principal, uint256 fees) = fixedLender.mpUserBorrowedAmount(7 days, address(this));

    Previewer.AccountMarketData[] memory data = previewer.accountData(address(this));

    assertEq(data[0].smartPoolAssets, 10 ether);
    assertEq(data[0].borrowedAssets, principal + fees);
    assertEq(data[0].oraclePrice, 1e18);
    assertEq(data[0].collateralFactor, 0.8e18);
    assertEq(data[0].decimals, 18);
    assertEq(data[0].isCollateral, true);
  }

  function testAccountDataWithAccountOnlyDeposit() external {
    fixedLender.deposit(10 ether, address(this));
    Previewer.AccountMarketData[] memory data = previewer.accountData(address(this));

    assertEq(data[0].smartPoolAssets, 10 ether);
    assertEq(data[0].borrowedAssets, 0);
    assertEq(data[0].oraclePrice, 1e18);
    assertEq(data[0].collateralFactor, 0.8e18);
    assertEq(data[0].decimals, 18);
    assertEq(data[0].isCollateral, false);
  }

  function testAccountDataWithEmptyAccount() external {
    Previewer.AccountMarketData[] memory data = previewer.accountData(address(this));

    assertEq(data[0].smartPoolAssets, 0);
    assertEq(data[0].borrowedAssets, 0);
    assertEq(data[0].oraclePrice, 1e18);
    assertEq(data[0].collateralFactor, 0.8e18);
    assertEq(data[0].decimals, 18);
    assertEq(data[0].isCollateral, false);
  }
}