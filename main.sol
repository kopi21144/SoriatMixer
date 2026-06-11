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

    modifier whenGridLive() {
        if (gridFrozen) revert SOR_GridFrozen();
        _;
    }

    modifier onlyOnboardedOperator() {
        if (!operatorDesks[msg.sender].onboarded) revert SOR_NotOperator();
        _;
    }

    constructor() {
        ADDRESS_A = 0x92cFddDCa1e0AA4fD2d63BC2E9F3E3b77f95449d;
        ADDRESS_B = 0x82230Cb7a047e775A298c2Fe921Aa0dC2d0A2d38;
        ADDRESS_C = 0xF61B81b03Db00A264Ffc7ecDC1dD4F927E5C5fa0;
        sheriff = msg.sender;
        mixer = ADDRESS_A;
        _lock = 1;
        deployBlock = block.number;
        activeRound = 1;
        _openRound(1);
        _seedPots();
    }

    function queueSheriff(address next_) external onlySheriff {
        if (next_ == address(0) || next_ == sheriff) revert SOR_ZeroAddr();
        pendingSheriff = next_;
        emit SheriffQueued(next_, block.number);
    }

    function acceptSheriff() external {
        if (msg.sender != pendingSheriff) revert SOR_PendingMismatch();
        address prev = sheriff;
        sheriff = pendingSheriff;
        pendingSheriff = address(0);
        emit SheriffAccepted(prev, sheriff, block.number);
    }

    function assignMixer(address next_) external onlySheriff {
        if (next_ == address(0)) revert SOR_ZeroAddr();
        mixer = next_;
    }

    function setGridFrozen(bool on) external onlySheriff {
        gridFrozen = on;
        emit Frozen(on, msg.sender, block.number);
    }

    function advanceRound() external onlySheriff whenGridLive {
        uint256 n = activeRound + 1;
        if (n > 29) revert SOR_RoundBad();
        activeRound = n;
        _openRound(n);
        emit Rotated(n, uint64(block.timestamp), _roundNoteWeight(), openBatches);
    }

    function sealPot(uint256 potId) external onlyMixer {
        SrmPot storage p = pots[potId];
        if (p.phase == SrmPotPhase.Idle) revert SOR_PotVoid();
        p.phase = SrmPotPhase.Closed;
    }

    function onboardOperator(address operator, bytes32 label) external onlySheriff {
        if (operator == address(0)) revert SOR_ZeroAddr();
        if (operatorDesks[operator].onboarded) revert SOR_OperatorKnown();
        operatorDesks[operator] = SrmOperatorDesk({
            onboarded: true,
            label: label,
            joinedAt: uint64(block.timestamp),
            noteTally: 0
        });
        emit OperatorOnboard(operator, label, 0);
    }

    function offboardOperator(address operator) external onlySheriff {
        if (!operatorDesks[operator].onboarded) revert SOR_NotOperator();
        operatorDesks[operator].onboarded = false;
        emit OperatorOff(operator, block.number);
    }

    function sweepSurplus(uint256 amt, address payable to) external onlySheriff nonReentrant {
        if (to == address(0)) revert SOR_ZeroAddr();
        if (amt == 0 || amt > address(this).balance) revert SOR_ZeroWei();
        if (amt > address(this).balance - totalLockedWei) revert SOR_QuotaFull();
        _sendNative(to, amt);
    }

    function depositNote(
        bytes32 noteId,
        uint256 potId,
        bytes32 commitment,
        uint8 blendTier
    ) external payable nonReentrant whenGridLive onlyOnboardedOperator {
        if (noteId == bytes32(0)) revert SOR_HashVoid();
        if (noteIdUsed[noteId]) revert SOR_NoteExists();
        if (msg.value < SRM_NOTE_FEE) revert SOR_StakeLow();
        if (blendTier == 0 || blendTier > SRM_TIER_CAP) revert SOR_TierBad();
        SrmPot storage p = pots[potId];
        if (p.phase != SrmPotPhase.Live) revert SOR_PotSealed();
        if (p.noteTally >= SRM_MAX_NOTES) revert SOR_QuotaFull();
        noteIdUsed[noteId] = true;
        notes[noteId] = SrmNote({
            potId: potId,
            depositor: msg.sender,
            commitment: commitment,
            blendTier: blendTier,
            yesClaims: 0,
            noClaims: 0,
            lockedWei: msg.value,
            depositedAt: uint64(block.timestamp),
            active: true
        });
        unchecked {
            p.noteTally += 1;
            p.weightSum = SrmWeigh.cappedSum(
                p.weightSum, uint256(blendTier) * 97, SRM_WEIGHT_CAP
            );
            operatorDesks[msg.sender].noteTally += 1;
        }
        operatorWeight[activeRound][msg.sender] += uint256(blendTier) * 13;
        totalLockedWei += msg.value;
        _notesByDepositor[msg.sender].push(noteId);
        _noteIndex.push(noteId);
        emit Deposited(noteId, potId, msg.sender, blendTier, msg.value);
    }

    function claimNote(bytes32 noteId, bool affirm) external whenGridLive {
        SrmNote storage n = notes[noteId];
        if (!n.active) revert SOR_NoteMissing();
        if (n.depositor == msg.sender) revert SOR_ClaimSelf();
        if (claimCast[noteId][msg.sender]) revert SOR_ClaimUsed();
        claimCast[noteId][msg.sender] = true;
        if (affirm) unchecked { n.yesClaims += 1; }
        else unchecked { n.noClaims += 1; }
        emit Claimed(noteId, msg.sender, affirm, activeRound);
    }

    function stakeNote(bytes32 noteId) external payable nonReentrant whenGridLive {
        if (msg.value == 0) revert SOR_ZeroWei();
        SrmNote storage n = notes[noteId];
        if (!n.active) revert SOR_NoteMissing();
        n.lockedWei += msg.value;
        totalLockedWei += msg.value;
        emit Staked(noteId, msg.sender, msg.value, activeRound);
    }

    function joinOperator(bytes32 label) external payable nonReentrant whenGridLive {
        if (msg.value < SRM_OPERATOR_STAKE) revert SOR_StakeLow();
        if (operatorDesks[msg.sender].onboarded) revert SOR_OperatorKnown();
        operatorDesks[msg.sender] = SrmOperatorDesk({
            onboarded: true,
            label: label,
            joinedAt: uint64(block.timestamp),
            noteTally: 0
        });
        totalLockedWei += msg.value;
        emit OperatorOnboard(msg.sender, label, msg.value);
    }

    function queueBatch(bytes32 batchId, uint256 potId, bytes32 blendTag)
        external
        payable
        nonReentrant
        whenGridLive
        onlyOnboardedOperator
    {
        if (batchId == bytes32(0)) revert SOR_HashVoid();
        if (batchIdUsed[batchId]) revert SOR_BatchOpen();
        if (msg.value < SRM_NOTE_FEE) revert SOR_StakeLow();
        if (openBatches >= SRM_OPEN_BATCH_CAP) revert SOR_QuotaFull();
        SrmPot storage p = pots[potId];
        if (p.phase != SrmPotPhase.Live) revert SOR_PotSealed();
        batchIdUsed[batchId] = true;
        batches[batchId] = SrmBatch({
            potId: potId,
            submitter: msg.sender,
            blendTag: blendTag,
            phase: SrmBatchPhase.Queued,
            releaseHash: bytes32(0),
            blendScore: 0,
            queuedAt: uint64(block.timestamp)
        });
        unchecked {
            openBatches += 1;
            p.batchTally += 1;
        }
        totalLockedWei += msg.value;
        emit Queued(batchId, potId, blendTag, block.timestamp);
    }

    function releaseBatch(bytes32 batchId, bytes32 payloadHash, uint16 blendScore) external onlyMixer {
        SrmBatch storage b = batches[batchId];
        if (b.phase != SrmBatchPhase.Queued && b.phase != SrmBatchPhase.Mixing) revert SOR_BatchDone();
        if (blendScore < SRM_SCORE_FLOOR) revert SOR_ScoreLow();
        if (blendScore > SRM_SCORE_CEIL) revert SOR_ScoreHigh();
        b.phase = SrmBatchPhase.Settled;
        b.releaseHash = payloadHash;
        b.blendScore = blendScore;
        if (openBatches > 0) unchecked { openBatches -= 1; }
        emit Released(batchId, payloadHash, blendScore, activeRound);
    }

    function emitPulse(
        bytes32 pulseId,
        uint256 potId,
        bytes32 pulseTag,
        bytes32 laneHash,
        uint16 blendBand
    ) external onlyMixer whenGridLive {
        if (pulseIdUsed[pulseId]) revert SOR_OperatorStale();
        if (blendBand < SRM_BLEND_FLOOR) revert SOR_ScoreLow();
        if (blendBand > SRM_BLEND_CEIL) revert SOR_ScoreHigh();
        SrmPot storage p = pots[potId];
        if (p.phase != SrmPotPhase.Live) revert SOR_PotSealed();
        pulseIdUsed[pulseId] = true;
        pulses[pulseId] = SrmPulse({
            potId: potId,
            pulseTag: pulseTag,
            laneHash: laneHash,
            blendBand: blendBand,
            stampedAt: uint64(block.timestamp)
        });
        emit Blended(pulseId, potId, blendBand, block.timestamp);
    }

    function fundPot() external payable whenGridLive {
        if (msg.value == 0) revert SOR_ZeroWei();
        emit PotFunded(msg.sender, msg.value, block.number);
        emit Tick_0(tickSerial, msg.sender, msg.value, activeRound);
        unchecked { tickSerial += 1; }
    }

    function withdrawNote(bytes32 noteId, address payable to) external nonReentrant whenGridLive {
        SrmNote storage n = notes[noteId];
        if (!n.active) revert SOR_NoteMissing();
        if (n.depositor != msg.sender) revert SOR_ClaimSelf();
        if (to == address(0)) revert SOR_ZeroAddr();
        uint256 amt = n.lockedWei;
        if (amt == 0) revert SOR_ZeroWei();
        n.active = false;
        n.lockedWei = 0;
        totalLockedWei -= amt;
        _sendNative(to, amt);
    }

    function _sendNative(address to, uint256 amt) internal {
        (bool ok, ) = payable(to).call{value: amt}("");
        if (!ok) revert SOR_NativeFail();
    }

    function _openRound(uint256 roundId) internal {
        SrmBlendRing storage ring = blendRings[roundId];
        ring.openedAt = uint64(block.timestamp);
        ring.noteWeight = _roundNoteWeight();
        ring.batchWeight = openBatches;
        (ring.foldHA, ring.foldHB) = _foldDigest(roundId, ring.noteWeight, ring.batchWeight);
    }

    function _foldDigest(uint256 roundId, uint256 nw, uint256 bw)
        internal
        view
        returns (bytes32 hA, bytes32 hB)
    {
        hA = keccak256(abi.encode(SRM_DOMAIN, roundId, nw, ADDRESS_A, _PEPPER_0));
        hB = keccak256(abi.encode(bw, roundId, ADDRESS_B, _PEPPER_1, SRM_ROUND_BLOCKS));
    }

    function noteDigest(bytes32 noteId) public view returns (bytes32) {
        SrmNote storage n = notes[noteId];
        (bytes32 hA, bytes32 hB) = _foldDigest(n.potId, uint256(uint160(n.depositor)), n.lockedWei);
        return keccak256(abi.encodePacked(hA, hB, n.commitment, ADDRESS_C, _PEPPER_2));
    }

    function _roundNoteWeight() internal view returns (uint256 w) {
        for (uint256 i = 1; i <= 22; ++i) {
            w += pots[i].weightSum;
        }
    }

    function _seedPots() internal {
        pots[1] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(3),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 54,
            potKey: 0x115008296a3645717616dc2b63f725a0a9372c8b2c6ac4632b1c2f9b5ab64041
        });
        emit Pooled(1, 0x115008296a3645717616dc2b63f725a0a9372c8b2c6ac4632b1c2f9b5ab64041, uint8(3), 54);
        pots[2] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(5),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 91,
            potKey: 0xfc4660f8aa6273642b32bc3c5c3c1566f9f7eb7d90034e841fb6173b5c2b4133
        });
        emit Pooled(2, 0xfc4660f8aa6273642b32bc3c5c3c1566f9f7eb7d90034e841fb6173b5c2b4133, uint8(5), 91);
        pots[3] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(4),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 128,
            potKey: 0x8895a9aebdc20b9bec673ff1490e9c283f0598f83922e1d3c67fad17b6fb4405
        });
        emit Pooled(3, 0x8895a9aebdc20b9bec673ff1490e9c283f0598f83922e1d3c67fad17b6fb4405, uint8(4), 128);
        pots[4] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(6),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 165,
            potKey: 0xa1c348457710eeb2adb22d5c3aea60eee54ae41b2c3268c50c7fa2f605eef42d
        });
        emit Pooled(4, 0xa1c348457710eeb2adb22d5c3aea60eee54ae41b2c3268c50c7fa2f605eef42d, uint8(6), 165);
        pots[5] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(7),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 202,
            potKey: 0x48a065e1a4e34ec14c3898181ca713377f7dcd95ae704a8ae66f3e581cc6ff0b
        });
        emit Pooled(5, 0x48a065e1a4e34ec14c3898181ca713377f7dcd95ae704a8ae66f3e581cc6ff0b, uint8(7), 202);
        pots[6] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(5),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 239,
            potKey: 0xb731f56f29513acccf8f1e2c7c08a33a06b46b1d56df71aedbb143becf4e7a26
        });
        emit Pooled(6, 0xb731f56f29513acccf8f1e2c7c08a33a06b46b1d56df71aedbb143becf4e7a26, uint8(5), 239);
        pots[7] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(4),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 276,
            potKey: 0x6bfd9c4afaa3150ec34626498b23c5b2848f05b2c5b1fdea64bdb9c565fb330c
        });
        emit Pooled(7, 0x6bfd9c4afaa3150ec34626498b23c5b2848f05b2c5b1fdea64bdb9c565fb330c, uint8(4), 276);
        pots[8] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(8),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 313,
            potKey: 0x5f3f6b74506fcb64ee69b34141c674240a6f441d1bab4d4c48750fd5bc80e2ec
        });
        emit Pooled(8, 0x5f3f6b74506fcb64ee69b34141c674240a6f441d1bab4d4c48750fd5bc80e2ec, uint8(8), 313);
        pots[9] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(3),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 350,
            potKey: 0x115008296a3645717616dc2b63f725a0a9372c8b2c6ac4632b1c2f9b5ab64041
        });
        emit Pooled(9, 0x115008296a3645717616dc2b63f725a0a9372c8b2c6ac4632b1c2f9b5ab64041, uint8(3), 350);
        pots[10] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(5),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 387,
            potKey: 0xfc4660f8aa6273642b32bc3c5c3c1566f9f7eb7d90034e841fb6173b5c2b4133
        });
        emit Pooled(10, 0xfc4660f8aa6273642b32bc3c5c3c1566f9f7eb7d90034e841fb6173b5c2b4133, uint8(5), 387);
        pots[11] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(4),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 424,
            potKey: 0x8895a9aebdc20b9bec673ff1490e9c283f0598f83922e1d3c67fad17b6fb4405
        });
        emit Pooled(11, 0x8895a9aebdc20b9bec673ff1490e9c283f0598f83922e1d3c67fad17b6fb4405, uint8(4), 424);
        pots[12] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(6),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 461,
            potKey: 0xa1c348457710eeb2adb22d5c3aea60eee54ae41b2c3268c50c7fa2f605eef42d
        });
        emit Pooled(12, 0xa1c348457710eeb2adb22d5c3aea60eee54ae41b2c3268c50c7fa2f605eef42d, uint8(6), 461);
        pots[13] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(7),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 498,
            potKey: 0x48a065e1a4e34ec14c3898181ca713377f7dcd95ae704a8ae66f3e581cc6ff0b
        });
        emit Pooled(13, 0x48a065e1a4e34ec14c3898181ca713377f7dcd95ae704a8ae66f3e581cc6ff0b, uint8(7), 498);
        pots[14] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(5),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 535,
            potKey: 0xb731f56f29513acccf8f1e2c7c08a33a06b46b1d56df71aedbb143becf4e7a26
        });
        emit Pooled(14, 0xb731f56f29513acccf8f1e2c7c08a33a06b46b1d56df71aedbb143becf4e7a26, uint8(5), 535);
        pots[15] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(4),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 572,
            potKey: 0x6bfd9c4afaa3150ec34626498b23c5b2848f05b2c5b1fdea64bdb9c565fb330c
        });
        emit Pooled(15, 0x6bfd9c4afaa3150ec34626498b23c5b2848f05b2c5b1fdea64bdb9c565fb330c, uint8(4), 572);
        pots[16] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(8),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 609,
            potKey: 0x5f3f6b74506fcb64ee69b34141c674240a6f441d1bab4d4c48750fd5bc80e2ec
        });
        emit Pooled(16, 0x5f3f6b74506fcb64ee69b34141c674240a6f441d1bab4d4c48750fd5bc80e2ec, uint8(8), 609);
        pots[17] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(3),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 646,
            potKey: 0x115008296a3645717616dc2b63f725a0a9372c8b2c6ac4632b1c2f9b5ab64041
        });
        emit Pooled(17, 0x115008296a3645717616dc2b63f725a0a9372c8b2c6ac4632b1c2f9b5ab64041, uint8(3), 646);
        pots[18] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(5),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 683,
            potKey: 0xfc4660f8aa6273642b32bc3c5c3c1566f9f7eb7d90034e841fb6173b5c2b4133
        });
        emit Pooled(18, 0xfc4660f8aa6273642b32bc3c5c3c1566f9f7eb7d90034e841fb6173b5c2b4133, uint8(5), 683);
        pots[19] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(4),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 720,
            potKey: 0x8895a9aebdc20b9bec673ff1490e9c283f0598f83922e1d3c67fad17b6fb4405
        });
        emit Pooled(19, 0x8895a9aebdc20b9bec673ff1490e9c283f0598f83922e1d3c67fad17b6fb4405, uint8(4), 720);
        pots[20] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(6),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 757,
            potKey: 0xa1c348457710eeb2adb22d5c3aea60eee54ae41b2c3268c50c7fa2f605eef42d
        });
        emit Pooled(20, 0xa1c348457710eeb2adb22d5c3aea60eee54ae41b2c3268c50c7fa2f605eef42d, uint8(6), 757);
        pots[21] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(7),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 794,
            potKey: 0x48a065e1a4e34ec14c3898181ca713377f7dcd95ae704a8ae66f3e581cc6ff0b
        });
        emit Pooled(21, 0x48a065e1a4e34ec14c3898181ca713377f7dcd95ae704a8ae66f3e581cc6ff0b, uint8(7), 794);
        pots[22] = SrmPot({
            phase: SrmPotPhase.Live,
            blendTier: uint8(5),
            openedAt: uint64(block.timestamp),
            noteTally: 0,
            batchTally: 0,
            weightSum: 831,
            potKey: 0xb731f56f29513acccf8f1e2c7c08a33a06b46b1d56df71aedbb143becf4e7a26
        });
        emit Pooled(22, 0xb731f56f29513acccf8f1e2c7c08a33a06b46b1d56df71aedbb143becf4e7a26, uint8(5), 831);
    }

    // blend readers
    function peekNote_0(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_0));
    }

    function peekNote_1(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_1));
    }

    function peekNote_2(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_2));
    }

    function peekNote_3(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_3));
    }

    function peekNote_4(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_4));
    }

    function peekNote_5(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_5));
    }

    function peekNote_6(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_6));
    }

    function peekNote_7(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_7));
    }

    function peekNote_8(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_0));
    }

    function peekNote_9(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_1));
    }

    function peekNote_10(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_2));
    }

    function peekNote_11(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_3));
    }

    function peekNote_12(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_4));
    }

    function peekNote_13(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_5));
    }

    function peekNote_14(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_6));
    }

    function peekNote_15(bytes32 noteId) external view returns (
        uint256 potId,
        address depositor,
        uint8 tier,
        uint256 locked,
        bytes32 digest
    ) {
        SrmNote storage n = notes[noteId];
        potId = n.potId;
        depositor = n.depositor;
        tier = n.blendTier;
        locked = n.lockedWei;
        digest = keccak256(abi.encode(noteId, locked, _PEPPER_7));
