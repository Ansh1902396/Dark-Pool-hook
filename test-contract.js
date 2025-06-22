const { ethers } = require('ethers');
require('dotenv').config({ path: './operator/.env' });

async function testContract() {
    const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

    // Load deployment data
    const fs = require('fs');
    const path = require('path');

    const coreDeploymentData = JSON.parse(fs.readFileSync(path.resolve(__dirname, `./avs/deployments/core/31337.json`), 'utf8'));
    const avsDeploymentData = JSON.parse(fs.readFileSync(path.resolve(__dirname, `./avs/deployments/avs/31337.json`), 'utf8'));

    const avsDirectoryAddress = coreDeploymentData.addresses.avsDirectory;
    const avsServiceManagerAddress = avsDeploymentData.addresses.avsServiceManager;

    console.log('AVS Directory address:', avsDirectoryAddress);
    console.log('AVS Service Manager address:', avsServiceManagerAddress);

    // Check if contract exists
    console.log('\nChecking if contract exists...');
    const code = await provider.getCode(avsDirectoryAddress);
    console.log('Contract bytecode length:', code.length);
    console.log('Contract bytecode (first 100 chars):', code.substring(0, 100));

    if (code === '0x') {
        console.log('ERROR: No contract deployed at this address!');
        return;
    }

    // Load ABI
    const avsDirectoryABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, './abis/IAVSDirectory.json'), 'utf8'));

    // Create contract instance
    const avsDirectory = new ethers.Contract(avsDirectoryAddress, avsDirectoryABI, wallet);

    try {
        // Check available functions
        console.log('\nAvailable functions in ABI:');
        avsDirectoryABI.forEach(func => {
            if (func.type === 'function') {
                console.log(`- ${func.name}`);
            }
        });

        console.log('\nTesting OPERATOR_AVS_REGISTRATION_TYPEHASH...');
        const typeHash = await avsDirectory.OPERATOR_AVS_REGISTRATION_TYPEHASH();
        console.log('Type hash:', typeHash);

        // Test the problematic function
        console.log('\nTesting calculateOperatorAVSRegistrationDigestHash...');
        const salt = ethers.hexlify(ethers.randomBytes(32));
        const expiry = Math.floor(Date.now() / 1000) + 3600;

        console.log('Parameters:');
        console.log('- operator:', wallet.address);
        console.log('- avs:', avsServiceManagerAddress);
        console.log('- salt:', salt);
        console.log('- expiry:', expiry);

        const digestHash = await avsDirectory.calculateOperatorAVSRegistrationDigestHash(
            wallet.address,
            avsServiceManagerAddress,
            salt,
            expiry
        );
        console.log('Digest hash:', digestHash);

    } catch (error) {
        console.error('Error:', error);
        console.error('Error details:', {
            code: error.code,
            value: error.value,
            info: error.info
        });
    }
}

testContract(); 