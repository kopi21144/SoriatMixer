// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title SoriatMixer — soroban-styled batch pot blender for onchain settlement lanes.
/// @author codename: violet tumbler / duplex notch forty-one

library SrmWeigh {
    error SOR_ScaleFault();
    uint256 internal constant BPS = 10_000;
    function boundU16(uint256 v, uint16 lo, uint16 hi) internal pure returns (uint16) {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return uint16(v);
    }
    function sliceFee(uint256 gross, uint256 bps) internal pure returns (uint256) {
        unchecked { return (gross * bps) / BPS; }
    }
    function cappedSum(uint256 a, uint256 b, uint256 cap) internal pure returns (uint256) {
        unchecked {
            uint256 s = a + b;
            if (s < a || s > cap) revert SOR_ScaleFault();
            return s;
        }
    }
}

contract SoriatMixer {
    error SOR_NotSheriff();
    error SOR_NotMixer();
    error SOR_GridFrozen();
    error SOR_ZeroAddr();
    error SOR_ZeroWei();
    error SOR_Reentered();
    error SOR_PotVoid();
    error SOR_PotSealed();
    error SOR_NoteExists();
    error SOR_NoteMissing();
    error SOR_TierBad();
    error SOR_QuotaFull();
    error SOR_RoundBad();
    error SOR_BatchOpen();
    error SOR_BatchMissing();
    error SOR_BatchDone();
    error SOR_OperatorStale();
    error SOR_ScoreLow();
    error SOR_ScoreHigh();
    error SOR_HandoffSelf();
    error SOR_HashVoid();
    error SOR_ClaimUsed();
    error SOR_ClaimSelf();
    error SOR_StakeLow();
    error SOR_NativeFail();
    error SOR_BatchWide();
    error SOR_LengthMismatch();
    error SOR_NotOperator();
    error SOR_OperatorKnown();
    error SOR_NoPending();
    error SOR_PendingMismatch();
    error SOR_LineFault_31();
    error SOR_LineFault_32();
    error SOR_LineFault_33();
    error SOR_LineFault_34();
    error SOR_LineFault_35();
    error SOR_LineFault_36();
    error SOR_LineFault_37();
    error SOR_LineFault_38();
    error SOR_LineFault_39();
    error SOR_LineFault_40();
    error SOR_LineFault_41();

    event Deposited(bytes32 indexed noteId, uint256 indexed potId, address indexed depositor, uint8 tier, uint256 weiAmt);
    event Claimed(bytes32 indexed noteId, address indexed claimant, bool affirm, uint256 roundId);
    event Staked(bytes32 indexed noteId, address indexed from, uint256 weiAmt, uint256 roundId);
    event Queued(bytes32 indexed batchId, uint256 indexed potId, bytes32 blendTag, uint256 queuedAt);
