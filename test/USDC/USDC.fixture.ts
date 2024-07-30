import { ethers } from "hardhat";

import type { FiatTokenV2_2, OriginalToken } from "../../types";
import { getSigners } from "../signers";

export async function deployUSDC(): Promise<OriginalToken> {
  const signers = await getSigners(ethers);

  const contractFactory = await ethers.getContractFactory("OriginalToken");
  const contract = await contractFactory.connect(signers.alice).deploy();
  await contract.waitForDeployment();
  console.log("deploy_USDC -> " + await contract.getAddress());
  return contract;
}
export async function deploycUSDC(address:string): Promise<FiatTokenV2_2> {
  const signers = await getSigners(ethers);

  const contractFactory = await ethers.getContractFactory("FiatTokenV2_2");
  const contract = await contractFactory.connect(signers.alice).deploy(address);
  await contract.waitForDeployment();
  console.log("deploy_cUSDC -> " + await contract.getAddress());
  return contract;
}
