// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SequenceBase} from "./SequenceBase.sol";

/// @notice Deploy Permit2, PoolManager, PositionManager, Router and persist addresses.
contract DeployV4InfraToJson is SequenceBase {
    function run() external {
        vm.startBroadcast();
        deployArtifacts();
        vm.stopBroadcast();

        Deployments memory d = _readDeployments();
        d.permit2 = address(permit2);
        d.poolManager = address(poolManager);
        d.positionManager = address(positionManager);
        d.router = address(swapRouter);
        _writeDeployments(d);
    }
}

