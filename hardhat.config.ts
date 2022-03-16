import "dotenv/config";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "solidity-coverage";
import "hardhat-deploy";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import "hardhat-contract-sizer";
import { env } from "process";
import type { HardhatUserConfig as Config } from "hardhat/types";

const config: Config = {
  solidity: { version: "0.8.4" },
  networks: {
    hardhat: {
      tokens: ["DAI", "WETH", "USDC", "WBTC"],
      accounts: { accountsBalance: `1${"0".repeat(32)}` },
    },
    kovan: {
      tokens: ["DAI", "WETH"],
      url: env.KOVAN_NODE ?? "https://kovan.infura.io/",
      ...(env.MNEMONIC && { accounts: { mnemonic: env.MNEMONIC } }),
    },
  },
  namedAccounts: {
    deployer: { default: 0 },
    multisig: {
      default: 0,
      rinkeby: "0x0820289Cb202DbF23B709D4AC1a346331cd590c4",
    },
  },
  finance: {
    collateralFactor: { default: 0.8, WBTC: 0.6 },
    interestRateModel: {
      curveA: 0.0495,
      curveB: -0.025,
      maxUtilizationRate: 1.1,
      penaltyRatePerDay: 0.02,
      smartPoolRate: 0.1,
    },
  },
  typechain: { outDir: "types", target: "ethers-v5" },
  gasReporter: {
    currency: "USD",
    gasPrice: 100,
    enabled: env.REPORT_GAS ? true : false,
  },
};

export default config;

declare module "hardhat/types/config" {
  export interface FinanceConfig {
    collateralFactor: { default: number; [token: string]: number };
    interestRateModel: {
      curveA: number;
      curveB: number;
      maxUtilizationRate: number;
      penaltyRatePerDay: number;
      smartPoolRate: number;
    };
  }

  export interface HardhatUserConfig {
    finance: FinanceConfig;
  }

  export interface HardhatConfig {
    finance: FinanceConfig;
  }

  export interface HardhatNetworkUserConfig {
    tokens: string[];
  }

  export interface HttpNetworkUserConfig {
    tokens: string[];
  }

  export interface HardhatNetworkConfig {
    tokens: string[];
  }

  export interface HttpNetworkConfig {
    tokens: string[];
  }
}
