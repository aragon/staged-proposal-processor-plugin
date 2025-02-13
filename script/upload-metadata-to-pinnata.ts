import buildMetadata from '../src/build-metadata.json';
import releaseMetadata from '../src/release-metadata.json';

import {ethers} from 'ethers';
import dotenv from 'dotenv';
import path from 'path';
import {uploadToPinata} from '@aragon/osx-commons-sdk';

dotenv.config({path: path.resolve(__dirname, '../.env')});

async function uploadMetadataToIPFS(subdomainName: string): Promise<string> {
  if (!process.env.PUB_PINATA_JWT) {
    throw new Error('PUB_PINATA_JWT is not set');
  }

  const buildMetadataCIDPath = await uploadToPinata(
    buildMetadata,
    `${subdomainName}-build-metadata`,
    process.env.PUB_PINATA_JWT
  );

  const releaseMetadataCIDPath = await uploadToPinata(
    releaseMetadata,
    `${subdomainName}-release-metadata`,
    process.env.PUB_PINATA_JWT
  );

  return ethers.utils.defaultAbiCoder.encode(
    ['string', 'string'],
    [buildMetadataCIDPath, releaseMetadataCIDPath]
  );
}

(async () => {
  console.log(await uploadMetadataToIPFS(process.argv[2]));
})();
