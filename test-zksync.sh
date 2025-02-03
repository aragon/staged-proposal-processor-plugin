### Remappings for single solidity files are not supported yet.

cp src/StagedProposalProcessorSetup.sol src/temp.sol
cp src/StagedProposalProcessorSetupZkSync.sol src/StagedProposalProcessorSetup.sol

forge-zk test --zksync

mv src/temp.sol src/StagedProposalProcessorSetup.sol
