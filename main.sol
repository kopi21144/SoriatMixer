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
        bool onboarded;
        bytes32 label;
        uint64 joinedAt;
        uint32 noteTally;
    }

    uint256 public constant SRM_TIER_CAP = 8;
    uint256 public constant SRM_NOTE_FEE = 0.003 ether;
    uint256 public constant SRM_OPERATOR_STAKE = 0.08 ether;
    uint256 public constant SRM_MAX_NOTES = 156;
    uint256 public constant SRM_OPEN_BATCH_CAP = 42;
    uint256 public constant SRM_BLEND_FLOOR = 541;
    uint256 public constant SRM_BLEND_CEIL = 8345;
    uint256 public constant SRM_ROUND_BLOCKS = 549;
    uint256 public constant SRM_WEIGHT_CAP = 17822;
    uint256 public constant SRM_SCORE_FLOOR = 369;
    uint256 public constant SRM_SCORE_CEIL = 8141;

    bytes32 private constant _PEPPER_0 = 0x5f3f6b74506fcb64ee69b34141c674240a6f441d1bab4d4c48750fd5bc80e2ec;
    bytes32 private constant _PEPPER_1 = 0x115008296a3645717616dc2b63f725a0a9372c8b2c6ac4632b1c2f9b5ab64041;
    bytes32 private constant _PEPPER_2 = 0xfc4660f8aa6273642b32bc3c5c3c1566f9f7eb7d90034e841fb6173b5c2b4133;
    bytes32 private constant _PEPPER_3 = 0x8895a9aebdc20b9bec673ff1490e9c283f0598f83922e1d3c67fad17b6fb4405;
    bytes32 private constant _PEPPER_4 = 0xa1c348457710eeb2adb22d5c3aea60eee54ae41b2c3268c50c7fa2f605eef42d;
    bytes32 private constant _PEPPER_5 = 0x48a065e1a4e34ec14c3898181ca713377f7dcd95ae704a8ae66f3e581cc6ff0b;
    bytes32 private constant _PEPPER_6 = 0xb731f56f29513acccf8f1e2c7c08a33a06b46b1d56df71aedbb143becf4e7a26;
    bytes32 private constant _PEPPER_7 = 0x6bfd9c4afaa3150ec34626498b23c5b2848f05b2c5b1fdea64bdb9c565fb330c;
    bytes32 private constant SRM_DOMAIN = keccak256("SoriatMixer.foldPotRelay");

    address public immutable ADDRESS_A;
    address public immutable ADDRESS_B;
    address public immutable ADDRESS_C;

    address public sheriff;
    address public pendingSheriff;
    address public mixer;
    bool public gridFrozen;
    uint256 public activeRound;
    uint256 public tickSerial;
    uint256 public openBatches;
    uint256 public totalLockedWei;
    uint256 public deployBlock;

    mapping(uint256 => SrmPot) public pots;
    mapping(bytes32 => SrmNote) public notes;
    mapping(bytes32 => SrmBatch) public batches;
    mapping(bytes32 => SrmPulse) public pulses;
    mapping(uint256 => SrmBlendRing) public blendRings;
    mapping(uint256 => mapping(address => uint256)) public operatorWeight;
    mapping(bytes32 => mapping(address => bool)) public claimCast;
    mapping(bytes32 => bool) public noteIdUsed;
    mapping(bytes32 => bool) public batchIdUsed;
    mapping(bytes32 => bool) public pulseIdUsed;
    mapping(address => SrmOperatorDesk) public operatorDesks;
    mapping(address => bytes32[]) private _notesByDepositor;
    bytes32[] private _noteIndex;
    uint256 private _lock;

    modifier nonReentrant() {
        if (_lock == 2) revert SOR_Reentered();
        _lock = 2;
        _;
        _lock = 1;
    }

    modifier onlySheriff() {
        if (msg.sender != sheriff) revert SOR_NotSheriff();
        _;
    }

    modifier onlyMixer() {
        if (msg.sender != mixer) revert SOR_NotMixer();
        _;
    }

