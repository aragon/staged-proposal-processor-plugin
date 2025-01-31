import {ethers} from 'ethers';

const fs = require('fs').promises;

async function storeDeployments() {
  const chainId = process.argv[2];
  const addresses = process.argv[3].replace(/^"(.*)"$/, '$1');

  const decoded = ethers.utils.defaultAbiCoder.decode(['address[]'], addresses);
  const arrayAddr: string[] = decoded[0];

  const json = {
    StagedProposalProcessorRepoProxy: {
      address: arrayAddr[0],
      blockNumber: null, 
      deploymentTx: null
    },
    StagedProposalProcessorRepoImplementation: {
      address: arrayAddr[1],
      blockNumber: null, 
      deploymentTx: null
    }
  }

  await fs.writeFile('deployed-contracts.json', JSON.stringify(json, null, 2));
}

(async () => {
  await storeDeployments();
})();