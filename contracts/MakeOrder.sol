pragma solidity ^0.4.25;

import {Verifier as MakerOrderVerifier} from "./verifiers/MakerOrderVerifier.sol";
import "./ZkDaiBase.sol";


contract MakerOrder is MakerOrderVerifier, ZkDaiBase {
  uint8 internal constant NUM_PUBLIC_INPUTS = 8;

  /**
  * @dev Hashes the submitted proof and adds it to the submissions mapping that tracks
  *      submission time, type, public inputs of the zkSnark and the submitter
  */
  function submit(
      uint256[2] a,
      uint256[2] a_p,
      uint256[2][2] b,
      uint256[2] b_p,
      uint256[2] c,
      uint256[2] c_p,
      uint256[2] h,
      uint256[2] k,
      uint256[4] input)
    internal
  {
      bytes32 proofHash = getProofHash(a, a_p, b, b_p, c, c_p, h, k);
      uint256[] memory publicInput = new uint256[](NUM_PUBLIC_INPUTS);
      for(uint8 i = 0; i < NUM_PUBLIC_INPUTS; i++) {
        publicInput[i] = input[i];
      }
      submissions[proofHash] = Submission(msg.sender, SubmissionType.Spend, now, publicInput);
      emit Submitted(msg.sender, proofHash);
  }

  /**
  * @dev Commits the proof i.e. Marks the input note as Spent and mints two new output notes that came with the proof.
  * @param proofHash Hash of the proof to be committed
  */
  function makeOrderCommit(bytes32 proofHash)
    internal
  {
      Submission storage submission = submissions[proofHash];
      bytes32[4] memory _notes = get4Notes(submission.publicInput);
      // check that the first note (among public params) is committed and
      // new notes should not be existing at this point
      require(notes[_notes[0]] == State.Committed, "Note is either invalid or already spent");
      require(notes[_notes[1]] == State.Committed, "output note1 is already minted");

      notes[_notes[0]] = State.Trading;
      notes[_notes[1]] = State.Trading;

      delete submissions[proofHash];
      submission.submitter.transfer(stake);
      emit NoteStateChange(_notes[0], State.Trading);
      emit NoteStateChange(_notes[1], State.Trading);
  }

  function get2Notes(uint256[] input)
    internal
    pure
    returns(bytes32[2] notes)
  {
      notes[0] = calcHash(input[0], input[1]);
      notes[1] = calcHash(input[2], input[3]);
  }

  /**
  * @dev Challenge the proof for spend step
  * @notice params: a, a_p, b, b_p, c, c_p, h, k zkSnark parameters of the challenged proof
  * @param proofHash Hash of the proof
  */
  function challenge(
      uint256[2] a,
      uint256[2] a_p,
      uint256[2][2] b,
      uint256[2] b_p,
      uint256[2] c,
      uint256[2] c_p,
      uint256[2] h,
      uint256[2] k,
      bytes32 proofHash)
    internal
  {
      Submission storage submission = submissions[proofHash];
      uint256[NUM_PUBLIC_INPUTS] memory input;
      for(uint i = 0; i < NUM_PUBLIC_INPUTS; i++) {
        input[i] = submission.publicInput[i];
      }
      if (!spendVerifyTx(a, a_p, b, b_p, c, c_p, h, k, input)) {
        // challenge passed
        delete submissions[proofHash];
        msg.sender.transfer(stake);
        emit Challenged(msg.sender, proofHash);
      } else {
        // challenge failed
        makeOrderCommit(proofHash);
      }
  }
}