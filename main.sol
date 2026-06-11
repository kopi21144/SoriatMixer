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
    event Released(bytes32 indexed batchId, bytes32 payloadHash, uint16 blendScore, uint256 roundId);
    event Blended(bytes32 indexed pulseId, uint256 indexed potId, uint16 blendBand, uint256 stampedAt);
    event Pooled(uint256 indexed potId, bytes32 potKey, uint8 tier, uint256 weightSeed);
    event Rotated(uint256 indexed roundId, uint64 wallClock, uint256 noteWeight, uint256 batchWeight);
    event Frozen(bool gridFrozen, address indexed by, uint256 atBlock);
    event SheriffQueued(address indexed pending, uint256 atBlock);
    event SheriffAccepted(address indexed prev, address indexed next, uint256 atBlock);
    event OperatorOnboard(address indexed operator, bytes32 label, uint256 stakeWei);
    event OperatorOff(address indexed operator, uint256 atBlock);
    event PotFunded(address indexed from, uint256 weiAmt, uint256 atBlock);
    event Tick_0(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_1(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_2(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_3(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_4(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_5(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_6(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_7(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_8(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_9(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);
    event Tick_10(uint256 indexed slot, address indexed actor, uint256 meta, uint256 roundId);

    enum SrmPotPhase { Idle, Live, Closed }
    enum SrmBatchPhase { Queued, Mixing, Settled, Voided }

    struct SrmPot {
        SrmPotPhase phase;
        uint8 blendTier;
        uint64 openedAt;
        uint32 noteTally;
        uint32 batchTally;
        uint256 weightSum;
        bytes32 potKey;
    }

    struct SrmNote {
        uint256 potId;
        address depositor;
        bytes32 commitment;
        uint8 blendTier;
        uint32 yesClaims;
        uint32 noClaims;
        uint256 lockedWei;
        uint64 depositedAt;
        bool active;
    }

    struct SrmBatch {
        uint256 potId;
        address submitter;
        bytes32 blendTag;
        SrmBatchPhase phase;
        bytes32 releaseHash;
        uint16 blendScore;
        uint64 queuedAt;
    }

    struct SrmPulse {
        uint256 potId;
        bytes32 pulseTag;
        bytes32 laneHash;
        uint16 blendBand;
        uint64 stampedAt;
    }

    struct SrmBlendRing {
        uint64 openedAt;
        uint256 noteWeight;
        uint256 batchWeight;
        bytes32 foldHA;
        bytes32 foldHB;
    }

    struct SrmOperatorDesk {
