import {uploadToPinata} from '@aragon/osx-commons-sdk';

import buildMetadata from '../src/build-metadata.json';
import releaseMetadata from '../src/release-metadata.json';

import {ethers} from 'ethers';

async function uploadMetadataToIPFS(subdomainName: string): Promise<string> {
  const buildMetadataCIDPath = await uploadToPinata(
    JSON.stringify(buildMetadata, null, 2),
    `${subdomainName}-build-metadata`
  );

  const releaseMetadataCIDPath = await uploadToPinata(
    JSON.stringify(releaseMetadata, null, 2),
    `${subdomainName}-release-metadata`
  );

  return ethers.utils.defaultAbiCoder.encode(['string', 'string'], [buildMetadataCIDPath, releaseMetadataCIDPath]);
}

(async () => {
  console.log(await uploadMetadataToIPFS(process.argv[2]));
})();