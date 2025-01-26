// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**SOLANA IS SHIT */
/**
 * @title Raffle
 * @author 0xavcieth
 * @notice This contract is a raffle contract.
 * @dev Implementation of Chainlink VRFv2.5
 */
// entrenceFee ile  giris ucreti aldigimiz icin enterRaffle fonksiyonu icinde payable keywordunu kullandik.
// eğer bir kontratı inherite yapıyorsak ayrıca o kontratın içindeki constructor'ı da bizim kontrata ekleriz.
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffe__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );
    /* Type Declarations */
    // bool bize sadece true false yanit verir. Daha fazla durum belirlemek icin enum kullaniriz.
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }
    /* State Variables */
    uint256 private immutable i_entrenceFee;
    // @dev The duration of the lottery in seconds
    // constant degiskenler icin buyuk harf kullaniriz.
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState; // start with open

    /* Events */ // sadece 3 event tanimlayabiliriz.
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entrenceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entrenceFee = entrenceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN; // RaffleState(0); ayni anlama geliyor.
    }

    function enterRaffle() external payable {
        // Old way to check amount - require(msg.value >= i_entrenceFee, "Send more to enter raffle");
        // also old way to check but gass efficient
        if (msg.value < i_entrenceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffe__RaffleNotOpen();
        }
        // asagidakini kullanabilmemiz icin yuksek version ve spesifik bir comp version lazim(zaten bi sike yaramiyor)
        // require(msg.value >= i_entrenceFee, SendMoreToEnterRaffle());
        s_players.push(payable(msg.sender));
        // 1. migrationlari daha kolay yapabilmek icin events kullanilir.
        // 2. front-end tarafinda isleri kolaylastirmak icin kullanilir.
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is the function that the chainklink will interact to see
     * if the lottery is ready to have a winner picked.
     * the following should be true in order for upKeedNeeded to be true.
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is open.
     * 3. The contract has ETH.
     * 4. Implicitly, your subscription has LINK.
     * @param -ignored
     * @return upkeepNeeded - true if its time to restart the lottery
     * @return -ignored
     */

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    // 1. get a random number
    // 2. use random number to pick a winner
    // 3. be automatically called
    function performUpkeep(bytes calldata /* performData */) external {
        // check if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            // error icine ekstra bilgi koyabiliriz.
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;

        //generate random number with chainlink VRF v2.5
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

    // abstract kontratlar hem tanimlanmis fonksiyonlari hem de tanimlanmamis fonksiyonlari icerebilir.
    // override ekledik cunku bu fonksiyon virtual olarak tanimlanmis.
    // VRFConsumerBaseV2Plus /-/  function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual;
    // CEI: Checks, Effects, Interactions pattern
    function fulfillRandomWords(
        uint256, //requestId,
        uint256[] calldata randomWords
    ) internal override {
        // CHECKS: kosullar kontroller vs.

        // s_player = 10
        // rng = 12
        // 12 % 10 = 2 -> 2. indexdeki kisi kazandi
        // 23478946727837238467823 % 10 = 3 -> 3. indexdeki kisi kazandi

        // EFFECTS (Internal Contract State)

        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);
        // Interactions (External Contract Interactions)

        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entrenceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimestamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
