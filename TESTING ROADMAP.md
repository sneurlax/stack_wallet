# Stack Wallet Runtime Testing Feature - Implementation Roadmap

## Overview
This document outlines the implementation plan for adding a runtime testing feature to Stack Wallet's developer options menu. The feature will provide automated testing capabilities for plugin-based coins and core functionality.

## Discovery Analysis

### Secret Developer Options Access
- **Current Implementation**: `lib/pages/home_view/home_view.dart:221-235`
- **Access Method**: Tap Stack Wallet logo 5 times within 1-second intervals
- **Route**: `/hiddenSettings` → `HiddenSettings` class in `lib/pages/settings_views/global_settings_view/hidden_settings.dart`

### UI Design Reference
- **Pattern**: Stack Wallet Backup Recovery UI (`lib/pages/settings_views/global_settings_view/stack_backup_views/sub_views/stack_restore_progress_view.dart`)
- **Components**: `RestoringItemCard` with left icon, title/subtitle, and right status indicator
- **Status States**: waiting (loader), running (green loader), success (checkmark), failed (alert)

### Target Test Coverage
**Plugin-Based Coins:**
- Monero (`lib/wallets/wallet/impl/monero_wallet.dart`)
- Wownero (`lib/wallets/wallet/impl/wownero_wallet.dart`) 
- Salvium (`lib/wallets/wallet/impl/salvium_wallet.dart`)
- Epic Cash (`crypto_plugins/flutter_libepiccash/`)
- Firo (`lib/wallets/wallet/impl/firo_wallet.dart`)
- Litecoin MWEB (`lib/wallets/wallet/impl/litecoin_wallet.dart` + `lib/services/mwebd_service.dart`)

**Plugin-Based Services:**
- Tor functionality (`lib/services/tor_service.dart`)

## Implementation Plan

### Phase 1: Core Testing Infrastructure

#### 1.1 Base Testing Service (`lib/services/testing/`)
**File: `testing_service.dart`**
```dart
class TestingService {
  Stream<TestingSessionState> get statusStream;
  Future<void> runAllTests();
  Future<void> runTestSuite(TestSuiteType type);
  Future<void> cancelTesting();
  Future<void> resetTestResults();
}
```

**File: `test_suite_interface.dart`**
```dart
abstract class TestSuiteInterface {
  String get displayName;
  Widget get icon;
  TestSuiteStatus get status;
  Stream<TestSuiteStatus> get statusStream;
  
  Future<TestResult> runTests();
  Future<void> cleanup();
}
```

**File: `testing_models.dart`**
```dart
enum TestSuiteStatus { waiting, running, passed, failed }
enum TestSuiteType { monero, wownero, salvium, epicCash, firo, litecoinMWEB, tor }

class TestResult {
  final bool success;
  final String message;
  final List<String> logs;
  final Duration executionTime;
}

class TestingSessionState {
  final Map<TestSuiteType, TestSuiteStatus> suiteStatuses;
  final bool isRunning;
  final int completed;
  final int total;
}
```

#### 1.2 Individual Test Suite Implementations

**File: `test_suites/monero_test_suite.dart`**
- Test wallet creation and initialization
- Test node connectivity and sync status
- Test basic transaction validation
- Verify mnemonic and key generation

**File: `test_suites/wownero_test_suite.dart`**
- Similar tests to Monero (shared codebase)
- Wownero-specific network validation

**File: `test_suites/salvium_test_suite.dart`**
- Basic wallet operations testing
- Network connectivity validation

**File: `test_suites/epiccash_test_suite.dart`**
- Plugin connectivity verification
- Wallet initialization testing
- Epic Cash specific validation

**File: `test_suites/firo_test_suite.dart`**
- Privacy feature testing
- Spark/Lelantus functionality validation

**File: `test_suites/litecoin_mweb_test_suite.dart`**
- MWEB service connectivity (`MwebdService`)
- Extension block validation
- MWEB transaction testing

**File: `test_suites/tor_test_suite.dart`**
- Tor connection establishment
- Proxy functionality verification
- Node access through Tor

### Phase 2: UI Integration

