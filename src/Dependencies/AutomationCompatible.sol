// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AutomationBase} from "./AutomationBase.sol";
import {AutomationCompatibleInterface} from "./AutomationCompatibleInterface.sol";

abstract contract AutomationCompatible is AutomationBase, AutomationCompatibleInterface {}
