import { randomBytes } from "crypto";
import { bytesToHex } from "viem";
import { ethers } from "ethers";
import {
    delegationManager,
    account,
    publicClient,
    ecdsaRegistryContract,
    avsDirectory,
    serviceManager,
} from "./utils";


// Setup env variables
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
const wallet_2 = new ethers.Wallet(process.env.PRIVATE_KEY_2!, provider);

export const registerOperator = async () => {

    // Registers as an Operator in EigenLayer.
    try {
        const tx1 = await delegationManager.registerAsOperator(
            "0x0000000000000000000000000000000000000000", // initDelegationApprover
            0, // allocationDelay
            "", // metadataURI
        );
        await tx1.wait();
        console.log("Operator registered to Core EigenLayer contracts");
    } catch (error) {
        console.error("Error in registering as operator:", error);
    }
    const salt = ethers.zeroPadValue(ethers.randomBytes(32), 32); // force pad
    const expiry = Math.floor(Date.now() / 1000) + 3600; // Example 

    const currentNonce = await provider.getTransactionCount(wallet.address);


    const tx = await avsDirectory.initialize(wallet.address, 0, {
        nonce: currentNonce // Use correct nonce explicitly
    });
    await tx.wait();
    console.log("AVSDirectory initialized");
    // expiry, 1 hour from now

    // Define the output structure
    let operatorSignatureWithSaltAndExpiry = {
        signature: "",
        salt: salt,
        expiry: expiry
    };

    // Calculate the digest hash, which is a unique value representing the operator, avs, unique value (salt) and expiration date.
    // const operatorDigestHash = await avsDirectory.callStatic.calculateOperatorAVSRegistrationDigestHash(
    //     wallet.address,
    //     await serviceManager.getAddress(),
    //     salt,
    //     expiry
    //   );
    // console.log(operatorDigestHash);

    const digest = await avsDirectory.calculateOperatorAVSRegistrationDigestHash(
        wallet.address,
        await serviceManager.getAddress(),
        salt,
        expiry
    );
    console.log("Digest to sign:", digest);


    // // Sign the digest hash with the operator's private key
    // console.log("Signing digest hash with operator's private key");
    // const operatorSigningKey = new ethers.SigningKey(process.env.PRIVATE_KEY!);
    // const operatorSignedDigestHash = operatorSigningKey.sign(digest);

    const operatorSigningKey = new ethers.SigningKey(wallet.privateKey);  // No need to fetch from env again

// Digest must be a 32-byte hex string
const signature = operatorSigningKey.sign(digest);

// Serialized signature (r, s, v)
operatorSignatureWithSaltAndExpiry.signature = ethers.Signature.from(signature).serialized;
    // Encode the signature in the required format
    operatorSignatureWithSaltAndExpiry.signature = ethers.Signature.from(operatorSignedDigestHash).serialized;

    console.log("Registering Operator to AVS Registry contract");


    // Register Operator to AVS
    // Per release here: https://github.com/Layr-Labs/eigenlayer-middleware/blob/v0.2.1-mainnet-rewards/src/unaudited/ECDSAStakeRegistry.sol#L49
    const tx2 = await ecdsaRegistryContract.registerOperatorWithSignature(
        operatorSignatureWithSaltAndExpiry,
        wallet.address
    );
    await tx2.wait();
    console.log("Operator registered on AVS successfully");
};