#### 2.1 Add Testing Option to Developer Menu
**File: `lib/pages/settings_views/global_settings_view/hidden_settings.dart`**

Add new testing option after line 347:
```dart
const SizedBox(height: 12),
Consumer(
  builder: (_, ref, __) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(TestingView.routeName),
      child: RoundedWhiteContainer(
        child: Text(
          "Testing",
          style: STextStyles.button(context).copyWith(
            color: Theme.of(context).extension<StackColors>()!.accentColorDark,
          ),
        ),
      ),
    );
  },
),
```

#### 2.2 Create Testing UI Components
**File: `lib/pages/testing/testing_view.dart`**
- Main testing interface using `StackRestoreProgressView` as template
- List of test suites with status indicators
- Start/Stop/Cancel controls
- Real-time progress updates

**File: `lib/pages/testing/sub_widgets/test_suite_card.dart`**
- Reuse `RestoringItemCard` pattern
- Display test suite name, status, and progress
- Handle user interactions (tap to view details)

**File: `lib/pages/testing/sub_widgets/testing_progress_indicator.dart`**
- Overall testing progress visualization
- Status summary and completion metrics

#### 2.3 Route Registration
**File: `lib/route_generator.dart`**

Add testing routes:
```dart
import 'pages/testing/testing_view.dart';

// In route generation switch statement:
case TestingView.routeName:
  return getRoute(
    shouldUseMaterialRoute: shouldUseMaterialRoute,
    builder: (_) => const TestingView(),
    settings: settings,
  );
```

### Phase 3: Testing Implementation Details

#### 3.1 Test Execution Strategy
1. **Sequential Execution**: Run tests one at a time to avoid resource conflicts
2. **Timeout Management**: 30-second timeout per test suite
3. **Error Handling**: Graceful failure with detailed error reporting  
4. **Cleanup**: Automatic cleanup of test data and temporary wallets
5. **Cancellation**: User can cancel running tests at any time

#### 3.2 Test Data Management
- Create temporary test wallets in isolated directory
- Use deterministic test mnemonics for reproducible results
- Clean up test data after execution
- Avoid interfering with user's actual wallets

#### 3.3 Network Dependency Handling
- Pre-flight network connectivity checks
- Graceful handling of offline scenarios
- Optional network-dependent test skipping
- Configurable test node endpoints

### Phase 4: Advanced Features (Future Extensions)

#### 4.1 Test Configuration
- Enable/disable specific test suites
- Custom test node configuration
- Test execution scheduling

#### 4.2 Reporting & Logging
- Detailed test execution logs
- Export test results
- Historical test run tracking

#### 4.3 Additional Test Coverage
- Bitcoin and other UTXO coin testing
- Ethereum and ERC-20 token testing
- Exchange functionality testing
- Backup/restore testing

## Implementation Timeline

### Week 1: Infrastructure Setup
- [x] Create base testing service architecture
- [x] Implement core test suite interface
- [x] Set up testing models and state management
- [x] Create provider integration

### Week 2: Test Suite Implementation
- [x] Implement Monero test suite
- [x] Implement Wownero test suite  
- [x] Implement Salvium test suite
- [x] Implement Epic Cash test suite

### Week 3: Additional Test Suites & UI
- [x] Implement Firo test suite
- [x] Implement Litecoin MWEB test suite
- [x] Implement Tor test suite
- [x] Create basic testing UI components

### Week 4: UI Integration & Polish
- [x] Integrate testing option into developer menu
- [x] Create comprehensive testing view
- [x] Add route registration
- [x] Implement progress tracking and status updates
- [x] Testing and bug fixes

## Implementation Status (August 2025)

### ✅ COMPLETED PHASE 1: Core Testing Infrastructure

All infrastructure components have been successfully implemented:

**Created Files:**
- `lib/services/testing/testing_models.dart` - Core models and enums
- `lib/services/testing/test_suite_interface.dart` - Abstract interface for test suites
- `lib/services/testing/testing_service.dart` - Main testing service with Riverpod provider
- `lib/services/testing/test_suites/` - All 7 test suite implementations:
  - `monero_test_suite.dart` - Monero wallet testing
  - `wownero_test_suite.dart` - Wownero wallet testing
  - `salvium_test_suite.dart` - Salvium wallet testing  
  - `epiccash_test_suite.dart` - Epic Cash plugin testing
  - `firo_test_suite.dart` - Firo privacy features testing
  - `litecoin_mweb_test_suite.dart` - Litecoin MWEB functionality testing
  - `tor_test_suite.dart` - Tor service connectivity testing

