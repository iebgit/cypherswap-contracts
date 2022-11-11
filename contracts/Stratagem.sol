// SPDX-License-Identifier: GPL-2.0-or-later
// 0xF91C49506bc1925667cd16bA5128f3ca7192Af80
pragma solidity ^0.8.6;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Stratagem is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    address public owner;
    uint256 private immutable _cap;

    /**
     * @dev Sets the value of the `cap`. This value is immutable, it can only be
     * set once during construction.
     */
    constructor(uint256 cap_, address owner_) ERC20("Stratagem", "GEM") {
        require(cap_ > 0, "ERC20Capped: cap is 0");
        _cap = cap_;
        owner = owner_;
        _setupRole(MINTER_ROLE, owner);
        _setupRole(BURNER_ROLE, owner);
    }

    /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() public view returns (uint256) {
        return _cap;
    }

    function burn(address from, uint256 amount) public {
        require(hasRole(BURNER_ROLE, msg.sender), "Caller is not a burner");
        _burn(from, amount);
    }

    function ownerAddress() public view returns (address _contractCreator) {
        _contractCreator = owner;
    }

    function _mint(address account, uint256 amount) internal override {
        require(ERC20.totalSupply() <= cap(), "Supply cap reached");
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        super._mint(account, amount);
    }

    function mintToken(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }
}
