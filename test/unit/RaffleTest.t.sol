//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    //EVENTS - have to remake them in the test contract
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    //CORRECT START
    function testRaffleInitialisesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    //ENTERING RAFFLE
    function testRaffleRevertsWhenDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle(); //not sending any money
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assertEq(playerRecorded, PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testRaffleHandlesEntriesWithDifferentAmountsOfEther() public {
        address player2 = makeAddr("player2");
        vm.deal(player2, STARTING_USER_BALANCE);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.prank(player2);
        raffle.enterRaffle{value: 2 * entranceFee}();
        assertEq(raffle.getPlayer(1), player2);
    }

    //CHECK UPKEEP TESTS
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); // this sets the raffle state to calculating

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfNotEnoughTimeHasPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //no warp or roll means not enough time has passed

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfNoPlayers() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }

    //PERFORM UPKEEP TESTS
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep(""); //this passes without the need for an assert
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        vm.expectRevert(
            abi.encodeWithSelector( // this is how you handle custom errors WITH parameters
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequiestId()
        public
        raffleEnteredAndTimePassed
    {
        vm.recordLogs();
        raffle.performUpkeep(""); //emits requestid
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 requestId = entries[1].topics[1]; //entry 0 is the event vrfCoord mock emits, topic 0 is the whole event being emitted, topic 1 is requestId within that event
        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) != 0);
        assert(rState == Raffle.RaffleState.CALCULATING);
    }

    //fulFillRandomWords TESTS

    modifier skipFork() {
        //only runs on anvil
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFuzz_FulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randRequestId //this number will get fuzzed
    ) public raffleEnteredAndTimePassed skipFork {
        //arrange
        vm.expectRevert("nonexistent request"); //line 106 in VRFCoordinatorV2Mock.sol throws this error if requestId is not valid
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAwinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1; //we already have one entered from the modifier
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i)); //equivalent to address(1), address(2), etc
            hoax(player, STARTING_USER_BALANCE); //hoax = equivalent to vm.deal then vm.prank
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 prevTimestamp = raffle.getLastTimestamp(); //get the timestamp from before fulfillRandomWords is called

        vm.recordLogs();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        entries = vm.getRecordedLogs();
        bytes32 winner = entries[0].topics[1]; //fulfillRandomWordsWithOverride in vrf mock has an emit that is in entries[0]

        //asserts
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        assert(address(raffle).balance == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getNumPlayers() == 0);
        assert(prevTimestamp < raffle.getLastTimestamp());
        assert(address(uint160(uint256(winner))) == raffle.getRecentWinner()); //converting bytes32 to address
        assert(
            raffle.getRecentWinner().balance ==
                (STARTING_USER_BALANCE + prize - entranceFee)
        );
    }
}
