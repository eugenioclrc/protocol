// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

struct Pool {
    uint256 borrowed;
    uint256 lent;
}

interface IExafin {
    function rateBorrow(uint256 amount, uint256 maturityDate) external view returns (uint256, Pool memory);
    function rateLend(uint256 amount, uint256 maturityDate) external view returns (uint256, Pool memory);
    function lend(address to, uint256 amount, uint256 maturityDate) external;
    function borrow(address from, uint256 amount, uint256 maturityDate) external;
}