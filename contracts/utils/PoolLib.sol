// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./TSUtils.sol";
import "./Errors.sol";
import "hardhat/console.sol";

library PoolLib {
    /**
     * @notice struct that helps manage the maturity pools and also keep
     * @param borrowed total amount borrowed at the MP
     * @param supplied total amount supplied to the MP
     * @param suppliedSP total amount borrowed over time from the SP.
     *        It's worth noticing that it only increases, and it's the last
     *        debt to be repaid at maturity
     * @param earnings total amount of earnings to be collected at maturity.
     *        This earnings haven't accrued yet (see: lastAccrue). Each interaction
     *        with the MP, some of these earnings are accrued to earningsSP. This is
     *        done by doing:
     *             EARNINGSSP += DAYS(NOW - LAST_ACCRUE) * EARNINGS /
     *                              DAYS(MATURITY_DATE - LAST_ACCRUE)
     *        If there's a new deposit to the MP, the commission for that deposit comes
     *        out of the future earnings:
     *              NEWCOMMISSION = DEPOSIT * EARNINGS / (SUPPLIEDSP + DEPOSIT);
     *              EARNINGS -= NEWCOMMISSION;
     * @param earningsSP total amount of earnings that already belong to the SP
     * @param lastAccrue timestamp for the last time that some of the earnings
     *        have been transferred to earningsSP (SP gained some earnings for having
     *        supported the loans)
     */
    struct MaturityPool {
        uint256 borrowed;
        uint256 supplied;
        uint256 suppliedSP;
        uint256 earningsUnassigned;
        uint256 lastAccrue;
    }

    struct Position {
        uint256 principal;
        uint256 fee;
    }

    /**
     * @notice function that registers an operation to add money to
     *         maturity pool
     * @param pool maturity pool where money will be added
     * @param amount amount to be added to the maturity pool
     */
    function addMoney(MaturityPool storage pool, uint256 amount)
        internal
        returns (uint256 smartPoolDebtReduction)
    {
        uint256 suppliedSP = pool.suppliedSP;
        uint256 supplied = pool.supplied;

        smartPoolDebtReduction = Math.min(suppliedSP, amount);

        pool.supplied = supplied + amount;
        pool.suppliedSP = suppliedSP - smartPoolDebtReduction;
    }

    /**
     * @notice function that registers an operation to add money to
     *         maturity pool
     * @param pool maturity pool where money will be added
     * @param amount amount to be added to the maturity pool
     */
    function repayMoney(MaturityPool storage pool, uint256 amount)
        internal
        returns (uint256 smartPoolDebtReduction)
    {
        uint256 suppliedSP = pool.suppliedSP;
        uint256 borrowed = pool.borrowed;

        smartPoolDebtReduction = Math.min(suppliedSP, amount);

        pool.borrowed = borrowed - amount;
        pool.suppliedSP = suppliedSP - smartPoolDebtReduction;
    }

    /**
     * @notice function that registers an operation to take money out of the
     *         maturity pool that returns if there's new debt to be taken out
     *         of the smart pool
     * @param pool maturity pool where money needs to be taken out
     * @param amount amount to be taken out of the pool before it matures
     * @return newDebtSP amount of new debt that needs to be taken out of the SP
     */
    function takeMoney(
        MaturityPool storage pool,
        uint256 amount,
        uint256 maxDebt
    ) internal returns (uint256 newDebtSP) {
        uint256 newBorrowedMP = pool.borrowed + amount;
        uint256 suppliedMP = pool.supplied;
        uint256 suppliedALL = pool.suppliedSP + suppliedMP;

        if (newBorrowedMP > suppliedALL) {
            uint256 newSupplySP = newBorrowedMP - suppliedMP;

            if (newSupplySP > maxDebt) {
                revert GenericError(ErrorCode.INSUFFICIENT_PROTOCOL_LIQUIDITY);
            }

            // We take money out from the Smart Pool
            // because there's not enough in the MP
            newDebtSP = newBorrowedMP - suppliedALL;
            pool.suppliedSP = newSupplySP;
        }

        pool.borrowed = newBorrowedMP;
    }

    /**
     * @notice function that registers an operation to withdraw money out of the
     *         maturity pool that returns if there's new debt to be taken out
     *         of the smart pool
     * @param pool maturity pool where money needs to be withdrawn
     * @param amount amount to be taken out of the pool before it matures
     * @return newDebtSP amount of new debt that needs to be taken out of the SP
     */
    function withdrawMoney(
        MaturityPool storage pool,
        uint256 amount,
        uint256 maxDebt
    ) internal returns (uint256 newDebtSP) {
        uint256 borrowedMP = pool.borrowed;
        uint256 newSuppliedMP = pool.supplied - amount;
        uint256 newSuppliedALL = pool.suppliedSP + newSuppliedMP;

        // by reducing supply we might need to take debt from SP
        if (borrowedMP > newSuppliedALL) {
            // We verify the SP is not taking too much debt
            uint256 newSupplySP = borrowedMP - newSuppliedMP;
            if (newSupplySP > maxDebt) {
                revert GenericError(ErrorCode.INSUFFICIENT_PROTOCOL_LIQUIDITY);
            }

            // We take money out from the Smart Pool
            // because there's not enough in the MP
            newDebtSP = borrowedMP - newSuppliedALL;
            pool.suppliedSP = newSupplySP;
        }

        pool.supplied = newSuppliedMP;
    }

    /**
     * @notice External function to add fee to be collected at maturity
     * @param pool maturity pool that needs to be updated
     * @param fee fee to be added to the earnings for the pool at maturity
     */
    function addFee(MaturityPool storage pool, uint256 fee) internal {
        pool.earningsUnassigned += fee;
    }

    /**
     * @notice External function to remove fee to be collected from the maturity pool
     * @param pool maturity pool that needs to be updated
     * @param fee fee to be removed from the unassigned earnings
     */
    function removeFee(MaturityPool storage pool, uint256 fee) internal {
        pool.earningsUnassigned -= fee;
    }

    /**
     * @notice External function to accrue Smart Pool earnings
     * @param pool maturity pool that needs to be updated
     * @param maturityID timestamp in which maturity pool matures
     */
    function accrueEarnings(
        MaturityPool storage pool,
        uint256 maturityID,
        uint256 currentTimestamp
    ) internal returns (uint256 earningsSP) {
        uint256 lastAccrue = pool.lastAccrue;

        if (lastAccrue == maturityID) {
            return 0;
        }

        // seconds from last accrual to the closest:
        // maturity date or the current timestamp
        uint256 secondsSinceLastAccrue = TSUtils.secondsPre(
            lastAccrue,
            Math.min(maturityID, currentTimestamp)
        );
        // seconds from last accrual to the maturity date
        uint256 secondsTotalToMaturity = TSUtils.secondsPre(
            lastAccrue,
            maturityID
        );
        pool.lastAccrue = Math.min(maturityID, currentTimestamp);

        // assign some of the earnings to be collected at maturity
        uint256 earningsUnassigned = pool.earningsUnassigned;
        earningsSP = secondsTotalToMaturity == 0
            ? 0
            : (earningsUnassigned * secondsSinceLastAccrue) /
                secondsTotalToMaturity;
        pool.earningsUnassigned = earningsUnassigned - earningsSP;
    }

    function scaleProportionally(Position memory debt, uint256 amount)
        internal
        pure
        returns (Position memory)
    {
        // we proportionally reduce the values
        uint256 principal = (debt.principal * amount) /
            (debt.principal + debt.fee);
        debt.principal = principal;
        debt.fee = amount - principal;
        return debt;
    }

    function reduceProportionally(Position memory debt, uint256 amount)
        internal
        pure
        returns (Position memory)
    {
        // we proportionally reduce the values
        uint256 principal = (debt.principal * amount) /
            (debt.principal + debt.fee);
        debt.principal -= principal;
        debt.fee -= amount - principal;
        return debt;
    }

    function reduceFees(Position memory debt, uint256 fee)
        internal
        pure
        returns (Position memory)
    {
        // we only reduce the fees
        debt.fee = debt.fee - fee;
        return debt;
    }
}
