// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { FuzzTestContext, MutationState } from "./FuzzTestContextLib.sol";

import { LibPRNG } from "solady/src/utils/LibPRNG.sol";

import { vm } from "./VmUtils.sol";

import { Failure } from "./FuzzMutationSelectorLib.sol";

import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    Execution,
    OfferItem
} from "seaport-sol/SeaportStructs.sol";

import { ItemType } from "seaport-sol/SeaportEnums.sol";

enum MutationContextDerivation {
    GENERIC, // No specific selection
    ORDER, // Selecting an order
    CRITERIA_RESOLVER // Selecting a criteria resolver
}

struct IneligibilityFilter {
    Failure[] failures;
    MutationContextDerivation derivationMethod;
    bytes32 ineligibleMutationFilter; // stores a function pointer
}

struct FailureDetails {
    string name;
    bytes4 mutationSelector;
    bytes4 errorSelector;
    MutationContextDerivation derivationMethod;
    bytes32 revertReasonDeriver; // stores a function pointer
}

library FailureEligibilityLib {
    using LibPRNG for LibPRNG.PRNG;

    function ensureFilterSetForEachFailure(
        IneligibilityFilter[] memory failuresAndFilters
    ) internal pure {
        for (uint256 i = 0; i < uint256(Failure.length); ++i) {
            Failure failure = Failure(i);

            bool foundFailure = false;

            for (uint256 j = 0; j < failuresAndFilters.length; ++j) {
                Failure[] memory failures = failuresAndFilters[j].failures;

                for (uint256 k = 0; k < failures.length; ++k) {
                    foundFailure = (failure == failures[k]);

                    if (foundFailure) {
                        break;
                    }
                }

                if (foundFailure) {
                    break;
                }
            }

            if (!foundFailure) {
                revert(
                    string.concat(
                        "FailureEligibilityLib: no filter located for failure #",
                        _toString(i)
                    )
                );
            }
        }
    }

    function extractFirstFilterForFailure(
        IneligibilityFilter[] memory failuresAndFilters,
        Failure failure
    ) internal pure returns (bytes32 filter) {
        bool foundFailure = false;
        uint256 i;

        for (i = 0; i < failuresAndFilters.length; ++i) {
            Failure[] memory failures = failuresAndFilters[i].failures;

            for (uint256 j = 0; j < failures.length; ++j) {
                foundFailure = (failure == failures[j]);

                if (foundFailure) {
                    break;
                }
            }

            if (foundFailure) {
                break;
            }
        }

        if (!foundFailure) {
            revert(
                string.concat(
                    "FailureEligibilityLib: no filter extractable for failure #",
                    _toString(uint256(failure))
                )
            );
        }

        return failuresAndFilters[i].ineligibleMutationFilter;
    }

    function setIneligibleFailure(
        FuzzTestContext memory context,
        Failure ineligibleFailure
    ) internal pure {
        // Set the respective boolean for the ineligible failure.
        context.expectations.ineligibleFailures[
            uint256(ineligibleFailure)
        ] = true;
    }

    function setIneligibleFailures(
        FuzzTestContext memory context,
        Failure[] memory ineligibleFailures
    ) internal pure {
        for (uint256 i = 0; i < ineligibleFailures.length; ++i) {
            // Set the respective boolean for each ineligible failure.
            context.expectations.ineligibleFailures[
                uint256(ineligibleFailures[i])
            ] = true;
        }
    }

    function getEligibleFailures(
        FuzzTestContext memory context
    ) internal pure returns (Failure[] memory eligibleFailures) {
        eligibleFailures = new Failure[](uint256(Failure.length));

        uint256 totalEligibleFailures = 0;
        for (
            uint256 i = 0;
            i < context.expectations.ineligibleFailures.length;
            ++i
        ) {
            // If the boolean is not set, the failure is still eligible.
            if (!context.expectations.ineligibleFailures[i]) {
                eligibleFailures[totalEligibleFailures++] = Failure(i);
            }
        }

        // Update the eligibleFailures array with the actual length.
        assembly {
            mstore(eligibleFailures, totalEligibleFailures)
        }
    }

    function selectEligibleFailure(
        FuzzTestContext memory context
    ) internal pure returns (Failure eligibleFailure) {
        LibPRNG.PRNG memory prng = LibPRNG.PRNG(context.fuzzParams.seed ^ 0xff);

        Failure[] memory eligibleFailures = getEligibleFailures(context);

        if (eligibleFailures.length == 0) {
            revert("FailureEligibilityLib: no eligible failure found");
        }

        return eligibleFailures[prng.next() % eligibleFailures.length];
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 tempValue = value;
        uint256 length;

        while (tempValue != 0) {
            length++;
            tempValue /= 10;
        }

        bytes memory strBytes = new bytes(length);
        while (value != 0) {
            strBytes[--length] = bytes1(uint8(48) + uint8(value % 10));
            value /= 10;
        }

        return string(strBytes);
    }
}

