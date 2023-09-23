import "../interfaces/IPoolManager.sol";
import "../hooks/LSBHook.sol";

contract UniswapHooksFactory {
    function deploy(
        address owner,
        IPoolManager poolManager,
        bytes32 salt
    ) external returns (address) {
        return address(new LSBHook{salt: salt}(owner, poolManager));
    }

    function getPrecomputedHookAddress(
        address owner,
        IPoolManager pm,
        bytes32 salt
    ) external view returns (address) {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(type(LSBHook).creationCode, abi.encode(owner, pm))
        );
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)
        );
        return address(uint160(uint256(hash)));
    }
}
