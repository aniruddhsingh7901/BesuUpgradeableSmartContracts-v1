pragma solidity ^0.8.0;

contract PoseidonUnit2 {
  function poseidon(uint256[2] memory) public view returns (uint256) {}
}

contract PoseidonUnit3 {
  function poseidon(uint256[3] memory) public view returns (uint256) {}
}

contract Poseidon {
  PoseidonUnit2 _poseidonUnit2;
    PoseidonUnit3 _poseidonUnit3;

  constructor( address _poseidon2ContractAddr, address _poseidon3ContractAddr ) {
    _poseidonUnit2 = PoseidonUnit2(_poseidon2ContractAddr);
    _poseidonUnit3 = PoseidonUnit3(_poseidon3ContractAddr);
  }

  function hash2( uint256[2] memory inp ) public view returns (uint256) {
    return _poseidonUnit2.poseidon(inp);
  }

  function hash3( uint256[3] memory inp ) public view returns (uint256) {
    return _poseidonUnit3.poseidon(inp);
  }
}
