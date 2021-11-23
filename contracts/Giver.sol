// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.3/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.3/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.3/contracts/token/ERC20/utils/SafeERC20.sol";

interface IvMMN {
    function mint(address account, uint256 amount) external;
}

contract Giver is Ownable {
    using SafeERC20 for IERC20;
    
    IERC20 internal token;
    
    struct Mission {
        uint8 state;
        uint248 award;
        uint256 requiredDeposit;
        uint256 participant;
        uint256 maxParticipant;
        uint256 startBlock;
        uint256 endBlock;
        uint256 timeLimit;
    }
    uint256 public missionCount;
    Mission[] public missions;
    
    struct User {
        uint8 state; 
        uint248 startBlock;
    }
    mapping (uint256 => mapping (address => User)) public users;
    mapping (uint256 => mapping (address => bool)) public isSucceeds;
    
    mapping (bytes32 => bool) public queuedRewards;

    event missionCreated(uint256 indexed missionId, uint8 state, uint248 award, uint256 requiredDeposit, uint256 participant, uint256 maxParticipant, uint256 startBlock, uint256 endBlock, uint256 timeLimit);
    event missionUpdated(uint256 indexed missionId, uint8 state, uint248 award, uint256 requiredDeposit, uint256 participant, uint256 maxParticipant, uint256 startBlock, uint256 endBlock, uint256 timeLimit);
    event userJoin(uint256 indexed missionId, address indexed account, uint8 state, uint248 startBlock, uint256 timeLimit);
    event userUpdated(uint256 indexed missionId, address indexed account, uint8 state, uint248 startBlock, uint256 timeLimit);
    event rewardSubmit(uint256 indexed missionId, address indexed account);
    event rewardEvaluate(uint256 indexed missionId, address indexed account, bool isSucceed);
    
    constructor(
        IERC20 _tokenAddr
    ) {
        token = _tokenAddr;
    }
    
    /// @dev Enroll mission by owner.
    ///
    /// State:
    /// Pending (0)
    ///   |_ Cancle (3)
    ///   |_ Active (1)
    ///      |_ Expired (2)
    ///
    /// @param award_ amount of vMMN.
    /// @param requiredDeposit_ of this mission.
    /// @param maxParticipant_ of the mission.
    /// @param startBlock_ of the mission.
    /// @param endBlock_ of the mission.
    /// @param timeLimit_ of the mission.
    /// @return the mission's ID.
    function propose(
        uint248 award_,
        uint256 requiredDeposit_,
        uint256 maxParticipant_,
        uint256 startBlock_,
        uint256 endBlock_,
        uint256 timeLimit_ // block
    )
        public
        onlyOwner
        returns (uint256)
    {
        require(endBlock_ > block.number, "Giver: Invalid block number.");
        require(endBlock_ > startBlock_, "Giver: Invalid block number.");
        require(endBlock_ > startBlock_ + timeLimit_, "Giver: Invalid block number.");
        require(maxParticipant_ > 0, "Giver: Invalid number of max participant.");
        
        uint8 state_ = (startBlock_ <= block.number ? 1 : 0); // Active (1) or Pending (0)
        missions[missionCount++] = Mission({
           state: state_,
           requiredDeposit: requiredDeposit_,
           award: award_,
           participant: 0,
           maxParticipant: maxParticipant_,
           startBlock: startBlock_,
           endBlock: endBlock_,
           timeLimit: timeLimit_
        });
        
        emit missionCreated(missionCount, state_, award_, requiredDeposit_, 0, maxParticipant_, startBlock_, endBlock_, timeLimit_);
        return missionCount;
    }
    
    function activate(uint256 missionId) public onlyOwner {
        Mission memory m = _updateMission(missionId, 0, false);
        require(m.state == 1, "Giver: Fail to activate.");
        
        emit missionUpdated(missionId, m.state, m.award, m.requiredDeposit, m.participant, m.maxParticipant, m.startBlock, m.endBlock, m.timeLimit);
    }
    
    function cancle(uint256 missionId) public onlyOwner {
        Mission memory m = _updateMission(missionId, 0, false);
        require(m.state == 0, "Giver: Cannot cancle active mission.");
        m.state = 3; // Cancle (3)
        
        missions[missionId] = m;

        emit missionUpdated(missionId, m.state, m.award, m.requiredDeposit, m.participant, m.maxParticipant, m.startBlock, m.endBlock, m.timeLimit);
    }
    
    function _updateMission(uint256 missionId, uint256 participant_, bool decrease) internal returns (Mission memory){
        Mission memory m = stateMission(missionId);
        if (participant_ != 0) {
            if (decrease) { m.participant -= participant_; }
            else{ m.participant += participant_; }
            require(m.participant <= m.maxParticipant, "Giver: Cannot exceed max participant.");
        }
        missions[missionId] = m;
        return m;
    }
    
    function stateMission(uint256 missionId) public view returns (Mission memory){
        Mission memory m = missions[missionId];
        
        uint8 state_;
        if (m.state == 3) {
            state_ = m.state; // Cancle (3)
        }
        else if (m.endBlock <= block.number) {
            state_ = 2; // Expired (2)
        }
        else if (m.startBlock <= block.number) {
            state_ = 1; // Active (1)
        }
        else {
            state_ = m.state; // Pending (0)
        }
        
        return Mission({
            state: state_,
            award: m.award,
            requiredDeposit: m.requiredDeposit,
            participant: m.participant,
            maxParticipant: m.maxParticipant,
            startBlock: m.startBlock,
            endBlock: m.endBlock,
            timeLimit: m.timeLimit
        });
    }
    
    /// @dev join to the mission with locking some deposit.
    ///
    /// State:
    /// Nothing (0)
    /// |_ Join (1)
    ///    |_ Done(giveup) (3)
    ///    |_ On-test(submit) (2)
    ///       |_ Join(fail) (1)
    ///       |_ Done(succeed) (3)
    ///       |_ Done(fail after mission expired) (3)
    ///    |_ Banned (4)
    function join(uint256 missionId) public {
        Mission memory m = _updateMission(missionId, 1, false);
        require(m.state == 0 || m.state == 1, "Giver: Cannot join cancled or expired mission.");
        
        User memory u = _updateUser(missionId, msg.sender);
        require(u.state == 0, "Giver: already joined.");
        u.state = 1;
        u.startBlock = uint248(m.state == 0 ? m.startBlock : block.number);
        
        users[missionId][msg.sender] = u;
        
        token.safeTransferFrom(msg.sender, address(this), m.requiredDeposit);
        
        emit userJoin(missionId, msg.sender, u.state, u.startBlock, m.timeLimit);
    }
    
    function giveup(uint256 missionId) public {
        Mission memory m = _updateMission(missionId, 1, true);
        require(m.state == 1, "Giver: Invalid mission state.");
        
        User memory u = _updateUser(missionId, msg.sender);
        require(u.state == 1, "Giver: Not yet joined.");
        u.state = 3; // Done(giveup) (3)
        
        users[missionId][msg.sender] = u;

        token.safeTransfer(msg.sender, m.requiredDeposit);

        emit userUpdated(missionId, msg.sender, u.state, u.startBlock, m.timeLimit);
    }
    
    function submit(uint256 missionId) public {
        Mission memory m = _updateMission(missionId, 0, false);
        require(m.state == 1, "Giver: Invalid mission state.");
        
        User memory u = _updateUser(missionId, msg.sender);
        require(u.state == 1, "Giver: Not yet joined.");
        u.state = 2; // On-test(submit) (2)
        
        users[missionId][msg.sender] = u;

        bytes32 hash = keccak256(abi.encode(missionId, msg.sender));
        queuedRewards[hash] = true;

        emit userUpdated(missionId, msg.sender, u.state, u.startBlock, m.timeLimit);
        emit rewardSubmit(missionId, msg.sender);
    }
    
    /// @dev Anyone can call this function to get expired deposit.
    function ban(uint256 missionId, address account) public {
        Mission memory m = _updateMission(missionId, 1, true);
        require(m.state == 1, "Giver: Invalid mission state.");
        
        User memory u = _updateUser(missionId, account);
        require(u.state == 4, "Giver: Cannot ban.");

        token.safeTransfer(msg.sender, m.requiredDeposit);

        emit userUpdated(missionId, account, u.state, u.startBlock, m.timeLimit);
    }
    
    function _updateUser(uint256 missionId, address account) internal returns (User memory) {
        User memory u = stateUser(missionId, account);
        users[missionId][account] = u;
        return u;
    }

    function stateUser(uint256 missionId, address account) public view returns (User memory) {
        User memory u = users[missionId][account];
        
        uint8 state_;
        if (u.state == 1) { // Join (1)
            if (uint256(u.startBlock) + missions[missionId].timeLimit <= block.number) {
                state_ = 4; // Banned (4)
            }
        }
        else {
            state_ = u.state; // Nothing (0) or On-test (2) or Done (3)
        }

        return User({
            state: state_,
            startBlock: u.startBlock
        });
    }

    function grant(uint256 missionId, address account, bool succeed) public onlyOwner {
        User memory u = _updateUser(missionId, account);
        require(u.state == 2, "Giver: Not yet submitted.");
        
        bytes32 hash = keccak256(abi.encode(missionId, account));
        require(queuedRewards[hash], "Giver: Not yet submitted.");

        Mission memory m = _updateMission(missionId, 0, false);
        
        if (succeed) {
            u.state = 3; // Done(succeed) (3)
            
            token.safeTransfer(account, m.requiredDeposit);
            IvMMN(address(token)).mint(account, m.award);
        }
        else {
            if (m.state == 1) {
                u.state = 1; // Join(fail before mission expired) (1)
            }
            else if (m.state == 2) {
                u.state = 3; // Done(fail after mission expired) (3)
                
                token.safeTransfer(account, m.requiredDeposit);
            }
        }

        users[missionId][account] = u;
        queuedRewards[hash] = false;

        emit userUpdated(missionId, account, u.state, u.startBlock, m.timeLimit);
        emit rewardEvaluate(missionId, account, succeed);
    }
    
    function withdraw(uint256 amount) public onlyOwner {
        token.safeTransfer(msg.sender, amount);
    }
}