library MutationEligibilityLib {
    using Failarray for Failure;
    using LibPRNG for LibPRNG.PRNG;
    using FailureEligibilityLib for FuzzTestContext;

    error NoEligibleOrderFound();

    function withOrder(
        Failure failure,
        function(AdvancedOrder memory, uint256, FuzzTestContext memory)
            internal
            returns (bool) ineligibilityFilter
    ) internal pure returns (IneligibilityFilter memory) {
        return
            IneligibilityFilter(
                failure.one(),
                MutationContextDerivation.ORDER,
                fn(ineligibilityFilter)
            );
    }

    function withOrder(
        Failure[] memory failures,
        function(AdvancedOrder memory, uint256, FuzzTestContext memory)
            internal
            returns (bool) ineligibilityFilter
    ) internal pure returns (IneligibilityFilter memory) {
        return
            IneligibilityFilter(
                failures,
                MutationContextDerivation.ORDER,
                fn(ineligibilityFilter)
            );
    }

    function withCriteria(
        Failure failure,
        function(CriteriaResolver memory, uint256, FuzzTestContext memory)
            internal
            returns (bool) ineligibilityFilter
    ) internal pure returns (IneligibilityFilter memory) {
        return
            IneligibilityFilter(
                failure.one(),
                MutationContextDerivation.CRITERIA_RESOLVER,
                fn(ineligibilityFilter)
            );
    }

    function withCriteria(
        Failure[] memory failures,
        function(CriteriaResolver memory, uint256, FuzzTestContext memory)
            internal
            returns (bool) ineligibilityFilter
    ) internal pure returns (IneligibilityFilter memory) {
        return
            IneligibilityFilter(
                failures,
                MutationContextDerivation.CRITERIA_RESOLVER,
                fn(ineligibilityFilter)
            );
    }

    function withGeneric(
        Failure failure,
        function(FuzzTestContext memory)
            internal
            returns (bool) ineligibilityFilter
    ) internal pure returns (IneligibilityFilter memory) {
        return
            IneligibilityFilter(
                failure.one(),
                MutationContextDerivation.GENERIC,
                fn(ineligibilityFilter)
            );
    }

    function withGeneric(
        Failure[] memory failures,
        function(FuzzTestContext memory)
            internal
            returns (bool) ineligibilityFilter
    ) internal pure returns (IneligibilityFilter memory) {
        return
            IneligibilityFilter(
                failures,
                MutationContextDerivation.GENERIC,
                fn(ineligibilityFilter)
            );
    }

    function setAllIneligibleFailures(
        FuzzTestContext memory context,
        IneligibilityFilter[] memory failuresAndFilters
    ) internal {
        for (uint256 i = 0; i < failuresAndFilters.length; ++i) {
            IneligibilityFilter memory failuresAndFilter = (
                failuresAndFilters[i]
            );

            if (
                failuresAndFilter.derivationMethod ==
                MutationContextDerivation.GENERIC
            ) {
                setIneligibleFailures(
                    context,
                    asIneligibleGenericMutationFilter(
                        failuresAndFilter.ineligibleMutationFilter
                    ),
                    failuresAndFilter.failures
                );
            } else if (
                failuresAndFilter.derivationMethod ==
                MutationContextDerivation.ORDER
            ) {
                setIneligibleFailures(
                    context,
                    asIneligibleOrderBasedMutationFilter(
                        failuresAndFilter.ineligibleMutationFilter
                    ),
                    failuresAndFilter.failures
                );
            } else {
                revert(
                    "MutationEligibilityLib: unknown derivation method when setting failures"
                );
            }
        }
    }

    function setIneligibleFailures(
        FuzzTestContext memory context,
        function(AdvancedOrder memory, uint256, FuzzTestContext memory)
            internal
            returns (bool) ineligibleMutationFilter,
        Failure[] memory ineligibleFailures
    ) internal {
        if (hasNoEligibleOrders(context, ineligibleMutationFilter)) {
            context.setIneligibleFailures(ineligibleFailures);
        }
    }

    function setIneligibleFailures(
        FuzzTestContext memory context,
        function(FuzzTestContext memory)
            internal
            returns (bool) ineligibleMutationFilter,
        Failure[] memory ineligibleFailures
    ) internal {
        if (hasNoEligibleFailures(context, ineligibleMutationFilter)) {
            context.setIneligibleFailures(ineligibleFailures);
        }
    }

    function hasNoEligibleOrders(
        FuzzTestContext memory context,
        function(AdvancedOrder memory, uint256, FuzzTestContext memory)
            internal
            returns (bool) ineligibleCondition
    ) internal returns (bool) {
        for (uint256 i; i < context.executionState.orders.length; i++) {
            // Once an eligible order is found, return false.
            if (
                !ineligibleCondition(
                    context.executionState.orders[i],
                    i,
                    context
                )
            ) {
                return false;
            }
        }

        return true;
    }

    function hasNoEligibleFailures(
        FuzzTestContext memory context,
        function(FuzzTestContext memory)
            internal
            returns (bool) ineligibleCondition
    ) internal returns (bool) {
        // If the failure is not eligible for selection, return false.
        if (!ineligibleCondition(context)) {
            return false;
        }

        return true;
    }

    function setIneligibleOrders(
        FuzzTestContext memory context,
        function(AdvancedOrder memory, uint256, FuzzTestContext memory)
            internal
            returns (bool) condition
    ) internal {
        for (uint256 i; i < context.executionState.orders.length; i++) {
            if (condition(context.executionState.orders[i], i, context)) {
                setIneligibleOrder(context, i);
            }
        }
    }

    function setIneligibleOrder(
        FuzzTestContext memory context,
        uint256 ineligibleOrderIndex
    ) internal pure {
        // Set the respective boolean for the ineligible order.
        context.expectations.ineligibleOrders[ineligibleOrderIndex] = true;
    }

    function getEligibleOrderIndexes(
        FuzzTestContext memory context
    ) internal pure returns (uint256[] memory eligibleOrderIndexes) {
        eligibleOrderIndexes = new uint256[](
            context.expectations.ineligibleOrders.length
        );

        uint256 totalEligibleOrders = 0;
        for (
            uint256 i = 0;
            i < context.expectations.ineligibleOrders.length;
            ++i
        ) {
            // If the boolean is not set, the order is still eligible.
            if (!context.expectations.ineligibleOrders[i]) {
                eligibleOrderIndexes[totalEligibleOrders++] = i;
            }
        }

        // Update the eligibleOrderIndexes array with the actual length.
        assembly {
            mstore(eligibleOrderIndexes, totalEligibleOrders)
        }
    }

    function selectEligibleOrder(
        FuzzTestContext memory context
    )
        internal
        pure
        returns (AdvancedOrder memory eligibleOrder, uint256 orderIndex)
    {
        LibPRNG.PRNG memory prng = LibPRNG.PRNG(context.fuzzParams.seed ^ 0xff);

        uint256[] memory eligibleOrderIndexes = getEligibleOrderIndexes(
            context
        );

        if (eligibleOrderIndexes.length == 0) {
            revert NoEligibleOrderFound();
        }

        orderIndex = eligibleOrderIndexes[
            prng.next() % eligibleOrderIndexes.length
        ];
        eligibleOrder = context.executionState.orders[orderIndex];
    }

    function fn(
        function(AdvancedOrder memory, uint256, FuzzTestContext memory)
            internal
            returns (bool) ineligibleMutationFilter
    ) internal pure returns (bytes32 ptr) {
        assembly {
            ptr := ineligibleMutationFilter
        }
    }

    function fn(
        function(CriteriaResolver memory, uint256, FuzzTestContext memory)
            internal
            returns (bool) ineligibleMutationFilter
    ) internal pure returns (bytes32 ptr) {
        assembly {
            ptr := ineligibleMutationFilter
        }
    }

    function fn(
        function(FuzzTestContext memory)
            internal
            returns (bool) ineligibleMutationFilter
    ) internal pure returns (bytes32 ptr) {
        assembly {
            ptr := ineligibleMutationFilter
        }
    }

    function asIneligibleGenericMutationFilter(
        bytes32 ptr
    )
        internal
        pure
        returns (
            function(FuzzTestContext memory)
                internal
                returns (bool) ineligibleMutationFilter
        )
    {
        assembly {
            ineligibleMutationFilter := ptr
        }
    }

    function asIneligibleOrderBasedMutationFilter(
        bytes32 ptr
    )
        internal
        pure
        returns (
            function(AdvancedOrder memory, uint256, FuzzTestContext memory)
                internal
                returns (bool) ineligibleMutationFilter
        )
    {
        assembly {
            ineligibleMutationFilter := ptr
        }
    }
}

