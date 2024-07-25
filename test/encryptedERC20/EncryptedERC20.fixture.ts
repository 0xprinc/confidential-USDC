import { ethers } from "hardhat";

import type { FiatTokenV2_2 } from "../../types";
import { getSigners } from "../signers";

export async function deployFiatTokenV2_2Fixture(): Promise<FiatTokenV2_2> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("FiatTokenV2_2");
  const contract = await contractFactory.connect(signers.alice).deploy(); // City of Zama's battle
  await contract.waitForDeployment();
  console.log("Token Address: " + contract.getAddress());
  return contract;
}
