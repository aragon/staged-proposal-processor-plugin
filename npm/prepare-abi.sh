#!/usr/bin/env bash

# Exit on error
set -e

# Constants
CONTRACTS_FOLDER="../src"
BUILD_OUT_FOLDER="../out"
TARGET_ABI_FILE="./src/abi.ts"

# Move into contracts package and install dependencies
cd $CONTRACTS_FOLDER

yarn --ignore-scripts && yarn build

# Move back to artifacts package
cd - > /dev/null

# Wipe the destination file
echo "// NOTE: Do not edit this file. It is generated automatically." > $TARGET_ABI_FILE

# Extract the abi field and create a TS file
for SRC_CONTRACT_FILE in $(ls $CONTRACTS_FOLDER/*.sol )
do
    SRC_FILE_NAME=$(basename $(echo $SRC_CONTRACT_FILE))
    CONTRACT_NAME=${SRC_FILE_NAME%".sol"}
    SRC_FILE_PATH=$BUILD_OUT_FOLDER/$SRC_FILE_NAME/${SRC_FILE_NAME%".sol"}.json

    # Some ZkSync variants keep the contract name
    if [[ "$SRC_FILE_PATH" == *ZkSync.json ]]
    then
      SRC_FILE_PATH=${SRC_FILE_PATH%"ZkSync.json"}.json
    fi

    ABI=$(node -e "console.log(JSON.stringify(JSON.parse(fs.readFileSync(\"$SRC_FILE_PATH\").toString()).abi))")

    echo "const ${CONTRACT_NAME}ABI = $ABI as const;" >> $TARGET_ABI_FILE
    echo "export {${CONTRACT_NAME}ABI};" >> $TARGET_ABI_FILE

    echo "" >> $TARGET_ABI_FILE
done

echo "ABI prepared: $TARGET_ABI_FILE"