library MutationContextDeriverLib {
    using MutationEligibilityLib for FuzzTestContext;

    function deriveMutationContext(
        FuzzTestContext memory context,
        MutationContextDerivation derivationMethod,
        bytes32 ineligibilityFilter // use a function pointer
    ) internal returns (MutationState memory mutationState) {
        if (derivationMethod == MutationContextDerivation.ORDER) {
            context.setIneligibleOrders(
                MutationEligibilityLib.asIneligibleOrderBasedMutationFilter(
                    ineligibilityFilter
                )
            );
            (AdvancedOrder memory order, uint256 orderIndex) = context
                .selectEligibleOrder();

            mutationState.selectedOrder = order;
            mutationState.selectedOrderIndex = orderIndex;
        } else if ((derivationMethod != MutationContextDerivation.GENERIC)) {
            revert("MutationContextDeriverLib: unsupported derivation method");
        }
    }
}

library FailureDetailsHelperLib {
    function withOrder(
        bytes4 errorSelector,
        string memory name,
        bytes4 mutationSelector
    ) internal pure returns (FailureDetails memory details) {
        return
            FailureDetails(
                name,
                mutationSelector,
                errorSelector,
                MutationContextDerivation.ORDER,
                fn(defaultReason)
            );
    }

    function withOrder(
        bytes4 errorSelector,
        string memory name,
        bytes4 mutationSelector,
        function(FuzzTestContext memory, MutationState memory, bytes4)
            internal
            view
            returns (bytes memory) revertReasonDeriver
    ) internal pure returns (FailureDetails memory details) {
        return
            FailureDetails(
                name,
                mutationSelector,
                errorSelector,
                MutationContextDerivation.ORDER,
                fn(revertReasonDeriver)
            );
    }

    function withCriteria(
        bytes4 errorSelector,
        string memory name,
        bytes4 mutationSelector
    ) internal pure returns (FailureDetails memory details) {
        return
            FailureDetails(
                name,
                mutationSelector,
                errorSelector,
                MutationContextDerivation.CRITERIA_RESOLVER,
                fn(defaultReason)
            );
    }

    function withCriteria(
        bytes4 errorSelector,
        string memory name,
        bytes4 mutationSelector,
        function(FuzzTestContext memory, MutationState memory, bytes4)
            internal
            view
            returns (bytes memory) revertReasonDeriver
    ) internal pure returns (FailureDetails memory details) {
        return
            FailureDetails(
                name,
                mutationSelector,
                errorSelector,
                MutationContextDerivation.CRITERIA_RESOLVER,
                fn(revertReasonDeriver)
            );
    }

    function withGeneric(
        bytes4 errorSelector,
        string memory name,
        bytes4 mutationSelector
    ) internal pure returns (FailureDetails memory details) {
        return
            FailureDetails(
                name,
                mutationSelector,
                errorSelector,
                MutationContextDerivation.GENERIC,
                fn(defaultReason)
            );
    }

    function withGeneric(
        bytes4 errorSelector,
        string memory name,
        bytes4 mutationSelector,
        function(FuzzTestContext memory, MutationState memory, bytes4)
            internal
            view
            returns (bytes memory) revertReasonDeriver
    ) internal pure returns (FailureDetails memory details) {
        return
            FailureDetails(
                name,
                mutationSelector,
                errorSelector,
                MutationContextDerivation.GENERIC,
                fn(revertReasonDeriver)
            );
    }

    function fn(
        function(FuzzTestContext memory, MutationState memory, bytes4)
            internal
            view
            returns (bytes memory) revertReasonGenerator
    ) internal pure returns (bytes32 ptr) {
        assembly {
            ptr := revertReasonGenerator
        }
    }

    function deriveRevertReason(
        FuzzTestContext memory context,
        MutationState memory mutationState,
        bytes4 errorSelector,
        bytes32 revertReasonDeriver
    ) internal view returns (bytes memory) {
        return
            asRevertReasonGenerator(revertReasonDeriver)(
                context,
                mutationState,
                errorSelector
            );
    }

    function asRevertReasonGenerator(
        bytes32 ptr
    )
        private
        pure
        returns (
            function(FuzzTestContext memory, MutationState memory, bytes4)
                internal
                view
                returns (bytes memory) revertReasonGenerator
        )
    {
        assembly {
            revertReasonGenerator := ptr
        }
    }

    function defaultReason(
        FuzzTestContext memory /* context */,
        MutationState memory,
        bytes4 errorSelector
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(errorSelector);
    }
}

