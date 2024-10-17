// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

struct Users {
    address manager;
    address alice;
    address bob;
    address charlie;
    address dave;
    address eve;
    address unauthorized;
}

// helper type for fuzzing
struct Plugin {
    address pluginAddress;
    bool isManual;
    address allowedBody;
    uint8 resultType;
    bool tryAdvance;
}

struct Stage {
    uint64 maxAdvance;
    uint64 minAdvance;
    uint64 voteDuration;
    uint16 approvalThreshold;
    uint16 vetoThreshold;
}
