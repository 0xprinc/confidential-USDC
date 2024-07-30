import { expect } from "chai";
import { ethers } from "hardhat";

import { createInstances } from "../instance";
import { getSigners } from "../signers";
import { createTransaction } from "../utils";
import { deployUSDC, deploycUSDC } from "./USDC.fixture";
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
    const contract_USDC = await deployUSDC();
    const contract_cUSDC = await deploycUSDC(await contract_USDC.getAddress());

    const addressUSDC = await contract_USDC.getAddress();
    const addresscUSDC = await contract_cUSDC.getAddress();
    const addressAlice = this.signers.alice.getAddress();
    const addressBob = this.signers.bob.getAddress();
    const addressCarol = this.signers.carol.getAddress();
    const addressDave = this.signers.dave.getAddress();

    let fhevmInstance = await createInstances(addresscUSDC, ethers, this.signers);

    const tokenAlice = fhevmInstance.alice.getPublicKey(addresscUSDC) || {
      signature: "",
      publicKey: "",
    };
    
    const tokenBob = fhevmInstance.bob.getPublicKey(addresscUSDC) || {
      signature: "",
      publicKey: "",
    };

    const tokenCarol = fhevmInstance.carol.getPublicKey(addresscUSDC) || {
      signature: "",
      publicKey: "",
    };

    const tokenDave = fhevmInstance.dave.getPublicKey(addresscUSDC) || {
      signature: "",
      publicKey: "",
    };

    try {
      const txn = await contract_USDC.mint(
        addressBob,
        1000000
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("minting 1e6 tokens to bob successful");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

    console.log("USDC balance of Bob:" + await contract_USDC.balanceOf(addressBob));
  
    try {
      const txn = await contract_USDC.connect(this.signers.bob).approve(
        addresscUSDC,
        1000000000000000
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("bob approved cUSDC 1e15 tokens successful");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

    console.log("USDC allowance by Bob given to cUSDC" + await contract_USDC.allowance(addressBob, addresscUSDC));

  {
    console.log("\n\ 2) Initializing USDC contract \n");
    
    // console.log("owner before initialize: " + await contractSpace.owner());
    try {
      const txn = await contract_cUSDC.initialize(
        "USDC",
        "USDC",
        "USDC",
        4,
        this.signers.alice.getAddress(),
        this.signers.alice.getAddress(),
        this.signers.alice.getAddress(),
        this.signers.alice.getAddress()
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
    
    // try {
    //   const txn = await contract_cUSDC.connect(this.signers.alice).configureMinter(
    //     this.signers.bob.getAddress(),
    //     fhevmInstance.alice.encrypt32(100000)                                             // 1e5 USDC
    //   );
    //   console.log("Transaction hash:", txn.hash);
    
    //   // Wait for 1 confirmation (adjust confirmations as needed)
    //   await txn.wait(1);
    //   console.log("Configure Bob as minter successful!");
    // } catch (error) {
    //   console.error("Transaction failed:", error);
    //   // Handle the error appropriately (e.g., retry, notify user)
    // }

    try {
      const txn = await contract_cUSDC.connect(this.signers.bob).wrap(
        1000000                                          // 1e6 USDC
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("wrapping 1e5 cUSDC to bob successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }
    
    let bobBalance = await contract_cUSDC.connect(this.signers.bob).balanceOf(tokenBob.publicKey, tokenBob.signature, this.signers.bob.getAddress());
    
    console.log("Bob's balance: " + fhevmInstance.bob.decrypt(addresscUSDC, bobBalance));

    console.log("total supply: " + fhevmInstance.alice.decrypt(addresscUSDC, await contract_cUSDC.connect(this.signers.alice).totalSupply(tokenAlice.publicKey, tokenAlice.signature)));

  }

  {
    console.log("\n\ 4) Transfering tokens to Carol \n");
    
    try {
      const txn = await contract_cUSDC.connect(this.signers.bob).increaseAllowance(
        this.signers.carol.getAddress(),
        fhevmInstance.bob.encrypt32(1000000),        // 1e5 USDC

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
      const txn = await contract_cUSDC.connect(this.signers.carol).transferFrom(
        this.signers.bob.getAddress(),
        this.signers.carol.getAddress(),
        fhevmInstance.carol.encrypt32(1000000),        // 1e6 USDC

      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("carol calling transferFrom to transfer 1e5 to her successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

    let carolBalance = await contract_cUSDC.connect(this.signers.carol).balanceOf(tokenCarol.publicKey, tokenCarol.signature, this.signers.carol.getAddress());
    console.log("Carol's balance: " + fhevmInstance.carol.decrypt(addresscUSDC, carolBalance));

    try {
      const txn = await contract_cUSDC.connect(this.signers.alice).delegateViewerStatus(
        await this.signers.dave.getAddress(),
        true
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("delegating the viewing rights to dave successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

    console.log("dave trying to view the balance of carol");
    let carolBalance2 = await contract_cUSDC.connect(this.signers.dave).balanceOf(tokenDave.publicKey, tokenDave.signature, this.signers.carol.getAddress());
    console.log("Carol's balance when dave is trying to fetch it: " + fhevmInstance.dave.decrypt(addresscUSDC, carolBalance2));

  }

  {
    console.log("\n\ 5) Burning tokens of Carol \n");

    // try {
    //   const txn = await contract_cUSDC.connect(this.signers.alice).configureMinter(
    //     this.signers.carol.getAddress(),
    //     fhevmInstance.alice.encrypt32(100000)                                             // 1e6 USDC
    //   );
    //   console.log("Transaction hash:", txn.hash);
    
    //   // Wait for 1 confirmation (adjust confirmations as needed)
    //   await txn.wait(1);
    //   console.log("configuring carol as minter(role required also to burn the tokens) successful!");
    // } catch (error) {
    //   console.error("Transaction failed:", error);
    //   // Handle the error appropriately (e.g., retry, notify user)
    // }
    
    try {
      const txn = await contract_cUSDC.connect(this.signers.carol).unwrap(
        1000000,        // 1e6 USDC
      );
      console.log("Transaction hash:", txn.hash);
    
      // Wait for 1 confirmation (adjust confirmations as needed)
      await txn.wait(1);
      console.log("burn transaction of 1e4 tokens by carol successful!");
    } catch (error) {
      console.error("Transaction failed:", error);
      // Handle the error appropriately (e.g., retry, notify user)
    }

    let carolBalance = await contract_cUSDC.connect(this.signers.carol).balanceOf(tokenCarol.publicKey, tokenCarol.signature, this.signers.carol.getAddress());
    console.log("Carol's balance: " + fhevmInstance.carol.decrypt(addresscUSDC, carolBalance));

    console.log("total supply: " + fhevmInstance.alice.decrypt(addresscUSDC, await contract_cUSDC.connect(this.signers.alice).totalSupply(tokenAlice.publicKey, tokenAlice.signature)));

    console.log("USDC balance of Carol:" + await contract_USDC.balanceOf(addressCarol));
  }




  });

});

// });