library MutationHelpersLib {
    function isFilteredOrNative(
        FuzzTestContext memory context,
        OfferItem memory item,
        address offerer,
        bytes32 conduitKey
    ) internal pure returns (bool) {
        // Native tokens are not filtered.
        if (item.itemType == ItemType.NATIVE) {
            return true;
        }

        // First look in explicit executions.
        for (
            uint256 i;
            i < context.expectations.expectedExplicitExecutions.length;
            ++i
        ) {
            Execution memory execution = context
                .expectations
                .expectedExplicitExecutions[i];
            if (
                execution.offerer == offerer &&
                execution.conduitKey == conduitKey &&
                execution.item.itemType == item.itemType &&
                execution.item.token == item.token
            ) {
                return false;
            }
        }

        // If we haven't found one yet, keep looking in implicit executions...
        for (
            uint256 i;
            i < context.expectations.expectedImplicitExecutions.length;
            ++i
        ) {
            Execution memory execution = context
                .expectations
                .expectedImplicitExecutions[i];
            if (
                execution.offerer == offerer &&
                execution.conduitKey == conduitKey &&
                execution.item.itemType == item.itemType &&
                execution.item.token == item.token
            ) {
                return false;
            }
        }

        return true;
    }

    function isFilteredOrNative(
        FuzzTestContext memory context,
        ConsiderationItem memory item
    ) internal pure returns (bool) {
        if (item.itemType == ItemType.NATIVE) {
            return true;
        }

        address caller = context.executionState.caller;
        bytes32 conduitKey = context.executionState.fulfillerConduitKey;

        // First look in explicit executions.
        for (
            uint256 i;
            i < context.expectations.expectedExplicitExecutions.length;
            ++i
        ) {
            Execution memory execution = context
                .expectations
                .expectedExplicitExecutions[i];
            if (
                execution.offerer == caller &&
                execution.conduitKey == conduitKey &&
                execution.item.itemType == item.itemType &&
                execution.item.token == item.token
            ) {
                return false;
            }
        }

        // If we haven't found one yet, keep looking in implicit executions...
        for (
            uint256 i;
            i < context.expectations.expectedImplicitExecutions.length;
            ++i
        ) {
            Execution memory execution = context
                .expectations
                .expectedImplicitExecutions[i];
            if (
                execution.offerer == caller &&
                execution.conduitKey == conduitKey &&
                execution.item.itemType == item.itemType &&
                execution.item.token == item.token
            ) {
                return false;
            }
        }

        return true;
    }
}

