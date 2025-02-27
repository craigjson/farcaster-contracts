// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ERC1967Proxy} from "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin/contracts/utils/Strings.sol";

import "forge-std/Test.sol";

import {NameRegistry} from "../src/NameRegistry.sol";

/* solhint-disable state-visibility */
/* solhint-disable max-states-count */
/* solhint-disable avoid-low-level-calls */

contract NameRegistryTest is Test {
    NameRegistry nameRegistryImpl;
    NameRegistry nameRegistry;
    ERC1967Proxy nameRegistryProxy;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Renew(uint256 indexed tokenId, uint256 expiry);
    event Invite(uint256 indexed inviterId, uint256 indexed inviteeId, bytes16 indexed fname);
    event ChangeRecoveryAddress(uint256 indexed tokenId, address indexed recovery);
    event RequestRecovery(address indexed from, address indexed to, uint256 indexed tokenId);
    event CancelRecovery(address indexed by, uint256 indexed tokenId);
    event ChangeTrustedCaller(address indexed trustedCaller);
    event DisableTrustedOnly();
    event ChangeVault(address indexed vault);
    event ChangePool(address indexed pool);
    event ChangeFee(uint256 fee);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address defaultAdmin = address(this);

    // Known contracts that must not be made to call other contracts in tests
    address[] knownContracts = [
        address(0xCe71065D4017F316EC606Fe4422e11eB2c47c246), // FuzzerDict
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C), // CREATE2 Factory
        address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84), // address(this)
        address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A), // FORWARDER
        address(0x185a4dc360CE69bDCceE33b3784B0282f7961aea), // ???
        address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D) // ???
    ];
    address constant PRECOMPILE_CONTRACTS = address(9); // some addresses up to 0x9 are precompiled contracts

    address constant ADMIN = address(0xa6a4daBC320300cd0D38F77A6688C6b4048f4682);
    address constant FORWARDER = address(0xC8223c8AD514A19Cc10B0C94c39b52D4B43ee61A);
    address constant POOL = address(0xFe4ECfAAF678A24a6661DB61B573FEf3591bcfD6);
    address constant VAULT = address(0xec185Fa332C026e2d4Fc101B891B51EFc78D8836);

    uint256 constant ESCROW_PERIOD = 3 days;
    uint256 constant REVEAL_DELAY = 60 seconds;
    uint256 constant COMMIT_REPLAY_DELAY = 10 minutes;
    uint256 public constant FEE = 0.01 ether;
    uint256 public constant BID_START = 1_000 ether;

    uint256 constant DEC1_2022_TS = 1669881600; // Dec 1, 2022 00:00:00 GMT
    uint256 constant JAN1_2022_TS = 1640995200; // Jan 1, 2022 0:00:00 GMT
    uint256 constant JAN1_2023_TS = 1672531200; // Jan 1, 2023 0:00:00 GMT
    uint256 constant FEB1_2023_TS = 1675209600; // Feb 1, 2023 0:00:00 GMT
    uint256 constant JAN1_2024_TS = 1704067200; // Jan 1, 2024 0:00:00 GMT

    uint256 constant ALICE_TOKEN_ID = uint256(bytes32("alice"));
    uint256 constant BOB_TOKEN_ID = uint256(bytes32("bob"));

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        nameRegistryImpl = new NameRegistry(FORWARDER);
        nameRegistryProxy = new ERC1967Proxy(address(nameRegistryImpl), "");
        nameRegistry = NameRegistry(address(nameRegistryProxy));
        nameRegistry.initialize("Farcaster NameRegistry", "FCN", VAULT, POOL);
        nameRegistry.grantRole(ADMIN_ROLE, ADMIN);
    }

    /*//////////////////////////////////////////////////////////////
                              COMMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testGenerateCommit() public {
        address alice = address(0x123);

        // alphabetic name
        bytes32 commit1 = nameRegistry.generateCommit("alice", alice, "secret");
        assertEq(commit1, 0xe89b588f69839d6c3411027709e47c05713159feefc87e3173f64c01f4b41c72);

        // 1-char name
        bytes32 commit2 = nameRegistry.generateCommit("1", alice, "secret");
        assertEq(commit2, 0xf52e7be4097c2afdc86002c691c7e5fab52be36748174fe15303bb32cb106da6);

        // 16-char alphabetic
        bytes32 commit3 = nameRegistry.generateCommit("alicenwonderland", alice, "secret");
        assertEq(commit3, 0x94f5dd34daadfe7565398163e7cb955832b2a2e963a6365346ab8ba92b5f5126);

        // 16-char alphanumeric name
        bytes32 commit4 = nameRegistry.generateCommit("alice0wonderland", alice, "secret");
        assertEq(commit4, 0xdf1dc48666da9fcc229a254aa77ffab008da2d29b617fada59b645b7cc0928b9);

        // 16-char alphanumeric hyphenated name
        bytes32 commit5 = nameRegistry.generateCommit("al1c3-w0nderl4nd", alice, "secret");
        assertEq(commit5, 0xbf29b096d3867cc3f3d913d0ee76882adbfa28f28d73bbe372218bd7b282189b);
    }

    function testCannotGenerateCommitWithInvalidName(address alice, bytes32 secret) public {
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("Alice", alice, secret);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a/lice", alice, secret);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a:lice", alice, secret);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a`ice", alice, secret);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("a{ice", alice, secret);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit("-alice", alice, secret);

        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(" alice", alice, secret);

        bytes16 blankName = 0x00000000000000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(blankName, alice, secret);

        // Should reject "a�ice", where � == 129 which is an invalid ASCII character
        bytes16 nameWithInvalidAsciiChar = 0x61816963650000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(nameWithInvalidAsciiChar, alice, secret);

        // Should reject "a�ice", where � == NULL
        bytes16 nameWithEmptyByte = 0x61006963650000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(nameWithEmptyByte, alice, secret);

        // Should reject "�lice", where � == NULL
        bytes16 nameWithStartingEmptyByte = 0x006c6963650000000000000000000000;
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.generateCommit(nameWithStartingEmptyByte, alice, secret);
    }

    function testMakeCommit(address alice, bytes32 secret) public {
        _disableTrusted();
        vm.warp(JAN1_2022_TS);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);

        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);
        assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);
    }

    function testMakeCommitAfterReplayDelay(
        address alice,
        bytes32 secret,
        uint256 delay
    ) public {
        _disableTrusted();
        vm.assume(delay > COMMIT_REPLAY_DELAY);
        vm.warp(JAN1_2022_TS);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);

        // Make the first commit
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);
        assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);

        // Make the second commit after the replay delay
        vm.warp(block.timestamp + COMMIT_REPLAY_DELAY + 1);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);
        assertEq(nameRegistry.timestampOf(commitHash), block.timestamp);
    }

    function testCannotMakeCommitBeforeReplayDelay(
        address alice,
        bytes32 secret,
        uint256 delay
    ) public {
        _disableTrusted();
        delay = delay % COMMIT_REPLAY_DELAY; // fuzz between 0 and (COMMIT_REPLAY_DELAY - 1)
        vm.warp(JAN1_2022_TS);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);

        // Make the first commit
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);
        uint256 firstCommitTs = block.timestamp;
        assertEq(nameRegistry.timestampOf(commitHash), firstCommitTs);

        // Make the second commit before the replay delay
        vm.warp(block.timestamp + delay);
        vm.expectRevert(NameRegistry.CommitReplay.selector);
        nameRegistry.makeCommit(commitHash);
        assertEq(nameRegistry.timestampOf(commitHash), firstCommitTs);
    }

    function testCannotMakeCommitDuringTrustedRegister(address alice, bytes32 secret) public {
        vm.warp(JAN1_2022_TS);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.Invitable.selector);
        nameRegistry.makeCommit(commitHash);
    }

    /*//////////////////////////////////////////////////////////////
                           REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegister(
        address alice,
        address bob,
        address recovery,
        bytes32 secret,
        uint256 amount
    ) public {
        vm.assume(bob != address(0));
        _assumeClean(alice);
        _disableTrusted();
        vm.warp(DEC1_2022_TS);

        // Choose an amount that is at least equal to currYearFee()
        uint256 fee = nameRegistry.currYearFee();
        vm.assume(amount >= fee);
        vm.deal(alice, amount);

        vm.prank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("bob", bob, secret);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), bob, BOB_TOKEN_ID);
        vm.prank(alice);
        nameRegistry.register{value: amount}("bob", bob, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), 0);
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(BOB_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(BOB_TOKEN_ID), recovery);
        assertEq(alice.balance, amount - nameRegistry.currYearFee());
    }

    function testRegisterWorksWhenAlreadyOwningAName(
        address alice,
        address recovery,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.deal(alice, 1 ether);
        vm.warp(DEC1_2022_TS);

        // Register @alice to alice
        vm.startPrank(alice);
        bytes32 commitHashAlice = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(commitHashAlice);
        vm.warp(block.timestamp + REVEAL_DELAY);
        nameRegistry.register{value: nameRegistry.fee()}("alice", alice, secret, recovery);

        // Register @bob to alice
        bytes32 commitHashBob = nameRegistry.generateCommit("bob", alice, secret);
        nameRegistry.makeCommit(commitHashBob);
        vm.warp(block.timestamp + REVEAL_DELAY);
        nameRegistry.register{value: 0.01 ether}("bob", alice, secret, recovery);
        vm.stopPrank();

        assertEq(nameRegistry.timestampOf(commitHashAlice), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);

        assertEq(nameRegistry.timestampOf(commitHashBob), 0);
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(BOB_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(BOB_TOKEN_ID), recovery);

        assertEq(nameRegistry.balanceOf(alice), 2);
    }

    function testRegisterAfterUnpausing(
        address alice,
        address recovery,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        // _assumeClean(recovery);
        _disableTrusted();
        _grant(OPERATOR_ROLE, ADMIN);

        // 1. Make commitment to register the name @alice
        vm.deal(alice, 1 ether);
        vm.warp(DEC1_2022_TS);
        vm.prank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(commitHash);

        // 2. Fast forward past the register delay and pause and unpause the contract
        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.prank(ADMIN);
        nameRegistry.pause();
        vm.prank(ADMIN);
        nameRegistry.unpause();

        // 3. Register the name alice
        vm.prank(alice);
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotRegisterTheSameNameAgain(
        address alice,
        address bob,
        bytes32 secret,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _disableTrusted();
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.warp(DEC1_2022_TS);

        // Register @alice to alice
        bytes32 aliceCommitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(aliceCommitHash);
        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.prank(alice);
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, recovery);
        assertEq(nameRegistry.timestampOf(aliceCommitHash), 0);

        // Register @alice to bob which should fail
        bytes32 bobCommitHash = nameRegistry.generateCommit("alice", bob, secret);
        nameRegistry.makeCommit(bobCommitHash);
        vm.expectRevert("ERC721: token already minted");
        uint256 commitTs = block.timestamp;
        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.prank(bob);
        nameRegistry.register{value: 0.01 ether}("alice", bob, secret, recovery);

        assertEq(nameRegistry.timestampOf(bobCommitHash), commitTs);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);

        // Fast forward to renewable and register @alice to bob which should fail
        vm.warp(block.timestamp + COMMIT_REPLAY_DELAY);
        nameRegistry.makeCommit(bobCommitHash);
        vm.expectRevert("ERC721: token already minted");
        commitTs = block.timestamp;
        vm.warp(JAN1_2023_TS);
        vm.prank(bob);
        nameRegistry.register{value: 0.01 ether}("alice", bob, secret, recovery);

        assertEq(nameRegistry.timestampOf(bobCommitHash), commitTs);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotRegisterWithoutPayment(
        address alice,
        bytes32 secret,
        address recovery
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.deal(alice, 1 ether);
        vm.warp(DEC1_2022_TS);

        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        vm.prank(alice);
        uint256 balance = alice.balance;
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.register{value: 0.0001 ether}("alice", alice, secret, recovery);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(alice.balance, balance);
    }

    function testCannotRegisterWithoutCommit(
        address alice,
        address bob,
        bytes32 secret,
        address recovery
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.assume(bob != address(0));
        vm.deal(alice, 1 ether);
        vm.warp(DEC1_2022_TS);

        bytes16 username = "bob";
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: 0.01 ether}(username, bob, secret, recovery);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(BOB_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRegisterWithInvalidCommitSecret(
        address alice,
        address bob,
        bytes32 secret,
        bytes32 incorrectSecret,
        address recovery
    ) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        vm.assume(secret != incorrectSecret);
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        bytes16 username = "bob";
        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit(username, bob, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        vm.prank(alice);
        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: 0.01 ether}(username, bob, incorrectSecret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(BOB_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(BOB_TOKEN_ID), address(0));
    }

    function testCannotRegisterWithInvalidCommitAddress(
        address alice,
        address bob,
        bytes32 secret,
        address incorrectOwner,
        address recovery
    ) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        vm.assume(incorrectOwner != address(0));
        vm.assume(bob != incorrectOwner);
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        bytes16 username = "bob";
        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit(username, bob, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: 0.01 ether}(username, incorrectOwner, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(incorrectOwner), 0);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(BOB_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(BOB_TOKEN_ID), address(0));
    }

    function testCannotRegisterWithInvalidCommitName(
        address alice,
        address bob,
        bytes32 secret,
        address recovery
    ) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        bytes16 username = "bob";
        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit(username, bob, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        bytes16 incorrectUsername = "alice";
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.prank(alice);
        nameRegistry.register{value: 0.01 ether}(incorrectUsername, bob, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(BOB_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.expiryOf(BOB_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryOf(BOB_TOKEN_ID), address(0));
    }

    function testCannotRegisterBeforeDelay(
        address alice,
        bytes32 secret,
        address recovery
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        vm.prank(alice);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + REVEAL_DELAY - 1);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.InvalidCommit.selector);
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRegisterWithInvalidName(
        address alice,
        bytes32 secret,
        address recovery
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        bytes16 incorrectUsername = "al{ce";
        uint256 incorrectTokenId = uint256(bytes32(incorrectUsername));
        vm.warp(JAN1_2022_TS);

        uint256 commitTs = block.timestamp;
        bytes32 invalidCommit = keccak256(abi.encode(incorrectUsername, alice, secret));
        nameRegistry.makeCommit(invalidCommit);

        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.register{value: 0.01 ether}(incorrectUsername, alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(invalidCommit), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(incorrectTokenId), address(0));
        assertEq(nameRegistry.expiryOf(incorrectTokenId), 0);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.recoveryOf(incorrectTokenId), address(0));
    }

    function testCannotRegisterWhenPaused(
        address alice,
        address recovery,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        _grant(OPERATOR_ROLE, ADMIN);

        // 1. Make the commitment to register @alice
        vm.deal(alice, 1 ether);
        vm.warp(DEC1_2022_TS);
        vm.prank(alice);
        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(commitHash);

        // 2. Pause the contract and try to register the name alice
        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.prank(ADMIN);
        nameRegistry.pause();
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRegisterFromNonPayable(
        address alice,
        address recovery,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.warp(DEC1_2022_TS);

        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, secret);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.expectRevert(NameRegistry.CallFailed.selector);
        // call register() from address(this) which is non-payable
        nameRegistry.register{value: 0.01 ether}("alice", alice, secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRegisterToZeroAddress(
        address alice,
        address recovery,
        bytes32 secret
    ) public {
        _assumeClean(alice);
        _disableTrusted();
        vm.deal(alice, 1 ether);
        vm.warp(DEC1_2022_TS);

        uint256 commitTs = block.timestamp;
        bytes32 commitHash = nameRegistry.generateCommit("alice", address(0), secret);
        nameRegistry.makeCommit(commitHash);

        vm.warp(block.timestamp + REVEAL_DELAY);
        vm.expectRevert("ERC721: mint to the zero address");
        vm.prank(alice);
        nameRegistry.register{value: 0.01 ether}("alice", address(0), secret, recovery);

        assertEq(nameRegistry.timestampOf(commitHash), commitTs);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                         REGISTER TRUSTED TESTS
    //////////////////////////////////////////////////////////////*/

    function testTrustedRegister(
        address trustedCaller,
        address alice,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2022_TS);
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, ALICE_TOKEN_ID);
        vm.expectEmit(true, true, true, true);
        emit Invite(inviter, invitee, "alice");
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTrustedRegisterWhenDisabled(
        address trustedCaller,
        address alice,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2022_TS);

        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.prank(trustedCaller);
        vm.expectRevert(NameRegistry.NotInvitable.selector);
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTrustedRegisterNameTwice(
        address trustedCaller,
        address alice,
        address recovery,
        address recovery2,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.assume(recovery != recovery2);
        vm.warp(JAN1_2022_TS);

        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(trustedCaller);
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        vm.prank(trustedCaller);
        vm.expectRevert("ERC721: token already minted");
        nameRegistry.trustedRegister("alice", alice, recovery2, inviter, invitee);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTrustedRegisterFromArbitrarySender(
        address trustedCaller,
        address arbitrarySender,
        address alice,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.assume(arbitrarySender != trustedCaller);
        assertEq(nameRegistry.trustedOnly(), 1);
        vm.warp(JAN1_2022_TS);

        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(arbitrarySender);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTrustedRegisterWhenPaused(
        address trustedCaller,
        address alice,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2022_TS);

        assertEq(nameRegistry.trustedOnly(), 1);
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(trustedCaller);
        vm.expectRevert("Pausable: paused");
        nameRegistry.trustedRegister("alice", alice, recovery, inviter, invitee);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTrustedRegisterToZeroAddress(
        address trustedCaller,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2022_TS);

        assertEq(nameRegistry.trustedOnly(), 1);
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        vm.expectRevert("ERC721: mint to the zero address");
        nameRegistry.trustedRegister("alice", address(0), recovery, inviter, invitee);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTrustedRegisterWithInvalidName(
        address alice,
        address trustedCaller,
        address recovery,
        uint256 inviter,
        uint256 invitee
    ) public {
        vm.assume(alice != address(0));
        vm.assume(trustedCaller != FORWARDER);
        vm.warp(JAN1_2022_TS);

        assertEq(nameRegistry.trustedOnly(), 1);
        vm.prank(ADMIN);
        nameRegistry.changeTrustedCaller(trustedCaller);

        vm.prank(trustedCaller);
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.trustedRegister("al}ce", alice, recovery, inviter, invitee);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                               RENEW TESTS
    //////////////////////////////////////////////////////////////*/

    function testRenew(
        address alice,
        address bob,
        uint256 amount
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _register(alice);
        // TODO: Report foundry bug when setting the max to anything higher
        vm.assume(amount >= FEE && amount < (type(uint256).max - 3 wei));
        vm.warp(JAN1_2023_TS);

        vm.deal(bob, amount);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Renew(ALICE_TOKEN_ID, JAN1_2024_TS);
        nameRegistry.renew{value: amount}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(bob.balance, amount - FEE);
    }

    function testCannotRenewWithoutPayment(address alice, uint256 amount) public {
        _assumeClean(alice);
        _register(alice);
        vm.warp(JAN1_2023_TS);

        // Ensure that amount is always less than the fee
        amount = (amount % FEE);
        vm.deal(alice, amount);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.renew{value: amount}(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(alice.balance, amount);
    }

    function testCannotRenewIfInvitable(address alice) public {
        _assumeClean(alice);
        vm.deal(alice, 1 ether);

        // Fast forward to 2022, when registrations can occur and do not disable trusted register
        vm.warp(DEC1_2022_TS);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewIfRegistrable(address alice) public {
        _assumeClean(alice);
        vm.deal(alice, 1 ether);

        // Fast forward to 2022, when registrations can occur and disable trusted register
        vm.warp(DEC1_2022_TS);
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.prank(alice);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewIfBiddable(address alice) public {
        _assumeClean(alice);
        _register(alice);

        // Fast-forward to 2023 when @alice is biddable
        vm.warp(FEB1_2023_TS);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotRenewable.selector);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewIfRegistered(address alice) public {
        _assumeClean(alice);
        _register(alice);
        // Fast forward to the last second of 2022 when the registration is still valid
        vm.warp(JAN1_2023_TS - 1);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.Registered.selector);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewIfPaused(address alice) public {
        _assumeClean(alice);
        _register(alice);

        // Fast forward to the first second of 2023, when the name is renewable
        vm.warp(JAN1_2023_TS);

        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.expectRevert("Pausable: paused");
        vm.prank(alice);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRenewFromNonPayable(address alice) public {
        _assumeClean(alice);
        _register(alice);

        // Fast forward to the first second of 2023, when the name is renewable
        vm.warp(JAN1_2023_TS);

        vm.expectRevert(NameRegistry.CallFailed.selector);
        nameRegistry.renew{value: FEE}(ALICE_TOKEN_ID);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                                BID TESTS
    //////////////////////////////////////////////////////////////*/

    function testBid(
        address alice,
        address bob,
        address charlie,
        address recovery1,
        address recovery2,
        uint256 amount
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _register(alice);
        vm.assume(alice != charlie);
        vm.assume(charlie != address(0));

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery1);

        vm.warp(FEB1_2023_TS);
        uint256 winningBid = BID_START + nameRegistry.currYearFee();
        vm.assume(amount >= (winningBid) && amount < (type(uint256).max - 3 wei));
        vm.deal(bob, amount);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, charlie, ALICE_TOKEN_ID);
        nameRegistry.bid{value: amount}(charlie, ALICE_TOKEN_ID, recovery2);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), charlie);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(charlie), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery2);
        assertEq(bob.balance, amount - (winningBid));
    }

    function testBidResetsERC721Approvals(
        address alice,
        address bob,
        address charlie
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        // 1. Set bob as the approver of alice's token
        vm.prank(alice);
        nameRegistry.approve(bob, ALICE_TOKEN_ID);
        vm.warp(FEB1_2023_TS);

        // 2. Bob bids and succeeds because bid >= premium + fee
        vm.deal(bob, 1001 ether);
        vm.prank(bob);
        nameRegistry.bid{value: 1_000.01 ether}(bob, ALICE_TOKEN_ID, charlie);

        assertEq(nameRegistry.getApproved(ALICE_TOKEN_ID), address(0));
    }

    function testBidAfterOneStep(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1000 ether);

        // After 1 step, we expect the bid premium to be 900.000000000000606000 after errors
        vm.warp(FEB1_2023_TS + 8 hours);
        uint256 bidPremium = 900.000000000000606000 ether;
        uint256 bidPrice = bidPremium + nameRegistry.currYearFee();

        // Bid below the price and fail
        vm.startPrank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: bidPrice - 1 wei}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));

        // Bid above the price and succeed
        nameRegistry.bid{value: bidPrice}(bob, ALICE_TOKEN_ID, recovery);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testBidOnHundredthStep(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1 ether);

        // After 100 steps, we expect the bid premium to be 0.026561398887589000 after errors
        vm.warp(FEB1_2023_TS + (8 hours * 100));
        uint256 bidPremium = .026561398887589000 ether;
        uint256 bidPrice = bidPremium + nameRegistry.currYearFee();

        // Bid below the price and fail
        vm.prank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: bidPrice - 1 wei}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));

        // Bid above the price and succeed
        vm.prank(bob);
        nameRegistry.bid{value: bidPrice}(bob, ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testBidOnLastStep(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1 ether);

        // After 393 steps, we expect the bid premium to be 0.000000000000001000 after errors
        vm.warp(FEB1_2023_TS + (8 hours * 393));
        uint256 bidPremium = .000000000000001000 ether;
        uint256 bidPrice = bidPremium + nameRegistry.currYearFee();

        // Bid below the price and fail
        vm.prank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: bidPrice - 1 wei}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));

        // Bid above the price and succeed
        vm.prank(bob);
        nameRegistry.bid{value: bidPrice}(bob, ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testBidAfterLastStep(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(bob);
        _assumeClean(alice);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1 ether);

        // After 393 steps, we expect the bid premium to be 0.0 after errors
        vm.warp(FEB1_2023_TS + (8 hours * 394));
        uint256 bidPrice = nameRegistry.currYearFee();

        // Bid slightly lower than the bidPrice which fails
        vm.prank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: bidPrice - 1 wei}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));

        // Bid with the bidPrice which succeeds
        vm.prank(bob);
        nameRegistry.bid{value: bidPrice}(bob, ALICE_TOKEN_ID, recovery);
        vm.stopPrank();

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testBidShouldClearRecoveryClock(
        address alice,
        address bob,
        address charlie,
        address recovery1,
        address recovery2
    ) public {
        _assumeClean(alice);
        _assumeClean(charlie);
        _assumeClean(recovery1);
        vm.assume(alice != recovery1);
        vm.assume(bob != address(0));
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery1);

        // recovery1 requests a recovery of @alice to bob
        vm.prank(recovery1);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery1);

        // charlie completes a bid on alice
        vm.warp(FEB1_2023_TS);
        vm.deal(charlie, 1001 ether);
        vm.prank(charlie);
        nameRegistry.bid{value: 1001 ether}(charlie, ALICE_TOKEN_ID, recovery2);

        assertEq(nameRegistry.balanceOf(charlie), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), charlie);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery2);
    }

    function testCannotBidWithUnderpayment(
        address alice,
        address bob,
        address recovery,
        uint256 amount
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        // Ensure that amount is always less than the bid + fee
        amount = (amount % (BID_START + FEE));
        vm.deal(bob, amount);

        vm.warp(FEB1_2023_TS);
        vm.prank(bob);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.bid{value: amount}(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(bob.balance, amount);
    }

    function testCannotBidWhenRegistered(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.prank(bob);
        // Register alice and fast-forward to one second before the name expires
        vm.warp(JAN1_2023_TS - 1);
        vm.expectRevert(NameRegistry.NotBiddable.selector);
        nameRegistry.bid(bob, ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidIfRenewable(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);

        vm.prank(bob);
        // Fast-forward to when the registration expires and is renewable
        vm.warp(JAN1_2023_TS);
        vm.expectRevert(NameRegistry.NotBiddable.selector);
        nameRegistry.bid(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidIfInvitable(address bob, address recovery) public {
        _assumeClean(bob);

        // Fast forward to 2022 when registrations are possible
        vm.warp(DEC1_2022_TS);

        vm.prank(bob);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.bid(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidIfRegistrable(address bob, address recovery) public {
        _assumeClean(bob);

        // Fast forward to 2022 when registrations are possible and move to Registrable
        vm.warp(DEC1_2022_TS);
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();

        vm.prank(bob);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.bid(bob, ALICE_TOKEN_ID, recovery);

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotBidIfPaused(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        _register(alice);
        vm.deal(bob, 1001 ether);
        vm.warp(FEB1_2023_TS);

        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(bob);
        vm.expectRevert("Pausable: paused");
        nameRegistry.bid{value: (BID_START + FEE)}(bob, ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.balanceOf(alice), 1); // balanceOf counts expired ids by design
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(bob.balance, 1001 ether);
    }

    function testCannotBidFromNonPayable(address alice, address charlie) public {
        _assumeClean(alice);
        _register(alice);
        address nonPayable = address(this);
        vm.deal(nonPayable, 1001 ether);
        // Fast forward to Biddable state
        vm.warp(FEB1_2023_TS);

        vm.prank(nonPayable);
        vm.expectRevert(NameRegistry.CallFailed.selector);
        nameRegistry.bid{value: 1_000.01 ether}(nonPayable, ALICE_TOKEN_ID, charlie);

        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.balanceOf(alice), 1); // balanceOf counts expired ids by design
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.balanceOf(nonPayable), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nonPayable.balance, 1001 ether);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-721 TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnerOf(address alice) public {
        _assumeClean(alice);
        _register(alice);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
    }

    function testOwnerOfRevertsIfExpired(address alice) public {
        _assumeClean(alice);
        _register(alice);

        // Warp until the name is renewable
        vm.warp(JAN1_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.ownerOf(ALICE_TOKEN_ID);

        // Warp until the name is biddable
        vm.warp(FEB1_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.ownerOf(ALICE_TOKEN_ID);
    }

    function testOwnerOfRevertsIfInvitableOrRegistrable() public {
        vm.expectRevert("ERC721: invalid token ID");
        nameRegistry.ownerOf(ALICE_TOKEN_ID);
    }

    function testTransferFromOwner(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);

        _requestRecovery(alice, recovery);

        // alice transfers @alice to bob
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        // assert that @alice is owned by bob and that the recovery request was reset
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testTransferFromApprover(
        address alice,
        address bob,
        address approver,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        _assumeClean(approver);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        vm.assume(approver != alice);
        _register(alice);

        _requestRecovery(alice, recovery);

        // alice sets charlie as her approver
        vm.prank(alice);
        nameRegistry.approve(approver, ALICE_TOKEN_ID);

        // alice transfers @alice to bob
        vm.prank(approver);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        // assert that @alice is owned by bob and that the recovery request was reset
        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTransferFromIfFnameExpired(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != bob);
        vm.assume(bob != address(0));
        _register(alice);

        uint256 requestTs = _requestRecovery(alice, recovery);

        // Warp to renewable state and attempt a transfer
        vm.warp(JAN1_2023_TS);
        vm.startPrank(alice);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);

        // Warp to biddable state and attempt a transfer
        vm.warp(FEB1_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);
        vm.stopPrank();

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTransferFromIfPaused(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);

        uint256 requestTs = _requestRecovery(alice, recovery);

        // Pause the contract
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTransferFromIfRegistrable(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        vm.warp(DEC1_2022_TS);

        vm.prank(alice);
        vm.expectRevert("ERC721: invalid token ID");
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotTransferFromIfNotOwner(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);

        uint256 requestTs = _requestRecovery(alice, recovery);

        vm.prank(bob);
        vm.expectRevert("ERC721: caller is not token owner nor approved");
        nameRegistry.transferFrom(alice, bob, ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotTransferFromToZeroAddress(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(alice != bob);
        _register(alice);

        uint256 requestTs = _requestRecovery(alice, recovery);

        vm.prank(alice);
        vm.expectRevert("ERC721: transfer to the zero address");
        nameRegistry.transferFrom(alice, address(0), ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
    }

    function testTokenUri() public {
        uint256 tokenId = uint256(bytes32("alice"));
        assertEq(nameRegistry.tokenURI(tokenId), "http://www.farcaster.xyz/u/alice.json");

        // Test with min length name
        uint256 tokenIdMin = uint256(bytes32("a"));
        assertEq(nameRegistry.tokenURI(tokenIdMin), "http://www.farcaster.xyz/u/a.json");

        // Test with max length name
        uint256 tokenIdMax = uint256(bytes32("alicenwonderland"));
        assertEq(nameRegistry.tokenURI(tokenIdMax), "http://www.farcaster.xyz/u/alicenwonderland.json");
    }

    function testCannotGetTokenUriForInvalidName() public {
        vm.expectRevert(NameRegistry.InvalidName.selector);
        nameRegistry.tokenURI(uint256(bytes32("alicenWonderland")));
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeRecoveryAddress(
        address alice,
        address recovery1,
        address recovery2
    ) public {
        _assumeClean(alice);
        vm.assume(alice != recovery1);
        vm.assume(recovery1 != address(0));
        _register(alice);

        // alice sets recovery1 as her recovery address and requests a recovery
        _requestRecovery(alice, recovery1);

        // alice sets recovery2 as her recovery address
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ChangeRecoveryAddress(ALICE_TOKEN_ID, recovery2);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery2);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotChangeRecoveryAddressUnlessOwner(
        address alice,
        address bob,
        address recovery1,
        address recovery2
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);
        vm.assume(recovery1 != address(0));
        vm.assume(recovery2 != address(0));
        _register(alice);

        // alice sets recovery1 as her recovery address and requests a recovery
        uint256 requestTs = _requestRecovery(alice, recovery1);

        vm.prank(bob);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery1);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
    }

    function testCannotChangeRecoveryAddressIfExpired(
        address alice,
        address recovery1,
        address recovery2
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery1);
        vm.assume(recovery1 != address(0));
        vm.assume(recovery2 != address(0));
        _register(alice);

        // alice sets recovery1 as her recovery address and requests a recovery
        uint256 requestTs = _requestRecovery(alice, recovery1);

        // Warp to when name is renewable
        vm.warp(JAN1_2023_TS);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery1);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);

        // Warp to when name is biddable
        vm.warp(FEB1_2023_TS);
        vm.prank(alice);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery1);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
    }

    function testCannotChangeRecoveryAddressIfRegistrable(address alice, address recovery) public {
        _assumeClean(alice);
        vm.assume(alice != recovery);
        vm.assume(recovery != address(0));

        vm.prank(alice);
        vm.expectRevert("ERC721: invalid token ID");
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotChangeRecoveryAddressIfPaused(
        address alice,
        address recovery1,
        address recovery2
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery1);
        vm.assume(alice != recovery1);
        vm.assume(recovery1 != address(0));
        vm.assume(recovery2 != address(0));
        _register(alice);

        // alice sets recovery1 as her recovery address and requests a recovery
        uint256 requestTs = _requestRecovery(alice, recovery1);

        // the contract is paused
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        // alice tries to change her recovery address again
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery2);

        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery1);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
    }

    /*//////////////////////////////////////////////////////////////
                         REQUEST RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRecovery(
        address alice,
        address bob,
        address charlie,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(bob != address(0));
        vm.assume(charlie != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), address(0));

        // Request a recovery from alice to bob
        vm.prank(recovery);
        vm.expectEmit(true, true, true, true);
        emit RequestRecovery(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), bob);

        // Request another recovery from alice to charlie after some time has elapsed
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(recovery);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, charlie);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), charlie);
    }

    function testCannotRequestRecoveryToZeroAddr(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        _register(alice);

        // Start a recovery to set recoveryClockOf and recoveryDestinationOf to non-zero values
        uint256 requestTs = _requestRecovery(alice, recovery);

        // recovery requests a recovery of alice's id to 0x0
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(recovery);
        vm.expectRevert(NameRegistry.InvalidRecovery.selector);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, address(0));

        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotRequestRecoveryUnlessRecoveryAddress(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(bob != recovery);
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        // bob requests a recovery of @alice to bob, which fails
        vm.prank(bob);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);

        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotRequestRecoveryIfPaused(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);

        // Set and request a recovery so that recoveryClockOf is non-zero
        uint256 requestTs = _requestRecovery(alice, recovery);

        // pause the contract
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        // recovery requests a recovery which fails
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(recovery);
        vm.expectRevert("Pausable: paused");
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, recovery);

        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
    }

    /*//////////////////////////////////////////////////////////////
                         COMPLETE RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCompleteRecovery(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        _register(alice);

        // set recovery as the recovery address and request a recovery of @alice from alice to bob
        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(recovery);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);

        // after escrow period, complete the recovery to bob
        vm.prank(recovery);
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, ALICE_TOKEN_ID);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        if (alice != bob) assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(bob), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), bob);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), bob);
    }

    function testRecoveryCompletionResetsERC721Approvals(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);
        _requestRecovery(alice, recovery);

        // set recovery as the approver address for the ERC-721 token
        vm.prank(alice);
        nameRegistry.approve(recovery, ALICE_TOKEN_ID);

        // after escrow period, complete the recovery to bob
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.prank(recovery);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(recovery), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.getApproved(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotCompleteRecoveryUnlessRecovery(
        address alice,
        address recovery,
        address notRecovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(recovery != notRecovery);
        vm.assume(notRecovery != address(0));
        _register(alice);
        uint256 requestTs = _requestRecovery(alice, recovery);

        // notRecovery tries and fails to complete the recovery
        vm.warp(block.timestamp + ESCROW_PERIOD);
        vm.prank(notRecovery);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        if (alice != notRecovery) assertEq(nameRegistry.balanceOf(notRecovery), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotCompleteRecoveryIfNotStarted(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(recovery);
        vm.warp(block.number + ESCROW_PERIOD);
        vm.expectRevert(NameRegistry.NoRecovery.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), address(0));
    }

    function testCannotCompleteRecoveryWhenInEscrow(
        address alice,
        address recovery,
        uint256 waitPeriod
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);
        uint256 requestTs = _requestRecovery(alice, recovery);
        waitPeriod = waitPeriod % ESCROW_PERIOD;

        vm.warp(block.timestamp + waitPeriod);
        vm.prank(recovery);
        vm.expectRevert(NameRegistry.Escrow.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotCompleteRecoveryIfExpired(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        _register(alice);
        uint256 requestTs = _requestRecovery(alice, recovery);

        // Fast forward to renewal and attempt to recover
        vm.warp(JAN1_2023_TS);
        vm.prank(recovery);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), recovery);

        // Fast forward to biddable and attempt to recover
        vm.warp(FEB1_2023_TS);
        vm.prank(recovery);
        vm.expectRevert(NameRegistry.Expired.selector);
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), recovery);
    }

    function testCannotCompleteRecoveryIfPaused(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);
        uint256 requestTs = _requestRecovery(alice, recovery);

        // ADMIN pauses the contract
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        // Fast forward to when the escrow period is completed
        vm.warp(requestTs + ESCROW_PERIOD);

        // 3. recovery attempts to complete the recovery, which fails
        vm.prank(recovery);
        vm.expectRevert("Pausable: paused");
        nameRegistry.completeRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), requestTs);
        assertEq(nameRegistry.recoveryDestinationOf(ALICE_TOKEN_ID), recovery);
    }

    /*//////////////////////////////////////////////////////////////
                          CANCEL RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRecoveryFromCustodyAddress(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(recovery);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(alice, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCancelRecoveryFromRecoveryAddress(
        address alice,
        address bob,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(recovery);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, bob);

        vm.prank(recovery);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(recovery, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCancelRecoveryIfPaused(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);

        _requestRecovery(alice, recovery);

        // pause the contract
        _grant(OPERATOR_ROLE, ADMIN);
        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(alice, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCancelRecoveryIfRenewable(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);

        _requestRecovery(alice, recovery);

        vm.warp(JAN1_2023_TS);
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(alice, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCancelRecoveryIfBiddable(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);

        _requestRecovery(alice, recovery);

        vm.warp(FEB1_2023_TS);
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit CancelRecovery(alice, ALICE_TOKEN_ID);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(recovery), 0);
        vm.expectRevert(NameRegistry.Expired.selector);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotCancelRecoveryIfNotStarted(address alice, address recovery) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        _register(alice);

        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NoRecovery.selector);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotCancelRecoveryIfUnauthorized(
        address alice,
        address recovery,
        address bob
    ) public {
        _assumeClean(alice);
        _assumeClean(recovery);
        vm.assume(alice != recovery);
        vm.assume(bob != address(0));
        vm.assume(bob != recovery);
        vm.assume(bob != alice);
        _register(alice);

        _requestRecovery(alice, recovery);

        vm.prank(bob);
        vm.expectRevert(NameRegistry.Unauthorized.selector);
        nameRegistry.cancelRecovery(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(bob), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                           DEFAULT ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testGrantAdminRole(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != address(0));
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), false);

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), true);
    }

    function testRevokeAdminRole(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != address(0));

        vm.prank(defaultAdmin);
        nameRegistry.grantRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), true);

        vm.prank(defaultAdmin);
        nameRegistry.revokeRole(ADMIN_ROLE, alice);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, alice), false);
    }

    function testCannotGrantAdminRoleUnlessDefaultAdmin(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, bob), false);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(alice), 20),
                " is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
            )
        );
        nameRegistry.grantRole(ADMIN_ROLE, bob);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, ADMIN), true);
        assertEq(nameRegistry.hasRole(ADMIN_ROLE, bob), false);
    }

    /*//////////////////////////////////////////////////////////////
                             MODERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testReclaimRegisteredNames(
        address alice,
        address mod,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(mod);
        _assumeClean(recovery);
        vm.assume(alice != POOL);

        _register(alice);
        _grant(MODERATOR_ROLE, mod);
        _requestRecovery(alice, recovery);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, POOL, ALICE_TOKEN_ID);
        vm.prank(mod);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(POOL), 1);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), POOL);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testReclaimExpiredNames(
        address alice,
        address mod,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(mod);
        _assumeClean(recovery);
        vm.assume(alice != POOL);

        _register(alice);
        _grant(MODERATOR_ROLE, mod);
        _requestRecovery(alice, recovery);

        vm.warp(JAN1_2023_TS);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, POOL, ALICE_TOKEN_ID);
        vm.prank(mod);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(POOL), 1);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), POOL);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testReclaimBiddableNames(
        address alice,
        address mod,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(mod);
        _assumeClean(recovery);
        vm.assume(alice != POOL);

        _register(alice);
        _grant(MODERATOR_ROLE, ADMIN);
        _requestRecovery(alice, recovery);

        vm.warp(FEB1_2023_TS);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, POOL, ALICE_TOKEN_ID);
        vm.prank(ADMIN);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(alice), 0);
        assertEq(nameRegistry.balanceOf(POOL), 1);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), POOL);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2024_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testReclaimResetsERC721Approvals(address alice, address bob) public {
        _assumeClean(alice);
        _assumeClean(bob);
        vm.assume(alice != bob);

        _register(alice);
        _grant(MODERATOR_ROLE, ADMIN);

        vm.prank(alice);
        nameRegistry.approve(bob, ALICE_TOKEN_ID);

        vm.prank(ADMIN);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.getApproved(ALICE_TOKEN_ID), address(0));
    }

    function testReclaimWhenPaused(address alice) public {
        _assumeClean(alice);
        _register(alice);
        _grant(MODERATOR_ROLE, ADMIN);
        _grant(OPERATOR_ROLE, ADMIN);

        vm.prank(ADMIN);
        nameRegistry.pause();

        vm.prank(ADMIN);
        vm.expectRevert("Pausable: paused");
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
    }

    function testCannotReclaimIfRegistrable(address mod) public {
        _assumeClean(mod);
        _grant(MODERATOR_ROLE, mod);

        vm.prank(mod);
        vm.expectRevert(NameRegistry.Registrable.selector);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.balanceOf(POOL), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), 0);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), address(0));
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);
    }

    function testCannotReclaimUnlessModerator(
        address alice,
        address notModerator,
        address recovery
    ) public {
        _assumeClean(alice);
        _assumeClean(notModerator);
        _assumeClean(recovery);

        _register(alice);
        uint256 recoveryTs = _requestRecovery(alice, recovery);

        vm.prank(notModerator);
        vm.expectRevert(NameRegistry.NotModerator.selector);
        nameRegistry.reclaim(ALICE_TOKEN_ID);

        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);

        assertEq(nameRegistry.balanceOf(alice), 1);
        assertEq(nameRegistry.balanceOf(POOL), 0);
        assertEq(nameRegistry.ownerOf(ALICE_TOKEN_ID), alice);
        assertEq(nameRegistry.expiryOf(ALICE_TOKEN_ID), JAN1_2023_TS);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), recoveryTs);
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeTrustedCaller(address alice) public {
        vm.assume(alice != nameRegistry.trustedCaller());

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit ChangeTrustedCaller(alice);
        nameRegistry.changeTrustedCaller(alice);

        assertEq(nameRegistry.trustedCaller(), alice);
    }

    function testCannotChangeTrustedCallerUnlessAdmin(address alice, address bob) public {
        _assumeClean(alice);
        vm.assume(alice != ADMIN);
        address trustedCaller = nameRegistry.trustedCaller();
        vm.assume(bob != trustedCaller);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.changeTrustedCaller(bob);

        assertEq(nameRegistry.trustedCaller(), trustedCaller);
    }

    function testDisableTrustedCaller() public {
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();
        assertEq(nameRegistry.trustedOnly(), 0);
    }

    function testCannotDisableTrustedCallerUnlessAdmin(address alice) public {
        _assumeClean(alice);
        vm.assume(alice != ADMIN);
        assertEq(nameRegistry.trustedOnly(), 1);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.disableTrustedOnly();

        assertEq(nameRegistry.trustedOnly(), 1);
    }

    function testChangeVault(address alice, address bob) public {
        _assumeClean(alice);
        assertEq(nameRegistry.vault(), VAULT);
        _grant(ADMIN_ROLE, alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit ChangeVault(bob);
        nameRegistry.changeVault(bob);

        assertEq(nameRegistry.vault(), bob);
    }

    function testCannotChangeVaultUnlessAdmin(address alice, address bob) public {
        _assumeClean(alice);
        assertEq(nameRegistry.vault(), VAULT);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.changeVault(bob);

        assertEq(nameRegistry.vault(), VAULT);
    }

    function testChangePool(address alice, address bob) public {
        _assumeClean(alice);
        assertEq(nameRegistry.pool(), POOL);
        _grant(ADMIN_ROLE, alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit ChangePool(bob);
        nameRegistry.changePool(bob);

        assertEq(nameRegistry.pool(), bob);
    }

    function testCannotChangePoolUnlessAdmin(address alice, address bob) public {
        _assumeClean(alice);
        assertEq(nameRegistry.pool(), POOL);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotAdmin.selector);
        nameRegistry.changePool(bob);

        assertEq(nameRegistry.pool(), POOL);
    }

    /*//////////////////////////////////////////////////////////////
                             TREASURER TESTS
    //////////////////////////////////////////////////////////////*/

    function testChangeFee(address alice, uint256 fee) public {
        vm.assume(alice != FORWARDER);
        _grant(TREASURER_ROLE, alice);
        assertEq(nameRegistry.fee(), 0.01 ether);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ChangeFee(fee);
        nameRegistry.changeFee(fee);

        assertEq(nameRegistry.fee(), fee);
    }

    function testCannotChangeFeeUnlessTreasurer(address alice, uint256 fee) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotTreasurer.selector);
        nameRegistry.changeFee(fee);
    }

    function testWithdrawFunds(address alice, uint256 amount) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        vm.deal(address(nameRegistry), 1 ether);
        amount = amount % 1 ether;

        vm.prank(alice);
        nameRegistry.withdraw(amount);

        assertEq(address(nameRegistry).balance, 1 ether - amount);
        assertEq(VAULT.balance, amount);
    }

    function testCannotWithdrawUnlessTreasurer(address alice, uint256 amount) public {
        _assumeClean(alice);
        vm.deal(address(nameRegistry), 1 ether);
        amount = amount % 1 ether;

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotTreasurer.selector);
        nameRegistry.withdraw(amount);

        assertEq(address(nameRegistry).balance, 1 ether);
        assertEq(VAULT.balance, 0);
    }

    function testCannotWithdrawInvalidAmount(address alice, uint256 amount) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        amount = amount % 1_000_000_000 ether;
        vm.deal(address(nameRegistry), amount);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.InsufficientFunds.selector);
        nameRegistry.withdraw(amount + 1 wei);

        assertEq(address(nameRegistry).balance, amount);
        assertEq(VAULT.balance, 0);
    }

    function testCannotWithdrawToNonPayableAddress(address alice, uint256 amount) public {
        _assumeClean(alice);
        _grant(TREASURER_ROLE, alice);
        vm.deal(address(nameRegistry), 1 ether);
        amount = amount % 1 ether;

        vm.prank(ADMIN);
        nameRegistry.changeVault(address(this));

        vm.prank(alice);
        vm.expectRevert(NameRegistry.CallFailed.selector);
        nameRegistry.withdraw(amount);

        assertEq(address(nameRegistry).balance, 1 ether);
        assertEq(VAULT.balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             OPERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    // Tests that cover pausing and its implications on other functions live alongside unit tests
    // for the functions

    function testCannotPauseUnlessOperator(address alice) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotOperator.selector);
        nameRegistry.pause();
    }

    function testCannotUnpauseUnlessOperator(address alice) public {
        vm.assume(alice != FORWARDER);

        vm.prank(alice);
        vm.expectRevert(NameRegistry.NotOperator.selector);
        nameRegistry.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          YEARLY PAYMENTS TESTS
    //////////////////////////////////////////////////////////////*/

    // currYear() must be tested in a single test fn chronologically to reach all code paths
    function testCurrYear() public {
        // Date before 2021 incorrectly returns 2021
        vm.warp(1607558400); // Dec 10, 2020 0:00:00 GMT
        assertEq(nameRegistry.currYear(), 2021);

        // Date in known year range
        vm.warp(1640095200); // Dec 21, 2021 14:00:00 GMT
        assertEq(nameRegistry.currYear(), 2021);

        // Date in the same year as previous
        vm.warp(1640390400); // Dec 25, 2021 14:00:00 GMT
        assertEq(nameRegistry.currYear(), 2021);

        // Date which is the last second of a calendar year
        vm.warp(1672531199); // Dec 31, 2022 23:59:59 GMT
        assertEq(nameRegistry.currYear(), 2022);

        // Date which is the first second of the following year
        vm.warp(1672531200); // Jan 1, 2023 00:00:00 GMT
        assertEq(nameRegistry.currYear(), 2023);

        // Date which skips a year from the previous call
        vm.warp(1738368000); // Feb 1, 2025 00:00:00 GMT
        assertEq(nameRegistry.currYear(), 2025);

        // Date after 2072 which reverts
        vm.warp(3250454400); // Jan 1, 2073 0:00:00 GMT
        vm.expectRevert(NameRegistry.InvalidTime.selector);
        assertEq(nameRegistry.currYear(), 0);
    }

    function testCurrYearFee() public {
        _grant(TREASURER_ROLE, ADMIN);

        // fee is initialized to 0.01 ether
        vm.warp(1672531200); // Jan 1, 2023 0:00:00 GMT
        assertEq(nameRegistry.currYearFee(), 0.01 ether);

        vm.warp(1688256000); // Jul 2, 2023 0:00:00 GMT
        assertEq(nameRegistry.currYearFee(), 0.005013698630136986 ether);

        vm.warp(1704067199); // Dec 31, 2023 23:59:59 GMT
        assertEq(nameRegistry.currYearFee(), 0.000000000317097919 ether);

        vm.prank(ADMIN);
        nameRegistry.changeFee(0.02 ether);

        vm.warp(1672531200); // Jan 1, 2023 0:00:00 GMT
        assertEq(nameRegistry.currYearFee(), 0.02 ether);

        vm.warp(1688256000); // Jul 2, 2023 0:00:00 GMT
        assertEq(nameRegistry.currYearFee(), 0.010027397260273972 ether);

        vm.warp(1704067199); // Dec 31, 2023 23:59:59 GMT
        assertEq(nameRegistry.currYearFee(), 0.000000000634195839 ether);

        vm.prank(ADMIN);
        nameRegistry.changeFee(0 ether);

        vm.warp(1672531200); // Jan 1, 2023 0:00:00 GMT
        assertEq(nameRegistry.currYearFee(), 0);

        vm.warp(1688256000); // Jul 2, 2023 0:00:00 GMT
        assertEq(nameRegistry.currYearFee(), 0);

        vm.warp(1704067199); // Dec 31, 2023 23:59:59 GMT
        assertEq(nameRegistry.currYearFee(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Register the username @alice to the address on Dec 1, 2022
    function _register(address alice) internal {
        _disableTrusted();

        vm.deal(alice, 10_000 ether);
        vm.warp(DEC1_2022_TS);

        vm.startPrank(alice);
        bytes32 commitHash = nameRegistry.generateCommit("alice", alice, "secret");
        nameRegistry.makeCommit(commitHash);
        vm.warp(block.timestamp + REVEAL_DELAY);

        nameRegistry.register{value: nameRegistry.fee()}("alice", alice, "secret", address(0));
        vm.stopPrank();
    }

    /// @dev vm.assume that the address does not match known contracts
    function _assumeClean(address a) internal {
        for (uint256 i = 0; i < knownContracts.length; i++) {
            vm.assume(a != knownContracts[i]);
        }

        vm.assume(a > PRECOMPILE_CONTRACTS);
        vm.assume(a != ADMIN);
    }

    /// @dev Helper that assigns the recovery address and then requests a recovery
    function _requestRecovery(address alice, address recovery) internal returns (uint256 requestTs) {
        vm.prank(alice);
        nameRegistry.changeRecoveryAddress(ALICE_TOKEN_ID, recovery);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), 0);

        vm.prank(recovery);
        nameRegistry.requestRecovery(ALICE_TOKEN_ID, recovery);
        assertEq(nameRegistry.recoveryClockOf(ALICE_TOKEN_ID), block.timestamp);
        assertEq(nameRegistry.recoveryOf(ALICE_TOKEN_ID), recovery);
        return block.timestamp;
    }

    function _disableTrusted() internal {
        vm.prank(ADMIN);
        nameRegistry.disableTrustedOnly();
    }

    function _grant(bytes32 role, address target) internal {
        vm.prank(defaultAdmin);
        nameRegistry.grantRole(role, target);
    }
}