### ✅ COMPLETED PHASE 2: UI Implementation

**Created Files:**
- `lib/pages/testing/testing_view.dart` - Main testing interface
- `lib/pages/testing/sub_widgets/test_suite_card.dart` - Individual test suite cards
- `lib/pages/testing/sub_widgets/testing_progress_indicator.dart` - Overall progress display

**Modified Files:**
- `lib/pages/settings_views/global_settings_view/hidden_settings.dart` - Added "Testing" option
- `lib/route_generator.dart` - Added route registration for testing view

### ✅ COMPLETED PHASE 3: Integration & Testing

**Key Features Implemented:**
- **Developer Menu Integration**: Testing option accessible via 5-tap Stack Wallet logo secret
- **UI Design Consistency**: Matches Stack Wallet Backup recovery UI patterns using `RestoringItemCard` style
- **Real-time Progress**: Live status updates with spinning indicators, checkmarks, and error states
- **Sequential Test Execution**: Tests run one at a time to avoid resource conflicts
- **30-second Timeouts**: Automatic timeout handling for hanging tests
- **Clean State Management**: Proper cleanup and reset functionality
- **Desktop & Mobile Support**: Responsive design for both platforms

### 🎯 CURRENT STATUS: READY FOR USE

The runtime testing feature is now **fully functional** and ready for use! 

**To Access:**
1. Open Stack Wallet
2. Tap the Stack Wallet logo 5 times within 1-second intervals
3. Navigate to "Testing" option in the hidden developer menu
4. Run individual test suites or all tests at once

**Test Coverage:**
- ✅ Plugin-based cryptocurrencies (Monero, Wownero, Salvium, Epic Cash, Firo, Litecoin MWEB)
- ✅ Core services (Tor functionality)
- ✅ Real-time status tracking and progress indicators
- ✅ Error handling and timeout management
- ✅ Clean test data isolation and cleanup

## Risk Assessment & Mitigation

### High Risk Areas
1. **Plugin Dependencies**: Tests depend on external crypto plugins
   - *Mitigation*: Implement plugin availability checks before testing
2. **Network Instability**: Network-dependent tests may fail unpredictably  
   - *Mitigation*: Implement retry logic and network pre-checks
3. **Resource Conflicts**: Multiple wallets accessing same resources
   - *Mitigation*: Sequential test execution and proper cleanup

### Medium Risk Areas
1. **Test Data Isolation**: Risk of interfering with user data
   - *Mitigation*: Strict test data sandboxing and cleanup procedures
2. **Performance Impact**: Heavy testing affecting app responsiveness
   - *Mitigation*: Background execution with progress cancellation options

## Success Criteria

### Functional Requirements
- [ ] All 6 plugin-based coin tests implemented and working
- [ ] Tor functionality testing operational
- [ ] UI matches Stack Wallet design patterns
- [ ] Proper integration with developer options menu
- [ ] Clean test execution with progress feedback

### Non-Functional Requirements  
- [ ] Tests complete within reasonable time (< 5 minutes total)
- [ ] No interference with user wallet data
- [ ] Graceful handling of failures and edge cases
- [ ] Proper cleanup of test resources
- [ ] Intuitive user interface matching existing patterns

## Future Expansion Opportunities

1. **Extended Coin Coverage**: Add testing for all supported cryptocurrencies
2. **Integration Testing**: Cross-wallet functionality testing
3. **Performance Benchmarking**: Measure and track wallet performance metrics
4. **Automated CI Testing**: Integration with development workflows
5. **User-Configurable Tests**: Allow advanced users to customize test parameters

---

**Note**: This implementation follows Stack Wallet's existing architectural patterns and integrates seamlessly with the current developer options framework. The design prioritizes user experience consistency while providing comprehensive testing capabilities for plugin-based functionality.