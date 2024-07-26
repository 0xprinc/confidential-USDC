import { ethers } from "hardhat";

import type { FiatTokenV2_2 } from "../../types";
import { getSigners } from "../signers";

export async function deployUSDC(): Promise<FiatTokenV2_2> {
  const signers = await getSigners(ethers);

  const contractFactory = await ethers.getContractFactory("FiatTokenV2_2");
  const contract = await contractFactory.connect(signers.alice).deploy();
  await contract.waitForDeployment();
  console.log("deployToken -> " + await contract.getAddress());
  return contract;
}
