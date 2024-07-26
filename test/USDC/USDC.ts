import { expect } from "chai";
import { ethers } from "hardhat";

import { createInstances } from "../instance";
import { getSigners } from "../signers";
import { createTransaction } from "../utils";
import { deployUSDC } from "./USDC.fixture";
// import { InitializeCalldataStruct, StrategyStruct } from "../../types";
import { assert } from "console";
import fhevmjs, { FhevmInstance } from "fhevmjs";

import { AbiCoder } from "ethers";

// Remove the duplicate import statement for 'ethers'

describe("USDC", function () {
  before(async function () {
    this.signers = await getSigners(ethers);
  });

  // beforeEach(async function () {

  // });

  

  it("initialize USDC", async function () {

    console.log("\n 1) Deploying contracts... \n")

    const contractUSDC = await deployUSDC();

    const addressUSDC = await contractUSDC.getAddress();

    let fhevmInstance = await createInstances(addressUSDC, ethers, this.signers);

    const tokenAlice = fhevmInstance.alice.getPublicKey(addressUSDC) || {
      signature: "",
      publicKey: "",
    };
    
    const tokenBob = fhevmInstance.bob.getPublicKey(addressUSDC) || {
      signature: "",
      publicKey: "",
    };

    const tokenCarol = fhevmInstance.carol.getPublicKey(addressUSDC) || {
      signature: "",
      publicKey: "",
    };

  {
    console.log("\n\ 2) Initializing USDC contract \n");
    
    // console.log("owner before initialize: " + await contractSpace.owner());
    try {
      const txn = await contractUSDC.initialize(
        "USDC",
        "USDC",
        "USDC",
        4,
        this.signers.alice.getAddress(),
        this.signers.alice.getAddress(),
        this.signers.alice.getAddress(),
        this.signers.alice.getAddress(),
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("Initialize function call successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

  }

  {
    console.log("\n\ 3) Minting tokens to bob \n");
    
    // console.log("owner before initialize: " + await contractSpace.owner());
    try {
      const txn = await contractUSDC.connect(this.signers.alice).configureMinter(
        this.signers.bob.getAddress(),
        fhevmInstance.alice.encrypt32(100000)                                             // 1e5 USDC
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("Configure Bob as minter successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

    try {
      const txn = await contractUSDC.connect(this.signers.bob).mint(
        this.signers.bob.getAddress(),
        fhevmInstance.bob.encrypt32(100000)                                             // 1e5 USDC
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("minting 1e5 usdc to bob successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }
    
    let bobBalance = await contractUSDC.connect(this.signers.bob).balanceOf(tokenBob.publicKey, tokenBob.signature, this.signers.bob.getAddress());
    
    console.log("Bob's balance: " + fhevmInstance.bob.decrypt(addressUSDC, bobBalance));

    console.log("total supply: " + fhevmInstance.alice.decrypt(addressUSDC, await contractUSDC.connect(this.signers.alice).totalSupply(tokenAlice.publicKey, tokenAlice.signature)));

  }

  {
    console.log("\n\ 4) Transfering tokens to Carol \n");
    
    try {
      const txn = await contractUSDC.connect(this.signers.bob).increaseAllowance(
        this.signers.carol.getAddress(),
        fhevmInstance.bob.encrypt32(100000),        // 1e5 USDC

      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("bob allowing 1e5 tokens to carol successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

    try {
      const txn = await contractUSDC.connect(this.signers.carol).transferFrom(
        this.signers.bob.getAddress(),
        this.signers.carol.getAddress(),
        fhevmInstance.bob.encrypt32(100000),        // 1e5 USDC

      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("carol calling transferFrom to transfer 1e5 to her successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

    let carolBalance = await contractUSDC.connect(this.signers.carol).balanceOf(tokenCarol.publicKey, tokenCarol.signature, this.signers.carol.getAddress());
    console.log("Carol's balance: " + fhevmInstance.carol.decrypt(addressUSDC, carolBalance));


  }

  {
    console.log("\n\ 5) Burning tokens of Carol \n");

    try {
      const txn = await contractUSDC.connect(this.signers.alice).configureMinter(
        this.signers.carol.getAddress(),
        fhevmInstance.alice.encrypt32(100000)                                             // 1e5 USDC
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("configuring carol as minter(role required also to burn the tokens) successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }
    
    try {
      const txn = await contractUSDC.connect(this.signers.carol).burn(
        fhevmInstance.bob.encrypt32(100000),        // 1e5 USDC
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("burn transaction of 1e4 tokens by carol successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

    let carolBalance = await contractUSDC.connect(this.signers.carol).balanceOf(tokenCarol.publicKey, tokenCarol.signature, this.signers.carol.getAddress());
    console.log("Carol's balance: " + fhevmInstance.carol.decrypt(addressUSDC, carolBalance));

    console.log("total supply: " + fhevmInstance.alice.decrypt(addressUSDC, await contractUSDC.connect(this.signers.alice).totalSupply(tokenAlice.publicKey, tokenAlice.signature)));


  }




  });

});

// });