library Failarray {
    function one(Failure a) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](1);
        arr[0] = a;
        return arr;
    }

    function and(
        Failure a,
        Failure b
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](2);
        arr[0] = a;
        arr[1] = b;
        return arr;
    }

    function and(
        Failure a,
        Failure b,
        Failure c
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        return arr;
    }

    function and(
        Failure a,
        Failure b,
        Failure c,
        Failure d
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](4);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        return arr;
    }

    function and(
        Failure a,
        Failure b,
        Failure c,
        Failure d,
        Failure e
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](5);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        arr[4] = e;
        return arr;
    }

    function and(
        Failure a,
        Failure b,
        Failure c,
        Failure d,
        Failure e,
        Failure f
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](6);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        arr[4] = e;
        arr[5] = f;
        return arr;
    }

    function and(
        Failure a,
        Failure b,
        Failure c,
        Failure d,
        Failure e,
        Failure f,
        Failure g
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](7);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
        arr[4] = e;
        arr[5] = f;
        arr[6] = g;
        return arr;
    }

    function and(
        Failure[] memory originalArr,
        Failure a
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](originalArr.length + 1);

        for (uint256 i = 0; i < originalArr.length; ++i) {
            arr[i] = originalArr[i];
        }

        arr[originalArr.length] = a;

        return arr;
    }

    function and(
        Failure[] memory originalArr,
        Failure a,
        Failure b
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](originalArr.length + 2);

        for (uint256 i = 0; i < originalArr.length; ++i) {
            arr[i] = originalArr[i];
        }

        arr[originalArr.length] = a;
        arr[originalArr.length + 1] = b;

        return arr;
    }

    function and(
        Failure[] memory originalArr,
        Failure a,
        Failure b,
        Failure c
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](originalArr.length + 3);

        for (uint256 i = 0; i < originalArr.length; ++i) {
            arr[i] = originalArr[i];
        }

        arr[originalArr.length] = a;
        arr[originalArr.length + 1] = b;
        arr[originalArr.length + 2] = c;

        return arr;
    }

    function and(
        Failure[] memory originalArr,
        Failure a,
        Failure b,
        Failure c,
        Failure d
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](originalArr.length + 4);

        for (uint256 i = 0; i < originalArr.length; ++i) {
            arr[i] = originalArr[i];
        }

        arr[originalArr.length] = a;
        arr[originalArr.length + 1] = b;
        arr[originalArr.length + 2] = c;
        arr[originalArr.length + 3] = d;

        return arr;
    }

    function and(
        Failure[] memory originalArr,
        Failure a,
        Failure b,
        Failure c,
        Failure d,
        Failure e
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](originalArr.length + 5);

        for (uint256 i = 0; i < originalArr.length; ++i) {
            arr[i] = originalArr[i];
        }

        arr[originalArr.length] = a;
        arr[originalArr.length + 1] = b;
        arr[originalArr.length + 2] = c;
        arr[originalArr.length + 3] = d;
        arr[originalArr.length + 4] = e;

        return arr;
    }

    function and(
        Failure[] memory originalArr,
        Failure a,
        Failure b,
        Failure c,
        Failure d,
        Failure e,
        Failure f
    ) internal pure returns (Failure[] memory) {
        Failure[] memory arr = new Failure[](originalArr.length + 6);

        for (uint256 i = 0; i < originalArr.length; ++i) {
            arr[i] = originalArr[i];
        }

        arr[originalArr.length] = a;
        arr[originalArr.length + 1] = b;
        arr[originalArr.length + 2] = c;
        arr[originalArr.length + 3] = d;
        arr[originalArr.length + 4] = e;
        arr[originalArr.length + 5] = f;

        return arr;
    }
}
